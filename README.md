# 黄金发宝号 · CNKH POS Mobile

Android Flutter 手机收银端，配合本账号的 **CNKH_POS_Desktop** 使用。两端通过局域网直接同步，不需要云服务器。

## 当前源码线

- 源码版本：`1.8.0+22`
- LAN 协议：`cnkh-sync:v1`
- Desktop：`https://github.com/tyz11234/CNKH_POS_Desktop`
- 本仓 Releases：`https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases`

> GitHub Release 中已经发布的 APK 版本可能低于当前源码版本。只有在对应 Release 实际发布后，才把该源码版本视为正式发布 APK。

## 局域网配对

1. 手机和电脑连接同一个 Wi-Fi / LAN。
2. Desktop 打开后会作为局域网主机监听默认端口 `8787`。
3. Desktop 顶栏点击「扫码配对 / LAN pair」，电脑显示配对二维码。
4. Mobile 顶栏点击扫码配对，用手机扫描电脑二维码。
5. Mobile 保存主机地址和 Token，之后会自动重连并进行 HTTP 对账。

二维码格式：

```text
cnkh-sync:v1|{"baseUrl":"http://192.168.x.x:8787","token":"...","name":"CNKH-PC"}
```

## 同步模型

Desktop 是店内局域网的权威主机。Mobile 可以离线开单；恢复连接后会把待同步销售推送回 Desktop，再从 Desktop 拉取权威商品、库存、客户、分类和销售数据。

同步包含：

- 商品、库存、分类、客户增量同步
- 销售记录增量同步
- WebSocket 实时变更提示
- HTTP 定时对账和 WebSocket 断线重连
- Mobile 离线销售持久化与重试
- `client_sale_id` 幂等导入，避免重试导致重复记账
- 多设备离线收据号防碰撞
- Desktop 销售/进货/盘点后库存回传 Mobile
- Desktop 作废销售状态回传 Mobile
- 强制全量对账

## 手机端功能

- 收银 POS、商品搜索和摄像头扫码
- 现金 / 卡 / DuitNow / 赊账
- 折扣、挂单、今日销售
- 商品、分类、客户、供应商、进货、盘点和报表
- 电子收据 PDF / 分享
- 条码导出与打印队列
- 可选蓝牙小票打印

Windows 特有的硬件标签打印和整库备份/还原仍由 Desktop 处理。

## 开发与验证

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

正式 CI 会执行相同的 Analyze、测试和 Android Release APK 构建，并把 APK 作为 workflow artifact 上传。

## 仓库分支约定

- `main`：历史 APK / Releases / 分发说明
- `source/main`：当前 Flutter 源码主线
- 功能修复通过 PR 合并到源码主线后再构建 APK

这样 APK 分发历史和可维护源码不会再混在一起。
