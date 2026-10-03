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

