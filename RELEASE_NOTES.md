# CNKH POS Mobile 1.10.7+35

- F01–F02：首次配对在 ACK 中持久化唯一商品身份；软删除后同码新建保持新旧实体分离，保护历史及未确认操作。
- F03：本地/LAN 作废与税务提交认领共享事务保护；OAuth 等待后重新核对销售，保留 UUID、未知结果和审计。
- F04：以完整流水证明初始库存基线，保留真实后续活动，进货撤销与 Desktop 权威结果一致。
- F05：收据写入隔离缓存子目录，清理只删除有归属记录且内容校验相符的缓存；不确定归属的旧 PDF 保留。
- F06–F07：OCR 行 ID 按草稿稳定隔离；Desktop matcher 通过单一原子进货操作保存真正的执行前成本，失败全部回滚，重试幂等。
- F08：最后管理员必须活动、有管理权限且具备有效登录凭据；取消设置 PIN 不会允许锁死管理入口。
- F09：两端中文蓝牙小票使用内置字库生成 ESC/POS 栅格字节，保持现有打印入口；实体打印机支持尚待验收。
- F10–F11：恢复出厂保留号码防重及税务记录；日结以事务内现金与明确业务日期保存，防止页面缓存过期或跨日错存。

## 兼容性与验证

保持离线收银、现有页面布局、`cnkh-sync:v1` 与 schema v10。本轮不新增数据库版本或重绑历史实体；旧库增量升级、重复 ensure、旧草稿、历史业务及未确认队列保留已有实际回归。首次配对与库存基线修复建议两端同时更新。旧商品已删除的待上传业务仍明确拒绝并保留，需人工核对，不能通过清空队列解决。

修复分支本轮实际通过 Mobile 完整测试 **130 项**、Desktop **132 项**、Desktop `integration/` 真实 HTTP **29 项**。`flutter analyze --no-fatal-infos --no-fatal-warnings`：Mobile **0 errors / 5 warnings / 37 infos**，Desktop **0 errors / 6 warnings / 38 infos**；这不是零告警。main 发布 CI 已对 1.10.7+35 重跑完整测试、培训资源检查及 Android/Windows Release 构建，签名与 INTERNET 检查通过。[Mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37029961364) / [Desktop](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37029953298) / [HTTP](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37029961222)。实际发布命令、运行链接、文件 SHA-256 和签名证书记录于 README 与 [ELEVEN_BUG_VERIFICATION.md](ELEVEN_BUG_VERIFICATION.md)。

## 下载与升级

- [Android APK](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.7-mobile/CNKH_POS_Mobile.apk) / [APK SHA256SUMS](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.7-mobile/SHA256SUMS.txt)
- [Windows x64 ZIP 便携包](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.7/CNKH_POS_Desktop-windows-x64-v1.10.7-35.zip) / [ZIP SHA256SUMS](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.7/SHA256SUMS.txt)

本次 APK 是 Release 构建，实际使用 **Android Debug 签名证书**；没有使用稳定发布 keystore。证书 SHA-256：`51d08c3a894a972f03cfd99dac38a468ffba9de58f0062f6a3bba5b07da57406`。 **与 1.10.6 APK 的证书不同，不能直接覆盖安装该版本。** 更新前完成业务同步并备份，保留旧 APK 和未确认的离线操作；不要直接卸载含有未同步数据的旧版，卸载会清除本地数据。Android/Windows 实体覆盖升级尚未验收。 Windows 包为完整 ZIP 便携包，关闭程序后解压并保留 DLL 与 data。

未执行实体 Android/Windows 升级、门店旧数据库、门店网络/防火墙、相机 OCR、原生分享及实体蓝牙打印机验收；SQLite 旧库与 localhost HTTP 回归不代表现场验收。税务测试全部使用可控 HTTP，没有真实 MyInvois Sandbox/Production 提交。

---

# CNKH POS Mobile 1.10.6+34

- 配对前业务持久化；首次同步先上传再拉取。schema v10 恢复可核实的旧未配对操作，并分离新商品的库存基线与业务增量。
- 同步 Desktop 完整库存活动；配对撤销在 ACK 后才执行本地反向流水。明确拒绝保留请求、补偿旧本地撤销并继续同步；未知结果等待原请求确认。
- 全量目录停用已映射但缺失的资料，保护未确认操作与本地未映射资料；独立进货历史同步保护本机待确认记录。
- 手动进货事务保存原成本快照，重复商品行保持一致；撤销采用 Desktop 实际成本，旧缺失快照不猜测。
- 镜像最终 Invalid；离线销售、现有 POS 操作与 `cnkh-sync:v1` 保留。

## 本次实际验证

- Mobile 完整 `flutter test` **124 项通过**；Desktop 完整测试 **116 项通过**。
- Desktop `integration/` 的 `flutter test test regression` **19 项通过**；实际双端 HTTP 覆盖净零库存、首次配对、重复/丢失 ACK、队列拒绝和备份恢复。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：Mobile **0 error / 5 warnings / 37 infos**；Desktop **0 error / 6 warnings / 38 infos**。这不是零告警分析。
- PR 与 main 发布 CI 的 `flutter build apk --release`、`flutter build windows --release` 及培训资源检查通过；APK、Windows ZIP 与 SHA256SUMS 已正式发布。
- 旧数据库升级用例已执行。本机缺少 Flutter 的退出 127 记录与远端实际结果分别记载，详见 [FIX_VERIFICATION.md](FIX_VERIFICATION.md)。

本次 APK 实际采用 **Android Debug 签名**，证书 SHA-256：`4e28edc15b7df8f8fe3245805e7a7db7e88ba5c5217cd76fa196d993b12f2fc4`；CI 已验证签名、INTERNET 权限及培训资源。该签名不保证与旧 APK 或未来构建一致。签名不匹配时不能覆盖安装；先完成业务同步与备份，保留旧版未确认操作，避免卸载丢失数据。Windows 包沿用完整 ZIP 便携包，解压后运行 `cnkh_pos_desktop.exe`，保留 DLL 和 data 文件夹。

未执行 Android / Windows 真机升级、门店 Wi-Fi / 防火墙 / 打印机验收，未向真实 MyInvois Sandbox / Production 提交税务发票。MyInvois 回归使用可控 HTTP 响应，保留原 UUID、提交尝试和审计信息。

---

# CNKH POS Mobile 1.10.5+33

- Desktop 商品目录下发的库存变化写入本机库存流水；检测到进货后的跨设备库存变动时，手机明确拒绝撤销并保持本地业务与队列一致。
- 进货附件失败继续留在 Outbox 重试，但不再阻断商品、库存和销售记录拉取；真正影响业务数据的待同步操作仍受保护。
- 检测到 Desktop 进货游标回退时自动拉取全量历史；网络或落库失败不推进游标，校正不重复增加库存，也保留待同步业务和附件状态。
- 设置页电子收据缓存操作复用当前 repository，避免测试/嵌入场景误开第二个 SQLite 数据库。
- 与 Desktop 1.10.5+33 配套发布；数据库 schema、离线销售和 LAN 协议保持兼容。

## 验证

Mobile 完整 Flutter 测试 **111 项通过**；分析 **0 error、5 warnings、35 infos**。Desktop 完整测试 **110 项通过**，配套 HTTP 回归 **10 项通过**。Mobile widget 测试复跑后无 SQLite COMMIT 磁盘 I/O 诊断。

Android APK 由 Mobile Release workflow 构建并验证权限、签名和培训资源。若未配置稳定 keystore，按已授权的发布设置使用 Android Debug 签名；签名不匹配时不能覆盖安装，升级前请先同步和备份业务数据。

---

# CNKH POS Mobile 1.10.4+32

- 拉取完整进货历史时保留本机采购附件及其同步状态。
- 进货附件上传失败时暂缓该附件并继续处理后续 outbox 操作，避免阻塞销售上传；失败附件保留重试。
- 本次按需允许通过明确标记的发布提交使用 Android Debug 签名；未配置稳定 keystore 时，只允许此次明确授权的 Debug APK 发布。
- 同步协议文档更新至配套 Desktop / Mobile 1.10.4+32。

## 验证

Mobile 静态分析、完整测试、Android Release APK 构建、签名/权限/培训资源校验，以及与配套 Desktop 的 LAN HTTP 回归均通过。本次 APK 使用 GitHub Actions runner 上的 Android Debug 密钥签名，不是未签名 APK；该密钥不保证与旧 APK 或未来构建相同。若签名不匹配，Android 不允许覆盖安装；升级前请先同步并备份门店数据，再按需卸载重装。后续正式更新建议配置稳定 keystore。
