# WP29-R：可选托管 AI 的无密钥原型

基线 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`。分支 `codex/wp29-r`，工作树
`D:/Dev_project/martix-wp29-r`。提交身份只写在本工作树
`config.worktree`：`wp29-r-agent` / `wp29-r-agent@local.invalid`。
没有改共享 git 身份，没有 AGENTS.md、CLAUDE.md 或 .cursorrules。
本机 Flutter 3.32.8 stable / Dart 3.8.1，框架修订 `edada7c56e`，
引擎 `ef0cd00091`，与 `toolchain.json` 的
`edada7c56edf4a183c1735310e123c7f923584f1` /
`ef0cd000916d64fa0c5d09cc809fa7ad244a5767` 一致。
`PUB_CACHE=D:/Dev_project/martix-wp29-r-private/pub-cache`。
`pub get --enforce-lockfile` 退出码 0，`pubspec.yaml` 与 `pubspec.lock` 相对基线无差异。

本包是离线实验。生产应用仍由用户自带密钥，协议仍是 `AIProtocol.openai`、
`openaiResponses`、`anthropic`。本原型没有接入现有 AI 请求、密钥存储、
Store、设置或主导航，没有账号、服务端密钥、付费调用或服务部署。

## 原型

新增目录 `lib/experiments/wp29_hosted_ai/`。协议版本 `"0"`。
流程是明确选择最小任务文本（可选图片）→ 同意 → `send` → 结构校验 →
人工 `confirmApply` 或 `discard`。同一 `requestId` 复用已保存的 Future。
超时和 429 在同一请求 ID 上有限重试，默认最多 3 次，等待不超过 `maxRetryWait`。
鉴权失效、额度耗尽、重复、能力变化、结构非法和预算失败不重试。
取消或关闭后，迟到结果只记未应用用量，不解析、不应用。

建议 JSON 只接受 `title`、可选 `notes`、可选象限整数 1..4。
请求映射不含 `api_key`、`authorization`、`secret`、`token`、`customApiKey`。
图片字节留在 `Uint8List`，不进 JSON。普通日志只记长度和指纹；
指纹是 FNV-1a 64，用来发现选择或能力变化，不是安全哈希。
`HeuristicTokenCounter` 是估算，测试用 `ExactTokenCounter`。

传输只有 `FakeHostedTransport` 和 `DeferredTransport`，没有 `package:http` 或 `dart:io`。
`tool/wp29_hosted_ai_demo.dart` 用合成文本跑上述分支，并调用成本计算器。

## 协议、价格与义务

检索日 2026-10-04。目录在 `price_catalog.dart`，`QuoteKind.verified` 才是厂商报价。
计算器只计未缓存输入、缓存命中输入和输出。缓存写入、音频、缓存存储、
batch、fast mode 和地区加价写在备注里，不静默计费。
`retryFactor` 与 `abuseFraction` 标成假设。`override()` 得到 `userOverride`，
不是厂商报价。未核实行调用 `estimate` 时抛出 `UnverifiedQuote`。

| id | 货币 | 输入 / 缓存命中 / 输出，每百万 token |
| --- | --- | --- |
| deepseek-flash-offpeak | USD | 0.15 / 0.003 / 0.6 |
| deepseek-flash-peak | USD | 0.3 / 0.006 / 1.2 |
| deepseek-v4-pro-offpeak | USD | 0.66 / 0.022 / 1.98 |
| openai-gpt-6-luna-short | USD | 0.10 / 0.01 / 0.50 |
| openai-gpt-6-luna-long | USD | 0.20 / 0.02 / 0.75 |
| anthropic-sonnet-5-5 | USD | 2 / 0.20 / 10 |
| anthropic-haiku-4-5 | USD | 1 / 0.10 / 5 |
| anthropic-opus-5-5 | USD | 4 / 0.20 / 20 |
| bailian-qwen-plus-beijing-128k | CNY | 0.8 / 0.16 / 2 |
| volcengine-doubao-seed-2.1-lite | CNY | 0.80 / 0.16 / 2.70 |
| preset-doubao-pro-32k | CNY | 无数字，`unverified` |

来源：DeepSeek `https://api-docs.deepseek.com/quick_start/pricing`（高峰 UTC 周一至周五
01:00–04:00 与 06:00–10:00，不含中国法定节假日；非高峰为高峰一半；
旧 flash 名称按 flash 价格走到 V4.1-Flash）。
OpenAI `https://developers.openai.com/api/docs/pricing`（标准价；抓取的表没有在短/长列旁印出 token 分界，目录不补这个数字；同页写 Responses、Chat Completions、Realtime、Batch、Assistants 不单独标价）。
Anthropic `https://platform.claude.com/docs/en/about-claude/pricing`（标准价；Opus 5.5 缓存命中 0.20 来自该页“输入价 5%”的正文，表单元格在抓取结果里是空的）。
百炼 `https://help.aliyun.com/zh/model-studio/qwen-plus`（北京、输入 ≤128k、非思考、非 batch、标价；页面更新时间空白）。
火山方舟 `https://www.volcengine.com/docs/82379/1544106`（在线推理、非音频、输入长度带 `[0, 1024]`，列名是「千 token」）。
产品预设 `doubao-pro-32k` 不在该表，计算器拒绝它。

共用的是本包这条无密钥信封。DeepSeek 文档同时有 OpenAI、Anthropic 和 Responses 形态；
百炼与火山方舟的兼容模式、Anthropic Messages 不是同一个上游报文。
本原型不替换生产客户端的三种用户密钥协议，也不部署中转。
若以后做真实托管，应用运营者会收到任务文本；这项义务没有实现。

OpenAI 数据控制页 `https://developers.openai.com/api/docs/guides/your-data`
（2026-10-04）：其表述是 API 数据默认不用于训练，除非用户明确加入；
默认滥用监控日志最多约 30 天。Anthropic 保留与 ZDR 页
（同日）：ZDR 覆盖 Messages 与 Token Counting，响应后不把客户数据存于静止存储，
法律或滥用调查除外；被标记的滥用即使在 ZDR 下也可能保留最多约 2 年；
Batch 不在 ZDR 范围内。DeepSeek 与火山方舟的隐私/保留页这次没有打开，
所以目录里没有它们的保留期限报价。

可用原型：假传输上可以离线跑通选择、同意、请求、取消、校验和人工确认。
长期免费运营：上面每一条核实单价都大于 0。重试、滥用、驻留、缓存写入和托管
大多没有报价。没有账号，也没有可宣称的长期免费额度。

## 命令

工作目录 `D:/Dev_project/martix-wp29-r`，Flutter `D:/Dev_SDKs/Flutter_3.32.8`。

```powershell
dart format lib/experiments/wp29_hosted_ai tool/wp29_hosted_ai_demo.dart test/wp29_hosted_ai_test.dart test/wp29_budget_privacy_test.dart
# 退出码 0，10 个文件，0 个改动
flutter analyze --no-pub
# 第一次退出码 1：session.dart:271 unused_local_variable
# 删掉未使用的 consent 局部变量后，再次退出码 0
flutter test --no-pub test/wp29_hosted_ai_test.dart test/wp29_budget_privacy_test.dart
# 退出码 0，17 项通过
flutter test --no-pub test/models_test.dart
# 退出码 0，24 项通过。该文件相对基线无差异
flutter pub get --enforce-lockfile
# 退出码 0。随后 git 恢复了 pub get 改写的 windows/flutter/generated_plugin_*，
# 并删除了未跟踪的 linux/flutter/generated_plugin_*
dart format --output=none --set-exit-if-changed lib/experiments/wp29_hosted_ai/session.dart
# 退出码 0，0 个改动
dart run tool/wp29_hosted_ai_demo.dart
# 退出码 0。stdout 含 demo_ok，不含合成任务原文。
# 副本在 D:/Dev_project/martix-wp29-r-private/evidence/，不提交
```

`git diff` 相对基线只应出现本 NOTES 与 `lib/experiments/wp29_hosted_ai/`、
`tool/wp29_hosted_ai_demo.dart`、`test/wp29_hosted_ai_test.dart`、
`test/wp29_budget_privacy_test.dart`。`lib/main.dart`、`test/helpers.dart`、
pubspec 与 lock 无差异。主检出 `D:/Dev_project/martix` 保持干净。

## 未验证

本会话没有 Linux `/home/ubuntu/develop/flutter` 运行，没有真机，没有独立进程，
没有 `flutter build apk`，没有真实模型调用，没有服务端部署。
默认全量测试没有跑；产品行为文件未改，用未改动的 `test/models_test.dart`
和构建入口差异为空作为边界证据。OpenAI 短/长上下文的 token 分界、
百炼页面更新时间、`doubao-pro-32k` 价格、DeepSeek 与火山方舟的保留期限
都没有被补成报价。
