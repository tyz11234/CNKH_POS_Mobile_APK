# 黄金发宝号 · CNKH POS Mobile Source

> README 最后更新：**2026-09-06**

这是 CNKH POS Mobile 的完整 Flutter 源码主线。Android 正式 APK 由本分支 CI 构建并发布到 GitHub Releases。

## 当前源码与正式版

| 项目 | 当前版本 |
|---|---|
| Mobile 源码 | **1.9.0+25** |
| Mobile 正式 Release | **`v1.9.0-mobile`** |
| 配套 Desktop | **v0.3.3 / 0.3.3+6** |
| OCR | **v1.9.0 OCR Purchase** |
| LAN 协议 | `cnkh-sync:v1` |
| 更新日期 | **2026-09-06** |

推荐配套：**Desktop v0.3.3 + Mobile v1.9.0**。

Mobile v1.9.0 Release：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile

正式 APK：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.9.0-mobile/CNKH_POS_Mobile.apk

版本化 APK：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.9.0-mobile/CNKH_POS_Mobile_v1.9.0.apk

Desktop v0.3.3：
https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.3

本次 Mobile Release 固定到源码提交：

```text
46a5bc941eb05a58b16361518a0af9429d258174
```

APK SHA-256：

```text
1b892b8fd8f6760cf11fdbf1f1edeef1956229237dcccb320eb26f0307f09d5c
```

## v1.9.0：本地 OCR 智能进货

v1.9.0 在原有手动进货旁新增 OCR 进货。OCR 只负责识别与预填，**不会因为识别结果直接修改库存或成本**。

固定流程：

```text
拍照 / 相册
    ↓
Android 本机 OCR
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
    ↓
Persistent Outbox
    ↓
Desktop v0.3.3
```

只有点击 **确认并入库** 后，系统才会正式创建 Purchase、更新库存/成本、写库存流水，并建立待同步操作。

## OCR 运行方式

- Google ML Kit Text Recognition
- Android 本机执行
- APK 内置 Latin + Chinese 模型
- 不调用云 OCR
- 不上传进货单到第三方 OCR 服务
- 无网络仍可识别、编辑 Draft 和本地确认入库
- 恢复 LAN 后沿用现有 Outbox 同步

## OCR 入口

```text
管理 / Admin
→ 进货 / Purchases
→ +
```

可选择：

- 拍照扫描进货单
- 从相册选择进货单
- 继续 OCR 草稿
- 手动进货（原流程保留）

## OCR 识别字段

当前会尝试识别：

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

Discount、SST、Delivery、Other Fee 会作为整单费用处理，不会当成普通商品行。

## 商品匹配

当前匹配策略：

1. Barcode 精确匹配
2. SKU 精确匹配
3. 商品名精确匹配
4. 规范化名称匹配
5. 模糊名称匹配
6. 同一供应商过去确认过的商品别名记忆

系统可处理部分商品名称中的 OCR 字符混淆，例如 `0/O`、`1/I`，但**不会自动修正数量、价格、小计等关键数字**。

未匹配商品属于阻断错误，不能直接确认入库。

## 供应商记忆

用户确认后的：

```text
供应商 + OCR 原始商品名称 → POS 商品
```

会保存在本机 `supplier_product_aliases`。

以后同一供应商出现相同或规范化后的商品名称时，可优先复用历史匹配。

## 异常检查

当前检查：

- 数量必须 > 0
- 成本 / 小计不能为负数
- 商品必须匹配
- 匹配可信度过低
- `Qty × Unit Cost` 与行小计不一致
- 本次数量显著高于近期常见数量
- 单位成本与上次进货成本变化过大
- 系统计算总额与 Invoice Total 不一致
- 未识别 Invoice Total
- 未识别供应商
- 未可靠识别商品行

系统只提示，不会偷偷改关键数字。

## 单位换算

每行可设置 Conversion。

例如：

```text
1 CTN = 24 PCS
Invoice Qty = 2 CTN
Conversion = 24
实际库存增加 = 48 PCS
```

普通单件商品保持 `1`。

## OCR Draft

草稿：

- 不影响库存
- 不影响成本
- 可保存退出
- 可重新打开继续核对
- 保存 OCR 原文
- 保存压缩后的进货单图片
- 保存商品匹配结果
- 保存人工修改结果

确认后 Draft 状态改为 `committed`。

## 原图与 OCR 原文

进货单图片不会直接写成 SQLite BLOB。

Mobile 会：

1. 校正方向
2. 缩小过大图片
3. JPEG 压缩
4. 保存到 App Documents 的 `purchase_invoices`
5. SQLite 只保存图片路径
6. OCR 原始文字单独保存

## 人工修改审计

OCR 原始值与最终确认值分开保留。

例如：

```text
OCR Qty: 70
Final Qty: 10

OCR Unit Cost: RM8.20
Final Unit Cost: RM3.20
```

人工改过的商品行会写入 `purchase_audit_log`。

## 确认入库

确认后会在同一个 SQLite transaction 内：

- 创建正式 Purchase
- 更新商品库存
- 更新商品成本
- 创建 `stock_moves`
- 保存 Invoice No / Date / 费用字段
- 保存 OCR Raw Text
- 保存图片附件关联
- 更新供应商商品别名记忆
- 写审计记录
- 创建 `purchase` Outbox operation

## 撤销 OCR 进货

管理员可执行 **Reverse purchase**。

撤销不是删除原记录，而是：

- 保留原 Purchase
- 标记 reversed
- 写 `purchase_reversals`
- 生成负数库存流水
- 回退本次进货库存
- 在安全条件下恢复进货前成本
- 保存撤销人员、时间、原因和备注
- 创建 `purchase_reverse` Outbox operation

重复提交有幂等保护，不会重复扣库存。

## 局域网配对

1. 手机和 Windows 电脑连接同一 Wi-Fi / LAN。
2. 启动 Desktop v0.3.3。
3. Desktop 打开 LAN / 扫码配对并显示二维码。
4. Mobile 扫描二维码。
5. Mobile 保存 Desktop 地址与 Token。

二维码格式：

```text
cnkh-sync:v1|{"baseUrl":"http://192.168.x.x:8787","token":"...","name":"CNKH-PC"}
```

默认端口：**8787**。

## 同步模型

Desktop 是店内局域网权威主机；Mobile 支持断线继续工作。

当前同步包括：

- 商品、库存、分类、客户
- 销售记录
- WebSocket 实时变更提示
- HTTP 定时对账
- WebSocket 自动重连
- Mobile 离线销售持久化与重试
- `client_sale_id` 幂等销售导入
- 多设备离线收据号防碰撞
- Desktop 销售 / 进货 / 盘点库存回传
- Desktop 作废销售状态回传
- 强制全量对账
- Mobile 普通进货 / OCR 进货共用 `purchase` mutation
- OCR Invoice No / Date / 费用 / Raw Text 同步
- OCR 撤销通过 `purchase_reverse` 幂等同步

**`cnkh-sync:v1` 没有因为 OCR 改版本。**

## 手机端功能

- POS 收银、商品搜索、摄像头扫码
- 现金 / 卡 / DuitNow / 赊账
- 折扣、挂单、销售历史、作废
- 商品、分类、客户、供应商、进货、盘点、报表
- 本机 OCR 智能进货
- OCR Draft / 异常检查 / 供应商记忆 / 原图 / 审计 / 撤销
- 小票模板 / 预览
- PDF / WhatsApp 电子收据
- 条码导出 / 打印队列
- 可选蓝牙小票打印

Windows 特有的硬件标签打印和整库维护仍由 Desktop 处理。

## 当前不包含

- 云 OCR
- AI / LLM OCR
- 自动无确认入库
- Malaysia MyInvois / e-Invoice
- OCR 自动创建全新商品
- 云端多门店同步

## 开发与验证

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

v1.9.0 正式 CI：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34023967305

已验证：

- `flutter pub get`：通过
- `flutter analyze`：通过
- **32 项 Flutter tests：通过**
- Android Release APK：通过
- R8 shrink：通过
- Chinese + Latin bundled models：通过
- APK artifact：通过
- GitHub Release：通过
- Desktop / Mobile 既有 HTTP / 断线重连回归：通过

## 分支约定

- `main`：下载主页、正式状态、使用说明
- `source/main`：完整 Flutter Mobile 源码
- Release APK 与源码提交必须可追溯

## 相关入口

- Mobile v1.9.0：https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile
- Mobile 下载主页：https://github.com/tyz11234/CNKH_POS_Mobile_APK
- Desktop v0.3.3：https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.3
- Mobile OCR PR #6：https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/6
- Desktop OCR Sync PR #7：https://github.com/tyz11234/CNKH_POS_Desktop/pull/7
