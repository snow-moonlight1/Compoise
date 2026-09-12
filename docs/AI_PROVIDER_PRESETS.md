# AI 服务商预设与动态模型发现规范（AI Provider Presets & Model Discovery）

> 本文档依据 `docs/IMPLEMENTATION_PLAN_2026-09-08.md` 中 WP01-N 要求建立，记录主流 AI 服务商的官方 Base URL、协议、模型发现端点、鉴权与模型标识规范。
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
  - DeepSeek 支持专属的 `thinking: {"type": "enabled" | "disabled"}` 扩展参数。
  - 仅在服务商为 `deepseek` 时发送该思考控制字段；对其他服务商不无条件发送，避免 400 Bad Request。

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
- **兜底方案**：若自定义端点未实现 `/models`，用户直接手填模型名称即可正常调用生成。

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
   - 内存缓存以 `${provider}|${baseUrl}|${apiKey}` 为键，仅当配置未变时复用；配置变化缓存自动失效；
   - 请求绑定独立取消标记（`AICancellation`）；页面退出或切换服务商时 cancel；
   - 迟到的响应绝对不能覆盖用户已做出的新选择。
4. **异常容错与手填兜底**：
   - 若模型发现遇到 401（Key 无效）、403、404、网络超时或空数据，友好展示错误原因；
   - 保留手动输入模型名称输入框，确保在无 `/models` 接口的代理环境下也能正常调用任务分析与拆解。
