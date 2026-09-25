# 显式审查探针

## Flutter 全库审查（2026-09-22）

`preopensource_review_probe.dart` 在 `9c622fd` 加 R1–R5/S1 工作区基线上有 7 个预期行为断言失败：损坏启动覆盖、重复子项 ID、自定义模型 round-trip、跨协议发现缓存、未知 provider 设置页、远期提醒日期和退场键盘操作。均为合成数据/mock，不访问真实用户数据或商业 AI。

```powershell
& D:/Dev_SDKs/Flutter_SDK/bin/flutter.bat test --no-pub test/review/preopensource_review_probe.dart --reporter expanded
```

默认 359 项通过不覆盖这七个反例。按 [实施计划](../../../docs/IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md) 对应包修复后，将断言迁入默认可发现回归；不要把预期改成错误行为。完整依据见 [全库审查报告](../../../docs/FLUTTER_REVIEW_2026-09-22.md)。以下旧探针记录属于各自历史基线。

## WP28 基础复审探针

## 二次复审（2026-09-16）

`foundation_second_review_probe.dart` 检查未提交修复遗漏的生命周期和入口。当前 7 个用例均在业务断言失败：在途排程取消、冷启动递归、搜索返回草稿、换 Key 的迟到响应、脏侧栏缩窄、恢复中全取消、子项 48 dp 热区。使用合成数据，不启动真实应用。

```powershell
& D:/Dev_SDKs/Flutter_SDK/bin/flutter.bat test --no-pub test/review/foundation_second_review_probe.dart --reporter expanded
```

详见 [二次复审报告](../../../docs/FOUNDATION_SECOND_REVIEW_2026-09-16.md)。默认 280 项通过不代表上述场景已修复；修复后将对应断言整理为默认可发现的正式回归。

## 2026-09-25 集成后复审

`os_final_review_probe.dart` 使用合成数据、内存 prefs、假凭据及 HTTP；七项断言均针对期望行为，在 `9e30f01` 上 **0/7 通过**。显式运行：

```powershell
& D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat test --no-pub test/review/os_final_review_probe.dart --reporter expanded
```

RF-R01 → RF02 导入并发；RF-R02/03 → RF03 凭据/退出；RF-R04 → RF04 备份；RF-R05 → RF07 IME；RF-R06 → RF05 请求状态；RF-R07 → RF06 模型能力。修复后迁入默认回归，不删除失败断言。见[当前返修计划](../../../docs/IMPLEMENTATION_PLAN_2026-09-25_FINAL_REPAIR.md)。默认 578 项及上轮 preopensource 七项通过不覆盖这些边界。

## 第一轮记录

基线：`3a711c8`，2026-09-16。这里只使用合成数据、mock 持久化及假插件，不访问真实待办或商业 AI。

`wp28_review_probe.dart` 是复审当时的反例文件，有意不以 `_test.dart` 结尾。基线上 21 个业务断言失败。

对应行为已迁入默认可发现回归：

```powershell
& D:/Dev_SDKs/Flutter_SDK/bin/flutter.bat test --no-pub test/foundation_regression_test.dart --reporter expanded
```

完整套件：`flutter test --no-pub`（280 项）。不要用本目录探针冒充当前产品行为；原始失败证据保留在文件内。

报告及 F/R 映射：[FOUNDATION_REVIEW_2026-09-16.md](../../../docs/FOUNDATION_REVIEW_2026-09-16.md)。
