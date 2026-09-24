# CNKH POS Mobile 1.10.4+32

- 拉取完整进货历史时保留本机采购附件及其同步状态。
- 进货附件上传失败时暂缓该附件并继续处理后续 outbox 操作，避免阻塞销售上传；失败附件保留重试。
- 本次按需允许通过明确标记的发布提交使用 Android Debug 签名；未配置稳定 keystore 时，只允许此次明确授权的 Debug APK 发布。
- 同步协议文档更新至配套 Desktop / Mobile 1.10.4+32。

## 验证

Mobile 静态分析、完整测试、Android Release APK 构建、签名/权限/培训资源校验，以及与配套 Desktop 的 LAN HTTP 回归均通过。本次 APK 使用 GitHub Actions runner 上的 Android Debug 密钥签名，不是未签名 APK；该密钥不保证与旧 APK 或未来构建相同。若签名不匹配，Android 不允许覆盖安装；升级前请先同步并备份门店数据，再按需卸载重装。后续正式更新建议配置稳定 keystore。
