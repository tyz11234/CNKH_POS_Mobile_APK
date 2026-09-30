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
