# 黄金发宝号 · 手机收银 APK

本仓库只发布 **Android 安装包**。功能与 PC 桌面版对齐。

| | |
|--|--|
| 店名 | **黄金发宝号** |
| 当前版本 | **1.7.2**（`v1.7.2-mobile`） |
| 下载 | [Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases) |
| PC 桌面 | [CNKH_POS_Desktop](https://github.com/tyz11234/CNKH_POS_Desktop) |

> 旧 PySide「CNKH POS V5」桌面已停用，请改用上面的新 Desktop。

---

## 怎么安装

1. 打开最新 Release：https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.7.2-mobile  
2. 下载 `CNKH_POS_Mobile.apk` 或 `CNKH_POS_Mobile_v1.7.2.apk`  
3. 手机允许「未知来源」→ 安装 → 打开  

### 第一次登录

种子账号自动写入（演示 **PIN 任意**）：

| 用户名 | 角色 |
|--------|------|
| `admin` | 管理员 |
| `staff` / `staff2` | 员工 |

建议先用 Admin 设店名、DuitNow、小票；日常收银用 Staff。

手机数据与 PC 是**各自本地库**；需要两边互通时用局域网配对（`cnkh-sync`）。

---

## 1.7.2 重点

- 电子收据 PDF **中文不乱码**（嵌入 Noto Sans SC）
- 发送电子收据 → **直接打开 WhatsApp 并附加 PDF**（需已装 WhatsApp）
- 小票格式编辑 + 实时预览；今日/销售可点进小票详情
- 商品 **进货价 / 售价**；进货扫码 / 识别进货单（已有商品入库，没有则新建）
- 报表：销售额、成本、毛利、毛利率

---

## 功能一览

- 收银、扫码加购、挂单、结账（现金 / 卡 / DuitNow / 赊账）
- 今日销售、销售记录、作废（权限按角色）
- 设置：店名、小票格式、电子收据缓存、LAN 配对、DuitNow（Admin）
- 商品 / 客户 / 供货商 / 进货 / 报表
- 工厂初始化（危险操作，需确认）

---

## 和电脑一起用

1. 手机与 PC 同一 Wi‑Fi  
2. 在 **新 Desktop** 或同步端开配对  
3. 手机顶栏扫码配对（或设置里手填 `http://电脑IP:8787`）  

详见桌面 README：https://github.com/tyz11234/CNKH_POS_Desktop

---

## 版本

| Tag | 说明 |
|-----|------|
| **v1.7.2-mobile** | 中文 PDF + 直开 WhatsApp 发 PDF |
| v1.6.0-mobile | 小票模板 + 销售小票详情 |
| v1.5.0-mobile | 较早功能包 |

源码在 Flutter `mobile/` 工程（与 Desktop 功能同步维护），本仓以 **APK 发布**为主。
