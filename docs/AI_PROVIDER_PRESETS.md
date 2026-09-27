# AI 服务商配置

方寸的 AI 功能由用户提供密钥，直接请求所选端点。普通任务管理不需要 AI。本文记录**客户端当前配置与请求行为**；服务商的模型、价格和接口能力可能变化，使用前请查看服务商自己的说明。

## 预设和自定义端点

预设只提供初始端点、协议与模型默认值，**不内置完整模型目录**。模型列表通过服务商的 `/models` 接口动态获取；发现失败时可以手填模型或接入点 ID。

| 配置 | 默认 Base URL | 协议 | 初始模型 |
|---|---|---|---|
| DeepSeek (`deepseek`) | `https://api.deepseek.com` | OpenAI Compatible | `deepseek-flash` |
| 火山引擎 (`volcengine`) | `https://ark.cn-beijing.volces.com/api/v3` | OpenAI Compatible | `doubao-pro-32k` |
| 阿里云百炼 (`bailian`) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | OpenAI Compatible | `qwen-plus` |
| 自定义 (`custom`) | 用户填写 | OpenAI Compatible、OpenAI Responses 或 Anthropic Messages | 用户填写 |

初始模型只是客户端默认输入，**不表示服务商一定提供该模型**。发现结果优先保留当前模型；否则按预设偏好选择已返回的模型，再退到列表首项。自定义端点需要填写适用的 Base URL、协议、模型和密钥；缺少 `/models` 时手填模型仍可尝试生成。完整预设和选模逻辑见 [ai_presets.dart](../lib/ai_presets.dart)。

## 连接和请求

- 模型发现使用密钥查询端点，但不发送任务正文。缓存按服务商、规范化地址、协议和凭据区分；地址或密钥变化会使旧列表失效，迟到的旧请求不会更新当前列表。
- 连接检查分别报告端点与鉴权、模型发现、所选模型生成。生成检查会发起实际请求，可能计费；模型列表成功也不保证生成可用。
- 思考参数按**协议、具体模型 ID 和端点**决定。未知模型不猜测兼容能力；界面会在无法确认开关效果时提示。规则见 [ai_capabilities.dart](../lib/ai_capabilities.dart)，请求实现见 [ai_service.dart](../lib/ai_service.dart)。
- API 密钥保存在系统保护存储。切换服务商、取消请求与设置页退出时的状态处理见 [settings_model_request.dart](../lib/screens/settings_model_request.dart) 和 [settings_screen.dart](../lib/screens/settings_screen.dart)。备份中的密钥选择见 [JSON 备份格式](BACKUP_FORMAT.md)。
