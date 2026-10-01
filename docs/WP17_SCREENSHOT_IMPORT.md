# WP17：批量截图识别导入

状态：I1/I2/I3a 组件与 [I3b 应用入口、Android SAF 和原子写库](WP17_I3B_NOTES.md)已集成。默认构建未带原生 OCR 组件与模型，入口会说明缺失，**尚不属于正式支持功能**。Windows 外部模型合成图识别、Android API 23 x86_64 的 SAF 流程已有证据；模型分发、arm64 真机、Linux OCR bundle 与真实截图质量仍待验收。目标是用户一次选取多张待办截图，校对后一次导入。不读取其他应用数据库，也不自动抓屏。旧[系统笔记接口研究](evidence/wp17r/README.md)仅作历史证据。

## 用户流程与数据边界

1. 从首页“更多”进入，先检查本地 OCR 组件，再从系统选择器选择最多 10 张静态 PNG。按选择结果顺序处理，界面显示批次进度及逐图错误；校对页可跳过图片/任务。当前未提供选择前重排或其他图片格式转换。字节、尺寸和像素边界见 I3b 记录。
2. 识别引擎保留文本及其位置，按图片顺序生成可编辑的任务草稿。优先评估本地 OCR，选型以实测质量和设备负担为准。跨截图的重复内容只提示，不自动删；标题、父子层级、复选框状态和日期凡有歧义均标记待确认，不凭猜测写入期限或提醒。
3. 在同一预览页检查整批草稿：修改文字、合并/拆分任务、调整父子关系、剔除杂项，选择目标看板与象限；确认后一次提交。失败图片保留错误，其他图片仍可校对。取消或未确认时不写库；保存失败保留校对与稳定任务 ID 供重试。预览显示跳过数，成功提示显示导入条目数（包含子项）。
4. 原图不写入任务库或日志。Android 为 path-based OCR 逐张建立有界、流程私有临时副本，识别后删除；取消/异常/退出和下次启动清理本模块残留，不清除系统或其他插件缓存。桌面读取所选文件，不删除用户原图。草稿与识别中间结果只在流程内存中保留。当前没有远程图片上传；未来若引入视觉端点，应另定用户确认、端点和费用提示。

OCR 只负责读取图中文字和位置，不能把截图中的勾选、缩进和日期自动等同于可靠的任务结构。预览校对是本功能的必要步骤。导入草稿走现有任务模型和批量保存入口，备份导入继续使用自己的格式与预检门禁。

## 跨平台预筛（2026-09-29）

筛选条件是同一套 OCR 模型、推理及图像前后处理代码可用于 Android（本项目 `minSdk=23`）、Windows 和 Linux；各平台分别编译原生库、提供很薄的 Flutter 接口是正常的发行打包工作，不等于维护三套识别算法。**引擎支持某个平台，不代表整条 OCR 流程已在本项目通过运行验收。**

| 候选 | 三端共用依据 | 本轮位置 |
|---|---|---|
| **ncnn + PP-OCRv5 mobile 检测/识别模型（CPU）** | [ncnn 官方构建表](https://github.com/Tencent/ncnn)覆盖三端，[Android arm64 构建示例](https://github.com/Tencent/ncnn/wiki/how-to-build)目标为 API 21；[官方 PP-OCRv5 C++ 示例](https://github.com/Tencent/ncnn/blob/master/examples/ppocrv5.cpp)给出模型转换及检测/识别链路。同一 ncnn 模型文件[可跨平台使用](https://github.com/Tencent/ncnn/wiki/faq.en)。[PP-OCRv5 mobile](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/algorithm/PP-OCRv5/PP-OCRv5.en.md)覆盖中、英、日文。 | **首选实测**。优先 CPU，避免 Vulkan 变成设备门槛；统一 C++ 前后处理及模型，Android API 23 仍需实际加载和识别冒烟。示例的检测后处理有简化，不能把示例效果当作正式质量结论。 |
| **Tesseract 5 + tessdata_fast** | [官方构建说明](https://tesseract-ocr.github.io/tessdoc/Compiling.html)覆盖 Windows、Linux 和 Android NDK；同一 C++ 引擎可用，[快速语言包](https://github.com/tesseract-ocr/tessdata_fast)有 `chi_sim`、`eng`、`jpn`。 | **对照实测**。Android API 23 的原生依赖及 Leptonica 打包需要冒烟；比较小字、复选框旁文字和混合语言的误识别率与安装包体积。 |

暂不进入本轮质量测试：

- **ONNX Runtime + PP-OCRv6 small**：ONNX Runtime [支持三端](https://onnxruntime.ai/docs/install/)，PP-OCRv6 small [含中、英、日文](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/algorithm/PP-OCRv6/PP-OCRv6.en.md)，但检查 [Android 1.24.3 官方 AAR](https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.24.3/onnxruntime-android-1.24.3.aar) 的 `AndroidManifest.xml` 得到 `minSdkVersion=24`。官方说明允许[按指定 Android API 自建](https://onnxruntime.ai/docs/build/android.html)，但这会增加构建维护；在证明 API 23 可用、并说明额外成本前，不把它算作已通过的方案。PP-OCRv6 **tiny 不支持日文**，也不宜代替 small 做本项目的多语言候选。
- [ML Kit Text Recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)只有 Android 实现。[RapidOCR](https://github.com/RapidAI/RapidOCR)有多语言封装和 Android 工程，但主要复用 Paddle 模型与 ncnn/ONNX Runtime 等引擎，不单列为另一种识别模型；若借用其 C++ 处理代码，归入相应引擎方案并核对 Android API 23。可配置云端视觉模型依赖联网、端点协议及图片上传，不与本轮离线 OCR 混为同一候选。

上述是选型前的预筛记录。[R2 实测](WP17_OCR_EVALUATION.md)在合成样例上暂选 ncnn + PP-OCRv5 mobile；Android arm64 真机、模型再分发许可和实际 APK 体积仍未验收，不能宣称产品中已可用。

## 实施顺序

| 子包 | 交付与门禁 |
|---|---|
| WP17-R2 选型 | 已完成；[实测报告和证据](WP17_OCR_EVALUATION.md)记录了平台覆盖、质量、资源与许可门禁。 |
| WP17-I1 / I2 | 已集成 [ncnn 运行时](WP17_I1_NOTES.md)与 [可编辑草稿预览](WP17_I2_NOTES.md)，由 I3b 页面调用。 |
| WP17-I3a | 已集成[多图 OCR 转草稿](WP17_I3A_NOTES.md)；Windows 合成样例经外部模型识别通过。Android 原 file_picker 入口保持禁用，产品改走 I3b SAF。 |
| WP17-I3b | 已集成应用导航、校对确认后事务写库与有界 SAF 临时读取；[验收记录](WP17_I3B_NOTES.md)区分真实 Windows OCR 和注入 OCR 的 Android SAF 测试。 |
| WP17-I4 | 下一步处理模型分发与三端构建，不能用无 OCR 依赖的默认 CI 代替原生识别验收。后续设备与质量门禁见[路线图](ROADMAP.md#后续接线与门禁)。 |

R2 的比较方法和未测项目由[实测报告](WP17_OCR_EVALUATION.md)保存。[PaddleOCR 官方 Android 示例](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/inference_deployment/cross_platform/android_deployment.md)本身要求 API 26，不能直接移植进 `minSdk=23` 的应用。

## 验收

- 多张截图能在一轮操作中识别、校对并导入；其中一张失败不使其余草稿无声丢失，重复截图不会自动造成不可见的重复任务。
- 对识别错字、跨图重复、父子层级、勾选状态和日期误判有可复现的合成用例；用户能在提交前修正或跳过。
- 优先让无网络、无 AI 密钥的用户也能识别；若本地方案达不到质量门槛，选型报告必须说明替代方案的上传、费用和平台限制，不能虚报离线可用。低端设备不会因整批图片同时解码而崩溃。
- Android 和 Windows 在各自验收前不宣称支持；Linux 预览版同样按实测结果标注。用户明确确认前，任务库不变。
