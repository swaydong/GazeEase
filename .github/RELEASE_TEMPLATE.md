# GazeEase / 护眼之道 vX.Y.Z (Build N)

> Choose source-only or binary distribution. Delete unused sections and
> instructional text before publishing; report unverified items as limitations,
> never as passed checks.
>
> 选择源码或安装包发布，删除不适用的章节与说明文字；未验证的项目须明确列为限制，不能写成已通过。

## Distribution / 分发范围

- Source only / 仅源码：No ready-to-install binary is included. / 不附带通用安装包。
- Code: MIT; visual and brand assets: separate limited terms. Link to `LICENSE`
  and `ASSETS.md` at this release's tag. / 代码采用 MIT；视觉与品牌资产适用独立有限许可，请链接到本版本标签下的 `LICENSE` 与 `ASSETS.md`。

## Highlights / 版本亮点

### English

- Describe the user-visible outcome in one or two bullets.

### 中文

- 用一到两条说明用户可感知的核心变化。

## Changes / 变更内容

### English

- Added:
- Improved:
- Fixed:

### 中文

- 新增：
- 优化：
- 修复：

## Privacy and permissions / 隐私与权限

### English

- Data handling changes: None / describe changes.
- Permission changes: None / describe changes.
- Network behavior changes: None / describe changes.

### 中文

- 数据处理变化：无 / 请说明。
- 权限变化：无 / 请说明。
- 网络行为变化：无 / 请说明。

## Build from source / 从源码运行

For a source-only release, follow the README at this tag. Select your own Xcode
Team and a unique Bundle Identifier before running. Unsigned test/build commands
do not produce a public installer. / 仅源码版本请按本标签下的 README 操作；运行前选择自己的 Xcode Team 和独立 Bundle Identifier。无签名测试或编译结果不等于公开安装包。

## Optional binary installation / 可选：安装包使用方式

> Keep this section only when a verified, notarized binary is attached. Local
> Apple Development and trusted-test packages do not qualify.
>
> 仅在附有已验证、公证的安装包时保留本节；Apple Development 本机包和小范围测试包不适用。

### English

1. Download the attached notarized archive or disk image.
2. Move GazeEase to Applications.
3. Open it and follow the Input Monitoring permission guide.
4. Replace the existing app in place when upgrading so macOS can preserve its
   identity and permissions.

### 中文

1. 下载附件中的已公证压缩包或磁盘映像。
2. 将护眼之道移入“应用程序”。
3. 打开 App，并按引导授予“输入监控”权限。
4. 升级时请在原位置替换现有 App，以便 macOS 继续识别其身份与权限。

## Verification / 发布验证

- [ ] Full unit-test suite passed on the release commit. / 发布提交已通过全量单元测试。
- [ ] Static analysis and an unsigned Release compile check passed. / 静态分析和无签名 Release 编译检查通过。
- [ ] Published files contain no credentials, personal data, or local build output. / 公开文件不含凭据、个人数据或本机构建产物。
- [ ] Privacy and license documentation matches this release. / 隐私和许可文档与本版本一致。

### Only when distributing a binary / 仅安装包发布时

- [ ] Release build is universal `arm64` + `x86_64`. / Release 同时包含 `arm64` 与 `x86_64`。
- [ ] Signed with Developer ID Application and hardened runtime. / 已使用 Developer ID Application 和 Hardened Runtime 签名。
- [ ] `get-task-allow` is absent or false. / `get-task-allow` 不存在或为 false。
- [ ] Apple notarization succeeded and the ticket is stapled. / Apple 公证成功且票据已装订。
- [ ] `codesign`, `spctl`, and `stapler validate` checks passed. / `codesign`、`spctl` 与 `stapler validate` 均通过。
- [ ] Bundle ID, team, app name, and upgrade path were checked. / 已核对 Bundle ID、团队、App 名称和升级路径。
- [ ] Multi-display, full-screen, lock/sleep, and permission-revocation flows were checked. / 已验证多显示器、全屏、锁屏/睡眠与权限撤销。

## Optional binary downloads and checksums / 可选：安装包与校验值

> Remove for source-only releases. / 仅源码发布时删除本节。

| File / 文件 | SHA-256 |
| --- | --- |
| `GazeEase-X.Y.Z.zip` | `REPLACE_ME` |

## Known issues / 已知问题

### English

- None known / describe limitations and workarounds.

### 中文

- 暂无 / 请说明限制与临时解决方法。
