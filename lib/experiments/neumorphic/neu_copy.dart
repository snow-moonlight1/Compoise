import 'package:flutter/widgets.dart';

/// Synthetic gallery copy. These strings are not product catalog text and are
/// not stored as tasks.
class NeuCopy {
  const NeuCopy({
    required this.galleryTitle,
    required this.material,
    required this.neumorphic,
    required this.dark,
    required this.light,
    required this.highContrast,
    required this.reduceMotion,
    required this.sceneSingle,
    required this.sceneSteps,
    required this.sceneNote,
    required this.captionSingle,
    required this.captionSteps,
    required this.captionNote,
    required this.parentTitle,
    required this.stepOne,
    required this.stepTwo,
    required this.noteLabel,
    required this.noteBody,
    required this.propertySummary,
    required this.save,
    required this.schedule,
    required this.delete,
    required this.deleteError,
    required this.pressedSample,
    required this.focusedSample,
    required this.disabledSample,
    required this.errorSample,
    required this.idleStatus,
    required this.statusSaved,
    required this.statusScheduled,
    required this.statusBlocked,
    required this.compare,
    required this.stateMatrixTitle,
    required this.recommendation,
  });

  final String galleryTitle;
  final String material;
  final String neumorphic;
  final String dark;
  final String light;
  final String highContrast;
  final String reduceMotion;
  final String sceneSingle;
  final String sceneSteps;
  final String sceneNote;
  final String captionSingle;
  final String captionSteps;
  final String captionNote;
  final String parentTitle;
  final String stepOne;
  final String stepTwo;
  final String noteLabel;
  final String noteBody;
  final String propertySummary;
  final String save;
  final String schedule;
  final String delete;
  final String deleteError;
  final String pressedSample;
  final String focusedSample;
  final String disabledSample;
  final String errorSample;
  final String idleStatus;
  final String statusSaved;
  final String statusScheduled;
  final String statusBlocked;
  final String compare;
  final String stateMatrixTitle;
  final String recommendation;

  static const zh = NeuCopy(
    galleryTitle: '轻拟态外观实验',
    material: '普通 Material',
    neumorphic: '轻拟态',
    dark: '深色',
    light: '浅色',
    highContrast: '高对比',
    reduceMotion: '减少动画',
    sceneSingle: '单项',
    sceneSteps: '子步骤',
    sceneNote: '备注',
    captionSingle: '普通新建一项：一行可勾选的任务，不必先填父标题或属性。',
    captionSteps: '换行后的子步骤：第一行仍是步骤，父标题单独放在上面，不会把第一行吞成标题。',
    captionNote: '纯文本备注与属性摘要：备注里的换行仍是文字，属性收在摘要里，需要时再打开。',
    parentTitle: '轻拟态实验的外观样本',
    stepOne: '把提案写成可以勾选的一步',
    stepTwo: '核对明暗、按下、禁用、焦点和错误',
    noteLabel: '备注',
    noteBody: '这是纯文本备注。换行仍然是文字里的换行，不会变成新的子步骤，也不会被收成标题。属性留在下面的摘要里，需要时再打开。',
    propertySummary: '属性摘要：今天 · 重要且紧急',
    save: '保存这项合成任务',
    schedule: '时间',
    delete: '删除这项尚未保存的任务',
    deleteError: '还不能删除：实验样本没有任务数据，删除需要明确确认。',
    pressedSample: '按下',
    focusedSample: '焦点',
    disabledSample: '禁用',
    errorSample: '错误',
    idleStatus: '尚未写入任务。这只是外观样本。',
    statusSaved: '样本里按下了保存，没有写入任务库。',
    statusScheduled: '样本里按下了时间，没有打开生产面板。',
    statusBlocked: '样本里的删除被拦住了，没有删除任何任务。',
    compare: '比较外观',
    stateMatrixTitle: '状态样本：填充、边框和图标，不只靠阴影',
    recommendation:
        '建议：不要把这套轻拟态换成应用的默认主题。阴影只作装饰；按钮和状态靠填充、边框、图标和文字区分。高对比和减少动画时去掉阴影，留下清晰边框。默认构建不包含本实验。',
  );

  static const en = NeuCopy(
    galleryTitle: 'Neumorphic appearance experiment',
    material: 'Material',
    neumorphic: 'Neumorphic',
    dark: 'Dark',
    light: 'Light',
    highContrast: 'High contrast',
    reduceMotion: 'Reduce motion',
    sceneSingle: 'Single item',
    sceneSteps: 'Sub-steps',
    sceneNote: 'Note',
    captionSingle:
        'A normal new item: one checkable task. A parent title and properties are not required first.',
    captionSteps:
        'Sub-steps after a newline: the first line stays a step. The parent title sits above it and does not swallow that line.',
    captionNote:
        'Plain-text note and property summary: a line break inside the note stays text. Properties stay in the summary until opened.',
    parentTitle: 'Appearance sample for the neumorphic experiment',
    stepOne: 'Write the proposal as one checkable step',
    stepTwo: 'Check light, dark, pressed, disabled, focus, and error',
    noteLabel: 'Note',
    noteBody:
        'This is a plain-text note. A line break stays a line break inside the note. It does not become a new sub-step and it is not folded into the title. Properties stay in the summary below and open only when needed.',
    propertySummary: 'Property summary: today · important and urgent',
    save: 'Save this synthetic task',
    schedule: 'Schedule',
    delete: 'Delete this unsaved task',
    deleteError:
        'Cannot delete yet: the experiment has no task data, and delete needs an explicit confirmation.',
    pressedSample: 'Pressed',
    focusedSample: 'Focused',
    disabledSample: 'Disabled',
    errorSample: 'Error',
    idleStatus: 'Nothing was written. This is only an appearance sample.',
    statusSaved: 'Save was pressed in the sample. No task was stored.',
    statusScheduled:
        'Schedule was pressed in the sample. The production panel did not open.',
    statusBlocked: 'Delete was blocked in the sample. No task was deleted.',
    compare: 'Compare appearance',
    stateMatrixTitle: 'State samples: fill, border, and icon, not shadow alone',
    recommendation:
        'Recommendation: do not replace the app theme with this neumorphic skin. Shadows are decoration. Buttons and states are told apart by fill, border, icon, and text. High contrast and reduced motion drop the shadow and keep a clear border. Default builds do not include this experiment.',
  );

  static const ja = NeuCopy(
    galleryTitle: 'ニューモーフィック外観の実験',
    material: '通常の Material',
    neumorphic: 'ニューモーフィック',
    dark: 'ダーク',
    light: 'ライト',
    highContrast: '高コントラスト',
    reduceMotion: 'アニメーションを減らす',
    sceneSingle: '単一項目',
    sceneSteps: '子手順',
    sceneNote: 'メモ',
    captionSingle: '普通の新規項目：チェックできる一行です。親タイトルや属性を先に埋める必要はありません。',
    captionSteps: '改行後の子手順：最初の行は手順のままです。親タイトルはその上にあり、最初の行をタイトルへ取り込みません。',
    captionNote: 'プレーンテキストのメモと属性の要約：メモ内の改行は文字のままです。属性は要約にしまい、必要なときだけ開きます。',
    parentTitle: 'ニューモーフィック実験の外観サンプル',
    stepOne: '提案をチェックできる一つの手順として書く',
    stepTwo: '明暗、押下、無効、フォーカス、エラーを確認する',
    noteLabel: 'メモ',
    noteBody:
        'これはプレーンテキストのメモです。改行はメモの中の改行のままで、新しい子手順にはならず、タイトルにも畳み込まれません。属性は下の要約にあり、必要なときだけ開きます。',
    propertySummary: '属性の要約：今日 · 重要かつ緊急',
    save: 'この合成タスクを保存',
    schedule: '日時',
    delete: 'この未保存のタスクを削除',
    deleteError: 'まだ削除できません。実験サンプルにタスクデータはなく、削除には明確な確認が必要です。',
    pressedSample: '押下',
    focusedSample: 'フォーカス',
    disabledSample: '無効',
    errorSample: 'エラー',
    idleStatus: 'まだ書き込まれていません。これは外観サンプルです。',
    statusSaved: 'サンプルで保存を押しました。タスク庫には書いていません。',
    statusScheduled: 'サンプルで日時を押しました。本番のパネルは開いていません。',
    statusBlocked: 'サンプルの削除は止まりました。タスクは削除していません。',
    compare: '外観を比較',
    stateMatrixTitle: '状態サンプル：塗り、枠線、アイコン。影だけに頼らない',
    recommendation:
        '提案：このニューモーフィックをアプリの既定テーマに置き換えないでください。影は装飾です。ボタンと状態は塗り、枠線、アイコン、文字で区別します。高コントラストとアニメーション削減では影を外し、明確な枠線を残します。既定のビルドにはこの実験を含めません。',
  );

  static NeuCopy of(Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return en;
      case 'ja':
        return ja;
      default:
        return zh;
    }
  }
}
