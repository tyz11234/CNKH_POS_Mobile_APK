# 黄金发宝号 · 手机收银 APK

> README 最后更新：**2026-09-05**

本仓库的 `main` 分支用于 **Android APK / Releases 分发**。可维护的 Flutter Mobile 源码放在 [`source/main`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)，并与 **CNKH_POS_Desktop** 局域网协议同步维护。

| | |
|--|--|
| 店名 | **黄金发宝号** |
| 当前正式 APK | **1.7.2**（`v1.7.2-mobile`） |
| 正式 APK 发布日期 | **2026-09-04** |
| 当前源码 | **1.8.0+22**（`source/main`） |
| 当前源码更新日期 | **2026-09-05** |
| APK 下载 | [Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases) |
| Mobile 源码 | [`source/main`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main) |
| PC 桌面 | [CNKH_POS_Desktop](https://github.com/tyz11234/CNKH_POS_Desktop) |

> 当前源码版本高于已发布 APK 并不代表 1.8.0 已正式发布。只有对应 GitHub Release 实际创建并附带 APK 后，才把该版本视为正式发布版本。

---

## 版本概览

| 版本 | 状态 | 更新 / 发布日期 | 重点 |
|---|---|---|---|
| `1.8.0+22` | 当前源码，未正式发布 | **2026-09-05** | LAN 同步一致性、增量 cursor、断线重连、HTTP 对账、离线销售幂等、多设备收据号防碰撞、Android 构建工具链更新 |
| `1.7.2+21` | 正式 APK | **2026-09-04** | Noto Sans SC 中文电子收据、WhatsApp PDF 分享 |
| `1.6.0+18` | 正式 APK | **2026-09-04** | 小票模板编辑 / 预览、销售小票详情 |
| `1.5.0+17` | 正式 APK | **2026-09-04** | WhatsApp PDF、电子收据缓存、结账与销售列表 UI 修正 |
| `1.4.2+16` | 正式 APK | **2026-09-04** | 品牌、电子收据缓存、今日销售列表修正 |
| `1.4.1+15` | 正式 APK | **2026-09-04** | 黄金发宝号品牌整理，延续 1.4.0 功能包 |
| `1.4.0+14` | 正式 APK | **2026-09-04** | 连续扫码、分类、商品图、LAN、蓝牙打印、条码队列 |

正式 APK 日期以 GitHub Release 的 `published_at` 日期为准；未正式发布的源码版本使用源码更新日期。

---

## 怎么安装

1. 打开 [Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases)  
2. 选择最新正式 Release  
3. 下载 APK  
4. 手机允许「未知来源」→ 安装 → 打开

### 第一次登录

种子账号自动写入（演示 PIN 任意）：

| 用户名 | 角色 |
|--------|------|
| `admin` | 管理员 |
| `staff` / `staff2` | 员工 |

建议先用 Admin 设置店名、DuitNow、小票；日常收银用 Staff。

---

## 和电脑一起用

1. 手机与 PC 连接同一个 Wi‑Fi / LAN  
2. 打开 **CNKH_POS_Desktop**，Desktop 作为局域网主机  
3. Desktop 顶栏打开 LAN / 扫码配对，电脑显示二维码  
4. Mobile 顶栏点击扫码配对，用手机扫描电脑二维码  
5. 配对成功后 Mobile 会保存主机地址和 Token，并自动重连、实时提示和 HTTP 对账

协议前缀：`cnkh-sync:v1`

当前 `source/main` 已包含 Desktop-authoritative 商品、库存、分类、客户、销售同步，Mobile 离线销售持久化与重试、幂等导入、多设备收据号防碰撞、WebSocket 重连、HTTP 对账、作废状态同步和强制全量对账。

---

## 已发布 1.7.2 重点

**发布日期：2026-09-04**

- 电子收据 PDF 中文不乱码
- WhatsApp 分享 PDF
- 小票格式编辑 + 实时预览
- 商品进货价 / 售价
- 进货扫码 / 识别进货单
- 报表：销售额、成本、毛利、毛利率

---

## 功能一览

- 收银、扫码加购、挂单、结账（现金 / 卡 / DuitNow / 赊账）
- 今日销售、销售记录、作废
- 店名、小票格式、电子收据、LAN 配对、DuitNow
- 商品 / 客户 / 供货商 / 进货 / 报表
- 工厂初始化

---

## 分支约定

- `main`：APK / Releases / 分发说明
- `source/main`：当前 Flutter Mobile 源码主线
- 新功能和修复先在源码主线完成 Analyze、Tests、Android Release build，再发布 APK

源码开发请以 [`source/main`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main) 为准。
