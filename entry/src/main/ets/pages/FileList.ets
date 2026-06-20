import { promptAction, router } from '@kit.ArkUI';
import { common, wantConstant } from '@kit.AbilityKit';
import { fileIo, fileShare, fileUri, picker } from '@kit.CoreFileKit';
import { FtpsClient, DownloadCallbacks } from '../services/FtpsClient';
import {
  FileInfo,
  formatFileSize,
  formatDate,
  getFileIconLabel,
  getFileIconBgColor,
  getDownloadButtonColor,
  getNameWithoutExtension,
  getFileExtension
} from '../models/FileInfo';

const PAGE_SIZE = 30;

@Entry
@Component
struct FileList {
  @State files: FileInfo[] = [];
  @State allFiles: FileInfo[] = [];
  @State isLoading: boolean = false;
  @State currentPath: string = '/';
  @State currentPage: number = 0;
  @State errorMessage: string = '';
  @State downloadingFile: string = '';
  @State downloadProgress: number = 0;
  @State downloadSizeLabel: string = '';
  @State transferActionLabel: string = '下载';
  @State showExitDialog: boolean = false;
  @State loadingPath: string = '';

  private ftpsClient: FtpsClient = new FtpsClient();
  private serverAddress: string = '';
  private serverPort: number = 21;
  private username: string = '';
  private password: string = '';

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    this.serverAddress = params['serverAddress'] || '';
    this.serverPort = parseInt(params['serverPort'] || '21', 10);
    this.username = params['username'] || '';
    this.password = params['password'] || '';
    this.connectAndLoadFiles();
  }

  onBackPress(): boolean {
    if (this.downloadingFile.length > 0) return true;
    // 与左上「返回」按钮一致：非根目录返回上级，根目录弹退出确认
    this.goBackOrExit();
    return true;
  }

  async aboutToDisappear() {
    await this.ftpsClient.disconnect();
  }

  private isBusy(): boolean {
    return this.isLoading || this.downloadingFile.length > 0;
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Button('返回')
            .onClick(() => { this.goBackOrExit(); })
            .backgroundColor($r('app.color.btn_secondary_bg'))
            .fontColor($r('app.color.btn_secondary_text'))
            .height(40).margin({ left: 10 })
            .enabled(this.downloadingFile.length === 0)
            .opacity(this.downloadingFile.length > 0 ? 0.5 : 1)

          Text(this.currentPath)
            .fontSize(16).fontColor($r('app.color.text_primary')).margin({ left: 15 }).layoutWeight(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).maxLines(1)

          Button('登出')
            .onClick(() => { this.logout(); })
            .backgroundColor($r('app.color.btn_secondary_bg'))
            .fontColor($r('app.color.btn_secondary_text'))
            .height(40).margin({ right: 8 })
            .enabled(!this.isBusy())
            .opacity(this.isBusy() ? 0.5 : 1)

          Button('刷新')
            .onClick(() => { this.refreshFiles(); })
            .backgroundColor($r('app.color.btn_primary_bg'))
            .fontColor($r('app.color.btn_primary_text'))
            .height(40).margin({ right: 10 })
            .enabled(!this.isBusy())
            .opacity(this.isBusy() ? 0.5 : 1)
        }
        .width('100%').height(60).backgroundColor($r('app.color.card_bg'))
        .shadow({ radius: 2, color: $r('app.color.shadow'), offsetY: 2 })

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(14).fontColor($r('app.color.text_error'))
            .margin({ top: 10, left: 20, right: 20 }).textAlign(TextAlign.Center)
        }

        if (this.isLoading && this.files.length === 0) {
          Column() {
            LoadingProgress().width(60).height(60)
            Text('加载中...').fontSize(16).margin({ top: 15 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 2 }) {
            ForEach(this.files, (file: FileInfo) => {
              ListItem() {
                Row() {
                  Stack() {
                    Text(getFileIconLabel(file))
                      .fontSize(10)
                      .fontColor('#FFFFFF')
                      .fontWeight(FontWeight.Bold)
                  }
                  .width(36)
                  .height(36)
                  .borderRadius(8)
                  .backgroundColor(getFileIconBgColor(file))
                  .alignContent(Alignment.Center)
                  .margin({ right: 12 })

                  Column() {
                    Text(getNameWithoutExtension(file.name))
                      .fontSize(16).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
                      .textOverflow({ overflow: TextOverflow.None })
                      .maxLines(3)
                      .textAlign(TextAlign.Start)
                      .width('100%')

                    Row() {
                      Text(formatDate(file.modificationTime))
                        .fontSize(12).fontColor($r('app.color.text_secondary'))
                      if (!file.isDirectory) {
                        Text(formatFileSize(file.size))
                          .fontSize(12).fontColor($r('app.color.text_secondary')).margin({ left: 15 })
                      }
                    }
                    .margin({ top: 5 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (file.isDirectory && this.loadingPath === file.path) {
                    LoadingProgress()
                      .width(28)
                      .height(28)
                      .margin({ left: 8 })
                  }

                  if (!file.isDirectory) {
                    Column() {
                      Button('打开')
                        .onClick(() => { this.openRemoteFile(file); })
                        .height(34).fontSize(13)
                        .backgroundColor(getDownloadButtonColor(file))
                        .fontColor($r('app.color.btn_primary_text'))
                        .enabled(!this.isBusy())
                        .opacity(this.isBusy() ? 0.6 : 1)
                      Button('下载')
                        .onClick(() => { this.downloadFile(file); })
                        .height(34).fontSize(13)
                        .backgroundColor($r('app.color.btn_download_bg'))
                        .fontColor($r('app.color.btn_download_text'))
                        .enabled(!this.isBusy())
                        .opacity(this.isBusy() ? 0.6 : 1)
                        .margin({ top: 6 })
                    }
                    .width(72)
                  }
                }
                .width('100%').constraintSize({ minHeight: 70 }).padding({ left: 20, right: 20, top: 12, bottom: 12 })
                .backgroundColor($r('app.color.card_bg'))
                .opacity(this.isLoading ? 0.55 : 1)
              }
              .onClick(() => {
                if (file.isDirectory && !this.isBusy()) this.loadFiles(file.path);
              })
            })
          }
          .layoutWeight(1).width('100%').backgroundColor($r('app.color.page_bg'))
        }

        if (this.allFiles.length > PAGE_SIZE) {
          this.paginationBar()
        }

        if (this.downloadingFile.length > 0) {
          Column() {
            Text('正在' + this.transferActionLabel + ': ' + this.downloadingFile)
              .fontSize(14).fontColor($r('app.color.text_primary')).margin({ bottom: 6 })
            if (this.downloadSizeLabel.length > 0) {
              Text(this.downloadSizeLabel)
                .fontSize(12).fontColor($r('app.color.text_secondary')).margin({ bottom: 10 })
            }
            Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Linear })
              .width('90%').height(20)
          }
          .width('100%').padding(20).backgroundColor($r('app.color.card_bg'))
          .shadow({ radius: 2, color: $r('app.color.shadow'), offsetY: -2 })
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.page_bg'))

      if (this.showExitDialog) {
        this.exitDialogOverlay()
      }

      if (this.isLoading && this.files.length > 0) {
        this.loadingOverlay()
      }
    }
  }

  @Builder
  paginationBar() {
    Row() {
      Button('<')
        .onClick(() => { this.prevPage(); })
        .width(54).height(34).fontSize(18)
        .borderRadius(8)
        .backgroundColor($r('app.color.btn_secondary_bg'))
        .fontColor($r('app.color.btn_secondary_text'))
        .opacity(this.currentPage > 0 && !this.isBusy() ? 0.55 : 0.25)
        .enabled(this.currentPage > 0 && !this.isBusy())

      Text((this.currentPage + 1).toString() + ' / ' + this.totalPages().toString())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))

      Button('>')
        .onClick(() => { this.nextPage(); })
        .width(54).height(34).fontSize(18)
        .borderRadius(8)
        .backgroundColor($r('app.color.btn_secondary_bg'))
        .fontColor($r('app.color.btn_secondary_text'))
        .opacity(this.currentPage < this.totalPages() - 1 && !this.isBusy() ? 0.55 : 0.25)
        .enabled(this.currentPage < this.totalPages() - 1 && !this.isBusy())
    }
    .width('100%')
    .height(46)
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  exitDialogOverlay() {
    Column() {
      Column() {
        Text('确认退出').fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 20 })
        Text('确定要退出文件浏览器吗？').fontSize(16).margin({ bottom: 30 })
        Row() {
          Button('取消')
            .onClick(() => { this.showExitDialog = false; })
            .width('40%').height(45)
            .backgroundColor($r('app.color.btn_secondary_bg'))
            .fontColor($r('app.color.btn_secondary_text'))
          Button('确定退出')
            .onClick(() => { this.confirmExit(); })
            .width('40%').height(45)
            .backgroundColor($r('app.color.btn_danger_bg'))
            .fontColor($r('app.color.btn_primary_text'))
            .margin({ left: 20 })
        }
      }
      .width(320).padding(30).borderRadius(12).backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border') })
      .shadow({ radius: 10, color: $r('app.color.shadow') })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.scrim'))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  loadingOverlay() {
    Column() {
      Column() {
        LoadingProgress()
          .width(48)
          .height(48)
        Text('加载中...')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 10 })
      }
      .width(140)
      .height(120)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius(12)
      .shadow({ radius: 10, color: $r('app.color.shadow') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.scrim_light'))
  }

  private goBackOrExit(): void {
    if (this.downloadingFile.length > 0) return;
    if (this.currentPath === '/') {
      this.showExitDialog = true;
    } else {
      this.navigateUp();
    }
  }

  private async confirmExit(): Promise<void> {
    this.showExitDialog = false;
    await this.ftpsClient.disconnect();
    router.clear();
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.terminateSelf();
  }

  private async logout(): Promise<void> {
    if (this.isBusy()) return;
    await this.ftpsClient.disconnect();
    router.clear();
    router.replaceUrl({ url: 'pages/Main' });
  }

  async connectAndLoadFiles() {
    if (this.isLoading) return;
    this.isLoading = true;
    this.loadingPath = '/';
    this.errorMessage = '';
    try {
      await this.ftpsClient.connect(this.serverAddress, this.serverPort, this.username, this.password);
      this.allFiles = await this.ftpsClient.listFiles('/');
      this.currentPage = 0;
      this.updatePagedFiles();
      this.currentPath = '/';
    } catch (error) {
      this.errorMessage = this.toMessage(error, '连接失败');
    } finally {
      this.isLoading = false;
      this.loadingPath = '';
    }
  }

  async loadFiles(path: string) {
    if (this.isBusy()) return;
    this.isLoading = true;
    this.loadingPath = path;
    this.errorMessage = '';
    try {
      if (!this.ftpsClient.isConnected()) {
        await this.reconnectControl();
      }
      this.allFiles = await this.ftpsClient.listFiles(path);
      this.currentPage = 0;
      this.updatePagedFiles();
      this.currentPath = path;
    } catch (error) {
      try {
        await this.reconnectControl();
        this.allFiles = await this.ftpsClient.listFiles(path);
        this.currentPage = 0;
        this.updatePagedFiles();
        this.currentPath = path;
      } catch (retryError) {
        this.errorMessage = this.toMessage(retryError, '加载失败');
      }
    } finally {
      this.isLoading = false;
      this.loadingPath = '';
    }
  }

  private async reconnectControl(): Promise<void> {
    await this.ftpsClient.disconnect();
    this.ftpsClient = new FtpsClient();
    await this.ftpsClient.connect(this.serverAddress, this.serverPort, this.username, this.password);
  }

  async refreshFiles() {
    if (this.isBusy()) return;
    const targetPath = this.currentPath;
    this.isLoading = true;
    this.loadingPath = targetPath;
    this.errorMessage = '';
    try {
      await this.reconnectControl();
      this.allFiles = await this.ftpsClient.listFiles(targetPath);
      this.currentPage = 0;
      this.updatePagedFiles();
      this.currentPath = targetPath;
    } catch (error) {
      this.errorMessage = this.toMessage(error, '刷新失败');
    } finally {
      this.isLoading = false;
      this.loadingPath = '';
    }
  }

  navigateUp() {
    let parentPath = '/';
    const lastSlash = this.currentPath.lastIndexOf('/');
    if (lastSlash > 0) parentPath = this.currentPath.substring(0, lastSlash);
    this.loadFiles(parentPath);
  }

  private totalPages(): number {
    return Math.max(1, Math.ceil(this.allFiles.length / PAGE_SIZE));
  }

  private updatePagedFiles(): void {
    const total = this.totalPages();
    if (this.currentPage >= total) this.currentPage = total - 1;
    if (this.currentPage < 0) this.currentPage = 0;
    const start = this.currentPage * PAGE_SIZE;
    this.files = this.allFiles.slice(start, start + PAGE_SIZE);
  }

  private prevPage(): void {
    if (this.isBusy() || this.currentPage <= 0) return;
    this.currentPage--;
    this.updatePagedFiles();
  }

  private nextPage(): void {
    if (this.isBusy() || this.currentPage >= this.totalPages() - 1) return;
    this.currentPage++;
    this.updatePagedFiles();
  }

  private sanitizeFileName(name: string): string {
    let result = name.replace(/[\\/:*?"<>|]/g, '_');
    result = result.trim();
    if (result.length === 0) return 'download_file';
    return result;
  }

  private async pickSaveUri(fileName: string): Promise<string> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const documentPicker = new picker.DocumentViewPicker(ctx);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.autoCreateEmptyFile = false;
    const uris = await documentPicker.save(options);
    if (uris.length === 0) {
      return '';
    }
    return uris[0];
  }

  private async getOpenCacheUri(fileName: string): Promise<string> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const dirPath = ctx.cacheDir + '/ftps_open';
    try {
      await fileIo.mkdir(dirPath);
    } catch (_) {}
    const localPath = dirPath + '/' + fileName;
    return fileUri.getUriFromPath(localPath);
  }

  private async isExistingFile(uri: string, expectedSize: number): Promise<boolean> {
    try {
      const stat = await fileIo.stat(uri);
      return expectedSize > 0 && stat.size === expectedSize;
    } catch (_) {
      return false;
    }
  }

  private async openSavedFile(uri: string, fileName: string): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const policies: fileShare.PolicyInfo[] = [{
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE
    }];
    try {
      await fileShare.persistPermission(policies);
      await fileShare.activatePermission(policies);
    } catch (permissionError) {
      console.warn('持久化文件读取权限失败: ' +
        (permissionError instanceof Error ? permissionError.message : '未知错误'));
    }
    await ctx.startAbility({
      action: 'ohos.want.action.viewData',
      uri: uri,
      type: this.getMimeType(fileName),
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    });
  }

  private getMimeType(fileName: string): string {
    switch (getFileExtension(fileName)) {
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'bmp': return 'image/bmp';
      case 'webp': return 'image/webp';
      case 'svg': return 'image/svg+xml';
      case 'heic': return 'image/heic';
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'mkv': return 'video/x-matroska';
      case 'avi': return 'video/x-msvideo';
      case 'webm': return 'video/webm';
      case 'mp3': return 'audio/mpeg';
      case 'wav': return 'audio/wav';
      case 'flac': return 'audio/flac';
      case 'aac': return 'audio/aac';
      case 'm4a': return 'audio/mp4';
      case 'pdf': return 'application/pdf';
      case 'txt': return 'text/plain';
      case 'csv': return 'text/csv';
      case 'html': return 'text/html';
      case 'css': return 'text/css';
      case 'js': return 'text/javascript';
      case 'json': return 'application/json';
      case 'xml': return 'application/xml';
      case 'md':
      case 'markdown': return 'text/markdown';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'zip': return 'application/zip';
      case 'rar': return 'application/vnd.rar';
      case '7z': return 'application/x-7z-compressed';
      case 'tar': return 'application/x-tar';
      case 'gz': return 'application/gzip';
      default: return 'application/octet-stream';
    }
  }

  private toMessage(error: Object, prefix: string): string {
    if (error instanceof Error) return prefix + ': ' + error.message;
    return prefix;
  }

  private makeDownloadCallbacks(): DownloadCallbacks {
    return {
      onProgress: (received: number, total: number) => {
        if (total > 0) {
          this.downloadProgress = Math.min(99, Math.floor(received * 100 / total));
          this.downloadSizeLabel = formatFileSize(received) + ' / ' + formatFileSize(total);
        } else {
          this.downloadSizeLabel = formatFileSize(received);
        }
      }
    };
  }

  private beginTransfer(fileName: string, actionLabel: string): void {
    this.downloadingFile = fileName;
    this.transferActionLabel = actionLabel;
    this.downloadProgress = 0;
    this.downloadSizeLabel = '';
  }

  private endTransfer(): void {
    this.downloadingFile = '';
    this.downloadProgress = 0;
    this.downloadSizeLabel = '';
  }

  async downloadFile(file: FileInfo) {
    if (this.isBusy() || file.isDirectory) return;
    try {
      const fileName = this.sanitizeFileName(file.name);
      const saveUri = await this.pickSaveUri(fileName);
      if (saveUri.length === 0) {
        promptAction.showToast({ message: '已取消下载', duration: 1500 });
        return;
      }
      if (await this.isExistingFile(saveUri, file.size)) {
        this.errorMessage = '';
        promptAction.showToast({ message: '保存成功', duration: 1500 });
        return;
      }
      this.beginTransfer(file.name, '下载');
      await this.ftpsClient.downloadFile(file.path, saveUri, this.makeDownloadCallbacks());
      this.downloadProgress = 100;
      this.errorMessage = '';
      promptAction.showToast({ message: '下载完成', duration: 2000 });
    } catch (error) {
      await this.reconnectAfterTransferError();
      this.errorMessage = this.toMessage(error, '下载失败');
    } finally {
      this.endTransfer();
    }
  }

  async openRemoteFile(file: FileInfo) {
    if (this.isBusy() || file.isDirectory) return;
    let isSaved: boolean = false;
    try {
      const fileName = this.sanitizeFileName(file.name);
      const saveUri = await this.getOpenCacheUri(fileName);
      this.beginTransfer(file.name, '打开');
      await this.ftpsClient.downloadFile(file.path, saveUri, this.makeDownloadCallbacks());
      isSaved = true;
      this.downloadProgress = 100;
      this.errorMessage = '';
      await this.openSavedFile(saveUri, file.name);
    } catch (error) {
      if (!isSaved) {
        await this.reconnectAfterTransferError();
      }
      this.errorMessage = this.toMessage(error, '打开失败');
    } finally {
      this.endTransfer();
    }
  }

  private async reconnectAfterTransferError(): Promise<void> {
    try {
      await this.reconnectControl();
    } catch (reconnectError) {
      console.warn('下载失败后重连失败: ' + (reconnectError instanceof Error ? reconnectError.message : '未知错误'));
    }
  }
}
