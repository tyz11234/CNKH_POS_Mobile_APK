# 黄金发宝号 · CNKH POS Mobile

用于 Android 手机的门店收银客户端，与 [CNKH POS Desktop](https://github.com/tyz11234/CNKH_POS_Desktop) 配套使用。支持本地收银、离线业务、局域网同步，以及 **本机 OCR 智能进货**。

基于 **Flutter / Dart**，使用本地 SQLite 保存业务数据。核心收银与店内同步不依赖云服务器。

> README 最后更新：**2026-10-08**。默认源码与发布分支：main。

## Mobile 1.10.11+39 — 首个固定证书签名版本

**首次正式签名版本：** Mobile 1.10.11+39，新证书身份；原有 [1.10.10+38 Debug Release](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.10-mobile) 完整保留，不覆盖、不重新命名。

- [GitHub 1.10.11 Mobile 正式签名发布页](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.11-mobile)（是否已正式发布及安装包 SHA-256，请以 Release 页面实时显示为准；流水线未完成时该链接可能尚不存在）
- 本次仅更新 Mobile 签名和版本号；Flutter 页面与业务代码未修改，SQLite schema v10、LAN `cnkh-sync:v1` 不变。Desktop 仍为 1.10.10+38。
- **首次换签不可覆盖旧 Debug 包。** 如有收银数据，请先完成可恢复的全量备份及实测迁移；未验证前不要卸载旧 App。

## Android 正式签名：固定 Keystore 与升级安全说明（2026-10-08）

> **历史 v1.10.10+38 APK 仍为 Debug 签名。** v1.10.11+39 是另一个独立的固定证书签名版本；是否成功发布、能否安装及升级，应分别查看 Release 页面、CI 和实机结果。严禁误把旧 Debug 包当作正式签名。

- 正式签名身份使用固定的 CNKH POS Mobile 密钥；证书 SHA-256 为 `6A:BA:50:A8:9D:F9:52:C1:7A:82:1C:7C:F5:6D:86:1D:6C:22:72:CD:A9:55:5C:E7:65:23:32:92:1A:84:99:C7`（证书指纹可以公开，私钥不能公开）。
- `android/app/build.gradle.kts` 的 Release 构建必须通过 `CNKH_ANDROID_KEYSTORE_PATH`、`CNKH_ANDROID_KEYSTORE_PASSWORD`、`CNKH_ANDROID_KEY_ALIAS`、`CNKH_ANDROID_KEY_PASSWORD` 提供密钥；**不再允许 Release 自动回退为 Debug 签名**。
- GitHub 仓库 **Settings → Secrets and variables → Actions → Repository secrets** 配置四项：`CNKH_ANDROID_KEYSTORE_BASE64`（JKS 的 Base64）、`CNKH_ANDROID_KEYSTORE_PASSWORD`、`CNKH_ANDROID_KEY_ALIAS`、`CNKH_ANDROID_KEY_PASSWORD`。密钥和密码不得写进源码、Issue、PR 或构建日志。Base64 不是加密。
- 在 GitHub **Actions → CNKH signed APK validation (no Release) → Run workflow（main）** 手动运行独立验证；只有密钥及证书指纹符合要求，且 Analyze、测试、培训截图生成、APK 生成、`apksigner` 签名检查和版本校验均通过时，才会生成可下载的 **CNKH_POS_Mobile_OfficialSigned** 工作流 Artifact。此工作流**不会**创建或覆盖 GitHub Release。
- 现有 `Mobile CI` 的后续正式 tag/`[release]` 发布也必须使用固定证书，签名指纹不符会失败。发布新版本前应提高 `pubspec.yaml` 的 Version Code；不得复用历史 `v1.10.10-mobile` Release 当作新签名产物。
- **首次由历史 Debug APK 切换到正式签名 APK，不是无损覆盖升级。** 不同签名下 Android 会拒绝覆盖安装；如卸载旧应用，本地 SQLite、SharedPreferences、图片和未同步 Outbox 可能丢失。必须先完成实际可恢复的完整备份与迁移验证，不能只凭“已与 Desktop 同步”就认定所有数据已备份；迁移未验证时不要卸载现有 POS。
- 正式签名后，未来沿用**同一 Application ID、同一私钥**并递增 Version Code 的 APK 才具备直接覆盖升级条件；仍须验证数据库迁移和真机安装。本次仅更改 Android 打包与发布机制，没有修改 Flutter 页面、收银、数据库结构或 LAN 同步业务逻辑。
- 私钥应保留多份**离线加密备份**。此密钥曾在聊天交付过程中处理过；正式面向真实门店使用前请评估暴露风险、保护文件访问，并根据安全状况决定是否更换密码或密钥（更换私钥会改变证书指纹并影响后续升级）。

## 2026-10-08 · Mobile 1.10.10+38 APK 已发布（Debug 签名）

本次修复审查发现的 16 项问题，涵盖购物车折扣、进货金额与商品匹配、未同步销售保护、条码 / SKU 唯一性、电子发票签名、双端销售对账、挂单价格、报表刷新、金额输入和 DuitNow 收据输出。SQLite schema 保持 **v10**，LAN 协议保持 **`cnkh-sync:v1`**。

- 收银与商品：删空购物车清除旧折扣；新挂单保留原售价；拒绝歧义条码 / SKU 和非法金额；12 位条码标签原样输出。
- 进货与报表：不同成本批次及不同商品不再误合并；电脑报表及时刷新，日期筛选不再漏掉最后一秒。
- 同步与电子发票：保护未上传销售；完整对账处理电脑恢复旧备份后的缺失销售；待核对作废仍更新发票状态；同步设置立即重载；更正发票状态正确关联，签名使用最终 1.1 内容。
- 收据：PDF 与蓝牙打印输出已配置的 DuitNow 付款图片，缺图不显示扫码提示。

完整逐项说明见 [变更记录](CHANGELOG.md) 和 [Release Notes](RELEASE_NOTES.md)。此前 [Bug Audit](docs/BUG_AUDIT.md) 与 [回归矩阵](docs/FEATURE_TEST_MATRIX.md) 保留历史审查记录，本次验证以本页和 Release Notes 为准。

## 当前源码与发布包

| 项目 | 本次源码版本 | 本次安装包状态 |
| --- | --- | --- |
| Desktop | **1.10.10+38** | Windows x64 Setup.exe 与 ZIP 已发布并校验 |
| Mobile | **1.10.10+38** | Android APK 已发布并校验（Debug 签名） |
| 数据兼容 | schema v10 / cnkh-sync:v1 | 保留现有数据库增量迁移 |

## 下载与更新

Windows 与 Android **1.10.10+38** 已发布，均已从 GitHub 重新下载并通过校验。Android 包按维护者要求使用 Debug 签名。

| 本次产物 | 版本 | 下载 / 状态 |
| --- | --- | --- |
| Windows x64 Setup.exe 安装包 | 1.10.10+38 | [下载安装包](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.10/CNKH_POS_Desktop-windows-x64-v1.10.10-38-Setup.exe) |
| Windows x64 ZIP 便携包 | 1.10.10+38 | [下载便携包](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.10/CNKH_POS_Desktop-windows-x64-v1.10.10-38.zip) |
| Android APK | 1.10.10+38 | [下载 APK](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.10-mobile/CNKH_POS_Mobile.apk)（Debug 签名） |

[Windows Release v1.10.10](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v1.10.10) · [SHA-256 校验文件](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.10/SHA256SUMS.txt)

[Mobile Release v1.10.10-mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.10-mobile) · [版本化 APK](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.10-mobile/CNKH_POS_Mobile_v1.10.10.apk) · [APK SHA-256 校验文件](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.10-mobile/SHA256SUMS.txt)

| 发布文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| CNKH_POS_Desktop-windows-x64-v1.10.10-38-Setup.exe | 15168784 | `9e52049b4ca56cddd4147b5ed908a4251bdddb4e82dc4a2513976399b7427b34` |
| CNKH_POS_Desktop-windows-x64-v1.10.10-38.zip | 18350569 | `aa099af7b5153c05707324f068f74f33d0a88d3203ee329733383f3924e96f7b` |
| CNKH_POS_Mobile.apk（版本化 APK 内容相同） | 115822239 | `5b7ac868de253bd72b66b8cdf1df6d289464632fc85836f7d1beab1f19ea160b` |

Windows 更新前先备份业务数据并关闭程序。Setup.exe 按当前用户安装到 `%LOCALAPPDATA%\Programs\CNKH POS Desktop`，支持 Windows 10 1809 及以上的 x64 环境；安装及卸载只管理程序目录，不迁移或清除文档目录中的业务数据库。便携 ZIP 请解压到独立目录，保留 EXE、DLL 和 `data` 文件夹。安装器未配置 Windows 代码签名，可用上述 SHA-256 校验下载文件。

本次 Android APK 是 Release 构建，按维护者要求使用 **Android Debug 签名**；证书 SHA-256：`5e52d71bf713265e9e8fffb0606d3c903c0250f6cf541f3ee6d9a4b2954099e9`。**本次证书与已发布的 1.10.7+35 不同，无法直接覆盖安装旧版。** 请先同步并备份业务，保留仍有未同步数据的旧应用。此 Debug 密钥不保证在后续构建中复用；签名不匹配时 Android 会拒绝覆盖安装。

历史版本可在 [Desktop Releases](https://github.com/tyz11234/CNKH_POS_Desktop/releases) 和 [Mobile Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases) 查找，旧包不包含本次全部修复。

## 本次验证

- Desktop 发布流水线 [37782987933](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37782987933) 全部成功：完整测试 **188 项通过**，培训截图及图片显示测试通过，Windows Release 编译、11 组培训资源、安装器及便携 ZIP 验证通过。首次安装和重复安装均核对 **56 个文件**的 SHA-256，安装测试没有启动 POS。
- Mobile 发布流水线 [37784970334](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37784970334) 全部成功：完整测试 **187 项通过**，双端培训截图、图片显示、APK Release 编译、培训资源、INTERNET 权限及 `apksigner` 签名验证通过。
- 两端真实 HTTP / WebSocket 配套回归 [37784970356](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37784970356) **29 项通过**；实际配对源码为 Desktop `8acda041983a10ab6f83fdbaae41be7a2e3e2c2c` 与 Mobile `c016ce1c90bdcff11ed63f0a2cfc562dc4ee93e9`。Desktop 发布提交 `9ae58847a43a3a70f481a22ba246591c0eb9f3b9` 仅追加安装器版本检测修正，业务源码相同。
- 两端 CI 的 `flutter analyze --no-fatal-infos --no-fatal-warnings` 均通过，未发现 error；保留原有 warning / info。
- 本地独立 ZXing 解码验证通过：两端 12 位条码均读回原内容；两端 PDF 及 384 / 576 dots ESC/POS 栅格中的 6 个二维码产物均读回正确测试内容。
- 本地 `git diff --check`、修复源码包完整性和补丁应用检查通过。

Windows EXE 与 ZIP 已从正式 Release 重新下载，SHA-256、ZIP 完整性、x64 程序、运行库和 11 组培训图片 / 箭头元数据验证通过。Android APK 校验通过：包名 `com.cnkh.cnkh_pos_mobile`、版本 `1.10.10` / build `38`、3 种架构、16 组培训图片 / 箭头元数据及 Debug 证书指纹均已核对。实体 Windows / Android 设备、打印机、门店网络和 MyInvois Sandbox / Production 线上验收未执行。

<details>
<summary>历史记录：1.10.9+37 源码、旧版安装包和验证（2026-10-03）</summary>

### 2026-10-03 · Mobile 1.10.9+37 源码已合并，APK 暂未发布

本轮修复 About 从已安装应用元数据读取版本、Mobile 商品图片异步写入错误处理，并将双端配对 CI 锁定到本轮源码。SQLite schema 仍为 v10，LAN 协议仍为 `cnkh-sync:v1`。六轮 Audit 已完成，Round 5 和 Round 6 Clean。

Final Regression：Mobile **147/147**、Desktop **151/151**、跨端 HTTP 集成 **29/29**；两端 analyze 均 0 errors。按最新配对 SHA 执行的 Mobile 全量 CI 与双端集成均通过。

**Mobile 1.10.9+37 APK 暂未发布。** 当前可下载的 1.10.7+35 APK 使用 Android Debug 签名证书（SHA-256 `51d08c3a894a972f03cfd99dac38a468ffba9de58f0062f6a3bba5b07da57406`）。当前环境没有可验证为相同签名的私钥；不同签名会使 Android 拒绝覆盖安装。为保护本地离线业务数据，本轮没有创建 Mobile APK 或 Release tag。

配套 Desktop **1.10.9+37** 已发布并从 GitHub 重新下载校验。Windows ZIP 为 **17,516,801 字节**，SHA-256 `5b02d3ce4eb00e57796dc5fd3360d48d6acb1abcb493d2fbed6d23d39848870f`。压缩完整性、EXE、Flutter runtime、data 和 11 组培训 PNG/JSON 均通过；未在 Windows 桌面会话实际启动程序。

详见 [变更记录](CHANGELOG.md)、[Release Notes](RELEASE_NOTES.md)、[Bug Audit](docs/BUG_AUDIT.md) 和 [完整回归矩阵](docs/FEATURE_TEST_MATRIX.md)。

### 当前源码与发布包

| 项目 | 当前源码 | 最新可下载包 |
| --- | --- | --- |
| Mobile main | **1.10.9+37** | Android APK **1.10.7+35**（签名兼容门槛） |
| 配套 Desktop main | **1.10.9+37** | Windows ZIP **1.10.9+37** |
| LAN 协议 | cnkh-sync:v1 | schema v10，增量升级旧数据库 |
| OCR | 本机 Latin + Chinese ML Kit | 不使用云 OCR |

### 下载与更新

- [Android APK（1.10.7+35）](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.7-mobile/CNKH_POS_Mobile.apk)
- [版本化 APK（1.10.7，内容相同）](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.7-mobile/CNKH_POS_Mobile_v1.10.7.apk)
- [APK SHA-256 校验文件](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.7-mobile/SHA256SUMS.txt)
- [Mobile Release v1.10.7-mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.7-mobile)
- [Windows x64 ZIP 便携包（1.10.9+37）](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.9/CNKH_POS_Desktop-windows-x64-v1.10.9-37.zip)
- [Windows ZIP SHA-256 校验文件](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.9/SHA256SUMS.txt)
- [Desktop Release v1.10.9](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v1.10.9)

| 发布文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| CNKH_POS_Mobile.apk | 115187111 | ba6e763059eebcee46ef8d55962546f92e3f4332391da82fedc81fb204e6e3ad |
| CNKH_POS_Desktop-windows-x64-v1.10.9-37.zip | 17516801 | 5b02d3ce4eb00e57796dc5fd3360d48d6acb1abcb493d2fbed6d23d39848870f |

Mobile APK 与校验文件已重新下载并验证 SHA-256、ZIP 完整性；它是 1.10.7+35，并非当前 1.10.9+37 源码产物。Windows 包从正式 Release 重新下载，checksum、ZIP 结构和关键文件通过。

**Android 升级前请同步业务并备份。** 不要卸载仍保存未同步业务的旧版本；若系统报告签名不匹配，停止安装并保留旧应用数据。Windows ZIP 是便携包，不含安装向导。关闭程序并备份后，解压到独立目录，运行 `cnkh_pos_desktop.exe`；保留同目录 DLL 和 `data` 文件夹。

Mobile 主线 CI [37129727944](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37129727944)、按配对 SHA 的 HTTP 集成 [37129727823](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37129727823)、Desktop Windows Release [37130267034](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37130267034) 均成功。桌面培训资源检查 [37130266986](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37130266986) 通过。

</details>

## 2026-10-01 · 1.10.6+34

- 配对前的本地业务持久化到 Outbox；首次同步先上传再应用目录。v10 恢复可核实的旧未配对业务，库存基线与业务增量分开上传，重试保持幂等。
- 同步 Desktop 的完整库存活动，销售后作废也会阻止不安全撤销。配对撤销收到 ACK 后才执行本机反向流水；明确拒绝保留请求与审计，未知结果等待原请求确认。
- 完整目录停用快照中消失的已映射资料，保护未上传业务；独立进货历史同步同样等待待确认操作。
- 手动进货事务保存进货前成本，重复商品行共享原快照；配对后采用 Desktop 权威成本。同步最终 Invalid 状态，纠错提交仍由 Desktop 处理。

GitHub Actions 已实际执行：Mobile 完整测试 **124 项**、Desktop **116 项**、双端真实 HTTP 回归 **19 项**全部通过；Android Release APK 与 Windows Release 构建通过。分析采用现有 CI 参数 `--no-fatal-infos --no-fatal-warnings`：Mobile **0 error / 5 warnings / 37 infos**，Desktop **0 error / 6 warnings / 38 infos**。正式 Release 的 main 工作流也已重跑通过，安装包与校验文件已上传。逐项证据、命令、日志与范围见 [FIX_VERIFICATION.md](FIX_VERIFICATION.md)。

1.10.6 历史 APK 是 Release 构建，实际使用 **Android Debug 签名证书**；没有使用稳定发布 keystore。证书 SHA-256：`4e28edc15b7df8f8fe3245805e7a7db7e88ba5c5217cd76fa196d993b12f2fc4`。该证书不保证与旧 APK 或未来构建一致；签名不匹配时 Android 会拒绝覆盖安装。请保留旧版，先同步并备份业务数据，尤其是未确认的离线操作；卸载会清除应用本地数据。

## 2026-09-26 · 源码与 APK 1.10.5+33

- Desktop 在同一事务中保存进货执行前成本，撤销恢复电脑真实成本；重复上传和撤销保持幂等。
- Desktop 回退进货游标时，手机自动全量校正采购历史；失败不推进游标，也不影响库存或待同步附件。
- 手机发现 Desktop 目录库存已变化时拒绝不安全的进货撤销；持续失败的采购附件仍重试，但不阻塞销售与目录拉取。
- e-Invoice 设置重新打开后正确显示已保存的证书名称。
- 更新包使用新版本号；APK 签名方式以 Release 页面及下方升级说明为准。

本版本回归范围与验证结果见 [Release Notes](RELEASE_NOTES.md)。

## 2026-09-24 · 源码与 APK 1.10.4+32

- 完整拉取进货历史时保留本机采购附件及其同步状态。
- 进货附件上传失败时单独延迟重试，并继续处理后续 Outbox 操作，避免附件问题阻塞销售上传。
- 本次 Android APK 使用 Debug 签名；后续正式更新建议配置稳定 keystore。
- LAN 同步及 Release Notes 更新至配套 Desktop / Mobile **1.10.4+32**。

本次变更范围和验证记录见 [Release Notes](RELEASE_NOTES.md)。如需从旧 APK 升级，请先完成业务同步和备份；签名不匹配时需要卸载旧 APK，可能清除本地数据。

## 2026-09-20 结账与数据保护修复

- 保存结账时禁止关闭或重复点击；成功落库后立即处理购物车，即使页面被程序移除也不会依赖旧页面回调才能完成。
- 找零使用已保存销售的应付和实收金额，避免购物车清空后金额变成零。
- 取单前请先挂单或清空当前购物车；不再直接覆盖当前商品，连续取单也不会重复消费同一挂单。
- 进货列表采用紧凑分页栏，恢复有数据列表的可见区域。
- 商品图片下载独立排队并持久保存在本机；失败后稍后重试，重启仍保留。第一次开启图片功能会补查完整商品目录。
- 每轮最多处理 4 张图片，失败至少等待 30 秒再尝试；图片失败不回退销售同步。图片很多时会逐批补齐。

保持数据库 schema v9、现有金额算法、离线销售及 LAN 协议不变。修复范围、测试和限制见 [BUGFIX_REPORT.md](BUGFIX_REPORT.md)。

## 2026-09-19 手机界面修复（1.10.1）

- 修复商品、客户和供应商页的分页栏撑满屏幕，导致有记录却显示空白的问题；分页栏保持在底部，列表恢复可见和可点击。
- 列表增加加载中、空数据、读取失败及重试提示，保留已有分页、搜索、编辑和多选操作；已有记录列表可下拉刷新。
- 收银页采用统一纵向滚动。向上滑动时顶部操作区移出，商品区域收缩为紧凑卡片，为购物车让出空间；滑回顶部恢复。商品仍可横向浏览和点击加购。
- 空购物车和仅一件商品也能滑动收缩；合计及结账固定在底部，适配小屏、大字体和键盘弹出。
- 员工培训增加收银页收缩后的实际截图；构建核验 16 组实际截图及箭头坐标。
- 本次不修改数据库版本、销售计算、库存、LAN 协议、MyInvois 提交或 Desktop 代码。

测试范围和构建记录见 [MOBILE_LAYOUT_REPORT.md](MOBILE_LAYOUT_REPORT.md)。此版本仍沿用原 debug 签名配置；若 Android 提示签名不一致，请先完成同步和备份，不要直接卸载带有未同步数据的旧版本。

## Malaysia e-Invoice / MyInvois

自 1.10.0 起，e-Invoice 以独立模块接入并保留离线销售。Desktop 负责调用 MyInvois；Mobile 只通过已有配对连接同步状态，不保存 MyInvois 凭据。1.10.3+31 仅统一双端应用版本号；Mobile 业务代码未改动。

### Desktop 设置与提交

1. 管理员登录，打开 **设置 → e-Invoice Setup**。默认选择 **Sandbox**。
2. 输入公司名称、TIN、BRN、MSIC、业务描述、地址、州代码、电话，以及适用的 SST/TTX 登记资料。无登记时按官方规则填写 `NA`。
3. 填写适用的商品分类、整单税种及税率。售价按含税金额映射，保留原折扣、舍入和实售金额。当前仅支持整单相同税种、税率与分类的 MYR 国内普通发票；混合税率、汇总发票和贷项/退款票请在 MyInvois Portal 处理。
4. 输入对应环境的 Client ID / Client Secret，点击 **保存**，再点 **Test Connection**。此按钮验证 OAuth 连接，不等于发票已获验证。
5. 在 **Submission History** 找到销售，点击 **买方资料 / 生成**。填写真实买方 TIN、登记/身份证明及地址，检查生成的 Invoice JSON。
6. 确认金额和环境后点击 **提交**，再点击 **查询 MyInvois**。`Submitted` 仅代表接收；`Validated` 才代表通过验证。查询同一发票至少间隔 5 秒。
7. 正式使用时切换 **Production**，重新保存正式环境专用凭据。Sandbox 与 Production 的设置及提交记录分别保存。

### 状态与错误处理

| 状态 | 含义及操作 |
| --- | --- |
| Pending | 本地销售尚未提交；补齐资料后由 Desktop 提交 |
| Submitted | MyInvois 已接收，等待查询验证结果 |
| Validated | 官方返回 Valid |
| Rejected | 同步拒收且无 UUID；在 Desktop 更正资料后生成新的重试记录 |
| Invalid | 已有 UUID 的最终验证失败；在 Desktop 查询错误并创建关联纠错尝试，保留原 UUID 与审计 |
| needs_review / submitting | 提交结果未知或程序中断；在 Desktop 核对 Portal UUID 和 Submission UID，不要重提 |
| Cancelled | 官方已确认取消；不会自动退款或改动 POS 库存 |

网络超时、重复提交响应或未知结果会冻结重试，防止重复发票。明确的认证/请求错误允许纠正后重试。取消须填写原因，并由 MyInvois 执行取消期限规则；超期调整、贷项和退款票在 Portal 办理。

### 手机与离线使用

手机继续离线开单。连接 Desktop 后，原 LAN 同步先上传待处理操作并拉取销售；新增 `einvoice_status_v1` 能力通过已认证的 `/api/v1/einvoices` 分页同步状态。手机 **设置 → e-Invoice 状态** 显示本地销售的 Pending / Submitted / Validated / Rejected 等状态，可切换环境。状态目前按分页拉取完整快照，尚未做大量历史记录的压力测试。状态同步失败保留上次结果，不阻断销售同步；旧 Desktop 未声明该能力时仍可正常同步原有业务。

### 数据库与凭据

- Desktop schema **v9** 时引入 `e_invoice_settings`、`e_invoice_documents`、`e_invoice_logs`；v8 及更早版本自动执行增量迁移，原业务表数据不变。
- Mobile schema **v9** 时引入独立 `e_invoice_status` 镜像表；按电脑地址和环境隔离，不修改 sales。
- 当前 schema **v10**：Desktop 保留原提交并增加尝试序号和父记录；Mobile 扩展 Outbox 并恢复可核实的从未配对业务。旧数据库升级、重复迁移及业务数据保留回归已通过。
- Client ID 和 Secret 以 AES-256-GCM 密文保存在 e_invoice_settings，密钥使用操作系统安全存储；OAuth Token 仅驻留内存。日志不记录凭据或完整发票资料。
- 旧 scaffold 中若曾人工保存明文凭据，升级后会清空该明文，需重新输入。公司和提交资料保留。旧备份可能仍含其原始内容，请按敏感资料保管。
- 更换电脑/Windows 用户或丢失 OS 密钥后，需要重新输入凭据。数据库备份保留加密内容，不导出解密密钥。

### CNKH POS Employee Training

右上角及 Settings 原培训入口均提供 11 课：登录与权限、商品销售、收款、退款、库存、手机连接电脑、数据同步、数据备份、e-Invoice 设置、e-Invoice 提交、常见错误处理。

培训使用 `tool/training_capture_test.dart` 实际渲染的应用页面截图；箭头坐标来自真实控件位置，可缩放查看。截图资料为隔离测试数据库内容，配对截图不是门店可用配对码。Desktop 培训使用本版本实际截图；Mobile 的电脑操作课程沿用其工作流固定的 Desktop 源码截图（见下方开发与验证）。

### 开发与验证

完整变更、测试结果、构建记录及已知范围见 [EINVOICE_REPORT.md](EINVOICE_REPORT.md)。手机培训截图使用发布工作流固定的 Desktop 源码 `8acda041983a10ab6f83fdbaae41be7a2e3e2c2c`；双端 HTTP 联调读取 `.github/paired-*-ref` 固定配套源码，手动运行可指定 companion ref。

发布 CI 执行 `flutter analyze --no-fatal-infos --no-fatal-warnings`、完整 `flutter test`、真实页面截图捕获，再执行 Windows/APK Release 构建。截图先生成到 `assets/training/` 再打包。源码首次运行前也需要生成截图；Mobile 截图流程须准备 `.training_desktop` 源码及其字体，参照 `mobile-ci.yml`。双端真实 HTTP 回归位于 Desktop `integration/`，运行 `flutter test test regression`。

目前 API 自动测试使用 HTTP 模拟响应，覆盖 OAuth 缓存/过期/401、提交成功/失败、重复提交和结果未知。真实 MyInvois Sandbox / Production 验收需要店主提供的已授权凭据，目前未执行真实税务提交。构建成功不等于真实设备、打印机或门店网络已验收。

发票映射以 **Invoice 1.0** JSON 为输入，Desktop 当前源码会生成 MyInvois 指南要求的 **Invoice 1.1** 签名结构。Desktop 必须导入有效的 PFX/P12 证书；真实 Sandbox / Production 提交尚未验收。

官方依据：[环境和版本 FAQ](https://sdk.myinvois.hasil.gov.my/faq/)、[Invoice 1.0](https://sdk.myinvois.hasil.gov.my/documents/invoice-v1-0/)、[JSON 数字签名指南](https://sdk.myinvois.hasil.gov.my/signature-creation-json/)、[OAuth](https://sdk.myinvois.hasil.gov.my/api/07-login-as-taxpayer-system/)、[提交](https://sdk.myinvois.hasil.gov.my/einvoicingapi/02-submit-documents/)、[查询](https://sdk.myinvois.hasil.gov.my/einvoicingapi/06-get-submission/)、[取消](https://sdk.myinvois.hasil.gov.my/einvoicingapi/03-cancel-document/)。

## 2026-09-13 同步与恢复修复

- 手机离线开单后作废，且没有中间库存操作时，直接同步作废状态，避免电脑零库存阻塞整条队列；客户等无库存影响的编辑不阻止合并。
- 已经入库的销售遇到确认响应丢失，重试作废只回补一次；存在中间盘点等库存依赖时，仍按原操作顺序同步。
- 手机手动全量对账会等待进货历史同步并执行全量拉取；失败或电脑不支持时显示错误，不再提示全部完成。
- 电脑版恢复备份时，会把已备份的商品图片引用改为当前电脑路径，兼容旧 Windows 用户目录。

两端本轮共新增 13 项回归测试和 2 项真实 HTTP 联调用例；发布流程执行本端完整测试、静态分析和构建。两端组合联调为 8 项。未执行真机升级、打印机和真实门店局域网验收。

## 2026-09-13 修复发布

- 修复单号并发重复、销售同步去重及小票改号后的库存流水关联。
- 修复同一商品多行进货撤销的数量计算，并加强流水缺失、数量不符和系统时间回拨时的撤销保护。
- 修复商品搜索对只读数据库结果排序导致的异常。
- 商品编辑按原始快照合并字段，保留期间更新的库存和成本；库存冲突时拒绝覆盖。
- 商品库存编辑记录流水，手机同步到电脑也保留流水，阻止不安全的旧进货撤销。

完整说明见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。

## 主要功能

| 模块 | 功能 |
| --- | --- |
| 收银 | 商品搜索、摄像头扫码、购物车、折扣、挂单与取单 |
| 收款 | 现金、银行卡、DuitNow、赊账、找零 |
| 商品与库存 | 商品、分类、库存、成本、售价、盘点 |
| 客户与供应商 | 客户、供应商、赊账、进货 |
| OCR 进货 | 拍照/相册、本机 OCR、Draft、匹配、异常检查、人工确认、撤销 |
| 销售 | 今日与历史销售、销售详情、作废与库存回补 |
| 小票 | 模板编辑、预览、PDF、WhatsApp、可选蓝牙打印 |
| 报表 | 销售、库存及基础经营报表 |
| LAN 同步 | QR 配对、HTTP 对账、WebSocket、离线 Outbox、自动重试 |
| 账号 | 管理员/员工权限、PIN 验证、员工 PIN 设置 |

现有收银金额、折扣、舍入规则和原有手动进货流程保持不变。

## v1.9.0：本机 OCR 智能进货

OCR 的设计原则是：**识别只负责预填，人工确认前绝不修改正式库存或成本。**

固定流程：

```text
拍照 / 相册
    ↓
本机 OCR
    ↓
OCR Draft
    ↓
商品匹配 + 异常检查
    ↓
人工预览 / 修改
    ↓
人工确认
    ↓
SQLite 原子入库
    ↓
Persistent Outbox
    ↓
Desktop 1.10.8+36
```

### OCR 入口

```text
管理 / Admin
→ 进货 / Purchases
→ +
```

可以选择：

- 拍照扫描进货单
- 从相册选择进货单
- 继续之前保存的 OCR 草稿
- 原有手动进货

### OCR 会尝试识别

- Supplier / 供应商
- Invoice No
- Invoice Date
- 商品名称
- Qty
- Unit
- Unit Cost
- Line Subtotal
- Discount
- Tax / SST
- Delivery / Freight / Shipping / Handling
- Other Fee
- Invoice Total / Grand Total

Discount、SST、Delivery、Other Fee 会作为整单费用处理，不会直接当普通商品行。

### 商品匹配与供应商记忆

商品匹配顺序包括：

1. Barcode
2. SKU
3. 商品名精确匹配
4. 规范化名称
5. 模糊名称
6. 该供应商历史确认过的商品别名

系统会记住：

```text
供应商 + OCR 原始商品名称 → POS 商品
```

以后同一供应商再出现相同名称时，可优先复用历史匹配。

商品名称中的部分 `0/O`、`1/I` 混淆会用于名称匹配，但**不会自动修正数量、价格、小计等关键数字**。

### 异常检查

当前包括：

- 数量 <= 0
- 成本 / 小计为负数
- 商品未匹配
- 匹配可信度过低
- `Qty × Unit Cost` 与行小计不一致
- 数量明显高于历史常见进货量
- 单位成本与上次进货成本变化过大
- 系统计算总额与 Invoice Total 不一致
- 未识别 Invoice Total
- 未识别供应商
- 未可靠识别商品行

阻断错误未解决前不能入库；普通警告可在人工确认后继续。

### OCR 草稿

Draft：

- 不改库存
- 不改成本
- 可保存退出
- 可重新打开继续核对
- 保存 OCR 原文
- 保存压缩后的本地进货单图片
- 保存商品匹配与人工修改结果

只有点击 **确认并入库** 后才成为正式 Purchase。

### 原图与审计

进货单图片会：

1. 校正方向
2. 缩小过大尺寸
3. JPEG 压缩
4. 保存到 App Documents 的 `purchase_invoices`
5. SQLite 只保存路径，不直接保存大型图片 BLOB

人工修改前后的 OCR Qty / Unit Cost / Subtotal 会保留，并写入 `purchase_audit_log` 供追溯。

### 单位换算

支持 Conversion。

例如：

```text
1 CTN = 24 PCS
Invoice Qty = 2 CTN
Conversion = 24
库存增加 = 48 PCS
```

普通单件商品保持 `1`。

### 确认入库

确认后会在同一个 SQLite transaction 内：

- 创建 Purchase
- 更新库存
- 更新成本
- 写 `stock_moves`
- 保存 Invoice No / Date / 费用
- 保存 OCR Raw Text
- 关联本地图片
- 更新供应商商品别名记忆
- 写审计记录
- 创建 `purchase` Outbox operation

### 撤销 OCR 进货

管理员可以从进货详情执行 **Reverse purchase**。

撤销不会删除原记录，而是：

- 保留原 Purchase
- 标记 reversed
- 生成负数库存流水
- 回退本次进货库存
- 在安全条件下恢复进货前成本
- 保存撤销人员、时间、原因和备注
- 创建 `purchase_reverse` Outbox operation

重复提交有幂等保护，不会重复扣库存。

## 本机 OCR 与隐私

v1.9.0 使用 Android 本机 Google ML Kit Text Recognition：

- Latin 模型内置 APK
- Chinese 模型内置 APK
- 不调用云 OCR
- 不上传单据到 OCR 云服务
- 无网络也可识别、编辑草稿和本地确认入库

APK 因内置中文 OCR 模型，体积会比 v1.8.x 明显增大。

## 连接电脑端

1. 安装并启动配套 **Desktop 1.10.8+36**。
2. 手机和电脑连接同一 Wi-Fi / LAN。
3. Desktop 打开 LAN / 扫码配对页面。
4. Mobile 扫描电脑二维码。
5. Mobile 保存电脑地址和 Token。

默认端口：**8787**。

二维码前缀：

```text
cnkh-sync:v1|
```

手机断线时仍可本地收银和处理 OCR；恢复连接后自动重试已确认的业务。

## 离线与同步

- Desktop 是店内局域网权威主机
- Mobile 销售、作废、资料修改、进货、盘点使用持久 Outbox
- Desktop ACK 后才从 Outbox 移除
- 重试不会重复销售、重复入库或重复撤销
- WebSocket 用于实时变更提示
- HTTP 用于对账与正式业务提交
- 首次连接失败会继续自动重连
- 盘点/资料冲突不会静默覆盖
- OCR 进货继续使用原有 `purchase` mutation
- OCR 撤销使用 `purchase_reverse`
- `cnkh-sync:v1` 协议版本未变化

## 首次登录

1. 选择管理员 `admin`。
2. 输入自定 **6–12 位数字 PIN**。
3. 再输入一次完成初始化。
4. 管理员可为 `staff`、`staff2` 等员工设置 PIN。

PIN 连续输错 5 次会锁定 5 分钟。Mobile 与 Desktop 账号凭据分别本机管理，LAN 配对不会自动同步 PIN。

## 安装说明

1. 先备份并更新配套 Desktop 1.10.8+36，再安装 Mobile。
2. Android 下载 `CNKH_POS_Mobile.apk`。
3. 按 Android 提示允许当前下载或文件管理 App 安装 APK。
4. 安装后登录并重新确认 LAN 配对状态。

APK 只能安装在 Android，不能直接安装到 iPhone。

本次 APK 是 Release 构建，实际使用 **Android Debug 签名证书**；没有使用稳定发布 keystore。证书 SHA-256：`51d08c3a894a972f03cfd99dac38a468ffba9de58f0062f6a3bba5b07da57406`。 **与 1.10.6 APK 的证书不同，不能直接覆盖安装该版本。** 更新前完成业务同步并备份，保留旧 APK 和未确认的离线操作；不要直接卸载含有未同步数据的旧版，卸载会清除本地数据。Android/Windows 实体覆盖升级尚未验收。

## 验证

本版 main 发布 CI 实际通过：Mobile 完整测试 **130 项**、Desktop **132 项**；使用配套新版源码的真实 HTTP **29 项**通过。Android Release APK 与 Windows x64 Release 构建、培训资源检查均成功。两端 analyze 使用 `--no-fatal-infos --no-fatal-warnings`，Mobile **0 errors / 5 warnings / 37 infos**，Desktop **0 errors / 6 warnings / 38 infos**。[Mobile 发布 CI](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37029961364)、[Windows 发布 CI](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37029953298)、[双端 HTTP](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37029961222)。实体打印、门店旧库/网络、相机 OCR 和真实 MyInvois 尚未验收。

完整命令、诊断与日志见 [ELEVEN_BUG_VERIFICATION.md](ELEVEN_BUG_VERIFICATION.md)。本机 Flutter 初始化受自动审批限制，以上实际结果来自本轮 GitHub Actions。

## 当前不包含

- 云 OCR
- AI / LLM OCR
- 无人工确认自动入库
- Mobile 直接向 MyInvois 提交（由 Desktop 处理；Mobile 可同步状态）
- OCR 自动创建全新商品
- 云端多门店同步

## 分支

| 分支 | 用途 |
| --- | --- |
| `main` | 默认源码分支：完整 Flutter 源码、测试、构建配置及使用说明 |
| `source/main` | 保留的兼容源码分支 |

源码构建：

```bash
git clone --branch main --single-branch https://github.com/tyz11234/CNKH_POS_Mobile_APK.git
cd CNKH_POS_Mobile_APK
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

## 相关入口

- Mobile v1.10.1：https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.1-mobile
- Mobile 源码：https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/main
- Desktop v0.4.0：https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.4.0
- OCR Mobile PR #6：https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/6
