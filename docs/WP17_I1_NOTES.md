# WP17-I1：离线 OCR 运行时

状态：运行时与 Flutter 调用边界已实现；图片选择、草稿校对和任务库接线属于 WP17-I2/I3。

## 已交付

- `native/ocr/ocr_runtime.cpp` 使用同一份 ncnn + PP-OCRv5 mobile CPU 代码编译 Windows、Linux 和 Android。
- `lib/ocr/ocr_runtime.dart` 以批次顺序返回每张图片的宽高、文字、矩形、置信度或错误；不解析任务、不写 Store。
- 一次最多处理 20 张图片，图片逐张解码和推理，跨运行时调用串行；取消会为尚未开始的图片返回 `cancelled`。
- 文件大小、PNG 尺寸、解码失败和模型加载失败均返回逐图错误。调用方负责把已确认的模型目录传给 `assetsRoot`。

## 构建边界

模型、字典、ncnn 源码和 `stb_image.h` 不提交仓库。Windows/Linux 通过显式 CMake 变量启用原生库，Android 通过 Gradle 的 `wp17OcrNcnnRoot` 与 `wp17OcrStbDir` 属性启用；未提供这些外部依赖时，普通 Flutter 构建不会尝试下载或打包 OCR。

R2 已在 Windows、WSL2 Linux 和 Android API 23 x86_64 模拟器验证过共享核心；本包的 Flutter 层默认测试不依赖本机 OCR 库。Android arm64 真机尚未运行，模型转换权重的再分发许可也尚未完成核验，因此当前不能把 OCR 标为正式发行能力。

## 后续接线

I3 需要把文件选择器产生的临时路径交给 `recognizeFiles`，将返回结果转换为 `wp17r2-draft/1`，在用户校对并明确确认后调用 Store。原图和 OCR 中间数据不得写入任务库或日志。
