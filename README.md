# HarmonyOS FTPS Client

基于 HarmonyOS NEXT 的 FTPS 文件浏览器应用。

## 功能特性

- 显式 FTPS 协议连接（端口 21，AUTH TLS）与隐式 FTPS（端口 990）
- TLS 协议优先 TLSv1.3，回退 TLSv1.2
- 用户名 / 密码认证
- 浏览远程服务器文件和文件夹（优先 MLSD，自动回退 LIST，兼容 UNIX / DOS 两种列表格式）
- 按修改时间排序（最新在前）
- 流式下载到用户选择的本地位置，边收边写避免 OOM，显示真实进度
- 只读模式
- 退出确认对话框
- 下载使用系统文档保存选择器，无需宽泛文件读写权限

## 使用方法

1. 使用 DevEco Studio 5.0+ 打开项目
2. 连接 HarmonyOS NEXT 设备或模拟器
3. 点击 Run 运行应用

## 首次构建

仓库未提交个人签名配置。首次构建：

1. 复制 `build-profile.template.json5` 为 `build-profile.json5`
2. 在 DevEco Studio 中打开 *Project Structure > Signing Configs*，让 IDE 自动填入
   `default` 签名材料（`build-profile.json5` 已被 `.gitignore` 忽略）

## 协议支持矩阵

| 模式 | 端口 | 握手 |
|---|---|---|
| 显式 FTPS | 21 | TCP → `AUTH TLS`（失败回退 `AUTH SSL`）→ TLS |
| 隐式 FTPS | 990 | 直接 TLS |

数据通道：`EPSV` 优先，失败回退 `PASV`；数据连接同样升级为 TLS。

## 工程结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets   入口 Ability
├── models/FileInfo.ets             文件模型、文件类型分类、格式化工具
├── pages/
│   ├── Index.ets                   连接页面（配置加载/保存、表单）
│   └── FileList.ets                文件浏览、目录导航、下载
└── services/FtpsClient.ets         FTPS socket 协议实现
```

## 隐私说明

应用仅申请 `ohos.permission.INTERNET` 权限用于连接 FTPS 服务器。

- 本地持久化（preferences）：服务器地址、端口、用户名
- **不保存密码**：每次启动应用密码输入框为空
- 下载文件位置由用户通过系统文档保存选择器自行选择，应用通过系统授予的 URI 写入
- 应用不收集、不上传任何用户数据到第三方服务
- 网络通信仅发生在用户与目标 FTPS 服务器之间

详见 [PRIVACY.md](./PRIVACY.md)。

## 相关文档

- [需求文档](./FTPS-Client-Requirements.md)
- [隐私政策](./PRIVACY.md)
