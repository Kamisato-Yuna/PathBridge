# PathBridge

让路径跨越系统。A native macOS menu bar app for Windows, UNC and SMB path conversion.

[![CI](https://github.com/Kamisato-Yuna/PathBridge/actions/workflows/ci.yml/badge.svg)](https://github.com/Kamisato-Yuna/PathBridge/actions/workflows/ci.yml) · **v0.1.0** · [MIT](LICENSE) · [问题反馈](https://github.com/Kamisato-Yuna/PathBridge/issues)

[下载 PathBridge 0.1.0 DMG](https://github.com/Kamisato-Yuna/PathBridge/releases/download/v0.1.0/PathBridge-0.1.0.dmg) · [发布说明](https://github.com/Kamisato-Yuna/PathBridge/releases/tag/v0.1.0)

支持 macOS 15.7+、Intel 和 Apple Silicon；发布的应用与 DMG 均已使用 Developer ID 签名、通过 Apple 公证并附加票据。打开 DMG，将 PathBridge 拖入 Applications 后启动。

Swift 6 + SwiftUI 原生 macOS 菜单栏工具，支持 macOS 15.7 及以上。用于 Windows 盘符、UNC 和 macOS 网络卷路径之间的转换。应用启动不弹出主窗口，也不显示 Dock 图标。

## 快速开始

需要 macOS 15.7+、完整 Xcode 26.3+（用于编译 Icon Composer 图标）及 Swift 6 工具链。

```bash
git clone https://github.com/Kamisato-Yuna/PathBridge.git
cd PathBridge
# 无开发者证书时使用本机 ad-hoc 签名
PATHBRIDGE_SIGNING_IDENTITY=- ./script/build_and_run.sh
```

启动后在菜单栏使用应用；“关于”可查看版本和仓库链接。ad-hoc 签名仅用于本地开发，不提供 Developer ID 身份或公证。

## 使用

1. 启动构建后的 `build/Build/Products/Debug/PathBridge.app`（或自行打包的 `dist/PathBridge.app`），从菜单栏图标打开“设置”。长期使用建议将应用放入 `/Applications`，再启用登录时启动。
2. 在“存储映射”中配置服务器、共享名称、可选盘符和 macOS 映射根目录。共享内的子目录也可单独作为 Storage。
3. 复制一个完整路径或包含路径的聊天文本，按 **⌥⌘O**。多个候选会弹出选择窗口。共享未挂载时自动连接；目录直接打开，文件在 Finder 中定位。
4. 菜单栏的 macOS、Windows、UNC 按钮将剪贴板路径转换后复制。Windows 优先输出盘符，未配置盘符时输出 UNC。
5. “路径转换”页支持手动输入及 macOS、Windows、UNC、Storage、SMB 格式的预览，不需要挂载即可进行纯路径转换。

未配置的完整 UNC 路径（例如 `\\server\share\目录`）会转换为正确编码的 `smb://server/share/目录`，通过系统注册的 SMB 默认处理程序打开。也支持现成的 SMB 地址、远程 `file://server/share/...` 地址，以及能从系统挂载信息确定来源的 macOS 网络卷路径。有主凭据时先用主凭据连接共享；未保存主凭据时由默认浏览器处理认证。PathBridge 不会将其他映射的专属凭据用于未知共享。转换页可以预览、复制 SMB 地址。

没有配置的盘符（例如 `R:\Project`）本身不包含服务器信息，仍需配置映射或改用完整 UNC 路径。已匹配映射的路径继续使用原有的自动挂载与 Finder 定位流程。

账号支持 `DOMAIN\username`。在编辑窗口勾选“将账号凭据保存在钥匙串”可保存该映射的专属账号与密码。“设置 → 主凭据”可保存、更新或删除通用 SMB 账号。凭据优先级为 **映射专属凭据 → 主凭据 → macOS 系统认证**；未配置映射时也会使用主凭据。密码不写入 JSON 或 SMB URL，也不随配置导出。已有 SMB 会话会被复用，修改凭据不会主动断开现有挂载。

## Finder 右键菜单与聊天文本

“通用 → Finder 扩展 → 管理 Finder 扩展”打开系统管理界面，启用 PathBridge 后，在 `/Volumes` 下的网络文件或目录上右键，选择 **PathBridge**：复制 macOS、Windows、UNC、SMB 路径，或在 Finder 中打开。复制支持最多 100 个项目，按行输出；打开只支持单选。没有盘符映射时 Windows 输出 UNC。已挂载但未配置的共享也能通过实际挂载来源生成 UNC/SMB。

扩展随主应用打包，不保存配置或凭据。首次启用或更新后，若已有 Finder 窗口没有出现菜单，重新打开该目录窗口。测试构建与长期使用版本不宜同时保留启用状态；使用固定位置的签名应用。

剪贴板快捷键和转换页均在本机识别聊天文本，例如：

```text
请查看“R:\镜头 01\成片.exr”，以及 smb://server/share/review。
```

多个候选按出现顺序去重并弹出选择，取消不执行操作。支持常见引号、换行及中文标点。无引号时，路径与末尾普通文字仅用空格隔开会存在歧义；此时保留全部文字以避免截断合法文件名，请用引号或换行明确路径边界。不使用在线模型，不发送剪贴板内容。

macOS 首次实际访问网络文件可能显示“PathBridge 想要访问网络宗卷上的文件”，需要用户选择“允许”。这是系统隐私授权，与 SMB 账号密码无关。挂载状态刷新不读取网络文件，应用不会重置或修改系统授权；仍遇到重复提示时可在“系统设置 → 隐私与安全性 → 文件与文件夹”检查 PathBridge 的网络宗卷权限。无需为本应用开启完全磁盘访问。[Apple 权限说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsnetworkvolumesusagedescription)

## 检查更新

应用默认在启动后检查 [GitHub Releases](https://github.com/Kamisato-Yuna/PathBridge/releases)，每 24 小时最多自动请求一次（应用运行时每小时检查是否到期）。在“通用 → 软件更新”或“关于”中可关闭自动检查，也可随时手动检查。

发现新版后，菜单栏、设置和关于窗口提供 Release 下载页面入口，由用户下载并手动安装。检查仅请求公开 Release 元数据，不发送剪贴板、存储路径或凭据，不需要 GitHub 令牌。GitHub 会收到正常网络请求信息，包括 IP 地址和应用版本 User-Agent。

更新源使用 [GitHub 最新正式 Release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)，忽略草稿和预发布。版本标签需为 `v0.1.0` 或 `0.1.0` 这样的三段数字；只推送 Git tag 不会触发更新。仓库尚无正式 Release 时显示“暂无更新的正式版本”；离线或限流时显示检查失败，手动检查可重试。

## 配置与路径规则

配置保存在 `~/Library/Application Support/PathBridge/configuration.json`，使用原子写入。示例见 `Resources/example-config.json`。导入会先验证并提示替换现有配置；损坏配置会被保留，不自动覆盖。

| 字段 | 说明 |
| --- | --- |
| `id` | Storage 唯一标识，同时用于 `storage://` 和钥匙串关联 |
| `name` | 显示名称 |
| `windowsDrive` | 可选盘符，例如 `R:`；省略即仅用 UNC |
| `server` / `share` | SMB 服务器与共享，不含协议、账号和密码 |
| `subpath` | 共享内可选相对目录，使用 `/` 分隔 |
| `mountPath` | Storage 对应的完整 macOS 根目录，位于 `/Volumes` 下 |

例如 `R:\shot\image.exr` 可以映射至 `\\server\Production\RenderOutput\shot\image.exr` 和 `/Volumes/Production/RenderOutput/shot/image.exr`。

- 所有路径先解析为 `ResolvedPath(storageID, components)`，对应 `storage://<id>/<encoded-relative-path>`。
- 支持盘符、UNC、macOS 路径、`smb://`、`file://`、`storage://`、包裹路径的引号及 Finder 文件剪贴板对象。
- URL 中的百分号编码只解码一次；普通路径中的 `%20` 保持字面值，避免误改文件名。支持中文与空格。
- Windows 服务器、共享、盘符匹配不区分大小写，macOS 路径匹配区分大小写。父子目录映射使用最长完整前缀。
- 拒绝相对路径、`.` / `..`、目录越界、重复盘符/Storage ID/映射根，以及不能表示为 Windows 路径的组件。核心 Resolver 每次处理一个路径；自然语言提取层支持多个候选并让用户选择。
- SMB 挂载通过系统内核挂载表核对服务器与共享，不把一个同名本地目录视为已挂载。系统将共享挂载为 `share-1` 等名称时，使用实际挂载位置。
- 映射专属凭据与 Storage ID、服务器、共享同时匹配才可用于连接。导入更换服务器不会复用该映射旧密码；编辑服务器后需重新填写专属凭据。用户在“主凭据”中明确保存的账号作为后备，可用于其他服务器及未映射共享；仅对可信的 SMB 路径使用此功能。系统钥匙串访问由用户会话保护。

## 构建、测试与签名

使用本机 Xcode 工具链，无第三方 Swift 依赖：

```bash
./script/build_and_run.sh          # Debug 构建、签名、启动
./script/build_and_run.sh --verify # 另检查启动后的进程
./script/test.sh                   # Xcode 核心单元测试与 xcresult
./script/package.sh                # Release Intel + Apple Silicon 通用应用及 zip
```

可直接打开 `PathBridge.xcodeproj`，使用 `PathBridge` scheme。启动脚本还支持 `--build`、`--debug`、`--logs` 和 `--telemetry`。

工程使用 Swift 6 严格并发、macOS 15.7 deployment target、Hardened Runtime；使用本机 Yuna Kamisato 的 Developer ID Application 证书（Team `852H844JG2`）手动签名。主应用没有启用 App Sandbox，以便读取用户指定的网络卷路径和调用系统 NetFS；Finder 扩展独立启用 App Sandbox，仅传递用户选择的本地路径。更换开发者时在 Xcode 的 Signing & Capabilities 中修改团队和证书，或通过 `PATHBRIDGE_SIGNING_IDENTITY` 与 `PATHBRIDGE_DEVELOPMENT_TEAM` 环境变量覆盖脚本签名设置；本地开发可使用 `PATHBRIDGE_SIGNING_IDENTITY=-`。

自行执行 `package.sh` 得到的是本机签名构建，仍需另行公证；GitHub Release 的 DMG 已完成公证。登录时启动使用系统 `SMAppService.mainApp`，可能需要用户在系统设置中允许。

独立核心也可执行 `swift test`。`Tests/Integration/Smoke.swift` 是需手动运行的真实 SMB/钥匙串验证程序，不属于默认测试，也不包含真实账号密码；`script/build_smoke.sh` 在完成 Debug 构建后编译它。集成程序不会向 SMB 写入文件，真实连接及本机配置/钥匙串写入需使用者明确授权。

## 模块

- `Sources/PathBridgeCore`：Storage 模型、映射校验、剪贴板文本解析、纯路径转换。
- `App/Services`：NetFS 挂载与取消/90 秒超时、Keychain 凭据、Carbon 全局快捷键、系统剪贴板。
- `App/Stores`：配置持久化、打开/复制操作、共享状态及登录项管理。
- `App/Views`：菜单栏、映射与凭据编辑、转换预览、通用设置。
- `FinderExtension`：原生 Finder Sync 扩展，复用核心命令编码，通过主应用执行转换。
- `Tests/PathBridgeCoreTests`：路径格式、编码、子目录映射、边界与配置校验。

SMB 状态在菜单或设置可见时每 10 秒刷新，打开与复制前也会刷新。应用不持续扫描剪贴板，不保存路径历史。状态刷新使用 `getfsstat(MNT_NOWAIT)` 读取内核缓存，不探测宗卷内容。独立 Finder Quick Action 暂未提供，右键操作由内置 Finder Sync 扩展实现。

系统接口参考：[NetFS](https://developer.apple.com/documentation/netfs)、[Finder 文件定位](https://developer.apple.com/documentation/appkit/nsworkspace/selectfile(_:infileviewerrootedatpath:))、[登录项](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)。

## 参与开发

欢迎提交问题与 Pull Request。请先阅读 [贡献指南](CONTRIBUTING.md)、[安全政策](SECURITY.md) 与 [更新记录](CHANGELOG.md)。本机历史验证及尚未覆盖的范围见 [VALIDATION.md](VALIDATION.md)，不代表每个环境均已验收。

可选 CodeGraph 索引用于本地代码导航，数据库不入库：

```bash
codegraph init .
codegraph explore "PathResolver"
codegraph sync
```

## 许可

本项目采用 [MIT License](LICENSE)，允许使用、修改和分发，须保留版权及许可声明。

## 图标与分发构建

应用图标源文件位于 `App/AppIcon.icon`，可用 Xcode 内的 Icon Composer 打开编辑；Xcode 会同时生成旧版 macOS 所需的图标资源。菜单栏继续使用单色符号，关于页显示应用图标。

```bash
./script/package.sh       # Developer ID 签名通用应用
./script/create_dmg.sh    # 生成含 Applications 快捷入口的签名 DMG
# 公证 profile 需先通过 notarytool store-credentials 在本机配置
PATHBRIDGE_NOTARY_PROFILE=PathBridge ./script/notarize.sh
```

公证脚本依次公证应用、附加票据、重新生成 DMG，再公证并附加 DMG 票据，最后执行 Gatekeeper 验证。只有验证通过的 DMG 才用于 GitHub Release 分发。公证日志保存在被 Git 忽略的 `build/notarization/`。
