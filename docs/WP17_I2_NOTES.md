# WP17-I2：截图任务草稿校对

状态：纯内存草稿模型与校对组件已完成独立验收。截图导入功能没有完成。文件选择器、真实 OCR、Store 写入和全局导航属于 WP17-I3，本包没有接入。

工作树 `D:\Dev_project\martix-wp17-i2`，分支 `grok/wp17-i2`，基线 `origin/main` 的 `c131dab`。`d82ff7f` cherry-pick 为 `f3a614d`，验收补强在其后的单独提交。`main` 未改，未 push。

## 已验收

- `wp17r2-draft/1` 会拒绝错误 schema、空批次、空或重复图片 id、缺任务列表、非法 level、重复行号、非布尔勾选、非字符串日期、非整数父项、非列表的待确认原因，以及 `hint_only != true`、未知图片或不成对的重复提示。
- 父项按源行号而不是 JSON 数组下标判断。父行必须更小；缺失父行或父行在后只记「父项缺失或顺序不对」，不建立 `parentId`。手动把 `parentId` 指到更晚的任务时不能提交。
- 日期原文保持字符串。只有用户勾选「作为文字保留日期」时，快照才带上去掉首尾空白后的原文；空白原文写成 null。这里不解析截止日期或提醒。
- 拆分使原任务和新片段失去确认。合并使并入的上一项和被改挂父项的子任务失去确认，未涉及的任务保持原确认。排除会取消该项确认；若它是父项，子项父关系清空并失去确认。恢复后的任务必须重新确认。
- `snapshot()` 在 `canSubmit` 为真时返回新的 `ImportSubmission`。`tasks` 是不可修改列表，元素是值字段拷贝。之后改标题、勾选、日期、看板或任务列表，已取出的快照不变。快照不含原图字节、缩略图、引擎名、失败信息、备注、重复原因或被排除的文字。
- 320×720 与 390×844、字号 1.0 和 2.0 下滚动到提交按钮无布局异常。320×720、字号 2.0、底部键盘 inset 320 时视口高度低于 420，列表仍可滚到提交按钮，语义树含隐式滚动。Tab 能到达可用的提交按钮，Enter 只在批次可提交时触发一次回调。
- 中文、英文、日文各自显示校对标题、说明、失败、日期提示、重复提示和提交/取消。标题是语义标题，图片有序号语义标签，移动按钮带对应语言的 tooltip。本组件生成的校对原因已翻译；适配器写入的 `needs_confirmation` 原文原样显示。
- 只有失败图片、全部可导入图片被跳过、空标题、存在未确认任务，或重复提示未确认且两张图都还要导入时，提交按钮不可用，`onSubmit` 不会被调用。取消也不会调用它。
- `lib/import_preview/` 只在内存中工作，不读文件、不写持久化、不引用 Store、OCR 运行时或导航。

## 测试

在该工作树、Flutter 3.32.8 上：

```text
flutter test test/wp17_import_preview_test.dart test/os27_copy_test.dart --reporter compact
All tests passed!（33 项）

flutter analyze --no-pub
No issues found!
```

`os27_copy_test.dart` 用来确认新增的三语文案键仍然对齐。没有跑整库 widget 回归；这次没有改共享页面或导航。

## WP17-I3 需要的接口

调用方持有 `DraftBatch` 和缩略图。预览组件不保存它们。

```dart
DraftBatch.fromJson / DraftBatch.fromJsonString   // schema wp17r2-draft/1
DraftPreview(
  batch: batch,
  boards: [ImportBoardChoice(id, name)],
  thumbnails: {imageId: imageProvider}, // 仅供当次显示
  language: Language.zh,
  onSubmit: (ImportSubmission submission) async { ... },
  onCancel: () {},
)
```

`onSubmit` 拿到的 `ImportSubmission` 只有：

| 字段 | 含义 |
|---|---|
| `boardId` | 调用方传入的目标看板 id |
| `quadrant` | 1–4 |
| `tasks` | 不可修改的 `ImportTask` 列表，父项排在子项前面 |
| `skippedCount` | 跳过图片中的任务数，加上未跳过图片里被排除的任务数 |

`ImportTask` 只有 `id`、`imageId`、`title`、`checked`、`parentId`、`dueText`。`id` / `parentId` 是草稿 id，不是 Store id。`checked` 表示截图里已勾选。`dueText` 只是用户选择保留的原文，I3 可以当文字保存，不能在这里推断截止日期或提醒。

I3 还要自己处理这些快照里故意没有的信息：

- 失败图片只留在调用方的 `batch.images`（`failed == true`，`error` 为字符串）。它们没有任务，也不计入 `skippedCount`。
- 重复提示的确认状态在 `batch.duplicates`。两张图都导入时必须已确认；其中一张已跳过则不再挡住提交。快照里没有重复提示。
- 原图、路径、OCR 行、引擎名和中间结果都不要写入任务库或日志。流程结束后丢掉 `DraftBatch` 和缩略图。
- 用现有批量任务命令创建任务，并按列表顺序把草稿 `parentId` 映射成新任务 id。写入前再做一次 Store 校验。`onSubmit` 抛出异常时，预览只显示「导入失败，请检查后重试」，不会把这次标记为已提交。

`rows`、`noise_lines` 和复选框几何不进入校对模型；适配器应已经把它们折成 `tasks`、`dropped` 和 `needs_confirmation`。
