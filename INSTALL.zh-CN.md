# 护眼之道安装、升级与卸载

[English](INSTALL.md) · 简体中文

## 适用范围

本文说明护眼之道（GazeEase）当前的私有本机分发流程。安装包使用供开发者本人 Mac 使用的 Apple Development 签名，没有使用 Developer ID，也没有经过 Apple 公证，不适合公开分发。

中文显示名为“护眼之道”，英文沿用 GazeEase。App 文件名、安装包和脚本名仍使用 GazeEase，以兼容现有安装；Bundle ID 和数据位置保持不变。

安装器会主动拒绝带 quarantine 的 App；不要通过移除隔离属性来强行运行私有开发包。从 GitHub 下载的包在 Developer ID 公证版本完成前，仅用于保存源码与发布证据。

唯一固定安装路径是：

```text
/Applications/GazeEase.app
```

日常不要直接从不断变化的 Xcode、DerivedData、下载目录或工程目录运行。保持 Bundle ID、开发团队、签名身份和路径稳定，可以减少 macOS 权限与登录项重复记录。

## 安装本机版本

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

如果 Gatekeeper 阻止命令文件或 App，请停止安装，不要绕过警告。私有 Apple Development 包只支持预定的开发 Mac；其他 Mac 需要 Developer ID 签名并完成公证的正式版本。

## 首次启动与输入监控

护眼之道需要“输入监控”来判断活动和休息中断。该权限完全由 macOS 控制，安装器不能代替用户授予。系统权限或登录项列表可能因旧缓存仍显示 GazeEase，它与护眼之道是同一个 App。

1. 打开护眼之道。
2. 按 App 引导操作，或进入“系统设置 → 隐私与安全性 → 输入监控”。
3. 开启护眼之道。
4. 如果状态没有立即刷新，退出并重新打开护眼之道。

护眼之道不需要“屏幕录制”权限。

第一次把已经授权的开发版本迁移到固定路径时，可能需要再授权一次。之后所有升级都应保持相同路径和身份。未来从 Apple Development 切换到 Developer ID 时，也可能需要重新授权。

## 升级

使用新 ZIP 中的 `Install GazeEase.command`，操作与首次安装完全相同。

- 偏好、疲劳历史、皮肤设置和运行状态位于 App 包之外，会继续保留。
- 安装器会拒绝更低的 `CFBundleVersion`。
- 重装相同 Build 时需要确认。
- 旧 App 会保留到新副本通过最终验证、且 macOS 接受打开请求，期间可以自动回滚。
- 安装器不会开启或关闭登录启动。若迁移后 macOS 显示“需要批准”，请到系统设置批准，或在 App 内重新切换一次。

## 验证已安装的本机版本

```sh
INSTALL_APP="/Applications/GazeEase.app"

codesign --verify --deep --strict --verbose=2 "$INSTALL_APP"
plutil -extract CFBundleIdentifier raw -o - "$INSTALL_APP/Contents/Info.plist"
plutil -extract CFBundleVersion raw -o - "$INSTALL_APP/Contents/Info.plist"
lipo -archs "$INSTALL_APP/Contents/MacOS/Eye Protection"
codesign -dv --verbose=4 "$INSTALL_APP"
codesign -d --entitlements :- "$INSTALL_APP"
```

本机版本预期身份：

- Bundle ID：`com.local.EyeProtection`
- Team ID：`3Q9DKW2UKF`
- 架构：`arm64` 与 `x86_64`
- Authority：Apple Development

当前私有开发版本不以 Gatekeeper 接受作为验收条件；未来公开的 Developer ID 公证版本必须通过 Gatekeeper。

## 保留数据卸载

1. 先打开护眼之道设置，关闭“登录时启动”，让 App 正确向 macOS 注销登录项。
2. 双击 `Uninstall GazeEase.command`。
3. 按提示输入 `UNINSTALL`。
4. 脚本会验证固定路径中的准确 App，让它正常退出，再把 `/Applications/GazeEase.app` 移到当前用户的废纸篓。

默认卸载可恢复，并保留偏好、疲劳历史和隐私权限。如果卸载前忘了关闭登录启动，请到“系统设置 → 通用 → 登录项”手动关闭残留项。

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

## 生成本机 ZIP

维护者需要安装 Xcode，并在钥匙串中具备预期的 Apple Development 身份，然后执行：

```sh
./Scripts/package-local-release.sh
```

脚本会在独立的临时 DerivedData 中构建，并在 `Dist/` 输出带版本的 ZIP 与 SHA-256 文件。相同版本和 Build 的产物已存在时，脚本会拒绝覆盖。

## 公开分发是另一套流程

正式向其他用户分发前，需要另外完成：

1. 确定全局唯一且长期稳定的 Bundle ID，并准备迁移方案。
2. 使用 Developer ID Application、Hardened Runtime 和安全时间戳签名。
3. Release entitlement 不含 `get-task-allow=true`。
4. 使用 `notarytool` 完成 Apple 公证。
5. 装订票据并通过 Gatekeeper 验证。
6. 在干净的目标 Mac 上验收公证 ZIP 或 DMG。

不能把本机打包脚本成功，视为已经满足公开分发条件。
