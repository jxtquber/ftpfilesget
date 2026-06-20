import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { FileInfo } from '../models/FileInfo';

export interface WebDavDownloadCallbacks {
  onProgress?: (received: number, total: number) => void;
}

class WebDavEntry {
  href: string = '';
  name: string = '';
  isDirectory: boolean = false;
  size: number = 0;
  modificationTime: number = -1;
}

class WebDavTextResponse {
  status: number = 0;
  body: string = '';
}

class WebDavBinaryResponse {
  status: number = 0;
  body: ArrayBuffer = new ArrayBuffer(0);
}

export class WebDavClient {
  private baseUrl: string = '';
  private username: string = '';
  private password: string = '';
  private authHeader: string = '';

  connect(address: string, port: number, basePath: string, username: string, password: string): void {
    const path = normalizeBasePath(basePath);
    this.baseUrl = 'https://' + address + (port > 0 ? ':' + port.toString() : '') + path;
    this.username = username;
    this.password = password;
    this.authHeader = buildBasicAuth(username, password);
  }

  disconnect(): void {
    this.baseUrl = '';
    this.username = '';
    this.password = '';
    this.authHeader = '';
  }

  isConnected(): boolean {
    return this.baseUrl.length > 0 && this.username.length > 0;
  }

  async listFiles(path: string): Promise<FileInfo[]> {
    if (!this.isConnected()) throw new Error('未连接');
    const targetUrl = this.resolveUrl(path, true);
    const response = await this.requestText(targetUrl, 'PROPFIND', {
      'Depth': '1',
      'Content-Type': 'application/xml; charset=utf-8'
    }, '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:getcontentlength/><d:getlastmodified/><d:resourcetype/></d:prop></d:propfind>');
    if (response.status < 200 || response.status >= 300) {
      if (response.status === 405) {
        throw new Error('WebDAV目录请求被拒绝(405)。请确认NAS已开启WebDAV，并把路径填成真实入口，例如 /webdav/ 或共享目录对应的WebDAV路径。当前请求: ' + targetUrl);
      }
      throw new Error('PROPFIND失败: ' + response.status.toString() + '，当前请求: ' + targetUrl);
    }
    const entries = this.parseMultiStatus(response.body, path);
    entries.sort((a: WebDavEntry, b: WebDavEntry) => b.modificationTime - a.modificationTime);
    const result: FileInfo[] = [];
    for (const e of entries) {
      const fi = new FileInfo();
      fi.name = e.name;
      fi.path = e.href;
      fi.isDirectory = e.isDirectory;
      fi.size = e.size;
      fi.modificationTime = e.modificationTime;
      result.push(fi);
    }
    return result;
  }

  async downloadFile(remotePath: string, localUri: string, callbacks?: WebDavDownloadCallbacks): Promise<void> {
    if (!this.isConnected()) throw new Error('未连接');
    const targetUrl = this.resolveUrl(remotePath, false);
    const response = await this.requestBinary(targetUrl, 'GET');
    if (response.status < 200 || response.status >= 300) {
      throw new Error('GET失败: ' + response.status.toString());
    }
    const bytes = new Uint8Array(response.body);
    if (callbacks !== undefined && callbacks.onProgress !== undefined) {
      callbacks.onProgress(bytes.byteLength, bytes.byteLength);
    }
    const file = await fs.open(localUri, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, bytes.buffer);
    } finally {
      try { await fs.close(file.fd); } catch (_) {}
    }
  }

  private async requestText(url: string, method: string, headers: Record<string, string>, body: string): Promise<WebDavTextResponse> {
    const request = http.createHttp();
    try {
      const mergedHeaders = this.buildHeaders(headers);
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        customMethod: method,
        header: mergedHeaders,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000,
        remoteValidation: 'skip'
      });
      const result = new WebDavTextResponse();
      result.status = response.responseCode as number;
      result.body = String(response.result);
      return result;
    } catch (error) {
      throw new Error(this.toRequestError(error, method, url));
    } finally {
      request.destroy();
    }
  }

  private async requestBinary(url: string, method: string): Promise<WebDavBinaryResponse> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: method as http.RequestMethod,
        header: this.buildHeaders({}),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 300000,
        remoteValidation: 'skip'
      });
      const result = new WebDavBinaryResponse();
      result.status = response.responseCode as number;
      result.body = response.result as ArrayBuffer;
      return result;
    } catch (error) {
      throw new Error(this.toRequestError(error, method, url));
    } finally {
      request.destroy();
    }
  }

  private toRequestError(error: Object, method: string, url: string): string {
    let detail = '未知错误';
    if (error instanceof Error) {
      detail = error.message;
    } else {
      detail = JSON.stringify(error);
    }
    if (detail.indexOf('2300060') >= 0 || detail.indexOf('SSL') >= 0 || detail.indexOf('certificate') >= 0) {
      return method + '连接失败: HTTPS证书校验失败。NAS如果使用自签名证书，需要先把证书安装到系统信任，或改用受信任证书。当前请求: ' + url + '，详情: ' + detail;
    }
    return method + '连接失败，当前请求: ' + url + '，详情: ' + detail;
  }

  private buildHeaders(headers: Record<string, string>): Record<string, string> {
    const result: Record<string, string> = {};
    result['Authorization'] = this.authHeader;
    result['Accept'] = '*/*';
    for (const key of Object.keys(headers)) {
      result[key] = headers[key];
    }
    return result;
  }

  private resolveUrl(path: string, directory: boolean): string {
    let relative = path;
    if (relative.length === 0 || relative === '/') {
      relative = '/';
    }
    if (!relative.startsWith('/')) {
      relative = '/' + relative;
    }
    const base = this.baseUrl.endsWith('/') ? this.baseUrl.substring(0, this.baseUrl.length - 1) : this.baseUrl;
    let url = base + encodePath(relative);
    if (directory && !url.endsWith('/')) url += '/';
    return url;
  }

  private parseMultiStatus(xml: string, requestPath: string): WebDavEntry[] {
    const result: WebDavEntry[] = [];
    const responseRegex = /<[^:>]*:?response[\s\S]*?<\/[^:>]*:?response>/g;
    const matches = xml.match(responseRegex) || [];
    const current = normalizeHref(requestPath);
    for (const block of matches) {
      const href = decodeXml(extractTag(block, 'href'));
      if (href.length === 0) continue;
      const hrefIsDirectory = href.endsWith('/');
      let normalizedHref = normalizeHref(stripBasePathFromHref(href, this.baseUrl));
      if (normalizedHref === current || normalizedHref === current + '/') continue;
      normalizedHref = decodePath(normalizedHref);
      if (normalizedHref === current || normalizedHref === current + '/') continue;
      const name = lastPathSegment(normalizedHref);
      if (name.length === 0) continue;
      const entry = new WebDavEntry();
      entry.href = hrefIsDirectory ? ensureTrailingSlash(normalizedHref) : normalizedHref;
      entry.name = name;
      entry.isDirectory = hrefIsDirectory || /<[^:>]*:?collection[\s\S]*?\/[^>]*>|<[^:>]*:?collection\s*\/?>/.test(block);
      entry.size = parseInt(extractTag(block, 'getcontentlength') || '0', 10) || 0;
      entry.modificationTime = parseHttpDate(extractTag(block, 'getlastmodified'));
      result.push(entry);
    }
    return result;
  }
}

function buildBasicAuth(username: string, password: string): string {
  const encoder = new util.TextEncoder();
  const helper = new util.Base64Helper();
  return 'Basic ' + helper.encodeToStringSync(encoder.encode(username + ':' + password));
}

function normalizeBasePath(path: string): string {
  let result = path.trim();
  if (result.length === 0) return '/';
  if (!result.startsWith('/')) result = '/' + result;
  if (!result.endsWith('/')) result += '/';
  return result;
}

function encodePath(path: string): string {
  const parts = path.split('/');
  const encoded: string[] = [];
  for (const part of parts) {
    encoded.push(encodeURIComponent(part));
  }
  return encoded.join('/');
}

function normalizeHref(href: string): string {
  let result = href;
  if (result.length === 0) return '/';
  if (!result.startsWith('/')) result = '/' + result;
  return result;
}

function ensureTrailingSlash(path: string): string {
  if (path.endsWith('/')) return path;
  return path + '/';
}

function decodePath(path: string): string {
  const parts = path.split('/');
  const decoded: string[] = [];
  for (const part of parts) {
    try {
      decoded.push(decodeURIComponent(part));
    } catch (_) {
      decoded.push(part);
    }
  }
  return decoded.join('/');
}

function stripBasePathFromHref(href: string, baseUrl: string): string {
  let result = href;
  const schemeIdx = result.indexOf('://');
  if (schemeIdx >= 0) {
    const pathIdx = result.indexOf('/', schemeIdx + 3);
    result = pathIdx >= 0 ? result.substring(pathIdx) : '/';
  }
  const basePath = getPathFromUrl(baseUrl);
  if (basePath !== '/' && result.startsWith(basePath)) {
    result = result.substring(basePath.length - 1);
  }
  return result;
}

function getPathFromUrl(url: string): string {
  const schemeIdx = url.indexOf('://');
  const searchStart = schemeIdx >= 0 ? schemeIdx + 3 : 0;
  const pathIdx = url.indexOf('/', searchStart);
  if (pathIdx < 0) return '/';
  return normalizeBasePath(url.substring(pathIdx));
}

function lastPathSegment(path: string): string {
  let trimmed = path;
  if (trimmed.endsWith('/')) trimmed = trimmed.substring(0, trimmed.length - 1);
  const idx = trimmed.lastIndexOf('/');
  return idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
}

function extractTag(xml: string, tag: string): string {
  const regex = new RegExp('<[^:>]*:?' + tag + '[^>]*>([\\s\\S]*?)<\\/[^:>]*:?' + tag + '>', 'i');
  const match = xml.match(regex);
  return match === null ? '' : match[1].trim();
}

function decodeXml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'');
}

function parseHttpDate(value: string): number {
  if (value.length === 0) return -1;
  const t = new Date(value).getTime();
  return isNaN(t) ? -1 : t;
}
