# 黄金发宝号 · CNKH POS Mobile

> README 最后更新：**2026-09-05**

本仓库的 `main` 分支用于 **Android 正式版下载与分发说明**。完整 Flutter 源码位于 [`source/main`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)。

## 当前正式组合

| 项目 | 当前正式版本 |
|---|---|
| Mobile | **1.8.2+24**（`v1.8.2-mobile`） |
| Desktop | **0.3.2+5**（`v0.3.2`） |
| LAN 协议 | `cnkh-sync:v1` |
| Mobile 发布日期 | **2026-09-05** |
| Desktop 发布日期 | **2026-09-05** |

推荐配套使用：**Desktop v0.3.2 + Mobile v1.8.2**。

## 下载正式 APK

- [Mobile v1.8.2 Release 页面](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.8.2-mobile)
- [直接下载 CNKH_POS_Mobile.apk](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.8.2-mobile/CNKH_POS_Mobile.apk)
- [直接下载 CNKH_POS_Mobile_v1.8.2.apk](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.8.2-mobile/CNKH_POS_Mobile_v1.8.2.apk)
- [全部 Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases)

> **正式安装包只以 GitHub Releases 为准。** `main` 不再保存容易混淆的旧 APK 文件，避免从 Code 页面误装历史版本。

当前 v1.8.2 APK SHA-256：

```text
c5514d470f4266bb51f26bf95b26d22d53073c725e4f7264f6db9cf9764587b9
```

## v1.8.2 重点

- Desktop 作为局域网权威主机
- Mobile 扫描 Desktop 二维码完成 LAN 配对
- 商品、库存、分类、客户、销售同步
- WebSocket 实时变更提示
- HTTP 定时对账与断线重连
- Mobile 离线销售持久化与重试
- `client_sale_id` 幂等导入，避免重复销售
- 多设备离线收据号防碰撞
- Desktop 库存变更回传 Mobile
- Desktop 作废销售状态回传 Mobile
- 强制全量对账
- 电子收据 PDF 与 WhatsApp 分享

## 怎么安装

1. 打开上面的 **v1.8.2 Release**。
2. 下载 `CNKH_POS_Mobile.apk` 或 `CNKH_POS_Mobile_v1.8.2.apk`。
3. Android 允许安装未知来源应用。
4. 安装并打开 CNKH POS Mobile。

### 第一次登录

种子账号自动写入（演示 PIN 任意）：

| 用户名 | 角色 |
|---|---|
| `admin` | 管理员 |
| `staff` / `staff2` | 员工 |

建议先用 Admin 设置店名、DuitNow、小票；日常收银用 Staff。

## 和 Desktop 配对

1. 手机和电脑连接同一个 Wi‑Fi / LAN。
2. 打开 **CNKH_POS_Desktop v0.3.2**。
3. Desktop 打开 LAN / 扫码配对，电脑显示二维码。
4. Mobile 点击扫码配对并扫描电脑二维码。
5. 配对成功后 Mobile 保存 Desktop 地址和 Token，并自动重连与对账。

二维码协议前缀：

```text
cnkh-sync:v1
```

Desktop 仓库：
https://github.com/tyz11234/CNKH_POS_Desktop

Desktop 正式版：
https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.2

## 功能一览

- 收银、商品搜索、摄像头扫码
- 现金 / 卡 / DuitNow / 赊账
- 折扣、挂单、今日销售、销售记录、作废
- 商品、分类、客户、供应商、进货、盘点、报表
- 小票格式、电子收据 PDF、WhatsApp 分享
- 条码导出 / 打印队列、可选蓝牙小票打印
- LAN 配对、离线销售与自动重连

## 版本说明

| 版本 | 状态 | 日期 | 说明 |
|---|---|---|---|
| `1.8.2+24` | **当前正式版** | 2026-09-05 | LAN 同步一致性、离线幂等、重连、库存 / 作废回传、正式发布流程整理 |
| `1.8.0 / 1.8.1` | 发布流程过渡版本 | 2026-09-05 | 不建议继续安装，请使用 1.8.2 |
| `1.7.2+21` | 历史正式版 | 2026-09-04 | 中文电子收据、WhatsApp PDF 分享 |
| `1.6.0+18` | 历史正式版 | 2026-09-04 | 小票模板编辑 / 预览、销售小票详情 |

## 分支约定

- `main`：正式版下载入口、Release 说明、协议文档
- `source/main`：当前 Flutter Mobile 源码主线
- 功能修复先在源码主线通过 Analyze / Tests / Android Release build，再发布正式 APK
- 正式 APK 一律从 GitHub Releases 下载

源码开发请以 [`source/main`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main) 为准。
