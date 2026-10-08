# CNKH POS Mobile 1.10.11+39 — 正式固定密钥签名

发布日期：2026-10-08。**首次正式 Release Keystore 签名**，不再使用每次可能变化的 Debug 密钥；包名仍为 `com.cnkh.cnkh_pos_mobile`。

## 本次版本

- 正式签名证书 SHA-256：`6A:BA:50:A8:9D:F9:52:C1:7A:82:1C:7C:F5:6D:86:1D:6C:22:72:CD:A9:55:5C:E7:65:23:32:92:1A:84:99:C7`。
- Android Version Name 为 `1.10.11`，Version Code 为 `39`，用于后续固定签名覆盖升级。
- **仅 Mobile 更新签名/打包配置与版本号**。没有改变收银页面、商品/库存、离线模式、SQLite schema v10、`cnkh-sync:v1`、e-Invoice 同步或其他业务实现。
- 配套 Desktop 维持 `1.10.10+38`；两端的发布编号暂不同，但 LAN 协议没有变化。
- 正式 APK 由 GitHub Actions 在使用 Repository Secrets 解码固定密钥后编译；验签与摘要在 Actions 中自动执行，构建失败不会自动发布。
- 线上实机、打印机、门店网络与历史数据完整迁移尚无实测结果，不应把 CI 通过等同于生产设备验收。

## 安装与数据安全警告

**这是新的 Android 证书身份，不能直接覆盖历史 Debug 签名的 Mobile APK。** 请勿直接卸载旧 App，也不要以“已同步到 Desktop”替代完整备份。旧应用中 SQLite、SharedPreferences、本地图片和未同步 Outbox 等数据，必须先备份并验证能实际恢复。没有完整可恢复备份时，请保留旧版并停止迁移。首次完成切换后，后续只要证书与包名保持一致、versionCode 正确递增且数据库迁移兼容，新版才可以正常覆盖。

参考 [README 固定密钥与升级说明](README.md#android-正式签名固定-keystore-与升级安全说明2026-10-08)；历史 [1.10.10 Debug 版本](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.10-mobile) 继续独立保留，不会被覆盖。

---
# CNKH POS Mobile 1.10.10+38

发布日期：2026-10-08。**Android APK 已发布并核验，按维护者要求使用 Debug 签名。** 数据库 schema 保持 v10，LAN 协议保持 `cnkh-sync:v1`。

## 本次修复

以下为 Desktop / Mobile 配套版本的完整 16 项修复；作用端标明实际变更范围。

| 编号 | 作用端 | 修复后行为 |
| --- | --- | --- |
| F01 | 双端 | 逐行删空购物车时清除整单折扣，下一笔销售不再继承旧折扣。 |
| F02 | Desktop | 进货追加相同商品但不同成本时保留独立明细，维持准确总额和最终成本顺序。 |
| F03 | Desktop | 进货不再合并不同 ID 或不同明确编码的同名商品；按名称匹配时要求结果唯一。 |
| F04 | Mobile | 清除交易前保护未同步销售及依赖交易记录的待处理任务，防止销售和上传任务丢失。 |
| F05 | 双端 | 商品保存、进货建品和电脑接收修改采用一致的条码 / SKU 冲突检查；旧歧义数据拒绝扫码误选，不自动删除商品。 |
| F06 | Desktop | 使用最终 Invoice 1.1 内容计算摘要和数字签名，并拒绝旧的错版本签名。 |
| F07 | Mobile | 完整销售对账时将电脑快照中缺失的已同步销售排除出有效销售；保护离线及待处理记录，失败不推进游标。 |
| F08 | Mobile | 销售作废待核对时继续拉取电子发票状态；保留库存保护，暂缓目录和依赖目录的销售拉取，解除后从保留游标重放。 |
| F09 | 双端 | 12 位数字条码使用 Code128 原样编码，打印标签不再自动追加第 13 位。 |
| F10 | Mobile | 后台轮询和主动同步重新加载已保存配置；地址或 token 变化后更换旧 WebSocket 连接。 |
| F11 | 双端联动 | 更正发票接口返回原销售收据号，并独立保留 invoice_no，使手机正确关联电脑销售的发票状态。 |
| F12 | 双端 | 新挂单保存售价及显示快照；取单保留原价，同时使用当前库存和删除状态检查，兼容旧挂单。 |
| F13 | Desktop | 报表响应交易及导航刷新，保留手选日期，并忽略过期异步查询结果。 |
| F14 | 双端 | 现金 / 定金以整数分解析并明确校验，拒绝 NaN、Infinity、指数及超范围输入。 |
| F15 | 双端 | PDF 和蓝牙打印输出已配置的 DuitNow 付款图片，保留比例和留白；缺图时不输出扫码提示。 |
| F16 | Desktop | 销售日期筛选使用次日排他上界，包含结束日最后一秒的小数部分。 |

## 验证记录

- Desktop 发布流水线 [37782987933](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37782987933) 全部成功：完整测试 **188 项通过**，培训截图及图片显示测试通过，Windows Release 编译、11 组培训资源、安装器及便携 ZIP 验证通过。首次安装和重复安装均核对 **56 个文件**的 SHA-256，安装测试没有启动 POS。
- Mobile 发布流水线 [37784970334](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37784970334) 全部成功：完整测试 **187 项通过**，双端培训截图、图片显示、APK Release 编译、培训资源、INTERNET 权限及 `apksigner` 签名验证通过。
- 两端真实 HTTP / WebSocket 配套回归 [37784970356](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37784970356) **29 项通过**；实际配对源码为 Desktop `8acda041983a10ab6f83fdbaae41be7a2e3e2c2c` 与 Mobile `c016ce1c90bdcff11ed63f0a2cfc562dc4ee93e9`。Desktop 发布提交 `9ae58847a43a3a70f481a22ba246591c0eb9f3b9` 仅追加安装器版本检测修正，业务源码相同。
- 两端 CI 的 `flutter analyze --no-fatal-infos --no-fatal-warnings` 均通过，未发现 error；保留原有 warning / info。
- 本地独立 ZXing 解码验证通过：两端 12 位条码均读回原内容；两端 PDF 及 384 / 576 dots ESC/POS 栅格中的 6 个二维码产物均读回正确测试内容。
- 本地 `git diff --check`、修复源码包完整性和补丁应用检查通过。

Windows EXE 与 ZIP 已从正式 Release 重新下载，SHA-256、ZIP 完整性、x64 程序、运行库和 11 组培训图片 / 箭头元数据验证通过。Android APK 校验通过：包名 `com.cnkh.cnkh_pos_mobile`、版本 `1.10.10` / build `38`、3 种架构、16 组培训图片 / 箭头元数据及 Debug 证书指纹均已核对。实体 Windows / Android 设备、打印机、门店网络和 MyInvois Sandbox / Production 线上验收未执行。

## 安装与发布状态

Windows 与 Android **1.10.10+38** 已发布，均已从 GitHub 重新下载并通过校验。Android 包按维护者要求使用 Debug 签名。

| 本次产物 | 版本 | 下载 / 状态 |
| --- | --- | --- |
| Windows x64 Setup.exe 安装包 | 1.10.10+38 | [下载安装包](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.10/CNKH_POS_Desktop-windows-x64-v1.10.10-38-Setup.exe) |
| Windows x64 ZIP 便携包 | 1.10.10+38 | [下载便携包](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.10/CNKH_POS_Desktop-windows-x64-v1.10.10-38.zip) |
| Android APK | 1.10.10+38 | [下载 APK](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.10-mobile/CNKH_POS_Mobile.apk)（Debug 签名） |

[Windows Release v1.10.10](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v1.10.10) · [SHA-256 校验文件](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.10/SHA256SUMS.txt)

[Mobile Release v1.10.10-mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.10-mobile) · [版本化 APK](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.10-mobile/CNKH_POS_Mobile_v1.10.10.apk) · [APK SHA-256 校验文件](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.10-mobile/SHA256SUMS.txt)

| 发布文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| CNKH_POS_Desktop-windows-x64-v1.10.10-38-Setup.exe | 15168784 | `9e52049b4ca56cddd4147b5ed908a4251bdddb4e82dc4a2513976399b7427b34` |
| CNKH_POS_Desktop-windows-x64-v1.10.10-38.zip | 18350569 | `aa099af7b5153c05707324f068f74f33d0a88d3203ee329733383f3924e96f7b` |
| CNKH_POS_Mobile.apk（版本化 APK 内容相同） | 115822239 | `5b7ac868de253bd72b66b8cdf1df6d289464632fc85836f7d1beab1f19ea160b` |

Windows 更新前先备份业务数据并关闭程序。Setup.exe 按当前用户安装到 `%LOCALAPPDATA%\Programs\CNKH POS Desktop`，支持 Windows 10 1809 及以上的 x64 环境；安装及卸载只管理程序目录，不迁移或清除文档目录中的业务数据库。便携 ZIP 请解压到独立目录，保留 EXE、DLL 和 `data` 文件夹。安装器未配置 Windows 代码签名，可用上述 SHA-256 校验下载文件。

本次 Android APK 是 Release 构建，按维护者要求使用 **Android Debug 签名**；证书 SHA-256：`5e52d71bf713265e9e8fffb0606d3c903c0250f6cf541f3ee6d9a4b2954099e9`。**本次证书与已发布的 1.10.7+35 不同，无法直接覆盖安装旧版。** 请先同步并备份业务，保留仍有未同步数据的旧应用。此 Debug 密钥不保证在后续构建中复用；签名不匹配时 Android 会拒绝覆盖安装。

历史版本可在 [Desktop Releases](https://github.com/tyz11234/CNKH_POS_Desktop/releases) 和 [Mobile Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases) 查找，旧包不包含本次全部修复。

下载区及校验信息同时记录于 [README](README.md#下载与更新)。

---
# CNKH POS Mobile 1.10.9+37 — Android APK not released

## Source fixes

- **B001 (Both):** About reads the installed package Version and Build Number, removing duplicate hard-coded values.
- **B002 (Mobile):** Await product image file writes so asynchronous filesystem failures reach the existing sync recovery path.
- **B003 (Both CI):** Pin paired regression workflows to the companion repository commits included in this release cycle.

## Audit and regression

Six complete audit rounds were performed; Rounds 5 and 6 were clean. Final local regression passed: Mobile **147/147**, Desktop **151/151**, and paired HTTP integration **29/29**. Both analyzers reported zero errors. Round 6 made the supplier selection regression test wait for the async repository and dropdown state observed on the Windows runner.

The current Mobile main source is 1.10.9+37. No APK or Mobile Release tag was created. The latest downloadable APK remains 1.10.7+35; its Android Debug signing certificate has SHA-256 `51d08c3a894a972f03cfd99dac38a468ffba9de58f0062f6a3bba5b07da57406`. The matching private key is unavailable, so a new APK cannot be confirmed as an in-place update. Do not uninstall before syncing and backing up local business data.

Database schema remains v10 and LAN protocol remains `cnkh-sync:v1`. Physical Android device, printer, store-network, and live MyInvois acceptance were not performed.

---
# CNKH POS Mobile 1.10.8+36

## 修复内容

- **B01** 清除客户切换或取消时旧客户的电话号码；保留手动输入的临时号码供当前销售与电子收据使用。
- **B02** 复用兼容的供应商 OCR 单位换算记忆，保持同步中的基础单位库存/成本，冲突时要求复核并尊重人工修改。
- **B04** 只合并尚未映射的匹配客户/供应商；保留 Desktop 删除并重建实体后的远端身份映射和历史引用。
- **B05** 进货、OCR 附件或撤销 Outbox 有未决请求（包括 ACK 丢失）时阻止清理；不阻塞无关目录操作。
- **B06** 持久化点击时的挂单快照，防止重复提交；成功后仅清除未变化的购物车。
- **B07** 在 SQL 分页前稳定处理条码优先级及 ID 排序。
- **B08** 将税务状态导致的销售作废拒绝持久化为 needs_review，保留原操作 ID，待明确复核后重试。
- **B09** 保留购物车屏幕时刷新商品、分类和图片设置，不重算购物车价格快照或覆盖手动折扣。
- **B10 / R03** 使用内置 Noto Sans SC 字体，并将中文及长收据分页排版为 80 mm 小票。

## 验证与发布状态

Mobile CI **145 项测试通过**，分析与培训资源校验通过。Windows 1.10.8+36 Release **149 项测试通过**，Windows 构建、资源校验与 ZIP 上传成功。运行记录见 [Mobile CI](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37114494489)、[Windows Release](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37115653774) 和 [双端 HTTP 回归](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37114494494)。

MyInvois R02 签名变更不在本版范围；官方要求与独立 verifier 尚待复核，未执行真实 Sandbox / Production 提交或作废。

**Android 1.10.8+36 APK 尚未发布。** 已发布的 1.10.7 APK 使用 Android Debug 签名证书，仓库没有对应私钥。换用新签名会导致 Android 无法覆盖安装旧版；卸载可能清除本地业务数据。旧 APK 与校验文件仍在 [1.10.7-mobile Release](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.7-mobile)。

## 当前下载

Windows ZIP： [CNKH_POS_Desktop-windows-x64-v1.10.8-36.zip](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.8/CNKH_POS_Desktop-windows-x64-v1.10.8-36.zip)，SHA-256：f114693cb0633b6ab46a0d5e7ae32885be4bcc0780971c3ce8fe603fc3fc73c6。Windows ZIP 是便携包，不含安装向导。
