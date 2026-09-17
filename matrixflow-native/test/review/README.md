# WP28 基础复审探针

## 二次复审（2026-09-16）

`foundation_second_review_probe.dart` 检查未提交修复遗漏的生命周期和入口。当前 7 个用例均在业务断言失败：在途排程取消、冷启动递归、搜索返回草稿、换 Key 的迟到响应、脏侧栏缩窄、恢复中全取消、子项 48 dp 热区。使用合成数据，不启动真实应用。

```powershell
& D:/Dev_SDKs/Flutter_SDK/bin/flutter.bat test --no-pub test/review/foundation_second_review_probe.dart --reporter expanded
```

详见 [二次复审报告](../../../docs/FOUNDATION_SECOND_REVIEW_2026-09-16.md)。默认 280 项通过不代表上述场景已修复；修复后将对应断言整理为默认可发现的正式回归。

## 第一轮记录

基线：`3a711c8`，2026-09-16。这里只使用合成数据、mock 持久化及假插件，不访问真实待办或商业 AI。

`wp28_review_probe.dart` 是复审当时的反例文件，有意不以 `_test.dart` 结尾。基线上 21 个业务断言失败。

对应行为已迁入默认可发现回归：

```powershell
& D:/Dev_SDKs/Flutter_SDK/bin/flutter.bat test --no-pub test/foundation_regression_test.dart --reporter expanded
```

完整套件：`flutter test --no-pub`（280 项）。不要用本目录探针冒充当前产品行为；原始失败证据保留在文件内。

报告及 F/R 映射：[FOUNDATION_REVIEW_2026-09-16.md](../../../docs/FOUNDATION_REVIEW_2026-09-16.md)。
