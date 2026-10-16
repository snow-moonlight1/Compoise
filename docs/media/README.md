# README 展示素材

这些素材由 `test/support/capture_readme.dart` 渲染真实的应用组件生成，使用独立的内存存储和虚构任务，不读取手机上的任务或 API 密钥。布局为 390 × 844 的 Android 逻辑视口，使用默认浅色主题和绿色主题色；日程固定为 2026-10-17，时区为 Asia/Shanghai。

每种语言包含：四象限总览 PNG、总览与聚焦之间实际切换的 GIF，以及日程 PNG。中英文 README 分别引用对应语言的素材。PNG 保留 1.5 倍分辨率，GIF 为 390 像素宽、10 fps、循环播放。

## 重新生成

使用项目固定的 Flutter 版本。在 PowerShell 中指定本机可用的中英文字体和 Flutter 的 Material 图标字体，再运行渲染脚本：

```powershell
$env:COMPOISE_README_FONT = 'C:\Windows\Fonts\msyh.ttc'
$env:COMPOISE_README_ICONS = 'C:\path\to\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'
flutter test --no-pub test/support/capture_readme.dart --reporter expanded

foreach ($language in @('zh', 'en')) {
    ffmpeg -y -hide_banner -framerate 10 -i "build/readme-frames/$language-%03d.png" -filter_complex '[0:v]scale=390:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle' -loop 0 "docs/media/matrix-focus-$language.gif"
}
```

字体只在本机渲染时加载，不复制到仓库。也可以指定其他有相应使用许可的 CJK 字体。生成后检查两种语言的文字、图标与动画，再提交 `docs/media/` 中的素材；中间帧保存在已被 Git 忽略的 `build/readme-frames/`。
