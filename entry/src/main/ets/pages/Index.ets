import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREF_NAME = 'ftps_config';
const DEFAULT_ADDRESS = '192.168.1.101';
const DEFAULT_PORT = '21';
const DEFAULT_USERNAME = 'ftpuser';
const DEFAULT_PASSWORD = 'jxt19851009';

@Entry
@Component
struct Index {
  @State serverAddress: string = DEFAULT_ADDRESS;
  @State serverPort: string = DEFAULT_PORT;
  @State username: string = DEFAULT_USERNAME;
  @State password: string = DEFAULT_PASSWORD;
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State showExitDialog: boolean = false;
  @State showAddressDropdown: boolean = false;

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
      const store = await preferences.getPreferences(ctx, PREF_NAME);
      const addr = await store.get('address', DEFAULT_ADDRESS);
      const port = await store.get('port', DEFAULT_PORT);
      const user = await store.get('username', DEFAULT_USERNAME);
      this.serverAddress = typeof addr === 'string' ? addr : DEFAULT_ADDRESS;
      this.serverPort = typeof port === 'string' ? port : DEFAULT_PORT;
      this.username = typeof user === 'string' ? user : DEFAULT_USERNAME;
      this.password = DEFAULT_PASSWORD;
    } catch (_) {}
  }

  private async saveConfig(): Promise<void> {
    try {
      const ctx = getContext(this);
      const store = await preferences.getPreferences(ctx, PREF_NAME);
      await store.put('address', this.serverAddress);
      await store.put('port', this.serverPort);
      await store.put('username', this.username);
      await store.flush();
    } catch (_) {}
  }

  build() {
    Column() {
      Text('FTPS文件浏览器')
        .fontSize(30).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 }).textAlign(TextAlign.Center)

      Text('连接并浏览远程文件')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 28 })

      Column() {
        this.addressInputRow()
        this.portInputRow()
        this.usernameInputRow()
        this.passwordInputRow()

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(14).fontColor($r('app.color.text_error'))
            .width('100%')
            .margin({ bottom: 14 }).textAlign(TextAlign.Center)
        }

        Button('连接服务器')
          .onClick(() => { this.connectToServer(); })
          .width('100%').height(50).fontSize(18).fontWeight(FontWeight.Medium)
          .borderRadius(8).backgroundColor($r('app.color.btn_primary_bg'))
          .fontColor($r('app.color.btn_primary_text'))
          .enabled(!this.isLoading && this.serverAddress.length > 0 && this.password.length > 0)
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
    .padding({ left: 16, right: 16 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
    .bindContentCover($$this.showExitDialog, this.exitDialogBuilder(),
      { backgroundColor: $r('app.color.scrim'), modalTransition: ModalTransition.ALPHA })
  }

  @Builder
  exitDialogBuilder() {
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
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private confirmExit(): void {
    this.showExitDialog = false;
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.terminateSelf();
  }

  @Builder
  addressInputRow() {
    Column() {
      Row() {
        Text('IP地址')
          .fontSize(15).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
          .width(76).textAlign(TextAlign.Start)
        Column() {
          Row() {
            TextInput({ placeholder: '服务器地址', text: this.serverAddress })
              .onChange((v: string) => { this.serverAddress = v; })
              .height(50).layoutWeight(1).borderRadius(8).backgroundColor($r('app.color.input_bg'))
            Button(this.showAddressDropdown ? '⌃' : '⌄')
              .onClick(() => { this.showAddressDropdown = !this.showAddressDropdown; })
              .height(50).width(48)
              .backgroundColor($r('app.color.input_bg'))
              .fontColor($r('app.color.text_primary'))
              .fontSize(20)
          }
          .width('100%')
          .height(50)
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(8)
          .border({ width: 1, color: this.showAddressDropdown ? $r('app.color.btn_primary_bg') : $r('app.color.border') })

          if (this.showAddressDropdown) {
            Column() {
              Button('192.168.1.101')
                .onClick(() => {
                  this.serverAddress = '192.168.1.101';
                  this.showAddressDropdown = false;
                })
                .width('100%').height(38)
                .backgroundColor($r('app.color.dropdown_bg'))
                .fontColor($r('app.color.dropdown_text'))
              Button('juneinter.site')
                .onClick(() => {
                  this.serverAddress = 'juneinter.site';
                  this.showAddressDropdown = false;
                })
                .width('100%').height(38).margin({ top: 6 })
                .backgroundColor($r('app.color.dropdown_bg'))
                .fontColor($r('app.color.dropdown_text'))
            }
            .width('100%')
            .padding({ top: 8 })
          }
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .margin({ bottom: 15 })
  }

  @Builder
  portInputRow() {
    Row() {
      Text('端口号')
        .fontSize(15).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
        .width(76).textAlign(TextAlign.Start)
      TextInput({ placeholder: '端口 (默认21 显式FTPS)', text: this.serverPort })
        .onChange((v: string) => { this.serverPort = v; })
        .type(InputType.Number)
        .height(50).layoutWeight(1).borderRadius(8).backgroundColor($r('app.color.input_bg'))
    }
    .margin({ bottom: 15 })
  }

  @Builder
  usernameInputRow() {
    Row() {
      Text('用户名')
        .fontSize(15).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
        .width(76).textAlign(TextAlign.Start)
      TextInput({ placeholder: '用户名', text: this.username })
        .onChange((v: string) => { this.username = v; })
        .type(InputType.Normal)
        .height(50).layoutWeight(1).borderRadius(8).backgroundColor($r('app.color.input_bg'))
    }
    .margin({ bottom: 15 })
  }

  @Builder
  passwordInputRow() {
    Row() {
      Text('密码')
        .fontSize(15).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
        .width(76).textAlign(TextAlign.Start)
      TextInput({ placeholder: '密码', text: this.password })
        .onChange((v: string) => { this.password = v; })
        .type(InputType.Password)
        .height(50).layoutWeight(1).borderRadius(8).backgroundColor($r('app.color.input_bg'))
    }
    .margin({ bottom: 20 })
  }

  async connectToServer() {
    if (this.serverAddress.length === 0) {
      this.errorMessage = '请输入服务器地址';
      return;
    }
    if (this.password.length === 0) {
      this.errorMessage = '请输入密码';
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    const port = parseInt(this.serverPort, 10) || 21;
    try {
      // 仅持久化表单配置；实际连接放到 FileList 页面统一处理，避免重复握手。
      await this.saveConfig();
      router.pushUrl({
        url: 'pages/FileList',
        params: {
          serverAddress: this.serverAddress,
          serverPort: port.toString(),
          username: this.username,
          password: this.password
        }
      });
    } catch (error) {
      this.errorMessage = error instanceof Error ? '连接失败: ' + error.message : '连接失败';
    } finally {
      this.isLoading = false;
    }
  }
}
