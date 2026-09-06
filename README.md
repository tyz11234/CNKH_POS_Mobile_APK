# 黄金发宝号 · CNKH POS Mobile Source

> README 最后更新：**2026-09-06**

这是 CNKH POS Mobile 的完整 Flutter 源码主线。Android 正式 APK 由本分支的 CI 构建并发布到 GitHub Releases。

## 当前源码与正式版

| 项目 | 当前版本 |
|---|---|
| Mobile 源码 | **1.9.0+25** |
| OCR 版本 | **v1.9.0 OCR Purchase** |
| 当前正式 Release | **`v1.9.0-mobile`** |
| 对应 Desktop | **Desktop `main` 已包含 OCR 进货同步兼容** |
| LAN 协议 | `cnkh-sync:v1`，未更换协议版本 |
| 更新日期 | **2026-09-06** |

Mobile v1.9.0 Release：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile

正式 APK：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.9.0-mobile/CNKH_POS_Mobile.apk

版本化 APK：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.9.0-mobile/CNKH_POS_Mobile_v1.9.0.apk

本次 Release 固定到源码提交：

```text
46a5bc941eb05a58b16361518a0af9429d258174
```

APK SHA-256：

```text
1b892b8fd8f6760cf11fdbf1f1edeef1956229237dcccb320eb26f0307f09d5c
```

Desktop：
https://github.com/tyz11234/CNKH_POS_Desktop

## v1.9.0：本地 OCR 智能进货

v1.9.0 在原有进货功能旁新增 **OCR 进货**，不会取代原来的手动进货流程。

### 设计原则

OCR 只负责识别和预填，**绝不会因为 OCR 识别结果直接修改库存或成本**。

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
数据库事务入库
    ↓
沿用现有 Outbox 同步到 Desktop
```

只有用户点击 **“确认并入库”** 后，系统才会在同一个数据库事务内写入进货记录、更新库存和成本、写库存流水，并建立待同步操作。

### OCR 运行方式

- Android 手机本机运行 Google ML Kit Text Recognition
- 不调用云 OCR
- 不需要上传进货单到第三方 OCR 服务
- APK 内置 **Latin + Chinese** 文字识别模型
- 可识别英文、数字及中文进货单文字
- 没有网络时仍可完成 OCR、草稿编辑和本地入库
- 恢复 Desktop LAN 连接后再沿用原有持久 Outbox 同步

### OCR 入口

进入：

```text
管理 / Admin
→ 进货 / Purchases
→ +
```

可以选择：

- **拍照扫描进货单**
- **从相册选择进货单**
- **继续 OCR 草稿**
- **手动进货**（原流程保留）

### OCR 会尝试识别

- Supplier / 供应商名称
- Invoice No
- Invoice Date
- 商品名称
- Qty / 数量
- Unit / 单位
- Unit Cost / 单位成本
- Line Subtotal / 行小计
- Discount
- Tax / SST
- Delivery / Freight / Shipping / Handling
- Other Fee
- Invoice Total / Grand Total

Discount、SST、Delivery 和 Other Fee 会作为整单费用字段处理，不会误当成普通商品行入库。

### 商品自动匹配

OCR 商品名称会与本机商品资料进行匹配，包括：

1. Barcode 精确匹配
2. SKU 精确匹配
3. 商品名精确匹配
4. 规范化商品名称匹配
5. 模糊名称匹配
6. 同一供应商过去确认过的商品名称记忆

系统会处理部分常见 OCR 字符混淆，例如商品名称中的 `0/O`、`1/I`，但**不会偷偷修正数量、价格、小计等关键数字**。

匹配可信度低或无法匹配时，会要求人工选择商品；未匹配商品属于阻断错误，不能直接确认入库。

### 供应商记忆

用户确认过的：

```text
供应商 + OCR 原始商品名称 → POS 商品
```

会写入本机供应商商品别名记忆。

以后同一供应商再次出现相同或规范化后的商品名称时，可优先复用历史匹配，减少重复人工选择。

### 异常检查

OCR 不会擅自修改疑似错误数字，而是保留原始值并显示警告。

当前检查包括：

- 数量必须大于 0
- 成本 / 小计不能为负数
- 商品必须匹配
- 商品匹配可信度过低
- `Qty × Unit Cost` 与行小计不一致
- 本次数量显著高于近期常见进货数量
- 单位成本与上次进货成本变化过大
- 系统计算整单金额与 Invoice Total 不一致
- 未识别 Invoice Total
- 未识别供应商
- 未可靠识别商品行

警告不会自动篡改单据数字。存在阻断错误时无法确认；普通警告可以在人工核对后继续确认。

### 单位换算

每一行可设置 Conversion / 换算倍率。

例如：

```text
1 CTN = 24 PCS
Invoice Qty = 2 CTN
Conversion = 24
实际库存增加 = 48 PCS
```

普通单件商品保持 `1` 即可。

### OCR 草稿

OCR 识别后会先保存为 Draft。

草稿：

- 不影响库存
- 不影响成本
- 可保存后退出
- 可从进货页重新打开继续核对
- 保留 OCR 原始文字
- 保留压缩后的本地进货单图片
- 保留商品匹配和人工修改结果

确认入库后 Draft 状态会改为 `committed`。

### 原图与 OCR 原文

进货单图片不会直接塞入 SQLite BLOB。

Mobile 会：

1. 校正照片方向
2. 将过大的图片缩至适合长期保存的尺寸
3. JPEG 压缩保存到 App Documents 下的 `purchase_invoices`
4. SQLite 保存图片路径
5. OCR 原始文字独立保存

这样既能追溯原始单据，又不会让 SQLite 因大量高清照片快速膨胀。

### 人工修改审计

OCR 识别值和最终确认值会分开保留。

例如：

```text
OCR Qty: 70
最终 Qty: 10

OCR Unit Cost: RM8.20
最终 Unit Cost: RM3.20
```

人工改过的 OCR 商品行会写入 `purchase_audit_log`，用于后续追溯。

### 确认入库

点击 **确认并入库** 后：

- 创建正式 Purchase
- 更新商品库存
- 更新商品成本
- 创建 `stock_moves`
- 保存 OCR Invoice 信息与费用字段
- 保存 OCR 原文
- 保存图片附件关联
- 更新供应商商品别名记忆
- 写审计记录
- 建立 `purchase` Outbox operation

上述本地业务更新使用同一个 SQLite transaction，避免只入库一半。

### 撤销 OCR 进货

管理员可从进货详情执行 **撤销进货 / Reverse purchase**。

撤销不是删除记录，而是：

- 保留原 Purchase
- 标记原 Purchase 已撤销
- 建立 `purchase_reversals`
- 生成负数库存流水
- 回退本次进货增加的库存
- 在安全条件下恢复进货前成本
- 保存撤销人员、时间、原因和备注
- 建立 `purchase_reverse` Outbox operation

撤销实现幂等保护，重复提交不会重复扣库存。

## 局域网配对

1. 手机和电脑连接同一个 Wi‑Fi / LAN。
2. Desktop 启动后作为局域网权威主机，默认监听端口 `8787`。
3. Desktop 打开 LAN / 扫码配对并显示二维码。
4. Mobile 点击扫码配对并扫描 Desktop 二维码。
5. Mobile 保存 Desktop 地址和 Token，之后自动重连并进行 HTTP 对账。

二维码格式：

```text
cnkh-sync:v1|{"baseUrl":"http://192.168.x.x:8787","token":"...","name":"CNKH-PC"}
```

## 同步模型

Desktop 是店内局域网权威主机；Mobile 支持断网继续工作。恢复连接后 Mobile 重试持久 Outbox，再从 Desktop 拉取权威业务数据。

当前同步能力包括：

- 商品、库存、分类、客户同步
- 销售记录同步
- WebSocket 实时变更提示
- HTTP 定时对账
- WebSocket 断线重连
- Mobile 离线销售持久化与重试
- `client_sale_id` 幂等导入，避免重试产生重复销售
- 多设备离线收据号防碰撞
- Desktop 销售 / 进货 / 盘点后的库存回传 Mobile
- Desktop 作废销售状态回传 Mobile
- 强制全量对账
- Mobile 普通进货 / OCR 进货使用同一 `purchase` mutation 通道
- OCR Invoice No/Date、费用、OCR 原文等元数据可同步到 Desktop
- OCR 进货撤销通过 `purchase_reverse` mutation 幂等同步

**没有改变 `cnkh-sync:v1` 的现有核心配对、HTTP、WebSocket 和销售幂等逻辑。**

## 手机端功能

- 收银 POS、商品搜索、摄像头扫码
- 现金 / 卡 / DuitNow / 赊账
- 折扣、挂单、今日销售、销售记录、作废
- 商品、分类、客户、供应商、进货、盘点、报表
- **本机 OCR 智能进货**
- OCR 草稿 / 预览 / 异常检查 / 供应商记忆 / 原图保存 / 撤销进货
- 小票格式编辑 / 预览
- 电子收据 PDF / WhatsApp 分享
- 条码导出 / 打印队列
- 可选蓝牙小票打印

Windows 特有的硬件标签打印及整库维护仍由 Desktop 处理。

## OCR 当前范围

本版 OCR 目标是 **让进货更快但仍由人确认**。

本版没有加入：

- 云 OCR
- 生成式 AI OCR
- 自动无确认入库
- Malaysia MyInvois / e-Invoice
- OCR 自动创建全新商品
- 云端多店同步

这些不属于 v1.9.0 OCR Purchase 范围。

## 开发与验证

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

v1.9.0 OCR 正式构建已验证：

- `flutter pub get`：通过
- `flutter analyze`：通过
- Flutter tests：**32 项通过**
- Android Release APK：通过
- R8 release shrink：通过
- Chinese + Latin ML Kit bundled model：通过 Release 打包
- APK artifact 上传：通过
- GitHub Release 创建：通过
- Desktop / Mobile 既有 LAN 联调回归：通过

正式构建记录：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34023967305

## 正式发布规则

- 当前源码版本：`1.9.0+25`
- 当前正式 tag：`v1.9.0-mobile`
- 正式 APK 只从 GitHub Releases 下载
- 功能 / 修复先在功能分支完成，通过 CI 后再进入 `source/main`
- Release APK 与源码必须可追溯到对应构建提交

## 仓库分支约定

- `main`：正式版下载入口、Release 说明、协议文档
- `source/main`：完整 Flutter Mobile 源码主线
- Release APK 与源码必须可追溯到同一提交

分发首页：
https://github.com/tyz11234/CNKH_POS_Mobile_APK
