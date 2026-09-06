# 黄金发宝号 · CNKH POS Mobile Source

这是 CNKH POS Mobile 的完整 Flutter 源码主线。Android 正式 APK 由 `source/main` 对应源码 CI 构建并发布到 GitHub Releases。

> README 最后更新：**2026-09-06**  
> Full Fix 开发分支：`fix/ocr-full-fix-20260906`（基于 **`source/main`**）  
> 仓库默认 `main` 是下载/说明主页，本次源码修复不会把 Flutter 工作错误合并到默认文档分支。

## 当前正式版本

| 项目 | 当前正式版本 |
|---|---|
| Mobile | **1.9.0+25 / `v1.9.0-mobile`** |
| 配套 Desktop | **0.3.3+6 / `v0.3.3`** |
| LAN 协议 | `cnkh-sync:v1` |
| 本地数据库 | Full Fix 后升级为 **schema v8** |

正式 APK / Release 仍以 GitHub Releases 页面为准；Full Fix 在合并前通过 Pull Request CI 验证。

## 2026-09-06 Full Fix

本轮修复不重写 POS，也不改变现有稳定 UI 风格、销售流程、SQLite 架构或 `cnkh-sync:v1`。重点是补齐 Desktop / Mobile 双端一致性与 OCR Purchase 的安全闭环。

已覆盖：

- Customer / Supplier / Product 完整 CRUD 与批量软删除。
- Supplier 双向同步，包括 Desktop → Mobile 拉取。
- Product 删除 tombstone 与防复活。
- Product Image stable ID / `has_image` 同步。
- Barcode 真正可扫描的 EAN-13 / Code128 输出与打印队列逐项 ACK。
- OCR P0 全部阻断安全规则。
- Original / Preview 分离。
- Original Invoice 独立附件 Outbox + SHA-256 + Lost-ACK retry。
- Desktop → Mobile Purchase History 只读同步，不二次改库存。
- Supplier Product Alias 查看 / 编辑 / 删除。
- OCR v8 正式 Migration 与旧数据保留。
- Pairing QR expiry / Token revoke / same-host Token rotation。

## OCR 运行方式

OCR 只在 Android 本机执行：

- Google ML Kit Text Recognition
- Latin + Chinese bundled model
- 不调用云 OCR
- 不上传进货单给第三方 AI/LLM
- 无网络仍可拍照/选图、OCR、编辑 Draft 与本地确认
- 恢复 LAN 后由 persistent outbox 同步到 Desktop

## Original 与 Preview

Full Fix 不再让“压缩预览图”同时承担 OCR 原图角色。

流程：

```text
Camera / Gallery
      ↓
Original：原始文件 byte-for-byte 保存
      ├──→ ML Kit OCR 读取 Original
      ↓
Preview：校正方向 / 缩小 / JPEG 压缩，仅用于 UI 预览
```

SQLite Draft 分别保存 Original / Preview 路径。删除未完成 Draft 时会清理对应图片；确认或失败流程也有生命周期清理，避免长期残留孤儿文件。

## OCR Purchase 流程

```text
拍照 / 相册
    ↓
Original + Preview
    ↓
Android 本机 OCR（Original）
    ↓
OCR Draft
    ↓
商品匹配 + 异常检查
    ↓
人工预览 / 修改
    ↓
人工确认
    ↓
SQLite transaction 原子入库
    ├──→ Purchase Outbox
    └──→ Independent Original Attachment Outbox
            ↓
        Desktop LAN Host
```

只有人工点击 **确认并入库** 后，系统才会正式创建 Purchase、更新库存与成本。

未确认 Draft：

- 不改变库存。
- 不改变成本。
- 不上传正式 Purchase。
- 可以保存退出后继续核对。

## OCR 识别字段

会尝试识别：

- Supplier
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

费用行不会被当成普通商品行。

## 统一金额解析

OCR 与手动进货使用统一 money parser。

支持例如：

```text
12.50
1,234.56
1.234,56
RM 1,234.56
```

非法金额不会无声变成 `0`：

- 保留用户原始输入。
- 显示字段错误。
- 阻止保存/确认。
- 不会 `tryParse(...) ?? 0` 静默写入数据库。

## Conversion 安全

每个进货行的 Conversion 必须：

- finite
- `> 0`
- 不能 NaN
- 不能 Infinity
- 不能 0
- 不能负数

UI 会直接显示错误；Repository 在事务边界再次验证，所以不能靠绕过 UI 写入错误换算。

例如：

```text
1 CTN = 24 PCS
Invoice Qty = 2 CTN
Conversion = 24
实际库存增加 = 48 PCS
```

历史数量与历史成本异常比较按 base unit / base stock quantity 进行，避免不同包装单位误报。

## 商品匹配与规格冲突

匹配顺序包括：

1. Barcode 精确匹配
2. SKU 精确匹配
3. Supplier Product Alias
4. 名称精确 / 规范化匹配
5. 模糊匹配

数字规格 token 会被提高权重。例如：

```text
500ML vs 1.5L
12PCS vs 24PCS
```

这类规格冲突会显著降低匹配可信度，避免名字相似但包装不同的商品被自动选错。

## Supplier Product Alias

只有用户**明确确认**的商品匹配才会学习：

```text
Supplier + OCR Raw Product Name → POS Product
```

管理入口：

```text
Admin
→ Purchases
→ 供应商商品记忆 / Aliases
```

可：

- 按供应商查看。
- 编辑匹配商品。
- 编辑单位与 Conversion。
- 删除错误记忆。
- Conversion 编辑仍使用 finite / `>0` 验证。

## Duplicate Invoice

默认按：

```text
Supplier ID + Invoice No
```

检查重复。

规则：

- 默认阻止重复入库。
- Staff 不能覆盖。
- Admin 必须填写 Force Commit 原因。
- Admin 再进行第二次确认后才能继续。
- 覆盖原因和操作写入 audit，并随 Purchase 同步 Desktop。

## Confirm 防双击与幂等

确认按钮第一次点击会立即：

```text
_busy = true
```

然后才重新验证，因此连续双击不会创建两次事务。

数据库还有第二层保护：

- Purchase 保存 `draft_id`。
- `draft_id` 唯一幂等。
- 同一个 Draft 重试会返回已有 Purchase。
- Outbox operation ID 同样幂等。

网络 timeout / Lost ACK / App 重试不会重复增加库存。

## Safe Purchase Reverse

Reverse 不是删除 Purchase。

执行前先整单预检：

- Purchase 是否存在且未撤销。
- 当前库存是否足够回退。
- 原 Purchase 的库存流水之后是否出现销售、盘点、其它进货或人工库存调整。

如果后续库存已经变化，会阻止直接撤销并提示使用库存调整或人工处理。

只有所有行都通过预检后才进入事务修改，因此不会出现半张单撤销成功、半张单失败。

重复 Reverse 使用幂等保护，不会重复扣库存。

## Desktop Purchase History 只读同步

Desktop 的 `/api/v1/purchases` 会把结构化 Purchase History 同步到 Mobile，包括 Supplier、Invoice、费用、商品明细、OCR evidence 与 Reverse 状态。

安全规则：

- Desktop 新建的 Purchase 在 Mobile 以 `desktop_sync` 历史记录保存，并使用稳定的远端 ID 映射。
- 拉取历史记录**不会执行本地进货库存增加、成本更新或 stock move**。
- Desktop 后续 Reverse 时，Mobile 只同步 Reverse 状态/原因，不会再次扣减库存；库存最终值仍由 Desktop Catalog 权威同步。
- Desktop-origin Purchase 的 Mobile 详情页是只读页面，不提供本地 Reverse。
- 即使绕过 UI 调用 Repository，服务层与 SQLite trigger 也会阻止对 `desktop_sync` Purchase 执行 Mobile 本地库存反转。
- Mobile 自己建立并上传的 Purchase 会识别为原记录，不会被 Desktop History 回传复制成第二张进货单。
- Client 使用 cursor-compatible reconciliation；兼容 Host 返回完整历史时，稳定 ID 与幂等写入仍保证不会触发第二次库存 mutation。

## Original Invoice 附件同步

确认 OCR Purchase 后，Original Invoice 不会只停留在手机本地路径。

Mobile 会创建一个与 Purchase mutation **分离**的 attachment operation：

- `attachment_id`
- `purchase_id`
- 原始文件名
- SHA-256 hash
- Base64 bytes
- pending / failed / synced 状态

好处：

- Purchase 已成功但图片失败时，只重试图片。
- 图片 retry 不会重播 Purchase。
- Lost ACK 后重试同一个 attachment ID 不会生成第二份附件。
- Desktop 会再次计算 SHA-256，hash 不一致会拒绝。

Desktop 可以在 Purchase Detail 查看附件资料，并导出经过 hash 校验的 Original。

## OCR Audit

保留 OCR evidence 与人工最终值。

例如：

```text
OCR Qty: 70
Final Qty: 10

OCR Unit Cost: RM8.20
Final Unit Cost: RM3.20
```

Raw OCR text 只作为证据保存，不会被事后自动“修正”为系统猜测结果。

Audit 包括人工修改、Duplicate Override、附件同步等关键操作。

## Database v8 Migration

Full Fix 把 OCR schema 正式接入 Mobile `onCreate/onUpgrade`：

- 新安装直接建立完整 v8 OCR schema。
- 旧数据库升级时增量迁移。
- 不删除旧 Product / Customer / Supplier / Sales / Purchase / outbox。
- 不要求 Factory Reset。
- 自动化 migration test 会建立旧版本数据库并确认旧数据与未发 outbox 在升级后仍存在。

## Customer / Supplier / Product 同步

### Customer / Supplier

- 新增、编辑保留稳定 ID。
- 删除使用 soft-delete tombstone。
- 支持多选/批量删除。
- Supplier 已加入 Desktop `/api/v1/suppliers` 拉取，不再只有 Mobile 本地资料。
- Supplier email / notes 等字段会随 mutation 同步。

### Product Delete

删除商品后：

- SQLite row 保留。
- `is_deleted=1`。
- 条码 / SKU /历史库存资料保留供历史记录引用。
- 商品搜索与扫码加购不再返回该商品。
- `product_upsert` outbox 发送 tombstone。
- Desktop 不允许迟到旧同步把 tombstone 重新变成可售商品。

## Product Image Sync

Desktop Catalog 使用稳定 `pc_id` 与 `has_image`。

Mobile：

- 通过稳定 ID map 找本地商品。
- `has_image=true` 时使用 Token 调用 Desktop 认证图片 endpoint。
- 保存到 Mobile 自己的 ProductImageStore。
- 不复制 Desktop 的 Windows `image_path`。
- `has_image=false` 或 404 时删除手机本地缓存并清空本地 `image_path`。

## Barcode 与 Print Queue

条码生成使用真正的 barcode bars：

- EAN-13：合法数字条码。
- Code128：其它 SKU / 字符条码。

测试会检查实际条纹区域，不只检查 PNG bytes。

Barcode Queue 同步会发送 `operation_id`，Desktop 逐项 ACK。只有收到对应 ACK 后 Mobile 才清除本地 pending queue；Lost ACK retry 不会在 Desktop 建第二个任务。

## LAN Pairing Security

二维码格式仍为：

```text
cnkh-sync:v1|{...}
```

Full Fix 增加/锁定：

- `iat`
- `exp`
- 默认约 7 分钟过期
- Mobile 拒绝过期 QR
- 所有 Desktop HTTP / WebSocket endpoint Token 认证
- Desktop Admin 可撤销旧手机配对并旋转 Token
- 旧 Token 立即 Unauthorized
- 现有 WebSocket 从 Host 活动连接集中移除

### 同一 Desktop 重新配对

Desktop 主动 rotate Token 后，Mobile 允许**相同 normalized Host** 更新 Token，因此旧手机可以扫新二维码重新授权。

如果二维码指向不同 Desktop Host，则继续阻止，并提示先完成同步与备份，防止带着未同步门店数据误切到另一台主机。

## Sales / Offline / Reconciliation

- Desktop 是局域网权威主机。
- Mobile 可离线销售。
- persistent outbox 保存待同步操作。
- HTTP 成功 ACK 后才删除 outbox。
- WebSocket 用于实时变更提示并自动重连。
- HTTP reconciliation 负责最终一致性。
- `client_sale_id` 是现代销售幂等路径。
- 两笔相同时间、相同金额、相同支付方式但商品明细不同的 legacy sale 不会被错误合并。
- 精确 legacy retry 仍防重复扣库存。
- Void / Refund 状态继续通过现有同步路径传播。

## 权限

Mobile Admin 页面只对 Admin 显示。

Staff 不能通过本轮新增页面绕过：

- Product / Customer / Supplier 管理
- OCR Admin Force Commit
- Purchase Reverse 管理入口
- User administration

Desktop 负责完整 Add/Edit/Role/Disable/PIN Reset 管理。

## 开发与验证

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

Full Fix 自动化重点包括：

- OCR money parser / thousands separators
- Conversion finite / `>0`
- Product spec conflicts
- Draft commit idempotency
- Duplicate invoice / Admin override
- Safe Reverse after later stock moves
- Desktop → Mobile Purchase History reconciliation / read-only stock safety
- Original/Preview lifecycle
- Attachment outbox status / hash / Lost ACK
- v8 migration preserving old data/outbox
- Customer / Supplier CRUD tombstones
- Product soft-delete tombstone and non-sellable lookup
- Same-host Token rotation / different-host protection
- Barcode real bars

Mobile CI 必须通过 Analyze、全部 Flutter tests 与 Android Release APK 后才允许合并到 `source/main`。

## 当前不包含

- 云 OCR
- AI / LLM OCR
- 自动无确认入库
- Malaysia MyInvois / e-Invoice
- OCR 自动创建全新商品
- 云端多门店同步

## 分支约定

- `main`：下载主页 / 使用说明
- `source/main`：完整 Flutter Mobile 源码
- `fix/ocr-full-fix-20260906`：本次 Full Fix，最终目标只合并回 `source/main`

## 相关入口

- Mobile Releases: https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases
- Desktop Releases: https://github.com/tyz11234/CNKH_POS_Desktop/releases
- Desktop Full Fix PR: https://github.com/tyz11234/CNKH_POS_Desktop/pull/8
- Mobile Full Fix PR: https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/7