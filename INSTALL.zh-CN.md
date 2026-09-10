# 护眼之道安装、升级与卸载

[English](INSTALL.md) · 简体中文

## 下载并安装测试版

护眼之道（GazeEase）Version `1.1.0`、Build `40` 现提供**未经公证的预发布测试包**。需要 macOS 14 或更高版本，包含适用于 Apple 芯片和 Intel Mac 的 `arm64`、`x86_64` 双架构，无需安装 Xcode。

1. 从[本项目官方发布页](https://github.com/swaydong/GazeEase/releases/tag/v1.1.0-test.40)下载 [`GazeEase-1.1.0-build40-macos-test.zip`](https://github.com/swaydong/GazeEase/releases/download/v1.1.0-test.40/GazeEase-1.1.0-build40-macos-test.zip)。
2. 完整解压 ZIP。可与同一官方发布页上的 SHA-256 校验值核对。
3. 将 `GazeEase.app` 拖入“应用程序（Applications）”。
4. 从“应用程序”打开护眼之道。

App 使用 **Apple Development 签名**，不是 Developer ID 签名，**未经 Apple 公证**。提供下载不代表已获得 Gatekeeper 放行，也不保证任何 Mac 都能运行；尚未在另一台干净 Mac 上验证。建议分享官方发布页，不要二次打包或转发改动过的 App。

中文显示名为“护眼之道”，英文沿用 GazeEase。App 文件名保持 `GazeEase.app`，Bundle ID 和数据位置不变，以兼容现有安装。固定安装路径是：

```text
/Applications/GazeEase.app
```

保持此路径可以减少 macOS 权限与登录项重复记录。日常不要直接从下载目录或不断变化的构建目录运行。

## 首次打开被 macOS 拦截时

只有在信任本项目官方发布、已核实下载来源，且没有理由怀疑 App 被篡改的情况下，才继续操作。

如果提示“无法验证开发者”或“Apple 无法检查它是否包含恶意软件”：

1. 先关闭提示。
2. 打开“系统设置 → 隐私与安全性”。
3. 在“安全性”中找到刚刚被阻止的护眼之道，点击“仍要打开”。
4. 按系统提示验证身份，再确认“打开”。

具体按 [Apple 官方说明](https://support.apple.com/zh-cn/102445)操作。如果没有该选项，请停止并反馈完整提示；受管理的 Mac 可能不允许打开。如果系统提示 App **“已损坏”或“会损害你的电脑”，不要继续**，请移除该副本，并向维护者反馈完整提示。

不要通过关闭 Gatekeeper、移除隔离属性或重新签名来强行运行下载的 App。

<details>
<summary>仅维护者使用：旧本机包的安装流程</summary>

旧的 `-local.zip` 包及其 `Install GazeEase.command` 只面向维护者预定的开发 Mac，不是本次公开测试下载。该安装器会主动拒绝带 quarantine 的 App；不要通过移除隔离属性绕过检查。

1. 完整解压 `GazeEase-<版本>-build<Build>-local.zip`。
2. 可将 ZIP 的 SHA-256 与旁边的 `.sha256` 文件核对。
3. 保持 `GazeEase.app` 与 `Install GazeEase.command` 位于同一文件夹。
4. 双击 `Install GazeEase.command`。
5. 安装器在替换任何内容前会验证：
   - Bundle ID 为 `com.local.EyeProtection`
   - Team ID 为 `3Q9DKW2UKF`
   - Apple Development 签名及完整代码封印有效
   - Build 号为数字
   - 同时包含 `arm64` 和 `x86_64` 架构
6. 安装器先复制并验证暂存 App，再让正在运行的 App 正常退出，最后原地替换。如果替换或最终验证失败，会恢复原来的 App 路径。
7. 安装成功后，护眼之道会从 `/Applications/GazeEase.app` 打开。

安装器不会运行 `tccutil`、清除权限、移除 quarantine、使用 ad-hoc 重签、修改登录启动开关或删除 App 数据。

如果 Gatekeeper 阻止这个命令文件或本机 App，请停止。其他测试用户应下载 `-macos-test.zip`，按上文的手动拖入方式安装。

</details>

## 首次启动与输入监控

护眼之道需要“输入监控”来判断活动和休息中断。该权限完全由 macOS 控制，安装 App 不能代替用户授予。系统权限或登录项列表可能因旧缓存仍显示 GazeEase，它与护眼之道是同一个 App。

1. 打开护眼之道。
2. 按 App 引导操作，或进入“系统设置 → 隐私与安全性 → 输入监控”。
3. 开启护眼之道。
4. 如果状态没有立即刷新，退出并重新打开护眼之道。

护眼之道不需要“屏幕录制”权限。

第一次把已经授权的开发版本迁移到固定路径时，可能需要再授权一次。之后所有升级都应保持相同路径和身份。未来从 Apple Development 切换到 Developer ID 时，也可能需要重新授权。

## 手动升级

目前没有自动更新。

1. 正常退出护眼之道，让它保存当前状态。
2. 从官方发布页下载更新的测试包并解压。
3. 将新的 `GazeEase.app` 拖入“应用程序”，选择“替换”。
4. 重新打开。如果 macOS 再次要求批准或“输入监控”权限，请按上文操作。

偏好、疲劳历史和皮肤设置位于 App 包之外，仅替换 App 时会继续保留；不要在升级时清除本地数据。如需备用版本，可自行保留已知可用的安装包；手动替换不会执行旧本机安装器的自动回滚或降级检查。

若 macOS 的登录项显示“需要批准”，请到系统设置批准，或在 App 内重新切换一次“登录时启动”。

## 测试版的已知限制

- 每台 Mac 首次启动，以及部分后续更新，都可能需要手动批准。
- 公司或学校管理的 Mac 可能完全阻止 App 或“输入监控”权限。
- 开发签名会到期，也可能被撤销，届时可能需要重新提供安装包。
- 需要手动更新；未公证测试包不保证在所有 Mac 上运行。
- 另一台干净 Mac 的验证仍待完成。安装失败时，请反馈 macOS 版本、芯片类型和完整提示。

<details>
<summary>可选：验证签名与架构</summary>

```sh
INSTALL_APP="/Applications/GazeEase.app"

codesign --verify --deep --strict --verbose=2 "$INSTALL_APP"
plutil -extract CFBundleIdentifier raw -o - "$INSTALL_APP/Contents/Info.plist"
plutil -extract CFBundleVersion raw -o - "$INSTALL_APP/Contents/Info.plist"
lipo -archs "$INSTALL_APP/Contents/MacOS/Eye Protection"
codesign -dv --verbose=4 "$INSTALL_APP"
codesign -d --entitlements :- "$INSTALL_APP"
```

测试版预期身份：

- Bundle ID：`com.local.EyeProtection`
- Team ID：`3Q9DKW2UKF`
- 架构：`arm64` 与 `x86_64`
- Authority：Apple Development

这些检查只验证代码封印和构建身份，本身不能证明已经公证或值得信任；当前测试包没有经过 Apple 公证。

</details>

## 保留数据卸载

1. 先打开护眼之道设置，关闭“登录时启动”，让 App 正确向 macOS 注销登录项。
2. 正常退出护眼之道。
3. 在 Finder 中将 `/Applications/GazeEase.app` 移到废纸篓。

仅将 App 移到废纸篓可恢复，并保留偏好、疲劳历史和隐私权限。如果卸载前忘了关闭登录启动，请到“系统设置 → 通用 → 登录项”手动关闭残留项。维护者的旧本机包也包含带校验的 `Uninstall GazeEase.command`，公开测试包不需要这个脚本。

## 可选：彻底清除本地数据

只有在已经退出并卸载护眼之道、且确认不希望以后重装时保留历史的情况下，才执行以下步骤。卸载脚本刻意不会自动完成这些操作。

移除偏好域：

```sh
defaults delete com.local.EyeProtection
```

然后在 Finder 中精确删除以下三个 SwiftData 文件（如果存在）：

```text
~/Library/Application Support/EyeProtection.store
~/Library/Application Support/EyeProtection.store-shm
~/Library/Application Support/EyeProtection.store-wal
```

如需移除系统权限记录，请在“系统设置 → 隐私与安全性 → 输入监控”中手动处理。项目脚本不会运行 `tccutil`，也不会重置隐私数据库。

## 维护者：生成本机 ZIP

维护者需要安装 Xcode，并在钥匙串中具备预期的 Apple Development 身份，然后执行：

```sh
./Scripts/package-local-release.sh
```

脚本会在独立的临时 DerivedData 中构建，并在 `Dist/` 输出带版本的 ZIP 与 SHA-256 文件。相同版本和 Build 的产物已存在时，脚本会拒绝覆盖。

## 未来的公证分发

当前测试 ZIP 可以公开下载；如果希望提供安装更顺畅的 Developer ID 公证版本，需要另行完成：

1. 确定全局唯一且长期稳定的 Bundle ID，并准备迁移方案。
2. 使用 Developer ID Application、Hardened Runtime 和安全时间戳签名。
3. Release entitlement 不含 `get-task-allow=true`。
4. 使用 `notarytool` 完成 Apple 公证。
5. 装订票据并通过 Gatekeeper 验证。
6. 在干净的目标 Mac 上验收公证 ZIP 或 DMG。

本机包打包成功或公开测试包可下载，都不代表这些公证步骤已经完成。
