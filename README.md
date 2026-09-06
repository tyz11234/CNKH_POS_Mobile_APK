# 黄金发宝号 · CNKH POS Mobile

用于 Android 手机的门店收银客户端。支持摄像头扫码、本地开单和局域网同步，与 [CNKH POS Desktop](https://github.com/tyz11234/CNKH_POS_Desktop) 配套使用，核心收银与店内同步不依赖云服务器。

基于 **Flutter / Dart**，使用本地 SQLite 保存业务数据。

[下载与安装](#下载与安装) · [首次登录](#首次登录) · [电脑配对](#连接电脑端) · [完整源码](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)

> 更新日期：2026-09-06。本仓库的 `main` 是下载与使用说明主页；Flutter 源码位于 `source/main`。下方登录与同步说明适用于已合并的修复代码及修复构建。

## 当前状态

| 项目 | 状态 |
| --- | --- |
| 手机源码 | [`source/main`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)，已合并 [本轮修复 #5](https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/5) |
| 配套电脑源码 | [Desktop `main`](https://github.com/tyz11234/CNKH_POS_Desktop)，已合并配套修复 |
| 修复构建 | Android Release APK 已构建成功，见下方 Actions |
| 最近正式 Release | [v1.8.2-mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.8.2-mobile)，发布于 2026-09-05，早于本轮修复 |
| 源码版本字段 | Mobile `1.8.2+24` / Desktop `0.3.2+5`，本轮未递增版本号 |
| 新增 OCR 进货功能 | 本轮未实施，不属于已完成修复 |

**本轮修复尚未单独发布新 Release。旧 Release APK 不会自动获得源码修复，请按构建链接或提交记录区分版本。**

## 主要功能

| 模块 | 功能 |
| --- | --- |
| 手机收银 | 商品搜索、摄像头扫码加购、购物车、折扣、挂单与取单 |
| 收款 | 现金、银行卡、DuitNow、赊账与找零 |
| 业务管理 | 商品、分类、客户、供应商、进货、盘点与报表 |
| 销售记录 | 今日与历史销售、销售详情、作废及库存回补 |
| 小票 | 模板编辑与预览、电子收据 PDF、WhatsApp 分享、可选蓝牙打印 |
| 店内同步 | 扫码连接电脑、离线业务保存、自动重连、待同步队列与全量对账 |
| 账号 | 管理员与员工权限、实际 PIN 验证及员工 PIN 设置 |

现有页面布局、收银金额、折扣与舍入规则保持不变。DuitNow 收款码展示不等同于银行自动到账确认。

## 下载与安装

### 已验证的修复构建

- [Android 修复 APK 构建及下载入口](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34006764842)
- [配套 Windows 修复构建及下载入口](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34007132758)

登录 GitHub，在运行页面下方 **Artifacts** 下载 `CNKH_POS_Mobile_release`，解压后取得 APK。Actions 产物有保留期限。

安装步骤：

1. 先更新并启动配套电脑端。
2. 在 Android 手机上下载并解压 artifact，选择其中的 APK。
3. 按 Android 提示允许当前下载或文件管理应用安装应用。
4. 安装后打开 CNKH POS Mobile，完成登录与配对。

APK 适用于 Android，不能直接安装到 iPhone。若覆盖安装提示签名不一致，请先保留现有应用和业务数据，不要直接卸载正在使用的版本。

### 既有正式发布

[v1.8.2-mobile Release](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.8.2-mobile) · [所有 Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases)

这些旧 APK 保留作版本追溯，**不包含本轮新增修复**。

## 首次登录

首次运行修复版，或从尚未设置真实 PIN 的旧版升级时：

1. 在原登录页选择管理员，用户名使用 `admin`。
2. 输入自定的 **6–12 位数字 PIN**，点击登录。
3. 按提示再次输入同一 PIN，完成初始化。
4. 管理员在用户管理列表点选员工，设置员工 PIN。

预置员工账号包括 `staff`、`staff2`。员工必须先由管理员分配 PIN；选择“管理员”选项本身不能提升账号权限。

PIN 连续输错 5 次会锁定 5 分钟。恢复出厂业务数据时保留管理员 PIN，员工 PIN 需重新设置。手机与电脑的账号凭据分别在本机管理，配对不会自动同步 PIN。

## 连接电脑端

1. 手机和电脑连接同一 Wi-Fi 或可互通的局域网。
2. 启动电脑端，打开 LAN / 扫码配对页面，显示二维码。
3. 手机点击扫码配对，扫描电脑二维码。
4. 手机保存电脑地址与配对令牌，完成同步。

电脑默认端口为 **8787**，二维码前缀为 `cnkh-sync:v1|`。连接失败时，检查电脑是否运行、IP 是否变化、防火墙和局域网设备隔离设置。

电脑保持运行时才可与手机同步。断线期间手机仍可本地开单；恢复连接后自动上传待处理业务，再拉取电脑端数据。

## 离线与同步说明

- 电脑作为店内主机，汇总手机提交的业务。
- 已配对手机的销售、作废、商品/客户/供应商/分类修改、进货及盘点保存到持久队列。
- 操作按顺序上传，收到电脑确认后才从队列移除；失败时保留并重试。
- 商品与客户保留两端 ID 对照，避免条码匹配后库存或赊账关联错误。
- 同一操作重试不会重复入库、扣库存或回补库存。
- 手机作废可上传到电脑，电脑作废也可回传手机。
- 首次连接时电脑离线，后台仍会继续尝试重连。
- 盘点或资料修改发生冲突时保留待处理数据，并通过同步操作提示错误；强制全量对账不会自动解决业务冲突。

已有配对数据时不能直接更换成另一门店的令牌；同一门店令牌的 IP 地址可以更新。

新销售会保存当时成本，历史查询取消默认 200 条截断。旧单未保存的历史成本无法凭空恢复，升级前已作废的旧单不会被批量自动回补。

详细边界见 [修复与升级说明](https://github.com/tyz11234/CNKH_POS_Mobile_APK/blob/source/main/RELIABILITY_NOTES.md)。

## 分支与源码构建

| 分支 | 用途 |
| --- | --- |
| `main` | 本主页：下载入口、状态与使用说明 |
| `source/main` | 完整 Flutter Android 源码 |

开发时请明确检出源码分支：

```bash
git clone --branch source/main --single-branch https://github.com/tyz11234/CNKH_POS_Mobile_APK.git
cd CNKH_POS_Mobile_APK
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

需要配置 Flutter 与 Android SDK。构建产物为 `build/app/outputs/flutter-apk/app-release.apk`。

## 已完成验证

- [Android：静态分析、25 项测试、Release APK 构建](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34006764842)
- [Desktop：静态分析、35 项测试、Windows Release 构建](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34007132758)
- [两端真实 HTTP 联调：6 项测试](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34007132843)

联调覆盖不同 ID 与赊账关联、离线进货/销售/作废顺序、盘点冲突、初始断线重连、确认丢失重试和电脑作废回传。自动化通过不代表已验证所有实际打印机和手机型号。

## 相关入口

- [电脑端主页](https://github.com/tyz11234/CNKH_POS_Desktop)
- [手机端完整源码](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)
- [本轮修复记录](https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/5)
