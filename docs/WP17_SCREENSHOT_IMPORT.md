# WP17：批量截图识别导入

状态：待实施。用户一次选取多张待办截图，识别出任务草稿，检查修改后一次导入。图片来源可以是小米笔记或其他代办应用；不读取其他应用数据库，也不自动抓屏。旧[系统笔记接口研究](evidence/wp17r/README.md)仅作历史证据。

## 用户流程与数据边界

1. 从系统文件/图片选择器选择多张图片；可调整顺序、删除误选图片，界面显示每张的识别进度和错误。限制单张大小、像素和批次数量，避免解码或推理耗尽内存。
2. 识别引擎保留文本及其位置，按图片顺序生成可编辑的任务草稿。优先评估本地 OCR，选型以实测质量和设备负担为准。跨截图的重复内容只提示，不自动删；标题、父子层级、复选框状态和日期凡有歧义均标记待确认，不凭猜测写入期限或提醒。
3. 在同一预览页检查整批草稿：修改文字、合并/拆分任务、调整父子关系、剔除杂项，选择目标看板与象限；确认后一次提交。取消、识别失败或未确认时不写库。导入完成后报告成功数和跳过数。
4. 原图不写入任务库或日志；识别中间结果在流程结束后清理。若选用用户自配的视觉模型，应单独显示将哪些图片发送到哪个端点及可能产生的费用，取得明确确认；本地模式不得悄悄回退为上传。

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

这份预筛只决定要测什么，**不宣称 ncnn 或 Tesseract 已在本项目可用，也不预测哪一个识别最好**。若两者都未达质量门槛，再单独评估 ONNX Runtime 的 API 23 自建版或经用户确认的云端方案。

## 实施顺序

| 子包 | 交付与门禁 |
|---|---|
| WP17-R2 选型 | **只测上表两套离线配置**：同一批合成待办截图对比中文、英文、日文、明暗主题、小字、长图、缩放、重复区域和已完成复选框。先做 Android API 23、Windows、Linux 的最小运行冒烟，再记录文字错误率、任务行召回与误提取、阅读顺序、单张与整批耗时、峰值内存、安装包增量和许可证。输出可复现的样例、脚本、结果表及“识别结果 → 草稿”契约；不改产品代码。 |
| WP17-I 实现 | 多图选择、顺序与错误处理、OCR 适配器、草稿解析与编辑预览、一次确认导入；用合成图片做回归并在受支持平台验证。未测过的平台不显示“已支持”。 |

**给 WP17-R2 Agent 的执行边界**：只对 ncnn + PP-OCRv5 mobile 与 Tesseract 5 + `tessdata_fast` 做可复现对照；固定输入图片、图像缩放和评价口径，保存逐图输出以便人工核错。先用桌面 CLI 建立基线，再用相同模型与处理代码在 Android API 23、Windows、Linux 各识别至少一张样例；任一平台失败应明确报告，不能换平台专用 OCR 填空。结果按“识别出的文字”和“能否正确形成任务草稿”分别评分，附冷启动、批量 10 张、峰值内存、额外磁盘/包体积与许可清单。保留模型版本、配置和复现命令，不提交含私人待办内容的截图。推荐哪套由测量结果决定，不为达到预设结论调整样本。[PaddleOCR 官方 Android 示例](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/inference_deployment/cross_platform/android_deployment.md)本身要求 API 26，不能直接移植进 `minSdk=23` 的应用。

## 验收

- 多张截图能在一轮操作中识别、校对并导入；其中一张失败不使其余草稿无声丢失，重复截图不会自动造成不可见的重复任务。
- 对识别错字、跨图重复、父子层级、勾选状态和日期误判有可复现的合成用例；用户能在提交前修正或跳过。
- 优先让无网络、无 AI 密钥的用户也能识别；若本地方案达不到质量门槛，选型报告必须说明替代方案的上传、费用和平台限制，不能虚报离线可用。低端设备不会因整批图片同时解码而崩溃。
- Android 和 Windows 在各自验收前不宣称支持；Linux 预览版同样按实测结果标注。用户明确确认前，任务库不变。
