# 护眼之道

[English](README.md) · 简体中文

护眼之道（GazeEase）是一个注重隐私、只驻留在 macOS 菜单栏的护眼计时器。默认有效使用 20 分钟达到 100% 疲劳，完整休息需要连续 20 秒；两项时长都可以在设置中自定义。部分休息使疲劳降到 100% 以下后，提醒暂停，重新达到 100% 时再提醒；完整休息会将疲劳归零。

中文显示名为“护眼之道”，英文沿用 GazeEase。为兼容现有安装与升级，App 文件名、安装路径和安装脚本仍使用 GazeEase；Bundle ID、偏好与历史数据位置保持不变。

## 分发状态

源代码已公开，采用 [MIT 许可证](LICENSE)。主题画面及品牌资产适用 [ASSETS.md](ASSETS.md) 中的独立有限许可，**不属于 MIT 授权范围**。

Version `1.1.0`、Build `39` 本次**只公开源码，不提供通用安装包**；开发者可按下文使用自己的开发身份构建。现有 Apple Development 本机包和小范围测试包均未使用 Developer ID 签名、未经过 Apple 公证，不是面向所有人的公开安装器。

<details>
<summary>已有本机安装包——仅适用于维护者的开发 Mac</summary>

如果你拿到的是护眼之道本机 ZIP 安装包：

> 该包只供生成它的同一台开发 Mac 使用。从 GitHub 下载的 ZIP 可能带有 quarantine，
> 本机安装器会主动拒绝，不能通过移除隔离属性绕过 Gatekeeper；普通公开下载需等待
> Developer ID 签名并公证的版本。

1. 完整解压 ZIP。
2. 保持 `GazeEase.app` 和 `Install GazeEase.command` 位于同一文件夹。
3. 双击 `Install GazeEase.command`。
4. 安装器会先验证 App，再安装到固定路径 `/Applications/GazeEase.app`。
5. 第一次启动时，按 App 引导开启“输入监控”。如果 macOS 没有立即应用权限，请退出并重新打开护眼之道。

macOS 的权限或登录项列表可能因旧缓存仍显示 GazeEase，它与护眼之道是同一个 App。

安装器不会授予或重置隐私权限，不会改动登录启动设置，也不会删除偏好和历史。完整说明见[安装、升级与卸载](INSTALL.zh-CN.md)。

</details>

## 主要行为

- 菜单栏实时显示疲劳百分比；疲劳可以超过 100%，超过 999% 后使用紧凑格式，但保留实际值。
- 提醒外观可选湖谷地平线、林间天光、雪岭晨雾、暮色沙丘、苔庭细雨、极夜微光、月下竹庭、雨后海崖和云野长风；全屏提醒、统一倒计时、顶部弹窗与菜单栏展开面板会同步使用所选皮肤。
- 设置页与菜单栏展开面板会延续所选皮肤的场景、色彩和氛围，而不仅是更换按钮颜色。
- 可选开启“自动随机更换皮肤”：默认每 60 分钟从全部皮肤中随机选择一套，间隔可设为 5–1440 分钟，且不会连续重复；提醒或休息界面显示时会延后到安全时机再更换。
- 默认情况下，普通静止、阅读或思考不会自动算作休息。
- 首次提醒可选三档：右上角无声系统通知、顶部双按钮弹窗或全屏双按钮提醒。
- 顶部弹窗和全屏提醒会直接显示“暂不休息”和“开始休息”；系统通知忽略即可继续工作，点击通知会开始休息。
- 选择“暂不休息”后，本次提示立即关闭，疲劳继续累积；之后每达到新的 100% 整数倍会再提醒一次。疲劳恢复到 100% 以下后，这些提醒档位会重新启用。
- 休息被操作中断时保留已恢复的疲劳度：仍达到 100% 时恢复顶部双按钮弹窗；低于 100% 时收起提醒，等重新达到阈值再提醒。中断仍计为中断记录。
- 点击“开始休息”会遮住全部显示器；输入会中断本次休息。
- 使用周期可直接输入 1–180 分钟，完整休息可直接输入 5–300 秒。
- 修改使用周期会按已累计有效使用量重算疲劳百分比；修改休息时长只影响休息倒计时。
- 可选开启“长时间无操作时自动完成休息”：连续 1–180 分钟完全没有键盘、鼠标或触控板输入时，清空疲劳并解除休息要求；任何输入都会重新计时。
- 锁屏、显示器休眠或系统睡眠达到自定义休息时长，也可以自动完成休息。
- App 重启后会恢复疲劳值、未解除的休息要求、提醒整数档位、皮肤轮换计划及当前过载记录。

## 隐私

护眼之道需要“输入监控”权限来判断活动和休息中断。App 不申请“屏幕录制”权限，也不采集屏幕内容。

所有处理和存储都在本机完成。App 不保存按键内容、鼠标坐标、截图、窗口标题、音频或剪贴板数据，也不包含遥测或网络上传逻辑。详见[隐私说明](PRIVACY.zh-CN.md)。

## 通过 Xcode 运行

要求 macOS 14 或更高版本、Xcode 16 或更高版本。

1. 打开 `EyeProtection.xcodeproj`。
2. 选择 `EyeProtection` Scheme 和 `My Mac`。
3. 在 **Signing & Capabilities** 中选择自己的 Team，并为开发副本设置独立的 Bundle Identifier；Xcode 如要求，也需更新测试 Target 的签名身份。不要沿用维护者的 Team 或 App 身份。
4. 运行后，按引导为自己的副本授予“输入监控”权限。它与原有安装的权限记录相互独立。
5. 权限变更后若系统未立即生效，请退出并重新打开 App。

仓库已包含 Xcode 工程。如需从 `project.yml` 重新生成，可先安装 XcodeGen，再执行下方命令；随后重新设置本机 Team 和 Bundle Identifier，或先在本地 `project.yml` 中设置。请勿提交个人签名配置。

```sh
xcodegen generate
```

<details>
<summary>维护者专用：生成本机安装包</summary>

打包脚本会使用全新的 DerivedData 生成签名 Release，验证准确的 Bundle ID、Team、Build、双架构和 Apple Development 签名，然后在 `Dist/` 输出 ZIP 及 SHA-256 文件。

```sh
./Scripts/package-local-release.sh
```

该脚本只服务于当前私有本机流程，因此会主动拒绝 Developer ID 或 ad-hoc 签名。它不会安装或打开生成的包。

</details>

## 验证

测试、静态分析和编译检查不需要维护者的签名凭据：

```sh
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionDerivedData CODE_SIGNING_ALLOWED=NO test
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionReleaseDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionAnalyzeDerivedData CODE_SIGNING_ALLOWED=NO analyze
```

无签名编译结果不等于可安装发行版。运行和权限测试应使用自己的签名开发副本；后续升级保持该副本的身份和位置稳定。

未来若提供普通用户可直接安装的公开包，需要单独完成 Developer ID 签名、Apple 公证、票据装订和 Gatekeeper 验证，并在目标 Mac 验证多显示器、全屏空间、权限撤销、锁屏/睡眠、登录启动及能耗。公开源码不代表这些安装包验收已完成。

## 文档

- [代码许可证（MIT）](LICENSE) · [视觉资产条款](ASSETS.md)
- [Contributing](CONTRIBUTING.md) · [贡献指南](CONTRIBUTING.zh-CN.md)
- [Installation, upgrade, and uninstall](INSTALL.md)
- [安装、升级与卸载](INSTALL.zh-CN.md)
- [Privacy statement](PRIVACY.md)
- [隐私说明](PRIVACY.zh-CN.md)
