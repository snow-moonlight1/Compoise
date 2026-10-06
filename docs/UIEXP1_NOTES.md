# UIEXP-1 外观实验

2026-10-06（二）：设置 → 外观 → 漫画描边，是一个开关，默认关闭。不再打开单独对比页，也不放在「实验性功能」里。打开后矩阵十字为 2 像素，关掉是 1 像素；不给四个象限加框，标题下和底栏上不加粗线。用户看过手机上的样子，接受先停，不再打磨。单独样本仍是 `flutter run -t tool/neumorphic_demo.dart`。

2026-10-06（三）：拟态主题在设置 → 外观 → 拟态，和漫画描边同级、默认关闭，两者互斥（开一个关另一个；备份里两个都开时漫画优先）。拟态是第三种样子：控件和底板同色，左上高光、右下暗影，所以凸出板面；按下或选中则这对阴影转到内侧，凹进去。不是换一层蓝灰底，也不是 Material 的一道投影。任务卡片、底栏按钮和输入框按这个画。卡片四周留出阴影淡出的空隙，避免被象限裁切切成齐边。底栏按钮按下时不拆掉重画，搜索、添加任务、更多才能点开。强调色仍用于图标、光标和进度。不给四个象限加框。漫画描边留在外观。「显示总体完成率」同日从外观挪到任务行为，键和文案未动。上面的单独样本仍是对照，不是这套皮肤。用户看过第一包，总体可以，并指出阴影被切断、底栏点不开；这两处已改。跟进包用户还没看。下一轮等用户的界面反馈，再改界面。

下面是当初的对比页记录，留着不删。

工作树 `D:/Dev_project/martix-uiexp-1`，分支 `codex/uiexp-1`，基线 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`。未改生产主题、主页面、输入面板、Store、依赖和 `pubspec.lock`。

定向测试使用 `PUB_CACHE=D:\Dev_project\martix-uiexp-1-private\pub-cache`。六个 `test/uiexp1_*.dart`（不含 harness）`flutter test` 退出码 0，33 项通过。`flutter analyze --no-pub` 退出码 0。

性能采样是 widget test 软件光栅，不是设备 GPU。原文在 `D:\Dev_project\martix-uiexp-1-private\perf-sample.txt`：

```
widget-test software frames, debugDisableShadows=false
viewport=400x320 items=40 fling plus 20 frames
material_micros=552047 material_shadow_layers=0 material_pixels=931.965552205944
neumorphic_micros=344057 neumorphic_shadow_layers=14 neumorphic_pixels=1600.0
high_contrast_micros=175671 high_contrast_shadow_layers=0 high_contrast_pixels=1600.0
```

三组都滚过了视口。轻拟态绘出 14 层阴影，高对比为 0 层。同一次采样里 Material 填充按钮没有阴影层，耗时更长。秒表包住 fling 和随后 20 帧，不能单独当成阴影的 GPU 成本，也不能当成滚动回归。

对比图在 `D:\Dev_project\martix-uiexp-1-private\shots\`：`compare-light-800-zh`、`narrow-320-zh`、`narrow-390-en-scale2`、`narrow-320-ja-dark`、`narrow-390-zh-contrast`、`narrow-320-zh-scale3-motion`。合成任务，不入库。

未验：Android 真机、Linux SDK、前台 `flutter run` / `flutter build`、设备 GPU。产品行为文件未改；边界测试确认默认入口未引用实验。

## 集成复验（2026-10-05）

`3c9c2b2754b4e1310719df8b361ebf9239be4687` 已摘到当前 `main`，新提交 `b7aebf0926b2f989640482cb67d8bb99728db33a`。定向 167 项通过，其中本包 33 项；`flutter analyze --no-pub` 与默认全量 `flutter test --no-pub`（`+1623 ~13`）退出码都是 0。默认主题和 `lib/main.dart` 未改。Android 真机、设备 GPU 和前台窗口仍未验。建议继续不要把这套皮肤换成默认主题。
