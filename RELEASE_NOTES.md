# CNKH POS Mobile 1.10.4+32

- 拉取完整进货历史时保留本机采购附件及其同步状态。
- 进货附件上传失败时暂缓该附件并继续处理后续 outbox 操作，避免阻塞销售上传；失败附件保留重试。
- Android Release 不再使用 Debug 签名；Release 构建要求配置稳定 keystore。
- 同步协议文档更新至配套 Desktop / Mobile 1.10.4+32。

## 验证

Mobile 静态分析、完整测试、使用临时签名密钥构建并检查 Release APK，以及与配套 Desktop 的 LAN HTTP 回归均通过。正式 APK 使用仓库配置的稳定 keystore。旧版 APK 使用 Debug 签名，Android 可能无法直接覆盖安装；升级前请先同步并备份门店数据，再按需重装。
