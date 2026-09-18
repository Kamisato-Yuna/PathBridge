# 贡献指南

欢迎以中文提交 Issue、Pull Request 和提交说明。请让每个改动聚焦一个问题。

## 开发与验证

1. Fork 仓库，从 `main` 创建分支；安装完整 Xcode 和 Swift 6 工具链。
2. 使用 `swift test` 验证纯路径转换核心。
3. 使用 `PATHBRIDGE_SIGNING_IDENTITY=- ./script/test.sh` 运行 Xcode 测试；使用同一环境变量运行 `./script/build_and_run.sh --build` 构建应用。
4. UI 改动请在 macOS 实际检查相关窗口；路径规则改动应增加对应回归用例。
5. 提交 PR 时说明问题、变化、验证结果及未验证范围。

签名变量仅覆盖本次命令，保持 Hardened Runtime。正式分发需要维护者自己的 Developer ID 和 Apple 公证流程。

真实 SMB 集成测试仅在获得授权的测试环境手动运行。`Tests/Integration/Smoke.swift` 的 seed 操作会写入本机配置与钥匙串，mount 操作会建立真实连接；默认 CI 不运行这些操作。

不要提交密码、令牌、私钥、内部服务器、个人配置、构建产物或 CodeGraph 数据库。测试使用 `example.com` 等示例地址。报告日志和截图前请去除真实路径与账号。

## 代码导航

已安装 CodeGraph 时运行 `codegraph init .`；索引后优先使用 `codegraph explore` 和 `codegraph node` 定位代码，修改后运行 `codegraph sync`。该工具可选，不影响普通构建和测试。

## 许可

提交贡献即表示你有权以本仓库 MIT 许可提供该贡献。
