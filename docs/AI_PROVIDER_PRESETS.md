# AI 服务商预设与动态模型发现规范（AI Provider Presets & Model Discovery）

> 本文最初依据历史工作包建立，现用于记录 AI 服务商的 Base URL、协议、模型发现端点、鉴权与模型标识规范。
> **原则：只内置服务商端点及必要协议元数据，不内置静态模型清单。模型列表必须来自服务商动态接口返回，或由用户高级手填兜底。**

---

## 1. 服务商端点与协议规范

### 1.1 DeepSeek（深度求索）
- **服务商标识（providerId）**：`deepseek`
- **官方 Base URL**：`https://api.deepseek.com`
- **默认协议**：`AIProtocol.openai`（OpenAI Compatible）
- **模型发现端点**：`GET https://api.deepseek.com/models`
- **鉴权方式**：`Authorization: Bearer <DeepSeek_API_Key>`
- **返回结构**：
  ```json
  {
    "object": "list",
    "data": [
      { "id": "deepseek-chat", "object": "model", "owned_by": "deepseek" },
      { "id": "deepseek-reasoner", "object": "model", "owned_by": "deepseek" }
    ]
  }
  ```
- **解析字段**：`data[].id`
- **首选偏好**：若发现列表中包含 `deepseek-v4-flash` 或 `deepseek-chat`，优先选中，否则选择返回的第一个模型。
- **思考参数兼容性（Thinking）**：
  - DeepSeek Chat Completions 支持 `thinking: {"type": "enabled" | "disabled"}`。官方默认是 enabled，因此用户关闭思考时必须显式发送 disabled。
  - 仅 DeepSeek 预设，或自定义端点上的 `deepseek-` 模型 id，才发送该字段。火山、百炼和未知兼容模型不发送。
  - 依据：<https://api-docs.deepseek.com/guides/thinking_mode>（查阅于 2026-09-23）。

### 1.2 火山引擎（Volcengine / 方舟 / 豆包）
- **服务商标识（providerId）**：`volcengine`
- **官方 Base URL**：`https://ark.cn-beijing.volces.com/api/v3`
- **默认协议**：`AIProtocol.openai`（OpenAI Compatible）
- **模型发现端点**：`GET https://ark.cn-beijing.volces.com/api/v3/models`
- **鉴权方式**：`Authorization: Bearer <Volcengine_API_Key>`
- **返回结构**：标准 OpenAI compatible 格式，返回开通或部署的模型/接入点：
  ```json
  {
    "object": "list",
    "data": [
      { "id": "doubao-pro-32k", "object": "model" },
      { "id": "doubao-lite-32k", "object": "model" }
    ]
  }
  ```
- **解析字段**：`data[].id`
- **首选偏好**：返回的第一个模型/Endpoint ID。
- **接入点与兜底说明**：
  - 火山方舟除了标准预置模型 ID 外，许多场景使用用户创建的推理接入点（Endpoint ID，例如 `ep-2024...`）。
  - 若模型发现未返回对应接入点，或用户使用的是专属推理接入点，设置界面提供高级手填与自定义模型/Endpoint 输入。
- **思考参数兼容性**：不支持 DeepSeek 专用 `thinking` 参数，不附加该字段。

### 1.3 阿里云百炼（Aliyun DashScope / 通义千问）
- **服务商标识（providerId）**：`bailian`
- **官方 Base URL**：`https://dashscope.aliyuncs.com/compatible-mode/v1`
- **默认协议**：`AIProtocol.openai`（OpenAI Compatible）
- **模型发现端点**：`GET https://dashscope.aliyuncs.com/compatible-mode/v1/models`
- **鉴权方式**：`Authorization: Bearer <DashScope_API_Key>`
- **返回结构**：标准 OpenAI compatible 格式：
  ```json
  {
    "object": "list",
    "data": [
      { "id": "qwen-plus", "object": "model" },
      { "id": "qwen-turbo", "object": "model" },
      { "id": "qwen-max", "object": "model" }
    ]
  }
  ```
- **解析字段**：`data[].id`
- **首选偏好**：若发现列表中包含 `qwen-plus` 优先选中，否则选择返回的第一个模型。
- **思考参数兼容性**：不支持 DeepSeek 专用 `thinking` 参数，不附加该字段。

### 1.4 自定义服务商（Custom）
- **服务商标识（providerId）**：`custom`
- **Base URL**：用户自定义填写（支持任何 OpenAI-compatible、Anthropic 或自建反代）
- **协议支持**：用户自主选择：
  - `openai`（OpenAI Compatible，默认请求 `GET <base>/models`）
  - `openaiResponses`（OpenAI Responses API）
  - `anthropic`（Anthropic Messages API，默认请求 `GET <base>/v1/models`）
- **鉴权方式**：依协议自动添加 `Authorization: Bearer <key>` 或 `x-api-key: <key>`
- **兜底方案**：若自定义端点未实现 `/models`，用户直接手填模型名称即可正常调用生成。404/405 只表示没有模型列表，不会自动改成一次生成请求。
- **协议能力（OS11，查阅于 2026-09-23）**：
  - OpenAI Compatible：默认只发送 `model`、`messages` 和需要 JSON 时的 `response_format`。
  - OpenAI Responses：`POST /responses`，字段为 `model`、`instructions`、`input`，需要 JSON 时使用 `text.format`。`reasoning.effort` 只发给 o1/o3/o4 与 gpt-5 标识；未知模型省略。依据：<https://developers.openai.com/api/reference/resources/responses/methods/create>。
  - Anthropic Messages：`POST /v1/messages`。旧的 Claude 4.5 及更早思考模型使用 `thinking.type=enabled` 和 `budget_tokens`。Claude 4.6 及更新的自适应模型使用 `thinking.type=adaptive` 与 `output_config.effort`。会拒绝 `thinking.type=disabled` 的模型不发送该字段。`output_config.effort` 不是所有模型的思考开关。依据：<https://platform.claude.com/docs/en/build-with-claude/extended-thinking> 与 <https://platform.claude.com/docs/en/build-with-claude/effort>。
- **连接测试**：分开报告端点/鉴权可达、模型发现成功、所选模型生成成功。生成测试可能计费，只在用户确认后发送一次短请求。模型列表成功不等于所选模型可以生成。真实厂商调用不属于默认自动回归。

---

## 2. 交互生命周期与安全规则

1. **Key-only 快速配置**：
   - 用户选择服务商后，Base URL 与协议自动就绪，高级参数隐藏在折叠面板中；
   - 用户仅需输入 API Key；
   - API Key 输入失焦（Blur）或键盘提交（Submit）时，自动触发一次异步模型发现，**严禁逐字符（onChanged）发送请求**；
   - 提供显式的“刷新模型列表”按钮。
2. **切服务商清空 Key 与取消旧请求**：
   - 切换服务商时，必须立即取消上一服务商正在进行的任何请求；
   - 必须清空当前界面的 Key 输入，**决不将原服务商的 Key 泄漏或发送给新服务商**；
   - 清除当前展示的动态模型下拉列表。
3. **缓存与迟到响应隔离**：
   - 内存缓存身份是 provider、规范化 base URL、protocol 和 credential。规范化地址小写 scheme/host，去掉默认端口和末尾斜杠。诊断只写 `credential:redacted`，不写密钥。
   - 协议、URL 或密钥变化立即清掉设置页上的旧模型列表。相同身份复用缓存；刷新按钮绕过缓存。失败结果不缓存。
   - 新的发现会取消其他身份的在途请求。迟到响应不写入缓存，页面 dispose 后不更新界面。
4. **异常容错与手填兜底**：
   - 若模型发现遇到 401（Key 无效）、403、404、网络超时或空数据，友好展示错误原因；
   - 保留手动输入模型名称输入框，确保在无 `/models` 接口的代理环境下也能正常调用任务分析与拆解。
