# UIEXP-1 外观实验

2026-10-06：设置 → 外观 → 漫画描边，是一个开关，默认关闭。不再打开单独对比页，也不放在「实验性功能」里。打开后矩阵十字为 2 像素，关掉是 1 像素；不给四个象限加框，标题下和底栏上不加粗线。用户看过手机上的样子，接受先停，不再打磨。真正的拟态以后再做。单独样本仍是 `flutter run -t tool/neumorphic_demo.dart`。

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
