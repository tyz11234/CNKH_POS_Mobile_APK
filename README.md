# 黄金发宝号 · CNKH POS Mobile

用于 Android 手机的门店收银客户端，与 [CNKH POS Desktop](https://github.com/tyz11234/CNKH_POS_Desktop) 配套使用。支持本地收银、离线业务、局域网同步，以及 v1.9.0 新增的 **本机 OCR 智能进货**。

基于 **Flutter / Dart**，使用本地 SQLite 保存业务数据。核心收银与店内同步不依赖云服务器。

> README 最后更新：**2026-09-06**。`main` 为下载与使用说明主页；完整 Flutter 源码位于 [`source/main`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)。

## 当前正式版本

| 项目 | 当前版本 |
| --- | --- |
| Mobile | **1.9.0+25** |
| 正式 Release | **`v1.9.0-mobile`** |
| 配套 Desktop | **v0.3.3 / 0.3.3+6** |
| LAN 协议 | `cnkh-sync:v1` |
| OCR | **本机 Latin + Chinese ML Kit** |
| OCR 云服务 | **不使用** |

推荐配套：**Desktop v0.3.3 + Mobile v1.9.0**。

### 正式下载

Mobile v1.9.0 Release：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile

直接下载 APK：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.9.0-mobile/CNKH_POS_Mobile.apk

版本化 APK：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.9.0-mobile/CNKH_POS_Mobile_v1.9.0.apk

配套 Desktop v0.3.3：
https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.3

APK SHA-256：

```text
1b892b8fd8f6760cf11fdbf1f1edeef1956229237dcccb320eb26f0307f09d5c
```

本次 Mobile Release 对应源码提交：

```text
46a5bc941eb05a58b16361518a0af9429d258174
```

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
Desktop v0.3.3
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

1. 安装并启动 **Desktop v0.3.3**。
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

1. 推荐先安装/更新 Desktop v0.3.3。
2. Android 下载 `CNKH_POS_Mobile.apk`。
3. 按 Android 提示允许当前下载或文件管理 App 安装 APK。
4. 安装后登录并重新确认 LAN 配对状态。

APK 只能安装在 Android，不能直接安装到 iPhone。

若覆盖安装提示签名不一致，请先备份/保留业务数据，不要直接卸载正在使用的版本。

## 已完成验证

Mobile v1.9.0 正式 CI：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34023967305

已通过：

- `flutter pub get`
- `flutter analyze`
- **32 项 Flutter tests**
- Android Release APK
- R8 release shrink
- Chinese + Latin ML Kit bundled models
- APK artifact 上传
- GitHub Release 创建

配套 Desktop v0.3.3：

- Desktop analyze：通过
- Desktop tests：通过
- Windows Release build：通过
- OCR Purchase mutation：通过
- `purchase_reverse` 幂等：通过
- 原有 Desktop / Mobile HTTP 与断线重连回归：通过

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
| `main` | 下载、正式状态和使用说明 |
| `source/main` | 完整 Flutter Mobile 源码 |

源码构建：

```bash
git clone --branch source/main --single-branch https://github.com/tyz11234/CNKH_POS_Mobile_APK.git
cd CNKH_POS_Mobile_APK
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

## 相关入口

- Mobile v1.9.0：https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile
- Mobile 源码：https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main
- Desktop v0.3.3：https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.3
- OCR Mobile PR #6：https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/6
