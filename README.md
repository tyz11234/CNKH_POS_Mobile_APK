# 黄金发宝号 · CNKH POS Mobile Source

> README 最后更新：**2026-09-05**

这是 CNKH POS Mobile 的完整 Flutter 源码主线。Android 正式 APK 由本分支的 CI 构建并发布到 GitHub Releases。

## 当前源码与正式版

| 项目 | 当前版本 |
|---|---|
| Mobile 源码 | **1.8.2+24** |
| Mobile 正式 Release | **`v1.8.2-mobile`** |
| 对应 Desktop | **0.3.2+5（`v0.3.2`）** |
| LAN 协议 | `cnkh-sync:v1` |
| 更新日期 | **2026-09-05** |

推荐配套：**Desktop v0.3.2 + Mobile v1.8.2**。

Mobile v1.8.2 Release：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.8.2-mobile

Desktop v0.3.2 Release：
https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.2

当前 `v1.8.2-mobile` tag 与正式 APK 对应的源码提交：

```text
d6f909b580c20267e06cf6a112e65af174163977
```

## 局域网配对

1. 手机和电脑连接同一个 Wi‑Fi / LAN。
2. Desktop v0.3.2 启动后作为局域网权威主机，默认监听端口 `8787`。
3. Desktop 打开 LAN / 扫码配对并显示二维码。
4. Mobile 点击扫码配对并扫描 Desktop 二维码。
5. Mobile 保存 Desktop 地址和 Token，之后自动重连并进行 HTTP 对账。

二维码格式：

```text
cnkh-sync:v1|{"baseUrl":"http://192.168.x.x:8787","token":"...","name":"CNKH-PC"}
```

## 同步模型

Desktop 是店内局域网权威主机；Mobile 支持断网继续开单。恢复连接后 Mobile 会重试待同步销售，再从 Desktop 拉取权威商品、库存、客户、分类和销售数据。

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

## 手机端功能

- 收银 POS、商品搜索、摄像头扫码
- 现金 / 卡 / DuitNow / 赊账
- 折扣、挂单、今日销售、销售记录、作废
- 商品、分类、客户、供应商、进货、盘点、报表
- 小票格式编辑 / 预览
- 电子收据 PDF / WhatsApp 分享
- 条码导出 / 打印队列
- 可选蓝牙小票打印

Windows 特有的硬件标签打印及整库维护仍由 Desktop 处理。

## 开发与验证

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

`source/main` 的 GitHub Actions 会执行 Analyze、测试和 Android release APK 构建。正式发布提交会同时创建版本化 GitHub Release，并把 Release tag 固定到实际构建该 APK 的源码提交。

## 正式发布规则

- 当前正式版本：`1.8.2+24`
- 当前正式 tag：`v1.8.2-mobile`
- 正式 APK 只从 GitHub Releases 下载
- `1.8.0 / 1.8.1` 是发布流程过渡版本，不建议继续安装
- 后续功能 / 修复先在源码分支完成，通过 CI 后再进入 `source/main`

## 仓库分支约定

- `main`：正式版下载入口、Release 说明、协议文档
- `source/main`：完整 Flutter Mobile 源码主线
- Release APK 与源码必须可追溯到同一提交

分发首页：
https://github.com/tyz11234/CNKH_POS_Mobile_APK
