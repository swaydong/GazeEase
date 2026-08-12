# Security Policy / 安全策略

## English

### Supported versions

Security fixes are applied to the current `main` branch and, after public
distribution begins, the latest published release. Older builds may not receive
security updates.

### Reporting a vulnerability

Please do not disclose a suspected vulnerability in a public issue, discussion,
pull request, screenshot, or social post.

1. Use this repository's **Security** tab and choose **Report a vulnerability**
   when GitHub Private Vulnerability Reporting is available.
2. If that option is unavailable, contact the repository owner through their
   GitHub profile and request a private reporting channel. Do not include exploit
   details in the initial public message.

Include the affected version or commit, macOS version, reproduction steps,
expected impact, and any suggested mitigation. Remove personal data, input
content, screenshots of private work, signing credentials, and tokens before
sending evidence.

We aim to acknowledge a complete report within seven days. Remediation and
disclosure timing depend on severity and the availability of a safe update.

### In scope

- unintended capture or persistence of user input or private content;
- bypasses of rest-overlay input handling or permission boundaries;
- unsafe local-data exposure, retention, or deletion behavior;
- launch-at-login, notification, signing, update, or distribution weaknesses;
- vulnerabilities in bundled dependencies or build/release automation.

General bugs, feature requests, and visual issues can use the normal issue
tracker once the repository enables it.

## 中文

### 支持范围

安全修复会优先应用到当前 `main` 分支；开始公开分发后，也会覆盖最新发布版本。更早的构建不保证继续获得安全更新。

### 报告漏洞

请勿通过公开 Issue、讨论、Pull Request、截图或社交媒体披露疑似漏洞。

1. 如果仓库已开启 GitHub 私密漏洞报告，请进入 **Security** 页面并选择 **Report a vulnerability**。
2. 如果该入口不可用，请通过仓库所有者的 GitHub 主页联系，先请求一个私密报告渠道；初次公开留言中不要包含利用细节。

报告应包括受影响版本或提交、macOS 版本、复现步骤、预期影响和可行的缓解建议。提交证据前，请移除个人数据、输入内容、私人工作截图、签名凭据和 token。

我们会尽量在收到完整报告后的 7 天内确认。修复和披露时间取决于严重程度以及安全更新的可用性。

### 范围内问题

- 意外采集或保存用户输入、私人内容；
- 绕过休息遮罩的输入处理或权限边界；
- 本地数据暴露、保留或删除行为不安全；
- 登录启动、通知、签名、更新或分发链路中的安全问题；
- 内置依赖或构建发布自动化中的漏洞。

普通 Bug、功能建议和视觉问题，可在仓库开放 Issue 后使用常规问题追踪渠道。
