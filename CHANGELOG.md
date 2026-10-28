# CNKH POS Mobile change log


## 1.10.14+42 — 2026-10-28，DuitNow 自动核销 + 播报新文案

- **结账自动对账核销**：结账页选 DuitNow QR 等待收款时，若银行到账推送金额与应付完全一致，弹出绿色到账确认，5 秒内可点「不是这单」否决，无操作则自动完成销售入账；同一银行参考号只核销一次，防重复入账。
- **到账播报文案**：统一为「DuitNow 收款成功，X 令吉 Y 仙」（令吉与仙分开念，与服务器播报一致）；收款记录重播同步使用新文案。

## 1.10.13+41 — 2026-10-28，账号服务器化：三端共用账号密码

- **账号以服务器为主（auth_v1）**：云端主机新增账号接口，登录改为向服务器校验 PIN；三台设备（网页/手机/电脑）共用同一套账号密码，不再各设各的。
- 任一端修改 PIN、新增/停用账号后自动推送到服务器；其他端下次登录即以服务器为准。
- 登录页新增「服务器设置」：新设备/新浏览器先填服务器地址 + 令牌，之后直接用全店共用账号登录，不再被要求在本机重新设置密码。
- 服务器无账号而本机已有账号时，管理员首次登录会自动把本机账号上传到服务器完成迁移。
- 修复：补回本文件缺失的 1.10.12+40 条目（app_version 测试要求版本号出现在 CHANGELOG）。

## 1.10.12+40 — 2026-10-28，收款记录 + 喇叭重播 + 网页角色入口

- 管理中心新增「收款记录 Payments」：读取服务器到账台账（金额、银行流水号、时间，含今日/本月/累计汇总）。
- 收款记录每行右侧新增喇叭按钮，点击按实时播报同一路径重新播报金额（只播金额）。
- 补回仓库缺失的到账播报监听服务与其接线（payment_broadcast_listener）。
- 网页版入口改为先选角色（/admin 或 /staff）再输 PIN 登录。


## 1.10.11+39 — 2026-10-08，首次固定 Release Key 签名的 Mobile 版本

- 仅 Mobile 安装包签名与发布系统更新：使用固定 CNKH Keystore，不允许 Android Release 回退到 Debug 证书，并校验官方证书 SHA-256。
- 递增 Android versionCode 为 39，versionName 为 1.10.11。配套 Desktop 暂保持 1.10.10+38；Mobile 业务功能与配对协议兼容原版。
- Flutter 业务功能、页面 UI、商品库存、离线收银、SQLite schema v10、`cnkh-sync:v1`、MyInvois 状态同步均不修改。
- **升级警告：** 历史 1.10.10+38 及更旧 Debug 签名 APK 不能直接被新证书覆盖；先在旧设备备份并验证恢复，未同步交易未备份时绝不要卸载旧应用。
- APK 及验证状态以 [GitHub v1.10.11-mobile Release](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.11-mobile) 和其 Actions 记录为准。实机安装及生产门店完整迁移仍需现场验收。


## 1.10.10+38 — 2026-10-08，安装包待 CI 构建

- **F01（双端）** 逐行删空购物车时清除整单折扣，下一笔销售不再继承旧折扣。
- **F04（Mobile）** 清除交易前保护未同步销售及依赖交易记录的待处理任务，防止销售和上传任务丢失。
- **F05（双端）** 商品保存、进货建品和电脑接收修改采用一致的条码 / SKU 冲突检查；旧歧义数据拒绝扫码误选，不自动删除商品。
- **F07（Mobile）** 完整销售对账时将电脑快照中缺失的已同步销售排除出有效销售；保护离线及待处理记录，失败不推进游标。
- **F08（Mobile）** 销售作废待核对时继续拉取电子发票状态；保留库存保护，暂缓目录和依赖目录的销售拉取，解除后从保留游标重放。
- **F09（双端）** 12 位数字条码使用 Code128 原样编码，打印标签不再自动追加第 13 位。
- **F10（Mobile）** 后台轮询和主动同步重新加载已保存配置；地址或 token 变化后更换旧 WebSocket 连接。
- **F11（双端联动）** 更正发票接口返回原销售收据号，并独立保留 invoice_no，使手机正确关联电脑销售的发票状态。
- **F12（双端）** 新挂单保存售价及显示快照；取单保留原价，同时使用当前库存和删除状态检查，兼容旧挂单。
- **F14（双端）** 现金 / 定金以整数分解析并明确校验，拒绝 NaN、Infinity、指数及超范围输入。
- **F15（双端）** PDF 和蓝牙打印输出已配置的 DuitNow 付款图片，保留比例和留白；缺图时不输出扫码提示。
- 配套版本同时修复Desktop 的进货成本 / 同名商品合并、最终 1.1 内容签名、报表刷新和销售日期边界；完整 16 项清单见 [Release Notes](RELEASE_NOTES.md)。
- 数据库 schema v10 和 `cnkh-sync:v1` 保持不变。
- 本地验证：Mobile 187 项及跨端 HTTP / WebSocket 29 项通过；Desktop 全量 187 项通过、1 项测试等待失败，调整等待后包含电子发票的 25 项定点复测通过。两端 analyze 无 error，条码及收据二维码独立解码通过。
- 发布安装包、校验值、CI 记录和 APK 签名兼容性待核实；未进行实体设备、打印机或 MyInvois 线上验收。

## 1.10.9+37 — source merged 2026-10-03; Android APK not released

- **B001 (Both):** Read the installed Version and Build Number in About instead of maintaining duplicate Dart constants.
- **B002 (Mobile):** Await product image writes so filesystem failures remain inside the existing sync recovery path.
- **B003 (Both CI):** Pin paired repository refs to the companion 1.10.9+37 source commits.
- Completed six audit rounds; Rounds 5 and 6 were clean. Final regression passed Mobile 147/147, Desktop 151/151, and paired integration 29/29.
- SQLite schema v10 and `cnkh-sync:v1` remain unchanged.
- APK publication is withheld because the available 1.10.7+35 APK uses a Debug signing certificate whose matching private key is unavailable; a different signer would prevent in-place Android upgrades.

## 1.10.8+36 — unreleased (APK pending matching signing key)

- **B01** Clear a previous customer-directory phone on customer change/cancel while preserving a manually entered temporary number for the saved sale and eReceipt recipient.
- **B02** Reuse compatible supplier OCR unit conversion memory and keep base-unit stock/cost values in the purchase sync payload; require review for unit conflicts and honor manual edits.
- **B04** Merge only unmapped matching customers/suppliers; keep immutable remote identity mappings and historical references when Desktop deletes and recreates an entity.
- **B05** Block transaction cleanup while purchase, OCR attachment, or purchase-reversal outbox requests remain unresolved, including an ACK-lost request; keep unrelated catalog operations.
- **B06** Persist a click-time held-cart snapshot, guard duplicate submits, and clear only an unchanged cart after success.
- **B07** Apply exact barcode precedence and deterministic ID ordering in SQL before product pagination.
- **B08** Persist Desktop tax-state sale-void rejections as `needs_review`, allow safe independent operations to proceed, and retain the original operation ID for an explicitly reviewed retry.
- **B09** Refresh catalog/category/image settings in the retained cart screen without repricing cart snapshots or replacing manual discounts.
- **B10 / R03** Use bundled Noto Sans SC and multi-page 80 mm receipt layout for Chinese content and long receipts.

MyInvois signing changes are not included. Latest official requirements and an independent verifier remain necessary to resolve R02. No production submission or cancellation was performed.

## Ongoing maintenance

For each future build, update `version` in `pubspec.yaml` and add the real changes to this file. About reads Version + Build Number from installed package metadata; do not add a second version constant. Keep prior release entries. `test/app_version_test.dart` checks the runtime label and changelog version.
