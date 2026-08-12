# GazeEase

[English](README.md) · 简体中文

GazeEase 是一个注重隐私、只驻留在 macOS 菜单栏的护眼计时器。默认有效使用 20 分钟达到 100% 疲劳，完整休息需要连续 20 秒；两项时长都可以在设置中自定义。达到阈值后，休息要求会保持锁存，直到完成一次完整休息。

## 分发状态

本仓库目前生成的是供开发者本人 Mac 使用的**私有本机 Apple Development 版本**。它没有使用 Developer ID 签名，也没有经过 Apple 公证，不应作为公开安装包转发。不要移除 quarantine 属性、使用 ad-hoc 签名覆盖 App，或把当前包当成正式公开版本。

公开分发前，需要确定长期稳定的 Bundle ID，配置 Developer ID Application 证书，生成不含 `get-task-allow` 的 Release，完成 Apple 公证和票据装订，并通过 Gatekeeper 验证。

## 不打开 Xcode 直接安装

如果你拿到的是 GazeEase 本机 ZIP 安装包：

> 该包只供生成它的同一台开发 Mac 使用。从 GitHub 下载的 ZIP 可能带有 quarantine，
> 本机安装器会主动拒绝，不能通过移除隔离属性绕过 Gatekeeper；普通公开下载需等待
> Developer ID 签名并公证的版本。

1. 完整解压 ZIP。
2. 保持 `GazeEase.app` 和 `Install GazeEase.command` 位于同一文件夹。
3. 双击 `Install GazeEase.command`。
4. 安装器会先验证 App，再安装到固定路径 `/Applications/GazeEase.app`。
5. 第一次启动时，按 App 引导开启“输入监控”。如果 macOS 没有立即应用权限，请退出并重新打开 GazeEase。

安装器不会授予或重置隐私权限，不会改动登录启动设置，也不会删除偏好和历史。完整说明见[安装、升级与卸载](INSTALL.zh-CN.md)。

## 主要行为

- 菜单栏实时显示疲劳百分比；疲劳可以超过 100%，超过 999% 后使用紧凑格式，但保留实际值。
- 提醒外观可选湖谷地平线、林间天光、雪岭晨雾和暮色沙丘；全屏提醒、统一倒计时、顶部弹窗与菜单栏展开面板会同步使用所选皮肤。
- 设置页与菜单栏展开面板会延续所选皮肤的场景、色彩和氛围，而不仅是更换按钮颜色。
- 可选开启“自动随机更换皮肤”：默认每 60 分钟从全部皮肤中随机选择一套，间隔可设为 5–1440 分钟，且不会连续重复；提醒或休息界面显示时会延后到安全时机再更换。
- 默认情况下，普通静止、阅读或思考不会自动算作休息。
- 首次提醒可选三档：右上角无声系统通知、顶部双按钮弹窗或全屏双按钮提醒。
- 顶部弹窗和全屏提醒会直接显示“暂不休息”和“开始休息”；系统通知忽略即可继续工作，点击通知会开始休息。
- 选择“暂不休息”后，本次提示立即关闭；疲劳、锁存的休息要求和高疲劳时长继续累积，之后每达到新的 100% 整数倍会再提醒一次。
- 手动休息被键盘、点击、滚动或明显鼠标移动打断后，会恢复顶部双按钮弹窗，方便重新开始休息。
- 点击“开始休息”会遮住全部显示器；输入会中断本次休息。
- 使用周期可直接输入 1–180 分钟，完整休息可直接输入 5–300 秒。
- 修改使用周期会按已累计有效使用量重算疲劳百分比；修改休息时长只影响休息倒计时。
- 可选开启“长时间无操作时自动完成休息”：连续 1–180 分钟完全没有键盘、鼠标或触控板输入时，清空疲劳并解除休息要求；任何输入都会重新计时。
- 锁屏、显示器休眠或系统睡眠达到自定义休息时长，也可以自动完成休息。
- App 重启后会恢复疲劳值、未解除的休息要求、提醒整数档位、皮肤轮换计划及当前过载记录。

## 隐私

GazeEase 需要“输入监控”权限来判断活动和休息中断。App 不申请“屏幕录制”权限，也不采集屏幕内容。

所有处理和存储都在本机完成。App 不保存按键内容、鼠标坐标、截图、窗口标题、音频或剪贴板数据，也不包含遥测或网络上传逻辑。详见[隐私说明](PRIVACY.zh-CN.md)。

## 通过 Xcode 运行

要求 macOS 14 或更高版本、Xcode 16 或更高版本。

1. 打开 `EyeProtection.xcodeproj`。
2. 选择 `EyeProtection` Scheme 和 `My Mac`。
3. 运行后，按引导授予“输入监控”权限。
4. 权限变更后若系统未立即生效，请退出并重新打开 App。

如需从 `project.yml` 重新生成工程，可先安装 XcodeGen，再执行：

```sh
xcodegen generate
```

## 生成私有本机安装包

打包脚本会使用全新的 DerivedData 生成签名 Release，验证准确的 Bundle ID、Team、Build、双架构和 Apple Development 签名，然后在 `Dist/` 输出 ZIP 及 SHA-256 文件。

```sh
./Scripts/package-local-release.sh
```

该脚本只服务于当前私有本机流程，因此会主动拒绝 Developer ID 或 ad-hoc 签名。它不会安装或打开生成的包。

## 验证

```sh
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionDerivedData test
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionReleaseDerivedData build
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionAnalyzeDerivedData CODE_SIGNING_ALLOWED=NO analyze
```

本机 Release 必须保留 Xcode 生成的 Apple Development 签名并整包复制，不能再用 ad-hoc 签名覆盖。固定使用相同的 Bundle ID、开发团队、签名身份和安装路径，才能让 macOS 尽可能把日常迭代识别为同一个 App。

公开发布前，还需要配置 Developer ID 签名并完成公证；多显示器、全屏空间、权限撤销、锁屏/睡眠、登录启动及 2 小时 Energy Log 应在目标 Mac 上做最终验收。

## 文档

- [Installation, upgrade, and uninstall](INSTALL.md)
- [安装、升级与卸载](INSTALL.zh-CN.md)
- [Privacy statement](PRIVACY.md)
- [隐私说明](PRIVACY.zh-CN.md)
