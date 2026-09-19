# CNKH POS Mobile 1.10.1+29

- 修复商品、客户和供应商列表空白、分页栏出现在屏幕中间的问题：底栏只占所需高度，数据列表恢复显示。
- 收银页支持统一纵向滑动，商品卡片随滚动收缩，购物车获得更多空间；横向选商品和固定底部结账保留。
- 空购物车、单件商品也可收缩和恢复；调整小屏、大字体及键盘弹出时的布局。
- 增加加载、空数据、读取失败重试和列表下拉刷新。
- 更新真实界面培训截图，包含收银收缩状态和三类管理列表；APK 检查 16 组截图及箭头资料。

本次不修改数据库 schema v9、销售金额、库存、LAN Sync、MyInvois 或 Desktop 程序。配套 Desktop 仍为 v0.4.0。

验证与修改文件说明：[MOBILE_LAYOUT_REPORT.md](https://github.com/tyz11234/CNKH_POS_Mobile_APK/blob/v1.10.1-mobile/MOBILE_LAYOUT_REPORT.md)。

下载后核对 SHA256SUMS.txt。APK 沿用项目现有 debug 签名；签名不同可能无法覆盖安装。先同步和备份，遇到签名错误不要直接卸载有未同步销售的旧版本。真实手机、打印机、门店 Wi-Fi 和真实 MyInvois 提交仍需现场验收。
