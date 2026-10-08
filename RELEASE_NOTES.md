# CNKH POS Mobile 1.10.10+38

发布准备日期：2026-10-08。**安装包待 CI 构建及核验，尚未确认本版发布成功。** 数据库 schema 保持 v10，LAN 协议保持 `cnkh-sync:v1`。

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

- Mobile 完整测试 **187 项通过**；随后调整收款测试的异步等待方式，该用例定点复测通过。
- Desktop 完整测试 **187 项通过，1 项因测试固定等待时间不足失败**；改为等待实际付款完成条件后，该用例及电子发票测试共 **25 项定点复测通过**。这不是一次重新执行的全量通过记录。
- 两端真实 HTTP / WebSocket 配套回归 **29 项通过**。
- 两端 `flutter analyze` 未发现 error；保留原有 warning / info。
- 独立 ZXing 解码验证通过：两端 12 位条码均读回原内容；两端 PDF 及 384 / 576 dots ESC/POS 栅格中的 6 个二维码产物均读回正确测试内容。
- `git diff --check`、修复源码包完整性和补丁应用检查通过。

以上为发布前本地验证。1.10.10+38 的 GitHub Actions 构建结果、产物大小、SHA-256 和 APK 签名核验待完成后补充。实体 Windows / Android 设备、打印机、门店网络和 MyInvois Sandbox / Production 线上验收未执行。

## 安装与发布状态

本次计划提供 **Android APK**，与 Desktop 1.10.10+38 配套。构建、签名核验及上传完成前，本页不提供未验证的下载链接或校验值。

Windows 更新前备份业务数据并关闭程序；使用便携 ZIP 时保持 EXE、DLL 和 `data` 目录完整。

Android 旧版 1.10.7+35 APK 使用 Debug 证书，其 SHA-256 为 `51d08c3a894a972f03cfd99dac38a468ffba9de58f0062f6a3bba5b07da57406`。**本版 APK 签名及与旧版的覆盖安装兼容性尚待核验，不承诺可直接覆盖。** 更新前先同步并备份；若 Android 提示签名不匹配，保留旧应用和本地数据，不要卸载仍含未同步业务的旧版本。

下载区、实际 CI 链接及校验值统一记录于 [README](README.md#下载与更新)。

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
