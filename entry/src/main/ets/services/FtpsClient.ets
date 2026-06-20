import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { FileInfo } from '../models/FileInfo';

interface ReadPromise {
  resolve: (value: string) => void;
  reject: (reason: Error) => void;
  timer: number;
}

class PasvResult {
  address: string = '';
  port: number = 0;
}

// 列表行解析结果。kind：'unix' | 'dos' | 'mlsd'
class ParsedEntry {
  name: string = '';
  path: string = '';
  isDirectory: boolean = false;
  size: number = 0;
  modificationTime: number = 0;
}

export interface DownloadCallbacks {
  onProgress?: (received: number, total: number) => void;
}

// 读取控制连接响应的统一超时
const RESPONSE_TIMEOUT_MS = 30000;
// 列表数据空闲判定：最后一个数据块到达后等待该时长即认为读取完成
const LIST_IDLE_MS = 150;

export class FtpsClient {
  private controlSocket: socket.TCPSocket | null = null;
  private tlsSocket: socket.TLSSocket | null = null;
  private dataSocket: socket.TCPSocket | null = null;
  private serverAddress: string = '';
  private isAuthenticated: boolean = false;
  private currentDirectory: string = '/';
  private readPromise: ReadPromise | null = null;
  private responseBuffer: string = '';

  constructor() {}

  async connect(address: string, port: number, username: string, password: string): Promise<boolean> {
    try {
      this.serverAddress = address;
      if (port === 990) {
        await this.connectImplicitTls(address, port, username, password);
      } else {
        await this.connectExplicitTls(address, port, username, password);
      }
      this.isAuthenticated = true;
      await this.sendCommand('TYPE I');
      return true;
    } catch (e) {
      this.cleanup();
      throw this.normalizeError(e, '连接失败');
    }
  }

  private async connectImplicitTls(address: string, port: number, username: string, password: string): Promise<void> {
    this.tlsSocket = socket.constructTLSSocketInstance();
    try {
      await this.tlsSocket.connect({
        address: { address: address, port: port, family: 1 },
        secureOptions: this.buildTlsSecureOptions(),
        skipRemoteValidation: true
      });
    } catch (e) {
      throw this.normalizeError(e, '隐式TLS握手失败');
    }
    this.setupTlsListener();
    const welcome = await this.readResponse('等待服务器欢迎语超时');
    if (!welcome.startsWith('220')) throw new Error('服务器返回异常: ' + welcome);
    await this.sendCommand('PBSZ 0');
    await this.sendCommand('PROT P');
    await this.login(username, password);
  }

  private async connectExplicitTls(address: string, port: number, username: string, password: string): Promise<void> {
    this.controlSocket = socket.constructTCPSocketInstance();
    this.setupControlListener();
    try {
      await this.controlSocket.connect({
        address: { address: address, port: port, family: 1 }
      });
    } catch (e) {
      throw this.normalizeError(e, 'TCP连接失败');
    }
    const welcome = await this.readResponse('等待服务器欢迎语超时');
    if (!welcome.startsWith('220')) throw new Error('服务器返回异常: ' + welcome);

    const auth = await this.startExplicitFtps();
    if (!auth.startsWith('234')) throw new Error('AUTH TLS失败: ' + auth);

    this.responseBuffer = '';
    this.tlsSocket = socket.constructTLSSocketInstance(this.controlSocket);
    try {
      await this.tlsSocket.connect({
        address: { address: address, port: port, family: 1 },
        secureOptions: this.buildTlsSecureOptions(),
        skipRemoteValidation: true
      });
    } catch (e) {
      throw this.normalizeError(e, '显式TLS握手失败');
    }
    // 切到 TLS 后，明文 controlSocket 不再监听数据，避免双重消费
    this.teardownControlListener();
    this.setupTlsListener();

    await this.sendCommand('PBSZ 0');
    await this.sendCommand('PROT P');
    await this.login(username, password);
  }

  private async login(username: string, password: string): Promise<void> {
    const ur = await this.sendCommand('USER ' + username);
    if (!ur.startsWith('2') && !ur.startsWith('3')) throw new Error('用户名错误: ' + ur);
    // 有些服务器直接 230 已登录，跳过 PASS
    if (ur.startsWith('2')) return;
    const pr = await this.sendCommand('PASS ' + password);
    if (!pr.startsWith('2')) throw new Error('密码错误: ' + pr);
  }

  private buildTlsSecureOptions(): socket.TLSSecureOptions {
    // 优先 TLSv1.3，回退 TLSv1.2，兼容大多数服务器（含纯 TLSv1.3 公网服务器）
    const options: socket.TLSSecureOptions = {
      protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13]
    };
    return options;
  }

  async disconnect(): Promise<void> {
    this.isAuthenticated = false;
    this.cleanup();
  }

  isConnected(): boolean {
    return this.isAuthenticated && this.tlsSocket !== null;
  }

  async listFiles(path: string): Promise<FileInfo[]> {
    if (!this.isAuthenticated) throw new Error('未连接');
    const p = await this.openPassiveEndpoint();
    const tcpDataSocket = await this.openDataTcpConnection(p);
    let ds: socket.TLSSocket | null = null;
    try {
      // 优先 MLSD（机器可读，最稳）；不支持时退回 LIST
      let listing: string = '';
      let usedMlsd: boolean = false;
      try {
        const mlsdResp = await this.sendCommand('MLSD ' + path);
        if (mlsdResp.startsWith('1')) {
          ds = await this.openDataTlsConnection(tcpDataSocket, p);
          listing = await this.readDataText(ds);
          await this.waitOkResponse();
          usedMlsd = true;
        }
      } catch (_) {
        // MLSD 不支持，落到 LIST
      }
      if (!usedMlsd) {
        const listResp = await this.sendCommand('LIST ' + path);
        if (!listResp.startsWith('1')) throw new Error('LIST失败: ' + listResp);
        ds = await this.openDataTlsConnection(tcpDataSocket, p);
        listing = await this.readDataText(ds);
        await this.waitOkResponse();
      }
      return this.parseListing(listing, path, usedMlsd);
    } finally {
      if (ds !== null) {
        this.closeDataSocket(ds);
      } else {
        this.closeDataTcpSocket();
      }
    }
  }

  /**
   * 下载文件。数据连接关闭后一次性写入目标文件。
   * 进度通过 onProgress(received, total) 回调，total<0 表示未知。
   *
   * 注：DocumentViewPicker 返回的 content URI 只适合一次写入，不适合分块追加；
   *     因此收集全部 chunk 后统一写入，同时实时上报已接收字节数作为进度。
   */
  async downloadFile(remotePath: string, localUri: string, callbacks?: DownloadCallbacks): Promise<void> {
    if (!this.isAuthenticated) throw new Error('未连接');

    // 先尝试取文件大小用于进度计算
    let total: number = -1;
    try {
      const sizeResp = await this.sendCommand('SIZE ' + remotePath);
      if (sizeResp.startsWith('213')) {
        const parsed: number = parseInt(sizeResp.substring(4).trim(), 10);
        if (!isNaN(parsed) && parsed > 0) total = parsed;
      }
    } catch (_) {
      // SIZE 失败不致命
    }

    const p = await this.openPassiveEndpoint();
    const tcpDataSocket = await this.openDataTcpConnection(p);
    let ds: socket.TLSSocket | null = null;
    try {
      const retrResp = await this.sendCommand('RETR ' + remotePath);
      if (!retrResp.startsWith('1')) throw new Error('RETR失败: ' + retrResp);
      ds = await this.openDataTlsConnection(tcpDataSocket, p);
      const raw = await this.readDataBinary(ds, total, callbacks);
      await this.waitOkResponse();
      // 一次性写入文件（content URI 只支持单次写入）
      const file = await fs.open(localUri, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        await fs.write(file.fd, raw.buffer);
      } finally {
        try { await fs.close(file.fd); } catch (_) {}
      }
      if (callbacks !== undefined && callbacks.onProgress !== undefined) {
        callbacks.onProgress(total > 0 ? total : 0, total);
      }
    } finally {
      if (ds !== null) {
        this.closeDataSocket(ds);
      } else {
        this.closeDataTcpSocket();
      }
    }
  }

  async getCurrentDirectory(): Promise<string> {
    const resp = await this.sendCommand('PWD');
    const m = resp.match(/"([^"]+)"/);
    if (m !== null) {
      this.currentDirectory = m[1];
    }
    return this.currentDirectory;
  }

  async changeDirectory(path: string): Promise<void> {
    const resp = await this.sendCommand('CWD ' + path);
    if (!resp.startsWith('2')) throw new Error('CWD失败: ' + resp);
    this.currentDirectory = path;
  }

  private async openDataTcpConnection(p: PasvResult): Promise<socket.TCPSocket> {
    this.dataSocket = socket.constructTCPSocketInstance();
    try {
      await this.dataSocket.connect({
        address: { address: p.address, port: p.port, family: 1 }
      });
    } catch (e) {
      throw this.normalizeError(e, '数据TCP连接失败');
    }
    return this.dataSocket;
  }

  private async openDataTlsConnection(tcpDataSocket: socket.TCPSocket, p: PasvResult): Promise<socket.TLSSocket> {
    const ds = socket.constructTLSSocketInstance(tcpDataSocket);
    try {
      await ds.connect({
        address: { address: p.address, port: p.port, family: 1 },
        secureOptions: this.buildTlsSecureOptions(),
        skipRemoteValidation: true
      });
    } catch (e) {
      throw this.normalizeError(e, '数据连接TLS握手失败');
    }
    return ds;
  }

  private async openPassiveEndpoint(): Promise<PasvResult> {
    const epsv = await this.sendCommand('EPSV');
    if (epsv.startsWith('229')) {
      return this.parseEpsv(epsv);
    }
    const pasv = await this.sendCommand('PASV');
    if (!pasv.startsWith('2')) throw new Error('EPSV失败: ' + epsv + '; PASV失败: ' + pasv);
    return this.parsePasv(pasv);
  }

  private closeDataSocket(ds: socket.TLSSocket): void {
    try { ds.close(); } catch (_) {}
    this.closeDataTcpSocket();
  }

  private closeDataTcpSocket(): void {
    try { this.dataSocket?.close(); } catch (_) {}
    this.dataSocket = null;
  }

  private readDataText(ds: socket.TLSSocket): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void) => {
      const chunks: Uint8Array[] = [];
      const dec = new util.TextDecoder('utf-8');
      let idleTimer: number = -1;
      let settled: boolean = false;
      const fail = (err: Error): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (idleTimer !== -1) clearTimeout(idleTimer);
        reject(err);
      };
      const done = (): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (idleTimer !== -1) clearTimeout(idleTimer);
        let total: number = 0;
        for (const c of chunks) total += c.byteLength;
        const merged: Uint8Array = new Uint8Array(total);
        let off: number = 0;
        for (const c of chunks) { merged.set(c, off); off += c.byteLength; }
        resolve(dec.decodeToString(merged));
      };
      const timer: number = setTimeout(() => {
        fail(new Error('读取数据连接超时'));
      }, RESPONSE_TIMEOUT_MS);
      ds.on('message', (info: socket.SocketMessageInfo) => {
        chunks.push(new Uint8Array(info.message));
        if (idleTimer !== -1) clearTimeout(idleTimer);
        idleTimer = setTimeout(() => done(), LIST_IDLE_MS);
      });
      ds.on('close', () => done());
      ds.on('error', () => fail(new Error('数据连接错误')));
    });
  }

  private readDataBinary(ds: socket.TLSSocket, total: number,
    callbacks?: DownloadCallbacks): Promise<Uint8Array> {
    return new Promise<Uint8Array>((resolve: (value: Uint8Array) => void, reject: (reason: Error) => void) => {
      const chunks: Uint8Array[] = [];
      let received: number = 0;
      let settled: boolean = false;
      let lastReport: number = 0;
      const timer: number = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error('下载数据连接超时'));
        }
      }, 300000); // 5 分钟总超时，大文件友好
      const report = (force: boolean): void => {
        if (callbacks === undefined || callbacks.onProgress === undefined) return;
        const stepOk: boolean = total > 0
          ? (received - lastReport >= total / 100 || force)
          : (received - lastReport >= 262144 || force);
        if (!stepOk) return;
        lastReport = received;
        callbacks.onProgress(received, total);
      };
      ds.on('message', (info: socket.SocketMessageInfo) => {
        if (settled) return;
        const chunk: Uint8Array = new Uint8Array(info.message);
        chunks.push(chunk);
        received += chunk.byteLength;
        report(false);
      });
      ds.on('close', () => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        report(true);
        let totalBytes: number = 0;
        for (const c of chunks) totalBytes += c.byteLength;
        const result: Uint8Array = new Uint8Array(totalBytes);
        let off: number = 0;
        for (const c of chunks) { result.set(c, off); off += c.byteLength; }
        resolve(result);
      });
      ds.on('error', () => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        reject(new Error('数据连接错误'));
      });
    });
  }

  private async waitOkResponse(): Promise<void> {
    const r = await this.readResponse();
    if (!r.startsWith('2')) {
      console.warn('传输结束非预期: ' + r);
    }
  }

  private setupTlsListener(): void {
    if (this.tlsSocket === null) return;
    const self = this;
    this.tlsSocket.on('message', (info: socket.SocketMessageInfo) => {
      const dec = new util.TextDecoder('utf-8');
      self.responseBuffer += dec.decodeToString(new Uint8Array(info.message));
      self.drainResponse();
    });
  }

  private teardownTlsListener(): void {
    if (this.tlsSocket === null) return;
    try { this.tlsSocket.off('message'); } catch (_) {}
  }

  private drainResponse(): void {
    while (this.readPromise !== null) {
      const idx = this.responseBuffer.indexOf('\r\n');
      if (idx === -1) break;
      const line = this.responseBuffer.substring(0, idx).trim();
      this.responseBuffer = this.responseBuffer.substring(idx + 2);
      // RFC 959 §4.2 多行响应：
      //  - "ABC-" 后续行
      //  - "ABC " 结束行（第4位为空格）
      //  - "ABCx" 同码多行（理论上还有内容）
      // 跳过所有 "ABC-" 续行；非空格且非'-' 的一律视为"终结行"。
      if (line.length >= 4 && line[3] === '-') continue;
      if (line.length >= 4 && line[3] !== ' ') {
        // 形如 "220" 后面直接接文字（无空格分隔的旧服务器）：当作终结行
      }
      const rp = this.readPromise;
      this.readPromise = null;
      clearTimeout(rp.timer);
      rp.resolve(line);
    }
  }

  private async sendCommand(cmd: string): Promise<string> {
    if (this.tlsSocket === null) throw new Error('连接已断开');
    await this.tlsSocket.send(cmd + '\r\n');
    return await this.readResponse('等待命令响应超时: ' + cmd);
  }

  private async sendPlainCommand(cmd: string): Promise<string> {
    if (this.controlSocket === null) throw new Error('连接已断开');
    await this.controlSocket.send({ data: cmd + '\r\n' });
    return await this.readResponse('等待命令响应超时: ' + cmd);
  }

  private async startExplicitFtps(): Promise<string> {
    const tlsResp = await this.sendPlainCommand('AUTH TLS');
    if (tlsResp.startsWith('234')) {
      return tlsResp;
    }
    const sslResp = await this.sendPlainCommand('AUTH SSL');
    if (sslResp.startsWith('234')) {
      return sslResp;
    }
    return 'AUTH TLS返回: ' + tlsResp + '; AUTH SSL返回: ' + sslResp;
  }

  private setupControlListener(): void {
    if (this.controlSocket === null) return;
    const self = this;
    this.controlSocket.on('message', (info: socket.SocketMessageInfo) => {
      const dec = new util.TextDecoder('utf-8');
      self.responseBuffer += dec.decodeToString(new Uint8Array(info.message));
      self.drainResponse();
    });
  }

  private teardownControlListener(): void {
    if (this.controlSocket === null) return;
    try { this.controlSocket.off('message'); } catch (_) {}
  }

  private readResponse(timeoutMessage: string = '响应超时'): Promise<string> {
    if (this.readPromise !== null) {
      this.readPromise.reject(new Error('并发读取'));
      clearTimeout(this.readPromise.timer);
      this.readPromise = null;
    }
    const self = this;
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void) => {
      const timer: number = setTimeout(() => {
        self.readPromise = null;
        reject(new Error(timeoutMessage));
      }, RESPONSE_TIMEOUT_MS);
      self.readPromise = { resolve: resolve, reject: reject, timer: timer };
      self.drainResponse();
    });
  }

  private normalizeError(e: Object, prefix: string): Error {
    if (e instanceof Error) {
      const msg: string = e.message.length > 0 ? e.message : String(e);
      return new Error(prefix + ': ' + msg);
    }
    if (typeof e === 'string') {
      return new Error(prefix + ': ' + e);
    }
    // 业务异常对象兜底：尝试取 message 字段
    const maybe: Object = (e as Record<string, Object>)['message'];
    if (typeof maybe === 'string' && maybe.length > 0) {
      return new Error(prefix + ': ' + maybe);
    }
    try { return new Error(prefix + ': ' + JSON.stringify(e)); } catch (_) {
      return new Error(prefix);
    }
  }

  private parsePasv(resp: string): PasvResult {
    const m = resp.match(/\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)/);
    if (m === null) throw new Error('PASV解析失败: ' + resp);
    const result: PasvResult = new PasvResult();
    result.address = m[1] + '.' + m[2] + '.' + m[3] + '.' + m[4];
    result.port = parseInt(m[5], 10) * 256 + parseInt(m[6], 10);
    return result;
  }

  private parseEpsv(resp: string): PasvResult {
    const m = resp.match(/\(\|\|\|(\d+)\|\)/);
    if (m === null) throw new Error('EPSV解析失败: ' + resp);
    const result: PasvResult = new PasvResult();
    result.address = this.serverAddress;
    result.port = parseInt(m[1], 10);
    return result;
  }

  private parseListing(text: string, basePath: string, isMlsd: boolean): FileInfo[] {
    const entries: ParsedEntry[] = [];
    const lines: string[] = text.split('\n');
    for (const rawLine of lines) {
      const trimmed: string = rawLine.trim();
      if (trimmed === '') continue;
      let entry: ParsedEntry | null = null;
      if (isMlsd) {
        entry = this.parseMlsdLine(trimmed, basePath);
      } else {
        entry = this.parseUnixLine(trimmed, basePath);
        if (entry === null) entry = this.parseDosLine(trimmed, basePath);
      }
      if (entry !== null) entries.push(entry);
    }
    entries.sort((a: ParsedEntry, b: ParsedEntry) => {
      return b.modificationTime - a.modificationTime;
    });
    const result: FileInfo[] = [];
    for (const e of entries) {
      const fi: FileInfo = new FileInfo();
      fi.name = e.name;
      fi.path = e.path;
      fi.isDirectory = e.isDirectory;
      fi.size = e.size;
      fi.modificationTime = e.modificationTime;
      result.push(fi);
    }
    return result;
  }

  // MLSD 行示例：modify=20240101120000;size=1024;type=file; name.txt
  private parseMlsdLine(line: string, basePath: string): ParsedEntry | null {
    const spaceIdx: number = line.indexOf(' ');
    if (spaceIdx < 0) return null;
    const factsRaw: string = line.substring(0, spaceIdx);
    const nameRaw: string = line.substring(spaceIdx + 1).trim();
    if (nameRaw.length === 0) return null;
    const name: string = nameRaw.replace(/^"|"$/g, '');
    if (name === '.' || name === '..') return null;
    const facts: Record<string, string> = {};
    const parts: string[] = factsRaw.split(';');
    for (const part of parts) {
      const eq: number = part.indexOf('=');
      if (eq < 0) continue;
      const k: string = part.substring(0, eq).trim().toLowerCase();
      const v: string = part.substring(eq + 1).trim();
      if (k.length > 0) facts[k] = v;
    }
    const type: string = facts['type'] || '';
    if (type === 'cdir' || type === 'pdir') return null;
    const entry: ParsedEntry = new ParsedEntry();
    entry.name = name;
    entry.path = joinPath(basePath, name);
    entry.isDirectory = type === 'dir' || type === 'cdir' || type === 'pdir';
    entry.size = parseInt(facts['size'] || '0', 10) || 0;
    entry.modificationTime = parseMlsdTime(facts['modify'] || '');
    return entry;
  }

  // UNIX ls -l：drwxr-xr-x 2 user group 4096 Jan 2 03:04 dirname
  private parseUnixLine(line: string, basePath: string): ParsedEntry | null {
    const parts: string[] = line.split(/\s+/);
    if (parts.length < 9) return null;
    if (!/^[d-]/.test(parts[0])) return null;
    const name: string = parts.slice(8).join(' ');
    if (name === '.' || name === '..') return null;
    if (name.length === 0) return null;
    const entry: ParsedEntry = new ParsedEntry();
    entry.name = name;
    entry.path = joinPath(basePath, name);
    entry.isDirectory = parts[0].startsWith('d');
    entry.size = parseInt(parts[4], 10) || 0;
    entry.modificationTime = this.parseTime(parts[5], parts[6], parts[7]);
    return entry;
  }

  // Windows IIS DOS：02-14-24  03:04PM <DIR> dirname 或 02-14-24  03:04PM 1234 file.txt
  private parseDosLine(line: string, basePath: string): ParsedEntry | null {
    const m = line.match(/^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})(AM|PM)\s+(<DIR>|[\d]+)\s+(.+)$/i);
    if (m === null) return null;
    const name: string = m[8].trim();
    if (name === '.' || name === '..') return null;
    const entry: ParsedEntry = new ParsedEntry();
    entry.name = name;
    entry.path = joinPath(basePath, name);
    entry.isDirectory = m[7].toUpperCase() === '<DIR>';
    entry.size = entry.isDirectory ? 0 : (parseInt(m[7], 10) || 0);
    entry.modificationTime = this.parseDosTime(m[1], m[2], m[3], m[4], m[5], m[6]);
    return entry;
  }

  private parseTime(mon: string, day: string, tos: string): number {
    let monthNum: number = parseMonth(mon);
    const now: Date = new Date();
    const dayNum: number = parseInt(day, 10);
    if (isNaN(dayNum)) return -1;
    if (tos.includes(':')) {
      const colonIdx: number = tos.indexOf(':');
      const hours: number = parseInt(tos.substring(0, colonIdx), 10);
      const minutes: number = parseInt(tos.substring(colonIdx + 1), 10);
      if (isNaN(hours) || isNaN(minutes)) return -1;
      const d: Date = new Date(now.getFullYear(), monthNum, dayNum, hours, minutes);
      if (d.getTime() > Date.now()) {
        return new Date(now.getFullYear() - 1, monthNum, dayNum, hours, minutes).getTime();
      }
      return d.getTime();
    }
    const yearNum: number = parseInt(tos, 10);
    if (isNaN(yearNum)) return -1;
    return new Date(yearNum, monthNum, dayNum).getTime();
  }

  private parseDosTime(month: string, day: string, year: string, hour: string, minute: string, ampm: string): number {
    let monthNum: number = parseInt(month, 10);
    let dayNum: number = parseInt(day, 10);
    let yearNum: number = parseInt(year, 10);
    if (isNaN(monthNum) || isNaN(dayNum) || isNaN(yearNum)) return -1;
    if (yearNum < 100) yearNum += 2000;
    let hours: number = parseInt(hour, 10);
    const minutes: number = parseInt(minute, 10);
    if (isNaN(hours) || isNaN(minutes)) return -1;
    const ap: string = ampm.toUpperCase();
    if (ap === 'PM' && hours < 12) hours += 12;
    if (ap === 'AM' && hours === 12) hours = 0;
    const d: Date = new Date(yearNum, monthNum - 1, dayNum, hours, minutes);
    const t: number = d.getTime();
    return isNaN(t) ? -1 : t;
  }

  private cleanup(): void {
    this.teardownTlsListener();
    this.teardownControlListener();
    try { this.tlsSocket?.close(); } catch (_) {}
    try { this.controlSocket?.close(); } catch (_) {}
    try { this.dataSocket?.close(); } catch (_) {}
    this.tlsSocket = null;
    this.controlSocket = null;
    this.dataSocket = null;
    this.responseBuffer = '';
    if (this.readPromise !== null) {
      this.readPromise.reject(new Error('连接已关闭'));
      clearTimeout(this.readPromise.timer);
      this.readPromise = null;
    }
  }
}

// === 模块级纯函数（可独立单测） ===

function joinPath(basePath: string, name: string): string {
  if (basePath.endsWith('/')) return basePath + name;
  return basePath + '/' + name;
}

function parseMonth(mon: string): number {
  switch (mon) {
    case 'Jan': return 0;
    case 'Feb': return 1;
    case 'Mar': return 2;
    case 'Apr': return 3;
    case 'May': return 4;
    case 'Jun': return 5;
    case 'Jul': return 6;
    case 'Aug': return 7;
    case 'Sep': return 8;
    case 'Oct': return 9;
    case 'Nov': return 10;
    case 'Dec': return 11;
    default: return 0;
  }
}

// MLSD modify=YYYYMMDDHHMMSS → 毫秒
function parseMlsdTime(s: string): number {
  const m = s.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/);
  if (m === null) return -1;
  const yearNum: number = parseInt(m[1], 10);
  const monthNum: number = parseInt(m[2], 10) - 1;
  const dayNum: number = parseInt(m[3], 10);
  const hours: number = parseInt(m[4], 10);
  const minutes: number = parseInt(m[5], 10);
  const seconds: number = parseInt(m[6], 10);
  const t: number = new Date(yearNum, monthNum, dayNum, hours, minutes, seconds).getTime();
  return isNaN(t) ? -1 : t;
}
