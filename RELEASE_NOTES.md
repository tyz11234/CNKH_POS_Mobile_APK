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
