# AI 服务商

方寸的 AI 功能使用用户自己的 API 密钥，直接请求用户选择的服务地址。不配置 AI 也能使用全部手动功能。服务商的模型、价格和接口随时可能变化，请以服务商自己的说明为准。

## 预设和自定义

预设只提供默认的地址、协议和模型，不内置完整的模型列表。模型列表通过服务商的 `/models` 接口获取；获取失败时，可以手动填写模型名或接入点 ID。

| 预设 | 默认地址 | 协议 | 默认模型 |
| --- | --- | --- | --- |
| DeepSeek（`deepseek`） | `https://api.deepseek.com` | OpenAI Compatible | `deepseek-flash` |
| 火山引擎（`volcengine`） | `https://ark.cn-beijing.volces.com/api/v3` | OpenAI Compatible | `doubao-pro-32k` |
| 阿里云百炼（`bailian`） | `https://dashscope.aliyuncs.com/compatible-mode/v1` | OpenAI Compatible | `qwen-plus` |
| 自定义（`custom`） | 用户填写 | OpenAI Compatible、OpenAI Responses 或 Anthropic Messages | 用户填写 |

- 默认模型只是一个初始值，服务商不一定提供这个模型。
- 获取到模型列表后，优先保留当前选择的模型；当前模型不在列表里时，按预设的偏好选一个，再不行就选列表中的第一个。
- 预设和选择模型的逻辑见 `lib/ai_presets.dart`。

## 测试连接

设置页只有一个“测试连接”按钮。它用当前配置发一个很小的生成请求（可能会产生少量费用）：

- 成功：只显示“连接成功”。
- 失败：用一句话说明原因，例如：
  - 密钥不对；
  - 网络连不上；
  - 模型不可用；
  - 额度不足或请求太频繁；
  - 服务商出错；
  - 地址有误；
  - 还没填地址、密钥或模型。

  不会显示状态码。错误归类在 `lib/screens/settings_model_request.dart` 的 `connectionResultText` 中。

## 请求行为

- **获取模型列表**：请求时带上密钥，但不发送任何任务内容。模型列表按服务商、地址、协议和密钥分别缓存；其中任何一项改变，旧列表就会失效。晚到的旧请求不会覆盖当前的列表。
- **分类、编组、拆解**：只有用户主动使用这些功能时，才会把相关任务的文字发给配置的服务地址。
- **思考模式**：思考参数要看协议、具体模型和服务地址才能决定。遇到未知的模型时，不去猜它支持什么。规则见 `lib/ai_capabilities.dart`，请求实现见 `lib/ai_service.dart`。
- **密钥**：保存在系统安全存储里。备份中是否包含密钥，见[备份格式](backup-format.md#密钥与敏感数据)。
