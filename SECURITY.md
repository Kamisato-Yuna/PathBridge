# 安全政策

当前维护版本为 0.1.x。安全修复将优先进入 main，并在更新记录中说明。

请通过 [GitHub 私密漏洞报告](https://github.com/Kamisato-Yuna/PathBridge/security/advisories/new) 报告凭据泄露、路径越界等安全问题，不要在公开 Issue 中附上密码、内部地址或可直接利用的细节。请提供受影响版本、复现条件、预期影响与脱敏示例。目前没有固定响应时限承诺。

密码存储在 macOS 钥匙串，不随 JSON 配置导出。配置仍包含服务器和目录等信息，分享前应脱敏。主凭据是用户选择启用的跨共享后备凭据，也可用于未映射路径；请只打开可信路径。

应用未启用 App Sandbox，需要访问用户指定的网络卷并调用系统 NetFS。Hardened Runtime 保持启用。源码构建与本机签名不等于 Apple 公证；请自行审核来源与签名。
