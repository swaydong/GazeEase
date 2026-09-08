# 护眼之道 / GazeEase 1.1.0 · Build 39

## 中文

首次公开源码版本。代码与文档采用 [MIT 许可证](https://github.com/swaydong/GazeEase/blob/v1.1.0-build.39/LICENSE)；皮肤、图标与品牌素材仍遵循[独立视觉资产条款](https://github.com/swaydong/GazeEase/blob/v1.1.0-build.39/ASSETS.md)，不属于 MIT 授权范围。

- 中文名称改为“护眼之道”，英文继续使用 GazeEase。
- 修正休息后的提醒：疲劳降到 100% 以下时收起提醒，重新达到 100% 时再提醒；完整休息仍归零。
- 包含九套主题、随机换肤、今日疲劳曲线与本地分析。
- 未新增权限、联网行为或数据采集。

本次只发布源码，GitHub 下方的 Source code 压缩包不是可直接安装的 App。请按[中文说明](https://github.com/swaydong/GazeEase/blob/v1.1.0-build.39/README.zh-CN.md)使用 Xcode 和自己的开发身份构建。没有附带通用安装包，也未完成 Developer ID 签名与 Apple 公证。既有熟人测试包继续单独提供，不包含在本公开发布中。

验证：208 项测试通过，0 失败、0 跳过；Release 双架构（Apple 芯片与 Intel）静态检查通过。源代码及已提交历史已检查，未发现密钥或私人用眼数据；这不等同于第三方安全审计。

## English

The first public source release. Code and documentation use the [MIT License](https://github.com/swaydong/GazeEase/blob/v1.1.0-build.39/LICENSE); theme artwork, icons, and branding retain their [separate asset terms](https://github.com/swaydong/GazeEase/blob/v1.1.0-build.39/ASSETS.md).

- Renamed the Chinese display name to 护眼之道; English remains GazeEase.
- Pauses reminders after recovery below 100% and re-arms them at 100%; a complete rest still resets fatigue to zero.
- Includes nine themes, random theme rotation, today's fatigue curve, and local analytics.
- No new permissions, network behavior, or data collection.

This is a source-only release. GitHub's Source code archives are not installable apps. Follow the [README](https://github.com/swaydong/GazeEase/blob/v1.1.0-build.39/README.md) to build with Xcode and your own development identity. No general-purpose binary is attached, and Developer ID signing and Apple notarization have not been completed. Existing trusted-test packages remain a separate workflow.

Validation: 208 tests passed, zero failed or skipped; universal Release static analysis passed for arm64 and x86_64. Source and committed history were checked for credentials and personal usage data with none found; this is not an independent security audit.
