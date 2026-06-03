# GenAI OpenTelemetry Framework Support

This document summarizes the example probes under `examples/` for DeepSeek with `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true`, plus the Workbench-specific GenAI normalization used by the dashboard and MCP tools.

## Scope

All probes use the same local receiver:

```bash
pnpm serve
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true
```

`DEEPSEEK_API_KEY` can be exported directly or stored in the repository `.env` file. Optional overrides:

```bash
export DEEPSEEK_MODEL=deepseek-chat
export DEEPSEEK_BASE_URL=https://api.deepseek.com
```

For TypeScript AI SDK, the provider package expects `https://api.deepseek.com/v1` by default; the example uses that URL unless `DEEPSEEK_BASE_URL` is set.

The AI SDK probes enable content capture through `experimental_telemetry.recordInputs` and `experimental_telemetry.recordOutputs`. The OTel GenAI capture environment variable is still exported for cross-framework comparison, but it is not the AI SDK content-capture switch.

## Result Matrix

| Platform | Framework | Example | Native OTel emission | GenAI semantic convention coverage | Content capture behavior | Dashboard support |
| --- | --- | --- | --- | --- | --- | --- |
| .NET | `Microsoft.Extensions.AI` | `examples/dotnet-webapi` | Yes, through `UseOpenTelemetry` | Strong. Emits GenAI semantic convention attributes from `OpenTelemetryChatClient`. | Honors `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true` unless explicitly overridden. | First-class through `gen_ai.*`. |
| Python | LangChain | `examples/python-agent` | Needs instrumentation packages. The example enables LangChain and OpenAI v2 instrumentation. | Mixed. LangChain run spans plus OpenAI-compatible GenAI spans/log events for the underlying DeepSeek request. | OpenAI v2 instrumentation uses the OTel GenAI capture flag, with `true` primarily capturing message content as events/logs unless latest experimental semconv mode is enabled. LangChain instrumentation may also have its own content-control behavior. | First-class for `gen_ai.*`; generic spans and exported logs remain visible in trace detail. |
| TypeScript | AI SDK | `examples/ts-agent` | Yes, when `experimental_telemetry.isEnabled` is set per model call. | Partial. Provider-call spans include selected `gen_ai.*` fields, but message content, tool schemas, tool calls, finish reason, usage details, and provider metadata are primarily `ai.*`. | AI SDK uses `experimental_telemetry.recordInputs` and `recordOutputs`, not the OTel GenAI capture env var, as its content switch. `functionId` and `metadata` are emitted as telemetry context. | First-class through Workbench's `ai.*` compatibility layer, including Messages, Steps, Requests, Tools, and RAG tabs. |

## Workbench GenAI Normalization

The dashboard does not require every framework to emit the exact same GenAI semantic convention version. The server builds a normalized `TraceDetail.genAi` model from several sources:

- Standard OTel GenAI fields: `gen_ai.*`, including message arrays, indexed prompt/completion attributes, usage, finish reason, tool fields, and response metadata.
- OpenInference-style span classification: `openinference.span.kind` for LLM, agent, tool, retriever, embedding, and reranker spans.
- Common LLM aliases: `llm.*`, `input.*`, `output.*`, `tool.*`, `function.*`, `mcp.tool.*`, and RAG document fields such as `retrieval.documents.*`.
- AI SDK fields: `ai.model.provider`, `ai.model.id`, `ai.operationId`, `ai.prompt`, `ai.prompt.messages`, `ai.prompt.tools`, `ai.response.text`, `ai.response.messages`, `ai.response.toolCalls`, `ai.toolCall.*`, `ai.usage.*`, `ai.response.finishReason`, and `ai.response.providerMetadata`.

The GenAI page then projects this normalized model into:

- `Messages`: reconstructed system/user/assistant/tool turns, including reasoning previews when present.
- `Steps`: an agent timeline with LLM, tool, retrieval, embedding, rerank, and agent spans.
- `Requests`: one row per canonical model call with Flow, Messages, Offered tools, Response, and Wire tabs.
- `Tools`: grouped tool calls with argument/result previews and failure counts.
- `RAG`: retrieved document counts and document previews.

For token and cost accounting, Workbench uses canonical LLM request spans instead of blindly summing every GenAI span. When AI SDK provider-call spans such as `ai.generateText.doGenerate`, `ai.streamText.doStream`, `ai.generateObject.doGenerate`, or `ai.streamObject.doStream` are present, their wrapper spans (`ai.generateText`, `ai.streamText`, `ai.generateObject`, `ai.streamObject`) are excluded from request accounting to avoid double-counting.

### AI SDK Compatibility Layer

The AI SDK layer adds support for fields that are not standard `gen_ai.*` but are useful for request-level debugging:

| Capability | AI SDK attributes | Workbench use |
| --- | --- | --- |
| Provider/model/operation | `ai.model.provider`, `ai.model.id`, `ai.operationId` | GenAI headers, trace list token summary, request labels, and request operation names |
| Prompt and response messages | `ai.prompt`, `ai.prompt.messages`, `ai.response.text`, `ai.response.messages` | Conversation turns and per-request Messages/Flow views |
| Offered tools | `ai.prompt.tools` | Requests -> Offered tab with tool name, description, and schema preview |
| Tool calls/results | `ai.response.toolCalls`, `ai.toolCall.name`, `ai.toolCall.args`, `ai.toolCall.result` | Tool turns, Tools breakdown, and request flow previews |
| Usage | `ai.usage.promptTokens`, `ai.usage.completionTokens`, `ai.usage.totalTokens` | Token totals and request-level accounting |
| Reasoning/cache usage | `ai.usage.reasoningTokens`, `ai.usage.outputTokenDetails.reasoningTokens`, `ai.usage.cachedInputTokens`, `ai.usage.inputTokenDetails.cacheReadTokens`, `ai.usage.cacheCreationInputTokens`, `ai.usage.inputTokenDetails.cacheCreationTokens` | Reasoning and cache mini-stats, timeline details, and response metadata |
| Finish/provider metadata | `ai.response.finishReason`, `ai.response.providerMetadata` | Finish mini-stat, request response fields, and provider metadata indicator |

Content and common secrets are redacted during normalization, so captured prompts, outputs, tool payloads, logs, and common credential-like values are not stored verbatim when they match the redaction rules.

## Live Validation

Validated against DeepSeek on May 19, 2026 with the local receiver on `http://127.0.0.1:14318`.

| Platform | Service | Trace shape | Captured content | Token usage |
| --- | --- | --- | --- | --- |
| .NET | `dotnet-meai-deepseek` | 2 spans, 1 GenAI span | system, user, assistant turns from `gen_ai.input.messages` / `gen_ai.output.messages` | 37 input / 15 output |
| Python | `python-langchain-deepseek` | 3 spans, 2 GenAI spans, 3 GenAI message logs | system, user, assistant turns from indexed `gen_ai.prompt.*` / `gen_ai.completion.*`; duplicate OpenAI v2 message logs are also exported | 68 input / 24 output across the LangChain and OpenAI-compatible spans |
| TypeScript | `ts-ai-sdk-deepseek` | 3 spans, 2 GenAI spans | content appears in `ai.prompt`, `ai.prompt.messages`, and `ai.response.text`; the dashboard maps these into conversation turns | 35 input / 16 output on the provider-call span |

The Python probe pins `wrapt<2` because the current `opentelemetry-instrumentation-langchain` release calls `wrap_function_wrapper` with keyword arguments that are incompatible with `wrapt` 2.x.

The richer TypeScript probe, `pnpm --dir examples/ts-agent complex`, is the release validation path for the GenAI page. It creates service `ts-ai-sdk-deepseek-complex`, emits an `agent.session.deepseek_complex_e2e` root span, two `agent.step.*` spans, AI SDK model-call spans, explicit `tool.*` spans, RAG retrieval spans, and a deterministic `llm.request.requests_view_fixture` span. Use it to verify Messages, Steps, Requests, Tools, RAG, cache tokens, reasoning tokens, finish reason, and provider metadata in one trace.

## How To Run

.NET:

```bash
dotnet run --project examples/dotnet-webapi/DotnetOtlpSmoke.csproj
```

Python:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r examples/python-agent/requirements.txt
python examples/python-agent/agent_smoke.py
```

TypeScript:

```bash
cd examples/ts-agent
pnpm install
pnpm start
pnpm complex
```

## What To Check

Open `http://localhost:18888`, then inspect the GenAI traces view:

- `.NET`: confirm service `dotnet-meai-deepseek`, model `deepseek-chat`, token usage, and captured prompt/response turns.
- `Python`: confirm service `python-langchain-deepseek`, LangChain wrapper span, OpenAI-compatible DeepSeek span, and whether prompt/response content appears as span attributes, span events, or exported logs.
- `TypeScript`: confirm service `ts-ai-sdk-deepseek`, `ai.generateText` and `ai.generateText.doGenerate` spans, token usage from `gen_ai.usage.*` or `ai.usage.*`, and prompt/response turns from `ai.prompt*` and `ai.response*`.
- `TypeScript complex`: confirm service `ts-ai-sdk-deepseek-complex`, the GenAI page tabs, request-level Offered/Response/Wire details, `searchIncidents` and other tool calls, retrieved documents, cache/reasoning token stats, finish reason, and provider metadata.

## Source Notes

- OpenTelemetry GenAI semantic conventions currently remain development status, and content capture is opt-in because prompts and outputs can be sensitive.
- `Microsoft.Extensions.AI` documents `UseOpenTelemetry` as following the OpenTelemetry GenAI semantic conventions, and `OpenTelemetryChatClient.EnableSensitiveData` defaults from `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`.
- AI SDK telemetry is experimental. It emits OpenTelemetry spans only when `experimental_telemetry` is enabled. Current AI SDK documentation shows `recordInputs` and `recordOutputs` as the privacy controls for disabling prompt/output capture, with inputs/outputs recorded by default when telemetry is enabled.
- Current OpenTelemetry Python contrib documentation lists official OpenAI v2 GenAI instrumentation. The LangChain probe therefore validates LangChain with both LangChain instrumentation and the underlying OpenAI-compatible DeepSeek request instrumentation rather than assuming LangChain alone emits standard `gen_ai.*`.
