# 黄金发宝号 · CNKH POS Mobile

用于 Android 手机的门店收银客户端，与 [CNKH POS Desktop](https://github.com/tyz11234/CNKH_POS_Desktop) 配套使用。支持本地收银、离线业务、局域网同步，以及 **本机 OCR 智能进货**。

基于 **Flutter / Dart**，使用本地 SQLite 保存业务数据。核心收银与店内同步不依赖云服务器。

> README 最后更新：**2026-09-23**。`main` 是完整源码与发布分支；`source/main` 仅保留为兼容分支。

## 当前源码与发布版本

| 项目 | 版本 |
| --- | --- |
| Mobile `main` 源码 | **1.10.4+32** |
| 配套 Desktop `main` 与 Windows Release | **1.10.4+32**（`v1.10.4`） |
| 最新已发布 Mobile APK | **1.10.3+31**（`v1.10.3-mobile`） |
| LAN 协议 | `cnkh-sync:v1` |
| OCR | 本机 Latin + Chinese ML Kit，不使用云 OCR |

Mobile **1.10.4+32** 源码的静态分析、完整测试、培训资源校验及双端 LAN HTTP 回归已通过。对应 Release APK 尚未生成：发布流程要求稳定 Android 签名 keystore，当前仓库没有配置。请勿把调试签名或临时签名包当作本版本正式 APK。当前可下载 APK 仍为 **1.10.3+31**。

### 下载

- [最新已发布 Android APK（1.10.3+31）](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.3-mobile/CNKH_POS_Mobile.apk)
- [版本化 APK（内容相同）](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.3-mobile/CNKH_POS_Mobile_v1.10.3.apk)
- [Mobile APK 的 SHA-256 校验文件](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.3-mobile/SHA256SUMS.txt)
- 当前 APK SHA-256：`a89f826c5f9c37a3cfbae7e84f0abf06aadcb183330f0d8c0d41263b6409def6`
- [最新 Mobile Release `v1.10.3-mobile`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.3-mobile)
- [配套 Windows x64 便携包（1.10.4+32）](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.4/CNKH_POS_Desktop-windows-x64-v1.10.4-32.zip)
- [Desktop Windows ZIP SHA-256 校验文件](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.4/SHA256SUMS.txt)

Mobile APK 仍沿用现有 Debug 签名。若 Android 提示签名不一致，请先同步并备份门店数据，再处理卸载重装；不要直接卸载带有未同步数据的旧版本。

## 2026-09-23 · 源码 1.10.4+32

- 完整拉取进货历史时保留本机采购附件及其同步状态。
- 进货附件上传失败时单独延迟重试，并继续处理后续 Outbox 操作，避免附件问题阻塞销售上传。
- Android 正式 Release 改为要求稳定 keystore，不再使用 Debug 签名。
- LAN 同步及 Release Notes 更新至配套 Desktop / Mobile **1.10.4+32**。

本次变更范围和验证记录见 [Release Notes](RELEASE_NOTES.md)。旧 APK 与新正式签名之间可能无法直接覆盖安装；升级前请先完成业务同步和备份。

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
| Rejected | 被拒收或验证失败；核对资料及 Portal 验证结果 |
| needs_review / submitting | 提交结果未知或程序中断；先在 Portal 查找 UUID，再使用“核对 UUID”，不要重提 |
| Cancelled | 官方已确认取消；不会自动退款或改动 POS 库存 |

网络超时、重复提交响应或未知结果会冻结重试，防止重复发票。明确的认证/请求错误允许纠正后重试。取消须填写原因，并由 MyInvois 执行取消期限规则；超期调整、贷项和退款票在 Portal 办理。

### 手机与离线使用

手机继续离线开单。连接 Desktop 后，原 LAN 同步先上传待处理操作并拉取销售；新增 `einvoice_status_v1` 能力通过已认证的 `/api/v1/einvoices` 分页同步状态。手机 **设置 → e-Invoice 状态** 显示本地销售的 Pending / Submitted / Validated / Rejected 等状态，可切换环境。状态目前按分页拉取完整快照，尚未做大量历史记录的压力测试。状态同步失败保留上次结果，不阻断销售同步；旧 Desktop 未声明该能力时仍可正常同步原有业务。

### 数据库与凭据

- Desktop schema **v9**：新增 `e_invoice_settings`、`e_invoice_documents`、`e_invoice_logs`；v8 及更早版本自动执行增量迁移，原业务表数据不变。
- Mobile schema **v9**：新增独立 `e_invoice_status` 镜像表；按电脑地址和环境隔离，不修改 sales。
- Client ID 和 Secret 以 AES-256-GCM 密文保存在 e_invoice_settings，密钥使用操作系统安全存储；OAuth Token 仅驻留内存。日志不记录凭据或完整发票资料。
- 旧 scaffold 中若曾人工保存明文凭据，升级后会清空该明文，需重新输入。公司和提交资料保留。旧备份可能仍含其原始内容，请按敏感资料保管。
- 更换电脑/Windows 用户或丢失 OS 密钥后，需要重新输入凭据。数据库备份保留加密内容，不导出解密密钥。

### CNKH POS Employee Training

右上角及 Settings 原培训入口均提供 11 课：登录与权限、商品销售、收款、退款、库存、手机连接电脑、数据同步、数据备份、e-Invoice 设置、e-Invoice 提交、常见错误处理。

培训使用 `tool/training_capture_test.dart` 实际渲染的应用页面截图；箭头坐标来自真实控件位置，可缩放查看。截图资料为隔离测试数据库内容，配对截图不是门店可用配对码。Mobile 的电脑操作课程使用同版本 Desktop 截图。

### 开发与验证

完整变更、测试结果、构建记录及已知范围见 [EINVOICE_REPORT.md](EINVOICE_REPORT.md)。手机打包固定 Desktop `v0.4.0` 对应源码 `47c665de`；Desktop 联调默认固定已测试 Mobile 源码，手动运行可通过 `mobile_ref` 指定其他版本。

发布 CI 执行 `flutter analyze`、完整 `flutter test`、真实页面截图捕获，再执行 Windows/APK Release 构建。截图先生成到 `assets/training/` 再打包。源码首次运行前也需要生成截图；Mobile 截图流程须准备 `.training_desktop` 源码及其字体，参照 `mobile-ci.yml`。双端真实 HTTP 回归位于 Desktop `integration/`，运行 `flutter test test regression`。

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
Desktop v0.4.0
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

1. 安装并启动 **Desktop v0.4.0**。
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

1. 推荐先安装/更新 Desktop v0.4.0。
2. Android 下载 `CNKH_POS_Mobile.apk`。
3. 按 Android 提示允许当前下载或文件管理 App 安装 APK。
4. 安装后登录并重新确认 LAN 配对状态。

APK 只能安装在 Android，不能直接安装到 iPhone。

本版本沿用项目现有调试签名配置，未验证与旧版签名相同或可覆盖升级。若提示签名不一致，不要直接卸载旧版，以免丢失本地业务数据；请先保留旧版并妥善导出/迁移数据。

## 验证

本轮源码基线已通过：

- Mobile 静态分析、**86 项 Flutter 测试**、Release APK 构建与 INTERNET 权限检查。
- Desktop 静态分析、**91 项 Flutter 测试**与 Windows Release 构建。
- **8 项双端 HTTP 同步与断线重连测试**。

[Mobile 发布流程](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/workflows/mobile-ci.yml) 会重新执行分析、测试和构建，通过后上传附件。未执行真机覆盖升级、打印机及真实门店局域网验收。

## 当前不包含

- 云 OCR
- AI / LLM OCR
- 无人工确认自动入库
- Malaysia MyInvois / e-Invoice
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
