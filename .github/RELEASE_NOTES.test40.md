# 护眼之道 / GazeEase 1.1.0 · Build 40 测试版

## 下载与安装

**[下载 macOS 测试安装包](https://github.com/swaydong/GazeEase/releases/download/v1.1.0-test.40/GazeEase-1.1.0-build40-macos-test.zip)**

需要 macOS 14 或更高版本，包含 Apple 芯片和 Intel 双架构，无需 Xcode。

1. 解压 ZIP，将 `GazeEase.app` 拖入“应用程序”。
2. 从“应用程序”打开，按引导授予“输入监控”权限。
3. 首次可能提示无法验证开发者：只有确认下载来自本官方发布页且未被篡改，才按随包说明前往“系统设置 → 隐私与安全性 → 仍要打开”。

这是 **Apple Development 签名、未经 Apple 公证的预发布测试版**，不是 Developer ID 公证版。若系统提示“已损坏”或“会损害你的电脑”，请停止并反馈，不要关闭系统防护或移除隔离属性。公司管理的 Mac 可能不允许打开。

另一台干净 Mac 的首次安装验证尚未完成，不保证所有 Mac 都可运行。签名到期或被撤销后可能需要新包；当前没有自动更新。

请下载上面的 `macos-test.zip`，不是下面 GitHub 自动提供的 Source code 源码包。ZIP 已包含中英文安装说明、隐私说明及许可证；旁边的 `.sha256` 文件供可选完整性核验。完整步骤见[安装说明](https://github.com/swaydong/GazeEase/blob/v1.1.0-test.40/INSTALL.zh-CN.md)。

## 本版变化

- 提供无需 Xcode 的测试安装包。
- 分析和设置页标题简化为“分析”“设置”。
- 保留九套主题、随机换肤、今日疲劳曲线和低于 100% 暂停提醒的规则。
- 不新增权限、联网行为或数据采集；升级时仅替换 App，不清除偏好和历史。

## 验证范围

Build 40 的 209 项测试通过（0 失败、0 跳过）；Release 双架构静态分析通过。测试包采用原团队签名，移除开发调试权限及编译路径；最终 ZIP 已通过签名、架构和压缩包完整性检查。包内不含私人用眼记录、偏好、日志、私钥、设备 provisioning profile 或本机专用安装脚本。这不等同于另一台 Mac 的安装验证或第三方安全审计。

代码与文档采用 [MIT](https://github.com/swaydong/GazeEase/blob/v1.1.0-test.40/LICENSE)；皮肤、图标与品牌资源遵循[单独资产许可](https://github.com/swaydong/GazeEase/blob/v1.1.0-test.40/ASSETS.md)。

## English

[Download the macOS test app](https://github.com/swaydong/GazeEase/releases/download/v1.1.0-test.40/GazeEase-1.1.0-build40-macos-test.zip). Requires macOS 14+, with arm64 and x86_64 included. Extract the ZIP, drag `GazeEase.app` into Applications, then open it and follow the Input Monitoring guide. No Xcode is required.

This is an **Apple Development-signed, unnotarized prerelease**, not a Developer ID notarized release. Only if you trust the official source and have verified the download has not been altered should you use Apple's Open Anyway flow as described in the included guide. Stop if macOS reports damage or malware; do not disable system protections. Managed Macs may block the app.

A fresh installation on a separate Mac has **not yet been verified**. Signing expiration or revocation may require a new package. Updates are manual. Download the `macos-test.zip`, not GitHub's automatic Source code archives. Installation instructions, privacy documents, and license notices are inside the ZIP; the `.sha256` asset is optional for integrity verification.

Build 40 simplifies the Analytics and Settings titles without adding permissions, network behavior, or data collection. All 209 tests and universal Release static analysis passed. The packaged app is signed by the existing team with debug entitlements and local compiler paths removed; the final archive passed signature, architecture, and integrity checks. No personal usage history, preferences, logs, private keys, provisioning profiles, or local-only installer scripts are included. These checks do not establish compatibility on every Mac or constitute an independent security audit.
