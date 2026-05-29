# ccglass Coding Agent Message View 调研

日期：2026-05-28

## 背景

本次调研对象是本地 `ccglass` 页面 `http://127.0.0.1:53378/` 中捕捉到的一段 coding agent message 记录。页面展示的是一个 agent 与 LLM 网关之间的多轮 `/chat/completions` 请求，包括模型调用、消息上下文、工具菜单、工具调用、工具结果、响应 usage、HTTP headers 等 wire-level 信息。

调研目标是总结 ccglass 对不同内容的展示方式，并对照 Local OTel Workbench 现有 GenAI 扩展，判断哪些数据视图可以直接支持，哪些需要新增数据模型或采集字段。

## ccglass 页面结构

ccglass 采用典型的 request inspector 布局：

- 顶部栏：session 选择、live 状态、模型过滤、总输入/输出 token、cache 命中率、估算成本、主题、错误入口、diff 开关。
- 左侧栏：请求序列和 latency trend。每一行代表一次 LLM HTTP 请求，展示序号、模型、时间、耗时、message 数、tool 数、HTTP 状态、tool-call 计数。
- 右侧详情区：针对选中的单次请求，通过 tab 展示 overview、flow、system、messages、tools、response、headers。

当前页面中选中的请求示例：

- 模型：`deepseek-v4-flash`
- 请求格式：`reasonix`
- message 数：`38`
- 可用工具数：`64`
- HTTP 状态：`200`
- stop reason：`tool_calls`
- 实际输入 token：`46,669`
- 输出 token：`117`
- cache read：`46,336`
- 估算成本：`$0.00021`

## 内容展示方式

### 1. Overview

`overview` 是单次 LLM 请求的 KPI 和 wire summary。

展示内容包括：

- Latency：total、TTFT、generation window。
- Token speed：pre-first-byte 输入速度、after-first-byte 输出速度。
- Request metadata：format、model、stop reason。
- Usage：估算输入、实际输入、输出、cache read、cache write。
- Cost：按模型和 token usage 估算的单次请求成本。
- Request line：例如 `POST /chat/completions`。
- 导出动作：raw、md、json、har、copy curl。

这个视图强调的是“单次 HTTP LLM 请求”的 wire-level 调试，而不是 trace-level 汇总。

### 2. Flow

`flow` 是最接近 agent execution replay 的视图。它把同一次请求中的上下文按执行顺序串起来：

- `user`：用户输入，包含引用文件信息。
- `assistant`：assistant 自然语言回复。
- `tool_use`：工具调用名称和 JSON 参数。
- `tool_result`：工具执行结果，包含执行状态和返回内容。
- 结束状态：例如 `stop_reason: tool_calls`。

相比 `messages`，`flow` 更偏人类阅读和调试，重点是“agent 为什么走到这一步”。长内容会折叠，工具调用和结果用不同图标、箭头、缩进表现。

### 3. System

`system` 展示 system prompt blocks。

当前页面只显示：

- `system[0].system`
- 可展开的 `show 154 lines`

这个视图强调 system prompt 的来源、索引和可折叠阅读，不把 system prompt 混入普通消息流。

### 4. Messages

`messages` 是原始 message array 结构视图。

展示方式包括：

- `msg[n].role` 索引，例如 `msg[1].user`、`msg[2].assistant`、`msg[3].tool`。
- assistant message 下展示 `tool_call[n]`。
- tool message 下展示对应 `result...`。
- 每个 tool call/result 保留 id 后缀，便于关联。
- 长文本使用 `show N lines` 折叠。

这个视图比 `flow` 更贴近 API payload，适合检查 message 顺序、role、tool_call/result 配对是否正确。

### 5. Tools

`tools` 展示的是“提供给模型的工具菜单”，不是实际调用统计。

每个工具包含：

- 工具名，例如 `read_file`、`search_content`、`run_command`。
- 工具描述。
- JSON schema。
- 折叠行数。

这类数据通常来自 request body 的 `tools` 字段。它回答的是“模型当时可选哪些工具”，而不是“模型实际调用了哪些工具”。

### 6. Response

`response` 展示模型响应的结构化摘要。

当前示例包括：

- usage JSON：input/output/cache read/cache creation token。
- streamed 标记。
- 最终 `tool_use` payload，例如 `run_command` 及其参数。

这个视图适合检查 stop reason、usage 和模型返回的 tool call 是否符合预期。

### 7. Headers

`headers` 展示 HTTP request headers，并对敏感字段脱敏。

当前示例中包括：

- `host`
- `connection`
- `authorization`，已显示为 `Bearer ...REDACTED...`
- `content-type`
- `accept`
- `user-agent`
- `content-length`

这个视图属于 wire inspector 能力，主要用于排查代理、网关、鉴权、流式响应、content length 等问题。

## 与现有 GenAI 扩展的能力映射

Local OTel Workbench 现有 GenAI 扩展的核心模型位于 `TraceDetail.genAi`，已经包含：

- GenAI span 列表
- timeline
- conversation
- RAG summary/documents
- token summary
- estimated cost
- tool call count / failed tool call count

服务端当前已经从多种字段体系抽取 GenAI 信息，包括：

- 标准 OTel GenAI：`gen_ai.*`
- OpenInference：`openinference.*`
- LangChain/LLM 兼容字段：`llm.*`
- AI SDK 字段：`ai.*`

### 可直接支持

| ccglass 视图 | 现有支持程度 | 对应 Workbench 能力 |
| --- | --- | --- |
| request 列表中的模型、trace duration、token in/out | 部分支持 | GenAI traces list、trace summary |
| flow 中的 user/assistant/tool_use/tool_result | 基本支持 | `genAi.conversation` + Messages view |
| messages 中的 role/message/tool call/result | 基本支持 | conversation turn：`system/user/assistant/tool` + `message/tool-call/tool-result` |
| tool call timeline | 支持 | `genAi.timeline` / Steps tab |
| 实际 tool call 聚合 | 支持 | Tools tab：toolName、count、failed、avg/total duration |
| provider/model/tokens | 支持 | GenAI detail header + mini stats |
| reasoning/thinking 内容 | 支持字段 | `reasoningPreview` + Messages reasoning 折叠 |
| RAG/retrieval | Workbench 更强 | RAG tab：retrieval/embedding/rerank/documents |

### 需要扩展后支持

| ccglass 能力 | 当前缺口 | 建议扩展方向 |
| --- | --- | --- |
| TTFT / generation window | 当前只有 span duration，没有首字节和 stream window | 在 normalized GenAI request 中新增 `ttftMs`、`generationMs` |
| 输入/输出速度 | 缺少 token/time 派生指标 | 基于 TTFT、generation window、input/output tokens 计算 |
| cache read/write tokens | 当前只抽取 input/output tokens | 支持 `cache_read_input_tokens`、`cache_creation_input_tokens`、`ai.usage.cachedInputTokens` 等字段 |
| stop reason | 当前 GenAI summary 不暴露 | 新增 `finishReason` / `stopReason` |
| 单次 LLM request wire view | 当前按 trace 聚合，不按 request body/response 展示 | 在 trace 内建立 `genAi.requests[]` 或从 LLM span 派生 request detail |
| offered tools menu/schema | 当前 Tools tab 聚合实际调用，不展示可用工具 schema | 采集 request body `tools` 或 `ai.prompt.tools`，新增 Tool Menu tab |
| HTTP headers/request line | 当前 trace detail 可看 raw attributes，但 GenAI 页面无专门视图 | 增加 Wire tab，谨慎脱敏 authorization/cookie |
| raw/md/json/har/curl 导出 | 当前无 GenAI request 级导出 | 支持 request snapshot export，默认脱敏 |
| session-level request replay | 当前 GenAI list 是 trace list | 增加按 LLM request 排列的 request list 或在 trace detail 内按 LLM span 列表展示 |

## 推荐产品化方向

### 阶段 1：增强现有 GenAI Trace Detail

优先复用现有模型，先落地 AI SDK 原生支持较好的字段：

- `finishReason`
- `cacheReadInputTokens`
- `cacheCreationInputTokens`，best-effort / provider-specific
- `reasoningTokens`
- `totalTokens`
- `providerMetadataPreview`
- `providerMetadataCount`

以下字段仍保留为后续 wire/request-level inspector 的方向，不作为第一阶段强依赖：

- `ttftMs`
- `generationMs`
- `requestFormat`

对应 UI：

- 在 GenAI detail header 增加 Cache、Reasoning、Finish、Metadata。
- 在 Steps tab 的 LLM step meta 中展示 finish reason、cache 命中、reasoning token 和 provider metadata 标记。
- 在 Messages view 中继续保留 role/kind 卡片，不改变现有 conversation 模型。

### 阶段 2：新增 LLM Request Inspector

在 trace detail 内新增一个 request-level 子视图，更接近 ccglass：

- 左侧：LLM request list，按 span/start time 排列。
- 右侧：Overview / Flow / Messages / Tools / Response / Headers。
- 数据来源优先使用 GenAI span attributes/events，不强依赖某个 SDK。
- 粒度上不直接暴露 span 为产品主对象，而是在 Trace 下派生 `genAi.requests[]`。每个 request 用 primary inference span 定位，保留 `primarySpanId` 和 `relatedSpanIds` 以便回跳到底层 span。
- 现有 trace-level `Messages` 继续用于 agent conversation 重建和跨请求去重；request-level `Messages` 展示单次模型请求的完整 payload，不做跨请求去重。

建议 normalized model：

```ts
interface GenAiRequestDetail {
  id: string;
  primarySpanId: string;
  relatedSpanIds: string[];
  provider?: string;
  model?: string;
  operation?: string;
  startTimeUnixNano: string;
  durationNano: number;
  inputTokens?: number;
  outputTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  cacheReadInputTokens?: number;
  cacheCreationInputTokens?: number;
  finishReason?: string;
  messages: ConversationTurn[];
  offeredTools?: OfferedTool[];
  providerMetadataPreview?: string;
}

interface OfferedTool {
  name: string;
  description?: string;
  schemaPreview?: string;
}
```

### 阶段 3：Wire Export 和脱敏策略

如果要支持 raw/json/har/curl 导出，需要先明确脱敏策略：

- 默认移除或遮蔽 `authorization`、`cookie`、`set-cookie`、API key、bearer token。
- 默认截断 prompt、tool result、response body。
- 提供“include sensitive payload”显式开关。
- 在导出文件中标记是否经过 redaction。

## 结论

ccglass 的核心价值不是单纯展示 GenAI span，而是把“单次模型请求”作为一等对象来调试：请求前的完整 messages、提供给模型的工具菜单、模型返回的 tool call、usage/cache/latency、HTTP headers 和导出能力都围绕这个对象组织。

Workbench 现有 GenAI 扩展已经能覆盖其中最重要的 agent 语义视图：

- conversation / messages
- tool call / tool result
- steps timeline
- tool call aggregate
- token summary
- RAG summary

但如果要达到 ccglass 这种 wire inspector 的体验，需要在现有 trace-level GenAI summary 之外，增加 request-level GenAI inspector。这个方向与现有架构兼容：保留 trace 作为顶层，LLM request 作为 trace 内的派生详情视图。
