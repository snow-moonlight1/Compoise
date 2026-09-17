# 基础二审返修记录（2026-09-16）

范围：二次复审 SR01–SR07，对应 F06/F09/F11/F12/F16/F19。基于 `main / 3a711c8` 的现有未提交修复继续修改，保留此前数据校验、字段合并、完成历史和发行配置改动；未提交 Git、未改 Android 包名、未启动真实应用。

## 修复与证据

| 二审项 | 本轮实现 | 自动化证据 |
|---|---|---|
| SR01 / F06 | 单项取消和排程进入同一有序队列，立即更新修订号；在途排程失效后补取消；全取消使旧恢复批次失效。恢复持有数据/修订快照，清板同步作废全部关联项，加法导入不打断其他有效恢复。 | 原 S01/S06；取消在调用前、原生请求中和完成后；生产 Store 清板与覆盖导入；并行加法恢复；保留 R14 权限检查期间取消断言。 |
| SR02 / F09 | main 初始化时不注册自引用回调，载荷缓存在服务内；MatrixHome 首帧后挂接导航并消费一次；子项 ID 传入详情高亮。通知切板先保护现有草稿。 | S02 使用修复后的实际启动方式；父任务/子任务首帧定位及重复挂接不重复投递。 |
| SR03 / F12 | 搜索与已完成页返回统一走 maybePop，复用详情 PopScope 的草稿确认。未确认时保留编辑；确认后关闭当前详情，后续返回退出页面。 | 搜索/已完成页 × 页面按钮/系统返回四条真实入口。 |
| SR04 / F16 | 模型请求使用独立配置快照，完整配置身份与请求代次同时校验；Key/URL/协议/手选模型变更失效旧请求并结束加载。 | S04 Key 变更；URL/协议/手选模型分别验证旧结果不写回、请求快照不随配置变更、加载结束。 |
| SR05 / F12 | 宽屏详情缩窄后成为全宽容器，GlobalKey 保留同一编辑状态；放宽后回到侧栏。 | S05 矩阵 1400→360；搜索/已完成 1400→360→1400，无布局异常，草稿保留并可保存。 |
| SR06 / F19 | 子项实际手势区域 48×48 dp；日期移到标题下方，避免窄象限内挤出。 | S07 尺寸断言；距左上角 2 dp 点击仅完成子项；既有子项截止日期与窄屏回归。 |
| SR07 / F11 | 生产服务暴露按提醒 ID 的失败状态；矩阵/搜索/已完成/详情显示任务名、三语失败说明及重试。任务和时间照常保存；重试从当前 Store 取值，成功才清错，取消清除对应错误。Windows 原生失败时保留进程内 Timer，但明确提示系统排程失败。 | 从矩阵详情选择提醒并保存，注入真实生产服务排程失败，检查可见提示和保存数据；点击重试成功后提示消失；失败不立即弹未来通知。 |

同时更正隐私政策中“安全明文 / encrypted or sandboxed”和一概官方 HTTPS 的表述，明确 SharedPreferences 未额外加密、自定义地址与含密钥明文备份的实际行为。

## 本轮验证

- `flutter test --no-pub --reporter expanded`：**305/305 通过**，其中二审默认回归新增 25 项（7 个原探针 + 18 个扩展场景）。
- `flutter analyze --no-pub`：**0 issues**。
- 默认入口：`matrixflow-native/test/foundation_second_regression_test.dart`，复用原二审探针。原 S02 改为实际新 main 的无回调初始化；S01/R14 将取消 Future 与在途请求一起等待，以适配有序生命周期，业务断言未删除。原探针另修测试结束前平台覆盖变量的复位。
- Android：`flutter build apk --release --no-pub` 本轮成功（退出码 0，221.2 秒，APK 24.7 MB）。Kotlin 增量缓存因 C/D 跨盘报错后回退编译成功；日志保留该环境问题。不将本地构建视为正式签名或商店验收。
- Windows：`flutter build windows --release --no-pub` 本轮成功（退出码 0，50.7 秒）。使用整个 `build/windows/x64/runner/Release/` 目录运行，未实际启动。
- 构建产物：`matrixflow-native/build/app/outputs/flutter-apk/app-release.apk`、`matrixflow-native/build/windows/x64/runner/Release/matrixflow_native.exe`。未重新生成发行 ZIP 或 GitHub Release。
- 本机日志（忽略文件）：`second-fix-full-tests.log`、`second-fix-analyze.log`、`second-fix-android-release.log`、`second-fix-windows-release.log`，均位于 `matrixflow-native/`。

## 仍未验收

没有运行真实通知/系统托盘/全局热键/Windows IME/Android 权限及进程冷启动，也未使用真实数据或密钥。上述结果是自动化与构建证据，不等于设备验收。F21 包名迁移仍待选择和安装验证，F22 正式签名与远端 CI 未执行。二审提到的其他桌面初始化/退出边界、远期日期选择上界、命令面板草稿入口不在本轮 SR01–SR07 关闭声明之内；继续暂停 WP10/WP29/UI 实验。
