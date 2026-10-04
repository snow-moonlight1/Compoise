/// Labels for the WP19-R prototype.
///
/// Deliberately Chinese-only and local to the experiment: the product keeps
/// en/zh/ja in lib/l10n.dart, and a throwaway lens should not push keys into a
/// shared file. Promoting dev mode would need three-language copy — that cost
/// is recorded in docs/WP19_R_NOTES.md instead of being paid here.
library;

class Wp19Labels {
  static const appTitle = 'WP19-R 开发视角原型';
  static const appSubtitle = '内存原型 · 不写产品库';

  static const modeNormal = '普通模式（现状）';
  static const modeDev = '开发视角';

  static const normalNote =
      '普通模式按象限和标签组织：勾选只会让任务换位置，被它挡住的任务不会有任何提示。';
  static const devNote =
      '开发视角只看多出的三件事：阶段、谁挡住谁、完成标准。字段属于本会话，不改任务本身。';

  static const phaseDesign = '设计';
  static const phaseBuild = '实现';
  static const phaseVerify = '验证';
  static const phaseShip = '发布';
  static const phaseNone = '未归阶段';

  static const ready = '可开始';
  static const done = '已完成';
  static const cycle = '循环等待';
  static const waitingPrefix = '等待';
  static const unresolvedBlocker = '阻塞项找不到或不属本项目';

  static const acceptance = '完成标准';
  static const noAcceptance = '未填完成标准';
  static const unlocks = '完成后解锁';
  static const allProjects = '全部项目';
  static const subtasksOf = '步骤';
  static const deadline = '截止';
  static const planned = '计划日';

  static const complete = '完成';
  static const restore = '撤销完成';
  static const undoLast = '撤销上一步';
  static const nothingToUndo = '没有可撤销的意图';
  static const selectedCount = '已选';
  static const batchComplete = '批量完成';
  static const clearSelection = '取消选择';
  static const batchNeedsSelection = '先选择任务';
  static const exportState = '导出实验状态';
  static const exportTitle = '实验状态（JSON，可直接审查）';
  static const exportNote = '这段文本只是实验视图的快照，不是备份格式，产品导入不认它。';
  static const close = '关闭';

  static const moreActions = '更多';
  static const resetFields = '清除实验字段';
  static const removeTask = '从原型移除';
  static const removeHint = '只影响本会话的合成任务，产品库没有这份数据。';
  static const leaveExperiment = '退出实验';
  static const leaveTitle = '退出后本会话全部丢弃';
  static const leaveBody = '状态只在内存。退出会丢掉未撤销的意图，产品任务、日程、设置和备份不受影响。';
  static const leaveConfirm = '退出并丢弃';
  static const leaveCancel = '继续查看';
  static const leftReceipt = '已退出原型';
  static const leftDetail = '本会话意图已丢弃，未向产品库写入任何内容。';
  static const restartSession = '重新载入合成会话';

  static const sessionLine = '本会话';
  static const intentsOf = '意图';
  static const touchedOf = '触及任务';
  static const libraryWrites = '写入产品库';
  static const themeToggle = '明暗主题';
  static const fontToggle = '200% 字号';
  static const emptyList = '当前筛选没有任务';

  static const hiddenBlockedHint = '普通模式看不到的依赖';
  static const countSuffix = '项';
}
