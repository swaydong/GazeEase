# 为 GazeEase 贡献

感谢你帮助改进 GazeEase。它是一款注重隐私的 macOS 护眼计时器，因此改动应保持聚焦、本地优先，并便于审阅。

英文说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 项目原则

- 不收集按键内容、鼠标坐标、截图、窗口标题、音频或剪贴板内容。
- 未经仓库维护者先行明确确认产品变更，不新增屏幕录制、分析埋点、遥测、网络请求或云同步。
- 普通静止不能被悄悄视为已验证休息；只有用户已配置的无操作休息规则可以这样处理。
- 疲劳、提醒和休息行为应保持确定性，并由测试覆盖。
- 优先提交小而清晰的改动，避免顺手进行大范围重构。

## 开发环境

你需要：

- macOS 14 或更高版本；
- Xcode 16 或更高版本；
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

构建前先生成 Xcode 工程：

```sh
xcodegen generate --spec project.yml
```

完整运行时验证需要为 App 授予“输入监控”权限；单元测试和 CI 的无签名构建不应依赖该权限。

## 提交改动

1. 行为变化、新权限、新数据收集或较大的视觉改动，请先创建 Issue 讨论。
2. 使用范围清晰的分支，不要夹带无关清理。
3. 行为变化需要新增或更新测试。
4. 修改 `project.yml` 或源码文件归属后，重新生成 Xcode 工程。
5. 不提交本机构建产物、Xcode 用户状态、批量生成的截图、签名凭据或打包后的 App。

请沿用项目现有的 Swift 6、SwiftUI、AppKit 和 actor 隔离习惯。只有代码本身无法清楚表达意图时才添加注释。

## 验证

先运行聚焦测试；可能影响共享行为时，再运行全量测试：

```sh
xcodebuild \
  -project EyeProtection.xcodeproj \
  -scheme EyeProtection \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/GazeEaseDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
```

修改提醒、菜单、设置或全屏界面时，还需检查对应的确定性截图。不要把完整生成的 `Preview/` 目录放进 Pull Request，只附上审阅所必需的最少证据。

## 隐私与安全

Pull Request 中应说明对权限、本地存储、保留周期及用户可见隐私行为的影响。安全漏洞请按 [SECURITY.md](SECURITY.md) 中的私密流程报告，不要创建公开 Issue。

## 视觉资产与许可

仓库的代码许可证不涵盖 [ASSETS.md](ASSETS.md) 中列出的主题背景、品牌视觉、衍生预览和截图。不要复用第三方视觉内容；提交生成式视觉内容时，必须记录来源和允许使用的范围。

## Pull Request 检查清单

- [ ] 改动范围聚焦，并说明了清晰的用户价值。
- [ ] 行为变化已有测试。
- [ ] 聚焦测试和相关全量测试均已通过。
- [ ] 未加入密钥、个人路径、生成产物或打包 App。
- [ ] 已说明隐私、权限、持久化和无障碍影响。
- [ ] 视觉改动在需要时附有精简的审阅证据。
