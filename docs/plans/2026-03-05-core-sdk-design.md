# Core SDK Design

## Goal

Implement the Core SDK layer that sits between the provider abstraction
(`ai_provider`) and the frontend. This is the OCaml equivalent of the
`ai` package's `generateText`, `streamText`, and UIMessage stream protocol.

The critical deliverable is **frontend interoperability** — an OCaml server
that speaks the exact SSE wire format that `useChat()` from `@ai-sdk/react`
expects, enabling an OCaml backend with a JavaScript/React frontend.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  JavaScript Frontend (useChat / @ai-sdk/react)          │
│  Consumes: SSE with UIMessage stream protocol v1        │
└─────────────────────┬───────────────────────────────────┘
                      │ HTTP POST → SSE response
                      │ Header: x-vercel-ai-ui-message-stream: v1
┌─────────────────────▼───────────────────────────────────┐
│  Core SDK (ai_core)        ← THIS IS WHAT WE BUILD     │
│                                                         │
│  generate_text : high-level non-streaming generation    │
│  stream_text   : high-level streaming generation        │
│  Tool          : tool definition with schema + execute  │
│  UIMessage_stream : SSE encoder for frontend interop    │
│                                                         │
│  Internally uses: Language_model.t from ai_provider     │
└─────────────────────┬───────────────────────────────────┘
                      │ Language_model.generate / stream
┌─────────────────────▼───────────────────────────────────┐
│  Provider Layer (ai_provider + ai_provider_anthropic)   │
│  Already implemented                                    │
└─────────────────────────────────────────────────────────┘
```

---

## 2. What We Need to Build

### 2.1 Core Functions

| Function | TypeScript equivalent | Purpose |
|----------|----------------------|---------|
| `generate_text` | `generateText()` | Non-streaming. Calls provider, executes tools in a loop, returns aggregated result. |
| `stream_text` | `streamText()` | Streaming. Returns stream of `Text_stream_part.t`, supports tool loop, provides `to_ui_message_stream` for frontend. |

### 2.2 UIMessage Stream Protocol (SSE Wire Format)

The frontend interop layer. An OCaml HTTP handler that emits SSE in the
exact format `useChat()` expects.

**Wire format** (from Vercel AI SDK source `json-to-sse-transform-stream.ts`):
```
data: {"type":"start","messageId":"msg_abc123"}

data: {"type":"text-start","id":"txt_1"}

data: {"type":"text-delta","id":"txt_1","delta":"Hello"}

data: {"type":"text-delta","id":"txt_1","delta":" world!"}

data: {"type":"text-end","id":"txt_1"}

data: {"type":"finish","finishReason":"stop"}

data: [DONE]

```

Each line is `data: <JSON>\n\n` (SSE format). Stream terminates with
`data: [DONE]\n\n`.

**Required response headers:**
```
content-type: text/event-stream
cache-control: no-cache
connection: keep-alive
x-vercel-ai-ui-message-stream: v1
x-accel-buffering: no
```

### 2.3 Tool System

The Core SDK wraps the provider's raw tool call/result into a managed loop:

1. User defines tools with `name`, `description`, `parameters` (JSON Schema), and an `execute` function
2. Model generates tool calls → Core SDK validates args → executes tools
3. Tool results fed back as messages → model called again
4. Loop until model stops calling tools or `max_steps` reached

---

## 3. UIMessage Stream Chunk Types

From the Vercel AI SDK source (`ui-message-chunks.ts`), the complete set:

### Message lifecycle
```ocaml
| Start of { message_id : string option; message_metadata : Yojson.Safe.t option }
| Finish of { finish_reason : Finish_reason.t option; message_metadata : Yojson.Safe.t option }
| Abort of { reason : string option }
```

### Step boundaries
```ocaml
| Start_step
| Finish_step
```

### Text streaming
```ocaml
| Text_start of { id : string }
| Text_delta of { id : string; delta : string }
| Text_end of { id : string }
```

### Reasoning streaming
```ocaml
| Reasoning_start of { id : string }
| Reasoning_delta of { id : string; delta : string }
| Reasoning_end of { id : string }
```

### Tool interaction
```ocaml
| Tool_input_start of { tool_call_id : string; tool_name : string }
| Tool_input_delta of { tool_call_id : string; input_text_delta : string }
| Tool_input_available of { tool_call_id : string; tool_name : string; input : Yojson.Safe.t }
| Tool_output_available of { tool_call_id : string; output : Yojson.Safe.t }
| Tool_output_error of { tool_call_id : string; error_text : string }
```

### Sources
```ocaml
| Source_url of { source_id : string; url : string; title : string option }
```

### Files
```ocaml
| File of { url : string; media_type : string }
```

### Error
```ocaml
| Error of { error_text : string }
```

### Custom data
```ocaml
| Data of { data_type : string; id : string option; data : Yojson.Safe.t }
```

---

## 4. Core SDK Types

### 4.1 Tool Definition (`Core_tool`)

```ocaml
type 'result t = {
  description : string option;
  parameters : Yojson.Safe.t;  (** JSON Schema *)
  execute : Yojson.Safe.t -> 'result Lwt.t;
  (** Execute the tool with validated args. Args are raw JSON. *)
}

(** Existential wrapper for heterogeneous tool maps. *)
type any_tool = Any_tool : 'a t * ('a -> Yojson.Safe.t) -> any_tool
(** The second function serializes the result to JSON for the model. *)
```

**Why existential:** Tools have different result types. The `any_tool` wrapper
pairs each tool with its result serializer, hiding the type parameter. The
Core SDK never needs to know the concrete result type — it just needs JSON.

**Alternative (simpler, recommended for v1):**

```ocaml
type t = {
  description : string option;
  parameters : Yojson.Safe.t;
  execute : Yojson.Safe.t -> Yojson.Safe.t Lwt.t;
}
```

All tools return `Yojson.Safe.t` directly. Simpler, no existential needed.
The user wraps their typed result with `to_yojson` at definition site.
**This is the recommended approach for v1.**

### 4.2 Generate Text Result (`Generate_text_result`)

```ocaml
type tool_call = {
  tool_call_id : string;
  tool_name : string;
  args : Yojson.Safe.t;
}

type tool_result = {
  tool_call_id : string;
  tool_name : string;
  result : Yojson.Safe.t;
  is_error : bool;
}

type step = {
  text : string;
  reasoning : string;
  tool_calls : tool_call list;
  tool_results : tool_result list;
  finish_reason : Finish_reason.t;
  usage : Usage.t;
}

type t = {
  text : string;
  reasoning : string;
  tool_calls : tool_call list;
  tool_results : tool_result list;
  steps : step list;
  finish_reason : Finish_reason.t;
  usage : Usage.t;  (** Aggregated across all steps *)
  response : Generate_result.response_info;
  warnings : Warning.t list;
}
```

### 4.3 Stream Text Result (`Stream_text_result`)

```ocaml
type t = {
  text_stream : string Lwt_stream.t;
  (** Just the text deltas. *)

  full_stream : Text_stream_part.t Lwt_stream.t;
  (** All events including tool calls, reasoning, finish. *)

  usage : Usage.t Lwt.t;
  (** Resolves when stream completes with aggregated usage. *)

  finish_reason : Finish_reason.t Lwt.t;
  (** Resolves when stream completes. *)

  steps : step list Lwt.t;
  (** All steps, resolves when complete. *)

  warnings : Warning.t list;
}

val to_ui_message_stream :
  ?message_id:string ->
  ?send_reasoning:bool ->
  t -> Ui_message_chunk.t Lwt_stream.t
(** Convert to UIMessage stream protocol chunks for frontend consumption. *)

val to_ui_message_stream_response :
  ?message_id:string ->
  ?send_reasoning:bool ->
  ?status:int ->
  ?headers:(string * string) list ->
  t -> Cohttp_lwt_unix.Server.response_action Lwt.t
(** Create an HTTP response streaming UIMessage SSE. *)
```

### 4.4 Text Stream Part (internal fullStream events)

```ocaml
type t =
  | Start
  | Start_step
  | Text_start of { id : string }
  | Text_delta of { text : string; id : string }
  | Text_end of { id : string }
  | Reasoning_start of { id : string }
  | Reasoning_delta of { text : string; id : string }
  | Reasoning_end of { id : string }
  | Tool_call of { tool_call_id : string; tool_name : string; args : Yojson.Safe.t }
  | Tool_call_delta of { tool_call_id : string; tool_name : string; args_text_delta : string }
  | Tool_result of { tool_call_id : string; tool_name : string;
                     result : Yojson.Safe.t; is_error : bool }
  | Source of { source_id : string; url : string; title : string option }
  | File of { url : string; media_type : string }
  | Finish_step of { finish_reason : Finish_reason.t; usage : Usage.t }
  | Finish of { finish_reason : Finish_reason.t; usage : Usage.t }
  | Error of { error : string }
```

---

## 5. generate_text Implementation

### Signature

```ocaml
val generate_text :
  model:Language_model.t ->
  ?system:string ->
  ?prompt:string ->
  ?messages:Prompt.message list ->
  ?tools:(string * Core_tool.t) list ->
  ?tool_choice:Tool_choice.t ->
  ?max_steps:int ->
  ?max_output_tokens:int ->
  ?temperature:float ->
  ?top_p:float ->
  ?top_k:int ->
  ?stop_sequences:string list ->
  ?seed:int ->
  ?headers:(string * string) list ->
  ?provider_options:Provider_options.t ->
  ?on_step_finish:(Generate_text_result.step -> unit) ->
  unit ->
  Generate_text_result.t Lwt.t
```

### Internal Flow

```
1. Build initial prompt:
   - If `prompt` is given, wrap as [System(system); User([Text(prompt)])]
   - If `messages` is given, prepend System if `system` is set
   - Convert tools to Tool.t list for Call_options

2. Step loop (max_steps iterations):
   a. Call Language_model.generate with current messages
   b. Parse result.content into text + tool_calls + reasoning
   c. If no tool calls or tool_choice = None_ → break
   d. Execute each tool call:
      - Find tool by name in tool map
      - Call tool.execute with args JSON
      - Catch exceptions → tool_result with is_error=true
   e. Append assistant message (with tool calls) to messages
   f. Append tool results as Tool message
   g. Record step, call on_step_finish callback
   h. Continue loop

3. Aggregate results:
   - Concatenate text from all steps
   - Concatenate reasoning from all steps
   - Sum usage across steps
   - Return final Generate_text_result.t
```

### Tool Execution

```ocaml
let execute_tool_call ~tools (tc : Content.Tool_call) =
  match List.assoc_opt tc.tool_name tools with
  | None ->
    Lwt.return
      { tool_call_id = tc.tool_call_id; tool_name = tc.tool_name;
        result = `String (Printf.sprintf "Tool '%s' not found" tc.tool_name);
        is_error = true }
  | Some tool ->
    let args = Yojson.Safe.from_string tc.args in
    Lwt.catch
      (fun () ->
        let%lwt result = tool.execute args in
        Lwt.return
          { tool_call_id = tc.tool_call_id; tool_name = tc.tool_name;
            result; is_error = false })
      (fun exn ->
        Lwt.return
          { tool_call_id = tc.tool_call_id; tool_name = tc.tool_name;
            result = `String (Printexc.to_string exn);
            is_error = true })
```

---

## 6. stream_text Implementation

### Signature

```ocaml
val stream_text :
  model:Language_model.t ->
  ?system:string ->
  ?prompt:string ->
  ?messages:Prompt.message list ->
  ?tools:(string * Core_tool.t) list ->
  ?tool_choice:Tool_choice.t ->
  ?max_steps:int ->
  ?max_output_tokens:int ->
  ?temperature:float ->
  ?top_p:float ->
  ?top_k:int ->
  ?stop_sequences:string list ->
  ?seed:int ->
  ?headers:(string * string) list ->
  ?provider_options:Provider_options.t ->
  ?on_step_finish:(Generate_text_result.step -> unit) ->
  ?on_chunk:(Text_stream_part.t -> unit) ->
  ?on_finish:(Generate_text_result.t -> unit) ->
  unit ->
  Stream_text_result.t
```

**Note:** `stream_text` returns **synchronously** (not Lwt.t). The stream
is consumed asynchronously. This matches the TypeScript SDK's behavior.

### Internal Flow

```
1. Build initial prompt (same as generate_text)

2. Create output streams:
   - full_stream (Stream_part.t Lwt_stream.t) with push function
   - text_stream derived by filtering full_stream for text deltas

3. Start background task (Lwt.async):
   a. Emit Start, Start_step
   b. Call Language_model.stream with current messages
   c. Consume provider stream parts, transforming:
      - Provider Text → emit Text_start, Text_delta (with generated ID)
      - Provider Reasoning → emit Reasoning_start, Reasoning_delta
      - Provider Tool_call_delta → emit Tool_call_delta
      - Provider Tool_call_finish → accumulate complete tool call
      - Provider Finish → if tool calls pending, execute tools:
        i.  Emit Tool_call for each complete call
        ii. Execute tools
        iii. Emit Tool_result for each
        iv. Emit Finish_step
        v.  If should continue: go back to step b with updated messages
        vi. Otherwise: emit Finish, close stream
      - Provider Finish (no tools) → emit Finish_step, Finish, close

4. Return Stream_text_result with streams + promises for final values
```

### Provider Stream → Text Stream Part Mapping

```
Provider Stream_part.t          →  Text_stream_part.t
─────────────────────────────────────────────────────
Stream_start                    →  Start, Start_step
Text { text }                   →  Text_start (first), Text_delta
Reasoning { text }              →  Reasoning_start (first), Reasoning_delta
Tool_call_delta { ... }         →  Tool_call_delta (accumulate args)
Tool_call_finish { id }         →  Tool_call (complete, with accumulated args)
Finish { reason; usage }        →  Finish_step (+ tool exec if needed)
                                   Then either loop or Finish
Error { error }                 →  Error
```

---

## 7. UIMessage Stream Protocol

### 7.1 Ui_message_chunk type

```ocaml
type t =
  | Start of { message_id : string option; message_metadata : Yojson.Safe.t option }
  | Finish of { finish_reason : Finish_reason.t option; message_metadata : Yojson.Safe.t option }
  | Abort of { reason : string option }
  | Start_step
  | Finish_step
  | Text_start of { id : string }
  | Text_delta of { id : string; delta : string }
  | Text_end of { id : string }
  | Reasoning_start of { id : string }
  | Reasoning_delta of { id : string; delta : string }
  | Reasoning_end of { id : string }
  | Tool_input_start of { tool_call_id : string; tool_name : string }
  | Tool_input_delta of { tool_call_id : string; input_text_delta : string }
  | Tool_input_available of { tool_call_id : string; tool_name : string; input : Yojson.Safe.t }
  | Tool_output_available of { tool_call_id : string; output : Yojson.Safe.t }
  | Tool_output_error of { tool_call_id : string; error_text : string }
  | Source_url of { source_id : string; url : string; title : string option }
  | File of { url : string; media_type : string }
  | Error of { error_text : string }
  | Data of { data_type : string; id : string option; data : Yojson.Safe.t }
```

### 7.2 JSON Serialization

Each chunk serializes to a JSON object with a `type` field:

```ocaml
val to_yojson : t -> Yojson.Safe.t
(** Serialize a UIMessage chunk to JSON.
    Type field names match the Vercel AI SDK wire format exactly. *)
```

Examples:
```json
{"type":"start","messageId":"msg_1"}
{"type":"text-start","id":"txt_1"}
{"type":"text-delta","id":"txt_1","delta":"Hello"}
{"type":"text-end","id":"txt_1"}
{"type":"tool-input-start","toolCallId":"tc_1","toolName":"search"}
{"type":"tool-input-available","toolCallId":"tc_1","toolName":"search","input":{"query":"test"}}
{"type":"tool-output-available","toolCallId":"tc_1","output":{"result":"found"}}
{"type":"finish-step"}
{"type":"finish","finishReason":"stop"}
```

**CRITICAL**: Field names use camelCase in JSON (matching TypeScript SDK)
but snake_case in OCaml types. The `to_yojson` function handles this mapping.

### 7.3 SSE Encoding

```ocaml
val chunk_to_sse : t -> string
(** Encode a single chunk as an SSE data line: "data: {json}\n\n" *)

val done_sse : string
(** The terminal SSE message: "data: [DONE]\n\n" *)
```

### 7.4 HTTP Response

```ocaml
val ui_message_stream_headers : (string * string) list
(** Required SSE headers for UIMessage stream protocol v1:
    content-type: text/event-stream
    cache-control: no-cache
    connection: keep-alive
    x-vercel-ai-ui-message-stream: v1
    x-accel-buffering: no *)
```

---

## 8. Text Stream Part → UIMessage Chunk Transformation

The `to_ui_message_stream` function on `Stream_text_result` transforms
the internal `Text_stream_part.t` stream into `Ui_message_chunk.t` stream:

```
Text_stream_part.t              →  Ui_message_chunk.t
─────────────────────────────────────────────────────
Start                           →  Start { message_id }
Start_step                      →  Start_step
Text_start { id }               →  Text_start { id }
Text_delta { text; id }         →  Text_delta { id; delta = text }
Text_end { id }                 →  Text_end { id }
Reasoning_start { id }          →  Reasoning_start { id }  (if send_reasoning)
Reasoning_delta { text; id }    →  Reasoning_delta { id; delta = text }
Reasoning_end { id }            →  Reasoning_end { id }
Tool_call_delta { ... }         →  Tool_input_delta { ... }
Tool_call { id; name; args }    →  Tool_input_available { id; name; input = args }
Tool_result { id; result; ... } →  Tool_output_available { id; output = result }
                                   OR Tool_output_error { id; error_text }
Finish_step { ... }             →  Finish_step
Finish { reason; usage }        →  Finish { finish_reason }
Error { error }                 →  Error { error_text }
```

---

## 9. Module Structure

```
lib/
  ai_core/
    ai_core.ml              -- top-level re-exports
    core_tool.ml             -- tool definition type
    generate_text.ml         -- generate_text function
    generate_text_result.ml  -- result types (step, tool_call, etc.)
    stream_text.ml           -- stream_text function
    stream_text_result.ml    -- stream result with to_ui_message_stream
    text_stream_part.ml      -- internal stream event types
    ui_message_chunk.ml      -- UIMessage protocol chunk types + JSON
    ui_message_stream.ml     -- SSE encoding + HTTP response helpers
    prompt_builder.ml        -- string prompt → Prompt.message list
```

---

## 10. Frontend Interop Verification

### 10.1 What We Test

We need to verify our SSE output is byte-compatible with what `useChat()`
expects. The key requirements:

1. **Headers**: `x-vercel-ai-ui-message-stream: v1` must be present
2. **SSE format**: `data: <JSON>\n\n` (double newline after each event)
3. **Terminator**: `data: [DONE]\n\n`
4. **JSON field names**: camelCase (`messageId`, `toolCallId`, `inputTextDelta`)
5. **Type values**: exact strings (`text-start`, `text-delta`, `tool-input-start`)
6. **Event ordering**: `start` → `start-step` → content blocks → `finish-step` → `finish`

### 10.2 Test Strategy

**Unit tests (OCaml):**
- Serialize each `Ui_message_chunk.t` variant to JSON, verify field names
- Encode chunks as SSE, verify `data: ...\n\n` format
- Full stream scenario: text generation → verify complete SSE output
- Tool call scenario: tool input + output → verify SSE sequence

**Integration test (cross-language):**
- OCaml server emitting SSE on an HTTP endpoint
- Node.js script using `readUIMessageStream` from `@ai-sdk/react` to consume
- Verify the stream parses correctly and produces expected UIMessage parts

This can be a simple test script:
```javascript
// test/interop/test_stream_protocol.mjs
import { readUIMessageStream } from 'ai';

const response = await fetch('http://localhost:PORT/test-stream');
for await (const message of readUIMessageStream({ stream: response.body })) {
  console.log(JSON.stringify(message));
}
```

### 10.3 Snapshot Tests

Capture known-good SSE output as test fixtures:
```
# test/fixtures/text_generation.sse
data: {"type":"start","messageId":"msg_1"}

data: {"type":"start-step"}

data: {"type":"text-start","id":"txt_1"}

data: {"type":"text-delta","id":"txt_1","delta":"Hello world!"}

data: {"type":"text-end","id":"txt_1"}

data: {"type":"finish-step"}

data: {"type":"finish","finishReason":"stop"}

data: [DONE]

```

Compare our output against these fixtures byte-for-byte.

---

## 11. Conversation Management

### 11.1 Message Conversion

The Core SDK needs helpers to convert between user-facing messages and
the provider-layer `Prompt.message` type:

```ocaml
val messages_of_prompt :
  ?system:string ->
  prompt:string ->
  Prompt.message list
(** Convert a simple string prompt (+ optional system) to messages. *)

val append_tool_results :
  messages:Prompt.message list ->
  assistant_content:Content.t list ->
  tool_results:Generate_text_result.tool_result list ->
  Prompt.message list
(** Append an assistant message and tool results for the next loop iteration. *)
```

### 11.2 Multi-Turn Support

For now, multi-turn is the **caller's responsibility** — they maintain
the message list and call `generate_text`/`stream_text` repeatedly.

The Core SDK provides the building blocks (message conversion, tool result
appending) but does NOT manage conversation state. This matches the Vercel
SDK's approach where `generateText`/`streamText` are stateless functions.

---

## 12. Dependencies

No new opam dependencies needed beyond what we already have:
- `ai_provider` (our abstraction layer)
- `lwt`, `lwt.unix`, `lwt_ppx`
- `yojson`
- `cohttp-lwt-unix` (for HTTP response helpers)
- `alcotest` (testing)

For the cross-language interop test: `node` + `npm install ai` (not an
OCaml dependency, just a test tool).

---

## 13. Open Questions

1. **Should `stream_text` handle multi-step tool loops?** The TypeScript SDK
   does — when the model returns tool calls during streaming, it executes
   them and calls the model again, all within the same stream. This is
   complex but essential for agents. Recommendation: yes, implement it.

2. **Should we support the `Output` API (structured output)?** This adds
   JSON schema validation on the response. Recommendation: defer to v2.
   The `Mode.Object_json` already gets the model to produce JSON; validation
   can be added later without breaking the API.

3. **Should we build a cohttp server handler helper?** Something like:
   ```ocaml
   val handle_chat :
     model:Language_model.t ->
     ?tools:(string * Core_tool.t) list ->
     Cohttp_lwt_unix.Server.conn ->
     Cohttp.Request.t ->
     Cohttp_lwt.Body.t ->
     (Cohttp.Response.t * Cohttp_lwt.Body.t) Lwt.t
   ```
   This would parse the request body (messages JSON), call `stream_text`,
   and return the SSE response. Very convenient for building chat APIs.
   Recommendation: yes, include it.

4. **ID generation for stream parts:** The UIMessage protocol requires
   IDs like `"txt_1"`, `"rsn_1"` for content blocks. Should we use
   incrementing counters or UUIDs? The TypeScript SDK uses `generateId()`
   which defaults to `nanoid()`. Recommendation: simple counter per stream
   (`txt_1`, `txt_2`, etc.) — deterministic and testable.

5. **Smooth streaming:** The TypeScript SDK has `smoothStream()` that
   buffers text for word-by-word delivery. Recommendation: defer to v2.
   Not needed for correctness, only for UX polish.


1. **Should `stream_text` handle multi-step tool loops?** yes, implement it.

2. **Should we support the `Output` API (structured output)?** defer to v2.

3. **Should we build a cohttp server handler helper?** yes, include it.

4. **ID generation for stream parts:** simple counter per stream
(`txt_1`, `txt_2`, etc.) — deterministic and testable.

5. **Smooth streaming:** defer to v2.

---

## 14. v2 Roadmap

Features deferred from v1, in priority order:

### High Priority

1. **Output API (structured output / schema validation)** — `Output.text()`,
   `Output.object(schema)`, `Output.array(schema)`. Requires JSON Schema
   validation on the response. The `Mode.Object_json` already gets the model
   to produce JSON; this adds parsing + validation + type inference.

2. **Tool approval workflow** — `tool-approval-request` / `tool-output-denied`
   chunk types are already defined. Need `needs_approval` field on `Core_tool.t`
   and a callback mechanism for the server handler to pause and wait for
   approval from the frontend.

3. **Cross-language interop test suite** — Node.js script using
   `readUIMessageStream` from `ai@6` to consume our SSE output and verify
   it parses correctly. Automated CI test.

### Medium Priority

4. **`smoothStream` text buffering** — Buffer text deltas and emit them
   word-by-word for smoother UI rendering. Configurable delay and chunk size.

5. **Telemetry / observability** — OpenTelemetry spans for generate/stream
   calls, tool executions, and step boundaries. Integration with `trace` library.

6. **`stopWhen` predicate for step loop** — Currently we only have `max_steps`.
   Add a `?stop_when:(Generate_text_result.step -> bool)` parameter for
   dynamic termination (matching TypeScript SDK's `stopWhen`).

7. **Retry logic with backoff** — Automatic retry on retryable errors
   (`Rate_limit_error`, `Overloaded_error`) with exponential backoff.

### Low Priority

8. **Image / Embedding / Transcription / Speech models** — Additional model
   type signatures in `ai_provider` and provider implementations.

9. **`convertToModelMessages` / `toResponseMessages`** — Full bidirectional
   message conversion between frontend UIMessage format and provider format,
   including tool invocation state reconstruction.

10. **Provider middleware** — Beyond basic `Middleware.apply`. Caching middleware,
    cost tracking middleware, rate limiting middleware as reusable modules.
