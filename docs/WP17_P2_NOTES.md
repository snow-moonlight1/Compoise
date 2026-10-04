# WP17-P2：native allocator 对照（2026-10-03）

固定基线 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`；分支 `codex/wp17-p2`；工作树 `D:/Dev_project/martix-wp17-p2`。只在本树配置 `wp17-p2-agent <wp17-p2-agent@localhost>`，未找到适用 AGENTS。未依赖 Q2/Q3 未提交代码，未派 Agent、跨会话发消息、push、amend、签名、tag 或发布。

**结论：保留 Q1 生产分配器。** 没有找到跨轮次、跨模式稳定且不增峰的候选。P2 只交付显式 opt-in 实验/回归及本记录；`ocr_runtime.cpp`、C ABI、模型/字典/锁、识别阈值/CTC、Dart/适配器、平台构建入口、质量真值、共享文档和 `test/helpers.dart` 均未改。不能把下面的单个平台/模式提速当默认优化。

## 策略与复现入口

`native/ocr/tools/p2_experiment.py` 仅生成外部源码，不覆盖既有目录；`p2_run.py` 串行执行 build/benchmark/regression，保存完整 argv、退出码和日志路径。生产 CMake 不引用这些文件，默认测试不生成模型/样本，也不启动设备。

- `q1`：当前 Q1，Net 本地缓存关闭。
- `rec-bounded`：仅识别 Extractor 共用一个会话内缓存。
- `all-bounded`：检测与识别 Extractor 共用同一个缓存。
- `q1-pool`：原 Q1 未采用方案；两个 ncnn PoolAllocator，ratio .75、drop threshold 2，每图 clear。

两个 bounded 候选均限制**空闲缓存计费字节**为 4 MiB，包括自身元数据和 ncnn overread padding，排除系统 malloc 元数据；活跃 tensor 不限额、不截断。75% 最低利用率/最小匹配块，互斥锁保护侵入链表，不在 free 路径创建容器节点。只通过 Extractor 设置分配器，不改变模型加载。每图 RAII 清空，包括 detect 错误/异常；成员声明在 Net 之前，析构时 Net 先销毁。跨会话不共享缓存；生产 Dart 队列仍串行。同一裸 C ABI handle 的并发 run/destroy 未作为支持契约。

ncnn 的 drop threshold 是块数条件，不能当字节上限；依据为固定提交的 [allocator.cpp](https://github.com/Tencent/ncnn/blob/c6b351b56fbe32e0381ae00331e3df649b20d7b7/src/allocator.cpp)。计费上限不是进程 RSS 上限；allocator clear 也不保证 libc/系统线程缓存立即归还 OS。

## 环境与方法

私有根 `W = D:/Dev_project/martix-wp17-p2-private`、`L = /home/ubuntu/wp17p2-private`。日志/模型缺失测试副本/边界 PNG/库/缓存均为本包私有；旧 SDK、官方部署只读且检查全部五模型及五许可/模型卡摘要。Windows 官方部署 `C:/Users/20214/AppData/Local/wp17i5-private/deploy-win`，Linux `/home/ubuntu/wp17i6-private/official-deploy`。未下载模型。

Flutter Windows `D:/Dev_SDKs/Flutter_3.32.8`、Linux `/home/ubuntu/develop/flutter`，均 3.32.8 / Dart 3.8.1；framework 完整 revision 和 engine revision 与 `toolchain.json` 一致。Windows 使用 VS2022，Linux clang 18.1.3 / Ninja，全部 **Release**。ncnn.lib SHA256 `7a3da36c6295ab64d1c40b1f4ad123daa72daf916d6612a129cc21f9e955312f`，libncnn.a `d6dea6d6eba1a50ab8774de131753c4d8ef7b18bd5bca8f058903461948b0c18`，stb `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3`。Windows 构建和 Linux `sdk.json`/CMakeCache 保存实际依赖。请求线程数 4；Linux consumer 未找到 OpenMP，链接列表只有固定 ncnn 静态库，不能宣称有效四线程并行。WSL 不是物理 Linux/低端设备。

沿用未改的 `q1_cases.json` 十图，含重复图，742720 字节 / 14738760 像素；不删识别内容、不减少批数、不改变上限。每个 trial 新进程，五批各十图；复用同一个 session 或每图销毁重建。seed 1702 随机初始顺序后逐轮旋转；Windows 复用四轮、重建三轮，Linux 两模式各三轮，共 2600 次正式 OCR。首批单独记录，热耗时为后四批的中位数，再取各 trial 中位数；重建模式包含创建/销毁耗时。每 20ms 采样真实 worker PID，峰值合并采样和进程自身最终高水位，RSS/HWM/PSS 分列，Windows PSS 为 null。

主机负载/频率及文件缓存未严格隔离。Windows 复用首轮有 WSL 服务启动干扰，**没有丢弃**；第 2–4 轮敏感性检查仍不支持不增峰的默认候选。Linux 轮次快慢反转，故同时报告同模式、同轮 Q1 比值的中位数（下表 Δ），而非仅用总体中位数相除。Linux all-bounded 总体中位数看似较快，但同轮 Δ 为正；`p2_tools_test.py` 专门防止这种统计误读。全部 trial 和范围保存在原报告。

## 完整批次结果

耗时 ms；内存 KiB。`批后/销毁后` 为 RSS 中位数；HWM 是各 trial 高水位中位数。Δ 为同轮 candidate/Q1 的中位比值减 1，正表示耗时/峰值增加。不同平台、模式、Debug/Release 不互算提升率。

| 平台/模式 | 策略 | 热十图 | HWM | 批后/销毁后 RSS | 耗时 Δ | HWM Δ |
|---|---|---:|---:|---:|---:|---:|
| Win 复用 | q1 | 3665.5 | 183446 | 54374/29836 | 0 | 0 |
| Win 复用 | rec-bounded | 3771.4 | 184008 | 51538/27522 | -0.64% | +0.29% |
| Win 复用 | all-bounded | 3386.6 | 185606 | 51164/27252 | -8.37% | +1.19% |
| Win 复用 | q1-pool | 2945.4 | 297102 | 51704/27506 | -20.17% | +62.09% |
| Win 重建 | q1 | 4200.6 | 186400 | 30064/31368 | 0 | 0 |
| Win 重建 | rec-bounded | 3973.9 | 189312 | 27912/29132 | -1.32% | +1.47% |
| Win 重建 | all-bounded | 4306.6 | 189464 | 27208/51852 | +2.52% | +1.57% |
| Win 重建 | q1-pool | 3423.9 | 310412 | 27900/63660 | -14.98% | +66.53% |
| Linux 复用 | q1 | 7831.7 | 212064 | 73636/65004 | 0 | 0 |
| Linux 复用 | rec-bounded | 6028.6 | 212708 | 74268/65624 | +2.72% | +0.30% |
| Linux 复用 | all-bounded | 6113.7 | 216560 | 78764/70188 | +16.06% | +2.15% |
| Linux 复用 | q1-pool | 6237.4 | 335300 | 177544/162492 | +0.57% | +58.08% |
| Linux 重建 | q1 | 7020.2 | 215008 | 77476/77476 | 0 | 0 |
| Linux 重建 | rec-bounded | 6507.0 | 215040 | 78616/78636 | +6.74% | +0.02% |
| Linux 重建 | all-bounded | 6720.0 | 217468 | 79424/85280 | +5.56% | +1.12% |
| Linux 重建 | q1-pool | 5885.3 | 332136 | 228728/228748 | -17.86% | +54.48% |

证据：`W/bench-win/summary.json`、`W/bench-win-recreate/summary.json`、`L/bench-linux-final/summary.json`（只读摘要副本 `W/bench-linux-summary.json`）、`W/comparison.json`。每个 trial 的 PID、完整 argv/exit、五批时间、逐阶段 RSS/HWM/PSS、输出 JSON 的 SHA256、库/官方资源/图片 SHA256 和原始采样均在对应目录。全部十图输出 hash 在同平台全部候选/轮次/重建间完全一致。销毁后 RSS 可能高于最后一批快照；不将它包装成零驻留或长期无泄漏证明。

## 验证与交付记录

原 Agent 停止时尚未提交；2026-10-04 集成端保留原实验源码并补齐此记录，没有采用实验分配器。以下结果根据私有根中的命令记录、退出码文件和实际日志核对。

- Windows 四种策略的 allocator、十图复用/重建、生命周期及边界回归均退出 0；Linux 同样四种策略的生命周期与边界回归退出 0。各策略同平台输出一致。
- Windows 生产 FFI 回归每种策略 9 项通过，退出 0。
- 原包默认 Flutter 全量 1413 通过 / 12 条件跳过；analyze 无问题；默认 Windows Release 构建退出 0。
- 统计工具 2 项通过；集成端再次执行 `python -B -m unittest discover -s native/ocr/tools -p p2_tools_test.py -v`，2 项通过，退出 0。

整合提交和组合测试以集成记录为准。未验：Android、实体低端设备、严格隔离负载、长时间泄漏及真实截图；WSL 不作为实体 Linux 性能证据。实验结论维持“保留 Q1”，没有新默认性能提升声明。
