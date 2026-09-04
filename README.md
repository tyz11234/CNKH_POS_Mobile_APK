# 黄金发宝号 · 手机收银助手（Android APK）

Flutter 手机端，配合桌面 **[CNKH Hardware POS V5](https://github.com/tyz11234/-CNKH_POS_V5)** 使用。  
登录页 / 顶栏店名：**黄金发宝号** · 工程包名仍为 `cnkh_pos_mobile`。

**当前版本：1.4.1**（店名更新）· 上一功能包 1.4.0（连续扫码 / 分类 / 商品图 / BT 等）

---

## 下载安装（Android）

1. 打开 [Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases)
2. 下最新 `CNKH_POS_Mobile.apk`（或带版本号的同名文件）
3. 手机允许「未知来源」安装 → 打开 App
4. 用 **Admin / Staff** 账号登录（演示账号见设置或店内约定）
5. **设置**里导入 DuitNow 收款码（仅 Admin 可改；Staff 只读）

> 本仓发布 **APK**；源码与桌面端在 [‑CNKH_POS_V5](https://github.com/tyz11234/-CNKH_POS_V5)。iOS 需 Mac + Apple 签名，Linux 无法直接出可装 IPA。

---

## 和电脑一起用（局域网，无云）

| 步骤 | 做什么 |
|------|--------|
| 1 | 手机与 PC **同一 Wi‑Fi** |
| 2 | PC 顶栏 **同步/配对**，开服务（默认端口 **8787**） |
| 3 | 手机顶栏 **扫码配对**，扫 PC 二维码 |
| 4 | 看连接状态点；结账后销售应近实时互见 |

扫不了时可在 **设置 → LAN Sync → 高级** 手填 `http://电脑IP:8787` 与 Token。

配对码格式：

```text
cnkh-sync:v1|{"baseUrl":"http://192.168.x.x:8787","token":"...","name":"CNKH-PC"}
```

---

## 手机端功能一览

| 模块 | 说明 |
|------|------|
| 收银 POS | 搜索 / 分类芯片过滤、连续摄像头扫码、挂单超时提醒 |
| 结账 | 现金 / 卡 / DuitNow / 赊账、找零、折扣审计 |
| 电子收据 | 生成 PDF，系统分享（含 WhatsApp）；临时文件用后删 |
| 今日 | 销售列表、搜索单号/手机/客户 |
| 管理 | 商品（自动/手动条码）、分类（选择器不手打）、客户供应商、进货、盘点、报表、日结 |
| 商品图 | 可选开启；文件在 `product_images/`，与 SQLite 分开 |
| 条码 | 打印队列 + **批量导出 PNG**（条码下带商品全名） |
| 蓝牙小票 | 可选（默认关） |
| 低库存 | LAN 推送提醒 |
| 角色 | Admin 可改收款码；Staff 收银为主 |

### 故意只在 PC 做的

- 条码**标签打印机**硬件对话框  
- Windows 备份 / 还原整库  

其余日常收银 / 管货手机基本可对等。对照表见仓库内 `MOBILE_PC_PARITY.md`（若已同步）。

---

## 版本简表

| Tag | 要点 |
|-----|------|
| **v1.4.1-mobile** | 登录/品牌：**黄金发宝号** |
| v1.4.0-mobile | 连续扫码、分类对齐 PC、商品图、BT、条码批量导出 |
| v1.3.0 / 1.2.0 | LAN 同步、电子收据、摄像头扫码、本机 SQLite 全功能移植 |

---

## 开发者构建

```bash
cd mobile   # 若在 monorepo；本 APK 仓根目录即 Flutter 工程时直接：
flutter pub get
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

桌面联调文档（若在源码树）：`LAN_SYNC.md` · `E_RECEIPT_AND_SCAN.md` · `NEXT_BATCH_NOTES.md`

---

## 相关链接

- **PC 仓库（装 Windows / 开同步）**：[tyz11234/-CNKH_POS_V5](https://github.com/tyz11234/-CNKH_POS_V5)
- **本仓 Releases（下 APK）**：[Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases)

有问题先看：同一 Wi‑Fi、防火墙放行 8787、PC 已点「同步/配对」、手机 Token 一致。
