import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const FTPS_PREF_NAME = 'ftps_config';
const WEBDAV_PREF_NAME = 'webdav_config';
const DEFAULT_ADDRESS = '192.168.1.101';
const DEFAULT_FTPS_PORT = '21';
const DEFAULT_WEBDAV_PORT = '5006';
const DEFAULT_USERNAME = 'ftpuser';
const DEFAULT_PASSWORD = 'jxt19851009';
const DEFAULT_WEBDAV_PATH = '/';
const OLD_DEFAULT_USERNAME = 'jxtquber';

@Entry
@Component
struct Main {
  @State ftpsAddress: string = DEFAULT_ADDRESS;
  @State ftpsPort: string = DEFAULT_FTPS_PORT;
  @State ftpsUsername: string = DEFAULT_USERNAME;
  @State ftpsPassword: string = DEFAULT_PASSWORD;
  @State webDavAddress: string = DEFAULT_ADDRESS;
  @State webDavPort: string = DEFAULT_WEBDAV_PORT;
  @State webDavPath: string = DEFAULT_WEBDAV_PATH;
  @State webDavUsername: string = DEFAULT_USERNAME;
  @State webDavPassword: string = DEFAULT_PASSWORD;
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State showExitDialog: boolean = false;
  @State showFtpsAddressDropdown: boolean = false;
  @State showWebDavAddressDropdown: boolean = false;

  aboutToAppear(): void {
    this.loadSavedConfig();
  }

  onBackPress(): boolean {
    this.showExitDialog = true;
    return true;
  }

  private async loadSavedConfig(): Promise<void> {
    try {
      const ctx = getContext(this);
      const ftpsStore = await preferences.getPreferences(ctx, FTPS_PREF_NAME);
      const ftpsAddr = await ftpsStore.get('address', DEFAULT_ADDRESS);
      const ftpsPort = await ftpsStore.get('port', DEFAULT_FTPS_PORT);
      const ftpsUser = await ftpsStore.get('username', DEFAULT_USERNAME);
      this.ftpsAddress = typeof ftpsAddr === 'string' ? ftpsAddr : DEFAULT_ADDRESS;
      this.ftpsPort = typeof ftpsPort === 'string' ? ftpsPort : DEFAULT_FTPS_PORT;
      this.ftpsUsername = this.normalizeUsername(ftpsUser);
      this.ftpsPassword = DEFAULT_PASSWORD;
    } catch (_) {}

    try {
      const ctx = getContext(this);
      const webDavStore = await preferences.getPreferences(ctx, WEBDAV_PREF_NAME);
      const webDavAddr = await webDavStore.get('address', DEFAULT_ADDRESS);
      const webDavPort = await webDavStore.get('port', DEFAULT_WEBDAV_PORT);
      const webDavPath = await webDavStore.get('basePath', DEFAULT_WEBDAV_PATH);
      const webDavUser = await webDavStore.get('username', DEFAULT_USERNAME);
      this.webDavAddress = typeof webDavAddr === 'string' ? webDavAddr : DEFAULT_ADDRESS;
      this.webDavPort = typeof webDavPort === 'string' ? webDavPort : DEFAULT_WEBDAV_PORT;
      this.webDavPath = this.normalizeWebDavPath(webDavPath);
      this.webDavUsername = this.normalizeUsername(webDavUser);
      this.webDavPassword = DEFAULT_PASSWORD;
    } catch (_) {}
  }

  private normalizeWebDavPath(value: preferences.ValueType): string {
    if (typeof value !== 'string' || value.length === 0 || value === '/webdav/') {
      return DEFAULT_WEBDAV_PATH;
    }
    return value;
  }

  private normalizeUsername(value: preferences.ValueType): string {
    if (typeof value !== 'string') return DEFAULT_USERNAME;
    if (value.length === 0 || value === OLD_DEFAULT_USERNAME) return DEFAULT_USERNAME;
    return value;
  }

  private async saveFtpsConfig(): Promise<void> {
    try {
      const ctx = getContext(this);
      const store = await preferences.getPreferences(ctx, FTPS_PREF_NAME);
      await store.put('address', this.ftpsAddress);
      await store.put('port', this.ftpsPort);
      await store.put('username', this.ftpsUsername);
      await store.flush();
    } catch (_) {}
  }

  private async saveWebDavConfig(): Promise<void> {
    try {
      const ctx = getContext(this);
      const store = await preferences.getPreferences(ctx, WEBDAV_PREF_NAME);
      await store.put('address', this.webDavAddress);
      await store.put('port', this.webDavPort);
      await store.put('basePath', this.webDavPath);
      await store.put('username', this.webDavUsername);
      await store.flush();
    } catch (_) {}
  }

  build() {
    Stack() {
      Tabs({ barPosition: BarPosition.End, index: 1 }) {
        TabContent() {
          this.ftpsPage()
        }
        .tabBar('FTPS')

        TabContent() {
          this.webDavPage()
        }
        .tabBar('WebDAV')
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_bg'))

      if (this.showExitDialog) {
        this.exitDialogOverlay()
      }
    }
  }

  @Builder
  ftpsPage() {
    Column() {
      Text('FTPS 文件浏览器')
        .fontSize(30).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 }).textAlign(TextAlign.Center)

      Text('连接并浏览远程文件')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 28 })

      Column() {
        this.addressInputRow('IP地址', this.ftpsAddress, true)
        this.portInputRow('端口号', '端口 (默认21 显式FTPS)', this.ftpsPort, true)
        this.usernameInputRow('用户名', this.ftpsUsername, true)
        this.passwordInputRow('密码', this.ftpsPassword, true)
        this.errorView()

        Button('连接服务器')
          .onClick(() => { this.connectFtps(); })
          .width('100%').height(50).fontSize(18).fontWeight(FontWeight.Medium)
          .borderRadius(8).backgroundColor($r('app.color.btn_primary_bg'))
          .fontColor($r('app.color.btn_primary_text'))
          .enabled(!this.isLoading && this.ftpsAddress.length > 0 && this.ftpsPassword.length > 0)
          .opacity(this.isLoading ? 0.6 : 1)

        if (this.isLoading) {
          LoadingProgress().width(46).height(46).margin({ top: 18 })
        }
      }
      .width('90%')
      .padding({ left: 18, right: 18, top: 22, bottom: 22 })
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius(14)
      .shadow({ radius: 12, color: $r('app.color.shadow'), offsetY: 4 })
    }
    .width('100%').height('100%')
    .padding({ left: 16, right: 16, bottom: 52 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  webDavPage() {
    Column() {
      Text('WebDAV')
        .fontSize(30).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 }).textAlign(TextAlign.Center)

      Text('通过 HTTPS 访问 NAS 文件')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 28 })

      Column() {
        this.addressInputRow('IP地址', this.webDavAddress, false)
        this.portInputRow('端口号', '端口 (默认5006 HTTPS)', this.webDavPort, false)
        this.webDavPathInputRow()
        this.usernameInputRow('用户名', this.webDavUsername, false)
        this.passwordInputRow('密码', this.webDavPassword, false)
        this.errorView()

        Button('连接服务器')
          .onClick(() => { this.connectWebDav(); })
          .width('100%').height(50).fontSize(18).fontWeight(FontWeight.Medium)
          .borderRadius(8).backgroundColor($r('app.color.btn_primary_bg'))
          .fontColor($r('app.color.btn_primary_text'))
          .enabled(!this.isLoading && this.webDavAddress.length > 0 && this.webDavPassword.length > 0)
          .opacity(this.isLoading ? 0.6 : 1)

        if (this.isLoading) {
          LoadingProgress().width(46).height(46).margin({ top: 18 })
        }
      }
      .width('90%')
      .padding({ left: 18, right: 18, top: 22, bottom: 22 })
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius(14)
      .shadow({ radius: 12, color: $r('app.color.shadow'), offsetY: 4 })
    }
    .width('100%').height('100%')
    .padding({ left: 16, right: 16, bottom: 52 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  errorView() {
    if (this.errorMessage.length > 0) {
      Text(this.errorMessage)
        .fontSize(14).fontColor($r('app.color.text_error'))
        .width('100%')
        .margin({ bottom: 14 }).textAlign(TextAlign.Center)
    }
  }

  @Builder
  addressInputRow(label: string, value: string, isFtps: boolean) {
    Column() {
      Row() {
        Text(label)
          .fontSize(15).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
          .width(76).textAlign(TextAlign.Start)
        Column() {
          Row() {
            TextInput({ placeholder: '服务器地址', text: isFtps ? this.ftpsAddress : this.webDavAddress })
              .onChange((v: string) => {
                if (isFtps) {
                  this.ftpsAddress = v;
                } else {
                  this.webDavAddress = v;
                }
              })
              .height(50).layoutWeight(1).borderRadius(8).backgroundColor($r('app.color.input_bg'))
            Button((isFtps ? this.showFtpsAddressDropdown : this.showWebDavAddressDropdown) ? '∧' : '∨')
              .onClick(() => {
                if (isFtps) {
                  this.showFtpsAddressDropdown = !this.showFtpsAddressDropdown;
                } else {
                  this.showWebDavAddressDropdown = !this.showWebDavAddressDropdown;
                }
              })
              .height(50).width(48)
              .backgroundColor($r('app.color.input_bg'))
              .fontColor($r('app.color.text_primary'))
              .fontSize(22)
          }
          .width('100%')
          .height(50)
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(8)
          .border({ width: 1, color: (isFtps ? this.showFtpsAddressDropdown : this.showWebDavAddressDropdown) ? $r('app.color.btn_primary_bg') : $r('app.color.border') })

          if (isFtps ? this.showFtpsAddressDropdown : this.showWebDavAddressDropdown) {
            Column({ space: 6 }) {
              this.addressOption('192.168.1.101', isFtps)
              this.addressOption('juneinter.site', isFtps)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(8)
          }
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .margin({ bottom: 15 })
  }

  @Builder
  addressOption(address: string, isFtps: boolean) {
    Button(address)
      .onClick(() => {
        if (isFtps) {
          this.selectFtpsAddress(address);
        } else {
          this.selectWebDavAddress(address);
        }
      })
      .width('100%').height(40)
      .backgroundColor($r('app.color.dropdown_bg'))
      .fontColor($r('app.color.dropdown_text'))
  }

  private selectFtpsAddress(address: string): void {
    this.ftpsAddress = address;
    this.ftpsPort = DEFAULT_FTPS_PORT;
    this.ftpsUsername = DEFAULT_USERNAME;
    this.ftpsPassword = DEFAULT_PASSWORD;
    this.showFtpsAddressDropdown = false;
  }

  private selectWebDavAddress(address: string): void {
    this.webDavAddress = address;
    this.webDavPort = DEFAULT_WEBDAV_PORT;
    this.webDavPath = DEFAULT_WEBDAV_PATH;
    this.webDavUsername = DEFAULT_USERNAME;
    this.webDavPassword = DEFAULT_PASSWORD;
    this.showWebDavAddressDropdown = false;
  }

  @Builder
  portInputRow(label: string, placeholder: string, value: string, isFtps: boolean) {
    Row() {
      Text(label)
        .fontSize(15).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
        .width(76).textAlign(TextAlign.Start)
      TextInput({ placeholder: placeholder, text: value })
        .onChange((v: string) => {
          if (isFtps) {
            this.ftpsPort = v;
          } else {
            this.webDavPort = v;
          }
        })
        .type(InputType.Number)
        .height(50).layoutWeight(1).borderRadius(8).backgroundColor($r('app.color.input_bg'))
    }
    .margin({ bottom: 15 })
  }

  @Builder
  webDavPathInputRow() {
    Row() {
      Text('路径')
        .fontSize(15).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
        .width(76).textAlign(TextAlign.Start)
      TextInput({ placeholder: 'WebDAV基础路径，默认 /', text: this.webDavPath })
        .onChange((v: string) => { this.webDavPath = v; })
        .height(50).layoutWeight(1).borderRadius(8).backgroundColor($r('app.color.input_bg'))
    }
    .margin({ bottom: 15 })
  }

  @Builder
  usernameInputRow(label: string, value: string, isFtps: boolean) {
    Row() {
      Text(label)
        .fontSize(15).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
        .width(76).textAlign(TextAlign.Start)
      TextInput({ placeholder: '用户名', text: value })
        .onChange((v: string) => {
          if (isFtps) {
            this.ftpsUsername = v;
          } else {
            this.webDavUsername = v;
          }
        })
        .type(InputType.Normal)
        .height(50).layoutWeight(1).borderRadius(8).backgroundColor($r('app.color.input_bg'))
    }
    .margin({ bottom: 15 })
  }

  @Builder
  passwordInputRow(label: string, value: string, isFtps: boolean) {
    Row() {
      Text(label)
        .fontSize(15).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
        .width(76).textAlign(TextAlign.Start)
      TextInput({ placeholder: '密码', text: value })
        .onChange((v: string) => {
          if (isFtps) {
            this.ftpsPassword = v;
          } else {
            this.webDavPassword = v;
          }
        })
        .type(InputType.Password)
        .height(50).layoutWeight(1).borderRadius(8).backgroundColor($r('app.color.input_bg'))
    }
    .margin({ bottom: 20 })
  }

  @Builder
  exitDialogOverlay() {
    Column() {
      Column() {
        Text('确定要退出吗？').fontSize(18).fontWeight(FontWeight.Medium).margin({ bottom: 24 })
        Row() {
          Button('取消').width(120).height(42)
            .backgroundColor($r('app.color.btn_secondary_bg'))
            .fontColor($r('app.color.btn_secondary_text'))
            .borderRadius(8).fontSize(15)
            .onClick(() => { this.showExitDialog = false; }).margin({ right: 12 })
          Button('退出').width(120).height(42)
            .backgroundColor($r('app.color.btn_danger_bg'))
            .fontColor($r('app.color.btn_primary_text'))
            .borderRadius(8).fontSize(15)
            .onClick(() => { this.confirmExit(); })
        }
      }
      .width(280).padding(28).backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius(16).alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.scrim'))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private confirmExit(): void {
    this.showExitDialog = false;
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.terminateSelf();
  }

  async connectFtps() {
    if (this.ftpsAddress.length === 0) {
      this.errorMessage = '请输入服务器地址';
      return;
    }
    if (this.ftpsPassword.length === 0) {
      this.errorMessage = '请输入密码';
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    const port = parseInt(this.ftpsPort, 10) || 21;
    try {
      await this.saveFtpsConfig();
      router.pushUrl({
        url: 'pages/FileList',
        params: {
          serverAddress: this.ftpsAddress,
          serverPort: port.toString(),
          username: this.ftpsUsername,
          password: this.ftpsPassword
        }
      });
    } catch (error) {
      this.errorMessage = error instanceof Error ? '连接失败: ' + error.message : '连接失败';
    } finally {
      this.isLoading = false;
    }
  }

  async connectWebDav() {
    if (this.webDavAddress.length === 0) {
      this.errorMessage = '请输入服务器地址';
      return;
    }
    if (this.webDavPassword.length === 0) {
      this.errorMessage = '请输入密码';
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    const port = parseInt(this.webDavPort, 10) || 5006;
    try {
      await this.saveWebDavConfig();
      router.pushUrl({
        url: 'pages/WebDavFileList',
        params: {
          serverAddress: this.webDavAddress,
          serverPort: port.toString(),
          basePath: this.webDavPath,
          username: this.webDavUsername,
          password: this.webDavPassword
        }
      });
    } catch (error) {
      this.errorMessage = error instanceof Error ? '连接失败: ' + error.message : '连接失败';
    } finally {
      this.isLoading = false;
    }
  }
}
