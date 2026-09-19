# Mobile 1.10.1 布局修复报告

日期：2026-09-19。目标版本：`1.10.1+29` / `v1.10.1-mobile`。

## 修复结果与原因

### 商品、客户及供应商列表

三个页面共用同一类布局错误：`bottomNavigationBar` 内页码的 `Center` 未限制高度，会在父布局提供的高度范围内扩展，分页底栏因而占用原本属于列表的空间。已有数据被挤出可见区域，页码出现在屏幕中部。这不是数据库记录丢失。

新增 `PagedListFooter`，让页码容器按内容测量高度（`heightFactor: 1`），底栏只占所需空间，列表在剩余区域显示。保留按钮、色彩、分页、搜索、编辑及多选功能。三个列表增加加载、空数据、读取失败重试提示，已有记录列表支持下拉刷新；翻页请求进行中禁用分页按钮，继续防止旧请求覆盖新结果。

### 收银与购物车

收银主体改用一个纵向 `CustomScrollView`：搜索、分类、扫码等原有操作区随页面向上移出，商品区通过 `SliverPersistentHeader` 逐步收缩，购物车获得更多可用空间。紧凑商品卡保留名称、价格与加购按钮，隐藏 SKU 和缩略图；滑回顶部恢复。商品仍可横向浏览。

合计及结账在滚动主体之外，保持固定。空购物车和只有一件商品时补足必要滚动空间，避免内容少便无法收缩；长购物车不额外增加长空白。另处理窄屏、大字体、键盘弹出时的按钮、文字和分页溢出。

## 修改文件

| 文件 | 作用 |
| --- | --- |
| `lib/widgets/paged_list_footer.dart` | 共用紧凑分页栏和加载错误提示 |
| `lib/screens/admin/products_admin.dart` | 商品列表高度、读取状态和刷新 |
| `lib/screens/admin/entities_page.dart` | 客户、供应商列表高度、读取状态和刷新 |
| `lib/screens/cart_screen.dart` | 统一滚动、商品区收缩、购物车空间及屏幕适配 |
| `lib/screens/training_page.dart` | 员工培训说明收缩及固定结账行为 |
| `test/mobile_layout_test.dart` | 12 项针对本次问题的界面回归测试 |
| `tool/training_capture_test.dart` | 从真实页面捕获修复后截图及箭头坐标 |
| `tool/verify_training_bundle.py` | 核对 APK 内 16 组截图和箭头资料 |
| `.github/workflows/layout-validation.yml` | 独立界面回归及实际截图产物 |
| `pubspec.yaml` | 版本升级到 1.10.1+29 |
| `README.md` | 功能、下载和升级说明 |
| `RELEASE_NOTES.md` | 本次发布说明 |
| `MOBILE_LAYOUT_REPORT.md` | 本报告 |

## 数据库及兼容性

- Mobile 数据库保持 schema v9，本次没有迁移、清空或重写任何业务数据。
- 不修改销售金额、折扣、库存计算、离线队列或 LAN 协议 `cnkh-sync:v1`。
- MyInvois 模块与状态同步未修改。
- Desktop 未修改、未重新打包，继续配套 v0.4.0。

## 已完成验证

发布前功能代码验证基于 Mobile `8ff29d6b055c4ebc3a101e863dcdea3f7258a8fa`；随后仅整理说明、版本号及截图工具的冗余导入。发布工作流会在最终 main 提交再次执行完整测试和 APK 构建，成功才上传 Release 附件。

| 检查 | 实际结果与依据 |
| --- | --- |
| 界面回归 | **12 项通过**：[运行记录](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/35458950977) |
| Mobile 完整单元/Widget 测试 | **99 项通过**：[运行记录](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/35458953088) |
| Desktop ↔ Mobile HTTP 联调 | **10 项通过**：[运行记录](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/35458953065) |
| 静态分析 | 按原 CI 参数通过，无编译错误；仍有已有 warning/info，未声称零告警 |
| Android Release APK | 发布前构建成功，约 **113.1 MB**；正式安装包由最终 main 构建生成 |
| 培训打包核验 | APK 内 **16 组**真实截图与箭头元数据通过逐项校验 |
| Android 网络权限 | 构建产物确认含 `android.permission.INTERNET` |
| 视觉检查 | 已检查正常/收缩收银页、商品、客户、供应商五张真实渲染截图；记录可见、分页在底部、结账固定 |

12 项新增测试覆盖三类有数据列表（每类 52 条）、下一页/上一页、商品搜索和无匹配状态、四类读取错误及重试、小屏大字体、长购物车、空/单件购物车收缩还原、收缩后加购、固定结账和键盘弹出。HTTP 联调使用隔离数据库和真实 localhost HTTP，覆盖离线销售、重连、重复确认、库存依赖和 e-Invoice 状态同步。

培训图片由隔离测试数据驱动真实 Flutter 页面生成，不使用生成式假 UI；截图构建后先检查再放入 APK。CI 的 `mobile-training-screenshots` 产物可供查看完整 PNG/JSON。

## 发布与已知限制

- 正式下载及 SHA-256：[v1.10.1-mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.1-mobile)。以 Release 的 APK 及 `SHA256SUMS.txt` 为准，发布前的测试 APK 使用旧版本号，不用于正式安装。
- 尚未在用户实际手机、打印机或门店 Wi-Fi 上验收；自动布局测试及截图不能替代实际设备操作。
- 沿用原项目 debug 签名配置。不同构建的签名可能不同；若无法覆盖安装，应先完成同步及备份，不要直接卸载带有未同步销售的旧版本。
- 本次未执行真实 MyInvois Sandbox / Production 提交，也未改变上一版的税务功能范围。
