# WP17-R 真机探针协议（给 WP17 执行包的第 0 步）

目的：把研究里唯一缺的东西补上——**小米笔记/待办在公开通道上实际交出什么形态的数据**。6 步全部做完约 20 分钟，不需要 root、不需要无障碍、不需要读任何真实笔记。

红线：测完只把**合成内容**写进仓库；真实笔记正文一律不入库，日志里也不留。

## 1. 记录环境版本

```bash
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release          # Android
adb shell getprop ro.build.version.sdk
adb shell getprop ro.miui.ui.version.name           # MIUI/HyperOS 分支
adb shell getprop ro.build.version.incremental       # ROM 版本号
adb shell dumpsys package com.miui.notes | grep -E "versionName|versionCode|targetSdk"
```

每次换机或系统升级都要重跑，小米的接口形态在这些号里翻脸不认人。

## 2. 造 4 条合成笔记（手动，只用测试内容）

在小米笔记里新建，别用你自己的真实待办：

| 编号 | 内容 | 考察点 |
|---|---|---|
| N1 | 单行一条：`买牛奶` | 最小形态：标题是否被包装、有没有多余前后缀 |
| N2 | 多行清单，两行未完成一行已完成（用笔记里的复选框功能，写成 `买鸡蛋` / `交房租` / `修水龙头`，最后一条勾掉） | 完成态在分享文本里是否保留、用什么标记 |
| N3 | 含日期与时间的一行：`周五 10月5日 15:00 交报告` | 日期是否变文本、是否丢结构 |
| N4 | 长文本（20 行以上，含空行、制表符、emoji） | 换行/空白/长度处理 |

## 3. 抓一次真实分享（关键步）

需要一个最小探针 Activity 才能看到 Intent 原貌。两种做法，选 A：

- **A（推荐）**：产品开工时先加 `SEND text/plain` filter + `MainActivity.onNewIntent` 暂存 + MethodChannel，把收到的 `action`、`type`、`extras` 键列表、`EXTRA_TEXT` 全文、`EXTRA_STREAM` 的 scheme/authority/是否带 grant flag 显示在调试页上。分享 N1–N4，逐条抄录。**注意**：小米的分享面板通常有“发送纯文本 / 长图 / PDF / 邮件”等选项，每个选项都要各测一次并分别记录。
- **B（不进仓库的旁路）**：装一个开源“Intent 查看器”类应用做接收端。优点是零产品改动，缺点是第三方 App 与我们的接收路径不完全同构（`singleTop`、冷启动），只能当参考。

记录表（抄进本目录 `probe-result.md`）：

```
分享选项 | action | type | EXTRA_TEXT 是否为空 | 是否有 EXTRA_STREAM | stream scheme | grant flag | 换行是否保留 | 完成态标记
```

判定：

- `EXTRA_TEXT` 有全文 → 文本分享通道成立，P0 可做。
- 只有 `content://` 且带临时 grant → 需要在接收 Activity 存活期内读完并转存，P0 加一条“即刻读取”约束。
- 只有 `file://` → **放弃该路径**（API 24+ 会抛 `FileUriExposure`/无读取权限），只能靠文本或 SAF。
- 只能得到长图/PDF → 文本通道不成立，WP17 降级为“文件导入 + 应用内粘贴”。

## 4. 合成分享（不碰小米笔记也能验通道）

这一步验证的是**我们的接收实现 + HyperOS 是否放行被拉起**，与小米 App 无关，可独立通过：

```bash
adb shell am start -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "买牛奶" -n com.matrixflow.app/.MainActivity
# 冷启动（先杀进程）与热启动各测一次
adb shell am force-stop com.matrixflow.app
adb shell am start -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "买牛奶" -n com.matrixflow.app/.MainActivity
# 多条：模拟真实清单
adb shell am start -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "买鸡蛋\n交房租" -n com.matrixflow.app/.MainActivity
```

要看清的两件事：热启动是否走到 `onNewIntent`（`launchMode="singleTop"`）、冷启动时 Dart 侧引擎 attach 之前 intent 有没有被丢掉。这两点是本包最容易写出“静默丢数据”的地方。

## 5. 结构化导出能力走查

在小米笔记里逐项找一遍是否存在“导出为文本/保存到本地文件”（设置里、长按多选里、分享面板里），并记录路径：

- 有 → P1 的文件通道值得做，接着用 SAF 挑选导出的文件，验 `takePersistableUriPermission` 后杀进程重启再读一次（确认跨重启可读）。
- 没有 → P1 只做成“通用文本文件导入”（用户自己把文本放成 `.txt`），不要对用户宣称“从系统笔记导出导入”。

## 6. 选中文本入口（P2，最后再看）

在小米笔记里长按选中一段文字，看弹出的选择菜单里有没有第三方“文本处理”项，以及我们的 App 若声明 `PROCESS_TEXT` 是否出现。HyperOS 的选中菜单常被厂商自有工具占据，这一步失败不影响 P0/P1，但决定 P2 是否值得存在。

## 完成标准

- 第 3、4 步有逐条原始记录；第 5 步有结论（有/无导出）。
- 依据第 3 步判定，明确写出：文本分享通道成立与否、完成态与日期能拿到什么、丢了什么。
- 只有 `com.miui.notes` 一条被测；其余厂商保持“未验证”，UI 上不得显示“已支持”。
- 任何未实测项继续标注为未实测，不用单元测试结论代替设备行为。
