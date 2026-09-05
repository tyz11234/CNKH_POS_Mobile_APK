# CNKH LAN Sync v1

> 当前推荐正式组合：**Desktop v0.3.2 + Mobile v1.8.2**  
> 最后更新：**2026-09-05**

CNKH POS 使用 **local-first / no-cloud** 架构。Desktop 是店内局域网权威主机，Mobile 通过同一个 Wi-Fi / LAN 与 Desktop 直接同步。

## 配对二维码

Desktop 打开 LAN / 扫码配对后显示二维码，Mobile 点击扫码配对读取。

格式：

```text
cnkh-sync:v1|{"baseUrl":"http://192.168.0.10:8787","token":"...","name":"CNKH-PC"}
```

字段：

- Prefix：`cnkh-sync:v1|`
- `baseUrl`：Desktop 当前局域网地址，默认端口 `8787`
- `token`：Desktop 持久化 LAN Token
- `name`：主机显示名称

Desktop 默认监听 `0.0.0.0:8787`。Mobile 配对成功后会保存地址与 Token，App 重启后自动尝试重连。

## 身份验证

HTTP 使用：

```text
X-CNKH-Token: <token>
```

WebSocket 也可通过查询参数携带 token。

## 实时与对账

| 通道 | 路径 | 用途 |
|---|---|---|
| WebSocket | `/api/v1/ws` | 实时变更提示 |
| Event poll | `/api/v1/events/poll` | WebSocket 不可用时的轮询补偿 |
| Notify | `POST /api/v1/notify` | 设备主动通知本地变更 |
| HTTP reconcile | REST endpoints | 定时 / 重连后的权威对账 |

Mobile 不把 WebSocket 当成唯一数据来源；断线、重连或事件遗漏时会通过 HTTP 重新对账。

## 主要 REST API

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/health` | 主机健康检查 |
| GET | `/api/v1/products?since=` | 商品 / 库存同步 |
| GET | `/api/v1/customers?since=` | 客户同步 |
| GET | `/api/v1/categories?since=` | 分类同步 |
| GET | `/api/v1/sales?since=` | 销售同步 |
| POST | `/api/v1/sales` | Mobile 上传本地 / 离线销售 |
| POST | `/api/v1/notify` | 同步事件通知 |
| GET | `/api/v1/events/poll` | 事件轮询 |

## 数据一致性规则

- Desktop 是商品、库存、分类、客户与已汇总销售的局域网权威来源。
- Mobile 可离线开单，并把待同步销售持久化到本地 outbox。
- 恢复连接后 Mobile 重试上传，再从 Desktop 做权威对账。
- Mobile 销售使用稳定 client sale identity，Desktop 幂等导入，避免网络重试造成重复记账。
- Desktop 销售 / 进货 / 盘点后的库存变化回传 Mobile。
- Desktop 作废销售状态回传 Mobile。
- Mobile 支持强制全量对账。

## 当前实现位置

Desktop：

```text
lib/services/lan_pairing_host.dart
lib/services/lan_sync.dart
lib/services/pos_repository.dart
```

Mobile：

```text
lib/services/lan_sync.dart
lib/services/pos_repository.dart
lib/screens/qr_capture_screen.dart
```

## 实机检查

1. Desktop 显示二维码，Mobile 扫描并连接。
2. Mobile 开一单，Desktop 出现销售并更新库存。
3. Desktop 开一单，Mobile 收到销售 / 库存变化。
4. Mobile 离线开单后恢复网络，确认只同步一次。
5. 重启两端，确认自动重连。
6. 作废销售后确认状态同步。

如果二维码正确但手机无法连接，请检查 Windows 防火墙、同一 Wi-Fi、访客网络 / AP isolation、VPN 或虚拟网卡导致的错误局域网 IP。
