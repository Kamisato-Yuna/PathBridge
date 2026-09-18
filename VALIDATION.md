# 本机验证记录

验证日期：2026-09-17。以下为已有本机历史记录，公开版本已将真实环境名称匿名化；不表示开源准备过程中重新执行了网络测试。

## 构建与签名

- 本机：macOS 15.8，Intel x86_64；Xcode 26.3，Swift 6.2.4，Swift 6 语言模式。
- Debug、Release 均经 `xcodebuild` 成功构建。
- 最终产物：`dist/PathBridge.app`、`dist/PathBridge-macOS.zip`。
- `lipo -archs` 确认包含 `x86_64 arm64`；`vtool -show-build` 确认两个架构的最低版本均为 macOS 15.7。
- `codesign --verify --deep --strict` 通过；Developer ID Application：Yuna Kamisato，Team `852H844JG2`；Hardened Runtime 已启用。
- Release 启动成功，进程正常，启动时窗口数为 0。

## 自动测试

执行 `./script/test.sh`，13 项 XCTest 全部通过，无失败。最终结果为 `build/Tests-20260917-164438.xcresult`。

覆盖盘符/UNC/macOS 往返、共享子目录及最长前缀、中文与空格、URL 解码一次、普通路径保留字面百分号、特殊字符共享名、混合中文与编码 URL、目录 URL 尾斜杠、剪贴板引号、多行拒绝、重复映射、越界与非法组件、无子目录字段的配置解码。新增回归用例曾发现 Foundation 对混合编码 URL 的再次转义，修正后通过。

## 实际系统验证

| 项目 | 实测结果 |
| --- | --- |
| 测试共享 A 映射 | 成功识别已有 SMB 挂载，解析用户指定的 测试子目录 目录 |
| R: 映射 | 原先未挂载；调用真实 NetFS，读取已保存测试凭据后成功挂载，并只读确认 RenderOutput 是目录 |
| 凭据存储 | 写入与读取钥匙串往返一致；配置 JSON 不含账号或密码字段；应用内凭据编辑表单可打开 |
| 菜单栏 | 两条映射显示已挂载，设置窗口可打开 |
| 复制转换 | 菜单栏 macOS → Windows → UNC 往返，中文、空格、字面 `%20` 保持一致 |
| 转换预览 | 原生设置页显示 macOS、盘符、UNC、Storage 四种表示 |
| 全局快捷键 | 默认 ⌥⌘O 成功打开指定目录；最终 Release 成功在 Finder 中选中已有 测试文件，选中路径由 Finder 查询确认 |
| UI | 原生窗口辅助功能树检查；存储映射页和转换页截图检查，截图位于 `build/integration/` |

网络测试未创建、修改或删除共享文件。剪贴板测试结束后恢复此前内容。提供的测试密码未写入源码、配置 JSON、构建产物或此记录。测试共享保留挂载，Release 应用留在菜单栏运行。

## 尚未实测的范围

- macOS 15.7 与 Apple Silicon 实机运行；目前已验证部署版本和双架构编译。
- 注销/重启后的登录启动；功能使用系统登录项 API，未替用户开启。
- 网络断开、认证失败、用户取消、90 秒超时等故障流程有处理实现，未对真实办公共享做故障注入。
- 未进行 Apple 公证或公开发布。

## 未配置路径支持补充验证

- 新增 4 项回归测试：无配置 UNC 转 SMB、远程 file/SMB URL 的单次解码、未知盘符及无效路径拒绝、已配置子目录的 SMB 输出。
- 使用未被 RenderOutput 映射覆盖的共享根目录，真实触发 ⌥⌘O。应用生成 SMB URL 并通过系统默认处理程序打开；Finder 查询确认位置为 `/Volumes/TestShare/`。
- 输入未配置的 `/Volumes/TestShare/`，根据实际挂载来源成功生成同一 SMB 地址并打开。
- 已配置路径继续走原挂载/定位流程；无映射情况下不会猜测盘符的服务器，也不会借用其他映射的专属凭据。后续主凭据功能可作为后备，以上历史结果不涵盖该功能。

## 0.1.0 开源准备验证

- 2026-09-17：使用 `PATHBRIDGE_SIGNING_IDENTITY=- ./script/test.sh`，13 项 XCTest 通过。
- 使用相同签名覆盖执行 `./script/build_and_run.sh --build`，Debug 应用构建成功，关于窗口纳入编译。
- 本轮未重新运行真实 SMB、钥匙串写入或 UI 交互验证。

## GitHub 更新检查验证

- `swift test`：17 项通过，含数字版本比较、稳定版筛选、无 Release、HTTP 失败及下载链接边界。
- Debug 应用构建通过；设置页版本改为读取应用元数据。
- 真实 GitHub latest Release API 返回 404（当前尚无正式 Release），该状态按“暂无更新的正式版本”处理。
- 初次开源提交的 GitHub CI 已通过；本轮没有发布用于测试的虚构 Release，也没有自动下载或安装应用。

## Finder 扩展、自然语言与主凭据补充验证

2026-09-17 本轮实际执行，下面的网络位置使用匿名描述：

- `./script/test.sh`：31 项 XCTest 通过，0 失败；结果 `build/Tests-20260917-171528.xcresult`。包含 8 项 Finder 命令校验测试及 6 项自然语言候选测试；此前的路径、配置和更新检查测试继续通过。
- Finder 命令覆盖单选打开、1～100 项复制、URL 编码往返、未知动作、重复参数、非本地路径、目录跳转与输入长度边界。外部链接入口只接受 `/Volumes` 下的本地路径，不接受任意 SMB 地址作为连接命令。
- 自然语言覆盖中文、引号、换行、URL 编码、多个候选及去重；完整路径中的括号、逗号不会被截断，URL 查询参数保留后由 Resolver 拒绝。
- 钥匙串主凭据读写往返通过；专属凭据优先、缺失/不匹配时使用主凭据的检查通过，临时测试钥匙串项已清理。配置与导出不含凭据。
- 未配置服务器别名使用主凭据调用真实 NetFS。系统返回共享已存在时，保留原挂载并继续交给默认浏览器；未断开办公共享。
- `mount-table-tests` 验证域账号字段移除、中文及百分号单次解码、字面挂载目录保留、错误来源拒绝。本机 `getfsstat(MNT_NOWAIT)` 快照正确识别两个已配置 Storage 的实际根目录。
- 最终 Release：多候选窗口选中第二条路径后，Finder 确认选中对应测试文件；此前 Debug 中取消候选窗口也验证通过。
- 最终 Release：含路径的中文聊天文本触发 ⌥⌘O，连续三次成功定位同一个测试文件，过程中未出现网络宗卷授权弹窗。此结果不代表新用户可以跳过首次 macOS 授权。
- 真实 Finder 右键菜单 → PathBridge → 复制 UNC 完整链路通过；最终 Release 的右键复制 SMB 也通过。主应用接收多选命令后逐行复制、以及 R: 盘符输出通过。
- Finder 首次仅监听 `/Volumes` 时菜单不出现，修正为同时监听具体挂载根；菜单回调改为从 Finder 获取选中项，避免跨进程丢失 `representedObject`。重新打开测试 Finder 目录窗口后验证成功。
- 最终主应用及内嵌 `.appex` 均为 `x86_64 arm64`，Developer ID 签名、Hardened Runtime、递归严格签名校验通过。扩展启用 App Sandbox；系统插件注册仅保留 `dist` 中的最终扩展，最终 Release 已启动。

本轮没有向 SMB 写入文件；剪贴板操作结束后恢复原内容。没有编辑或重置 macOS 隐私授权，没有请求完全磁盘访问。挂载刷新现在只查看内核缓存；首次打开文件仍由系统决定是否询问。测试构建切换、系统权限重置后是否再提示仍受 macOS 管理。

## 0.1.0 图标、关于页与 DMG 准备

- Icon Composer 分层源文件经 Apple 原生 ictool 渲染，Xcode 26.3 编译成功，应用元数据的图标名称为 AppIcon。
- `swift test`：31 项通过；关于页移除长说明、改用仓库和许可按钮，并显示真实应用图标。
- 主应用及 Finder 扩展均包含 Intel / Apple Silicon 架构，Developer ID 签名与 Hardened Runtime 保持启用，递归严格签名校验通过。
- 签名 DMG 已生成，`hdiutil verify` 通过；Apple 公证及 GitHub Release 发布仍待公证凭据配置，尚未宣称完成。

## 0.1.0 正式分发验证（2026-09-18）

- 修正 Release 签名：主应用与 Finder 扩展使用安全时间戳，不包含 `get-task-allow`；保留 Hardened Runtime 和扩展 App Sandbox。
- 打包脚本显式指定 Release 输出目录，避免本机 Xcode 自定义目录导致复制旧产物。
- 应用公证 Accepted：`7199d84d-5751-4cc4-acb3-d2e2100d31f2`。
- DMG 公证 Accepted：`3ecee30b-c7e0-4df4-991d-0332c92bfc09`。
- App 和 DMG 均完成 stapler staple / validate；Gatekeeper 均返回 `accepted / Notarized Developer ID`。
- 只读挂载最终 DMG，再次验证其中的 App 签名和公证票据；版本为 0.1.0，包含 Applications 安装快捷入口。
- 此前 31 项核心测试通过；本轮为签名、打包与发布验证，没有重新操作真实 SMB 或钥匙串业务凭据。
- 以上正式分发结果取代早期记录中的“未公证”状态，历史记录保留供追溯。
