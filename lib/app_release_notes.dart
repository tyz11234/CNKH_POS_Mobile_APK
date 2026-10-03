/// Keep this version and release record in sync with pubspec.yaml and
/// CHANGELOG.md whenever a Mobile build is updated.
const String appVersion = '1.10.8';
const String appBuildNumber = '36';
const String appVersionLabel = '$appVersion+$appBuildNumber';

const List<String> appReleaseNotes = <String>[
  'B01：切换客户或取消客户后不再误用上一位客户的自动带入电话；手动填写的临时号码会保留，并用于单据与电子收据分享。',
  'B02：供应商 OCR 记忆会在单位兼容且未被人工覆盖时复用换算倍率，库存数量、基础单位成本和同步载荷保持一致。',
  'B04：目录同步仅合并未关联的客户/供应商；已建立的身份映射与历史单据引用保持稳定。',
  'B05：存在未确认采购、采购附件或采购撤销请求时，清除交易会停止；无关商品和客户同步请求保留。',
  'B06：挂单使用点击时的购物车快照，避免异步保存期间的新修改被清除，并阻止重复提交。',
  'B07：商品搜索在 SQL 中全局优先精确条码，并以稳定 ID 排序后分页。',
  'B08：税务状态不明的销售作废会持久化为待核对请求；安全的后续同步继续进行，人工核对后可用原操作 ID 重试。',
  'B09：购物车刷新商品、分类和图片设置，同时保留购物车价格快照及人工折扣。',
  'B10/R03：电子收据 PDF 使用已打包的中文字库，并对长收据分页。',
  'MyInvois 签名规范仍需最新官方材料和独立验证器确认；本次未向生产环境提交或取消发票。',
];
