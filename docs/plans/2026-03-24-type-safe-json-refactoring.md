# Type-Safe JSON Refactoring Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace all raw `Yojson.Safe.t` manipulation (manual `Assoc` construction and `Util.member` parsing) with typed OCaml records using `[@@deriving yojson]`, leveraging the type system for compile-time JSON safety.

**Architecture:** Work bottom-up from the blocker (`cache_control.ml`) through the Anthropic provider layer, then the Core SDK. Each task replaces manual JSON code with typed records and `ppx_deriving_yojson` annotations (`[@key]`, `[@default]`, `[@yojson.option]`). Existing tests must continue passing byte-for-byte — this is a refactor, not a behavior change.

**Tech Stack:** OCaml 4.14, ppx_deriving_yojson 3.9.1, yojson 2.2.2, alcotest

**Key ppx_deriving_yojson features used:**
- `[@key "camelCase"]` — map OCaml snake_case to JSON camelCase
- `[@default value]` — default value for missing fields in `of_yojson`
- `[@yojson.option]` — omit field from JSON when `None` (vs `[@default None]` which accepts `null`)
- `[@@deriving yojson]` generates both `to_yojson` and `of_yojson`
- `[@@deriving to_yojson]` / `[@@deriving of_yojson]` — generate only one direction

---

## Task Dependency Graph

```
Task 1: cache_control.ml          (blocker — unblocks 4, 5, 6)
Task 2: convert_usage.ml          (independent — easy win)
Task 3: anthropic_error.ml        (independent — easy win)
Task 4: convert_tools.ml          (depends on 1)
Task 5: convert_prompt.ml         (depends on 1)
Task 6: anthropic_api.ml          (depends on 4, 5)
Task 7: convert_response.ml       (depends on 2)
Task 8: convert_stream.ml         (depends on 2, 7)
Task 9: ui_message_chunk.ml       (independent — biggest change)
Task 10: server_handler.ml        (independent)
```

---

### Task 1: cache_control.ml — Add `[@@deriving yojson]`

**Files:**
- Modify: `lib/ai_provider_anthropic/cache_control.ml`
- Modify: `lib/ai_provider_anthropic/cache_control.mli`

**Why first:** The `to_yojson_fields` pattern (returning `(string * Yojson.Safe.t) list`) blocks ppx derivation in `convert_prompt.ml`, `convert_tools.ml`, and `anthropic_api.ml`. Once `Cache_control.t` has a proper `to_yojson`, parent types can use it as a regular `[@yojson.option]` field.

**Step 1: Update the .ml**

The breakpoint type needs a custom yojson that serializes to `{"type": "ephemeral"}`:

```ocaml
type breakpoint = Ephemeral

type t = { cache_type : breakpoint }

let ephemeral = { cache_type = Ephemeral }

let breakpoint_to_yojson = function
  | Ephemeral -> `Assoc [ "type", `String "ephemeral" ]

let breakpoint_of_yojson = function
  | `Assoc [ ("type", `String "ephemeral") ] -> Ok Ephemeral
  | json -> Error (Printf.sprintf "Unknown cache breakpoint: %s" (Yojson.Safe.to_string json))

type t = { cache_type : breakpoint } [@@deriving yojson]
```

Wait — `ppx_deriving_yojson` needs `breakpoint_to_yojson` and `breakpoint_of_yojson` defined before the deriving. Since `breakpoint` is a simple ADT, we'll hand-write its yojson (it maps to `{"type":"ephemeral"}`, not a string), then derive `t`.

Keep `to_yojson_fields` for backward compatibility but also expose `to_yojson` / `of_yojson`.

**Step 2: Update the .mli**

Add `val to_yojson : t -> Yojson.Safe.t` and `val of_yojson : Yojson.Safe.t -> (t, string) result`.

**Step 3: Run tests**

```bash
dune runtest --force 2>&1 | grep -E 'FAIL|Error|tests run'
```

All 228 tests must pass.

**Step 4: Commit**

---

### Task 2: convert_usage.ml — Derive `of_yojson` for anthropic_usage

**Files:**
- Modify: `lib/ai_provider_anthropic/convert_usage.ml`
- Modify: `lib/ai_provider_anthropic/convert_usage.mli`

**What changes:** Replace 17 lines of manual `int_or_default`/`int_opt`/`member` parsing with `[@@deriving of_yojson]` on the record type.

```ocaml
type anthropic_usage = {
  input_tokens : int; [@default 0]
  output_tokens : int; [@default 0]
  cache_read_input_tokens : int option; [@default None]
  cache_creation_input_tokens : int option; [@default None]
} [@@deriving of_yojson]
```

Remove `int_or_default`, `int_opt`, and the manual `anthropic_usage_of_yojson`.

**Note:** `ppx_deriving_yojson` generates `anthropic_usage_of_yojson : Yojson.Safe.t -> (anthropic_usage, string) result` but the current signature returns `anthropic_usage` (no Result). Add a wrapper:

```ocaml
let anthropic_usage_of_yojson_exn json =
  match anthropic_usage_of_yojson json with
  | Ok u -> u
  | Error msg -> failwith (Printf.sprintf "Failed to parse usage: %s" msg)
```

Update callers (`convert_response.ml:37`, `convert_stream.ml:78`) to use the new signature.

**Step: Run tests, commit.**

---

### Task 3: anthropic_error.ml — Derive `of_yojson` for error response

**Files:**
- Modify: `lib/ai_provider_anthropic/anthropic_error.ml`

**What changes:** Define typed records for the Anthropic error JSON shape and use `[@@deriving of_yojson]`:

```ocaml
type error_detail = {
  typ : string; [@key "type"]
  message : string;
} [@@deriving of_yojson]

type error_wrapper = {
  error : error_detail;
} [@@deriving of_yojson]
```

Replace the manual `Yojson.Safe.Util.member` parsing in `of_response` with:

```ocaml
let error_type, message =
  try
    let json = Yojson.Safe.from_string body in
    match error_wrapper_of_yojson json with
    | Ok { error = { typ; message } } -> Some (error_type_of_string typ), message
    | Error _ -> None, body
  with Yojson.Json_error _ -> None, body
in
```

**Step: Run tests, commit.**

---

### Task 4: convert_tools.ml — Derive `to_yojson` for tool types

**Files:**
- Modify: `lib/ai_provider_anthropic/convert_tools.ml`
- Modify: `lib/ai_provider_anthropic/convert_tools.mli`

**Depends on:** Task 1 (cache_control with `to_yojson`)

**What changes:**

For `anthropic_tool`:
```ocaml
type anthropic_tool = {
  name : string;
  description : string option; [@yojson.option]
  input_schema : Yojson.Safe.t;
  cache_control : Cache_control.t option; [@yojson.option]
} [@@deriving to_yojson]
```

For `anthropic_tool_choice`, we need a custom encoding since the JSON uses `{"type": "auto"}` format (a tagged object, not a standard variant):

```ocaml
let anthropic_tool_choice_to_yojson = function
  | Tc_auto -> `Assoc [ "type", `String "auto" ]
  | Tc_any -> `Assoc [ "type", `String "any" ]
  | Tc_tool { name } -> `Assoc [ "type", `String "tool"; "name", `String name ]
```

**Note:** Keep `anthropic_tool_choice_to_yojson` manual — the JSON format (`{"type": "auto"}`) doesn't map cleanly to ppx_deriving_yojson's variant encoding. This is a legitimate exception.

Remove the manual `anthropic_tool_to_yojson` — let the ppx generate it.

**Step: Run tests, commit.**

---

### Task 5: convert_prompt.ml — Derive `to_yojson` for content types

**Files:**
- Modify: `lib/ai_provider_anthropic/convert_prompt.ml`
- Modify: `lib/ai_provider_anthropic/convert_prompt.mli`

**Depends on:** Task 1 (cache_control with `to_yojson`)

**What changes:** The Anthropic content types serialize to discriminated JSON objects like `{"type": "text", "text": "..."}`. ppx_deriving_yojson's default variant encoding doesn't match this — it would produce `["A_text", {"text": "..."}]`.

**Strategy:** Define flat record types for each JSON shape, derive `to_yojson` on each, and write a manual dispatcher in `anthropic_content_to_yojson`:

```ocaml
type text_json = {
  type_ : string; [@key "type"]
  text : string;
  cache_control : Cache_control.t option; [@yojson.option]
} [@@deriving to_yojson]

type image_source_base64_json = {
  type_ : string; [@key "type"]
  media_type : string;
  data : string;
} [@@deriving to_yojson]

type image_source_url_json = {
  type_ : string; [@key "type"]
  url : string;
} [@@deriving to_yojson]

type image_json = {
  type_ : string; [@key "type"]
  source : Yojson.Safe.t;
  cache_control : Cache_control.t option; [@yojson.option]
} [@@deriving to_yojson]

type document_json = {
  type_ : string; [@key "type"]
  source : Yojson.Safe.t;
  cache_control : Cache_control.t option; [@yojson.option]
} [@@deriving to_yojson]

type tool_use_json = {
  type_ : string; [@key "type"]
  id : string;
  name : string;
  input : Yojson.Safe.t;
} [@@deriving to_yojson]

type tool_result_content_json = {
  type_ : string; [@key "type"]
  text : string option; [@yojson.option]
  source : Yojson.Safe.t option; [@yojson.option]
} [@@deriving to_yojson]

type tool_result_json = {
  type_ : string; [@key "type"]
  tool_use_id : string;
  content : Yojson.Safe.t list;
  is_error : bool;
} [@@deriving to_yojson]

type thinking_json = {
  type_ : string; [@key "type"]
  thinking : string;
  signature : string;
} [@@deriving to_yojson]

type message_json = {
  role : string;
  content : Yojson.Safe.t list;
} [@@deriving to_yojson]
```

Then `anthropic_content_to_yojson` maps each variant → the appropriate JSON record → `to_yojson`. This keeps the type discriminant handling manual (it must be, since Anthropic's `{"type": "text"}` format doesn't match ppx variant encoding) but makes the field serialization type-safe.

**Step: Run tests, commit.**

---

### Task 6: anthropic_api.ml — Derive `to_yojson` for request body

**Files:**
- Modify: `lib/ai_provider_anthropic/anthropic_api.ml`
- Modify: `lib/ai_provider_anthropic/anthropic_api.mli`

**Depends on:** Tasks 4 and 5

**What changes:** Define a typed request body record:

```ocaml
type thinking_config = {
  type_ : string; [@key "type"]
  budget_tokens : int;
} [@@deriving to_yojson]

type request_body = {
  model : string;
  messages : Yojson.Safe.t list;
  system : string option; [@yojson.option]
  tools : Yojson.Safe.t list option; [@yojson.option]
  tool_choice : Yojson.Safe.t option; [@yojson.option]
  max_tokens : int;
  temperature : float option; [@yojson.option]
  top_p : float option; [@yojson.option]
  top_k : int option; [@yojson.option]
  stop_sequences : string list option; [@yojson.option]
  thinking : thinking_config option; [@yojson.option]
  stream : bool option; [@yojson.option]
} [@@deriving to_yojson]
```

**Note:** `messages`, `tools`, `tool_choice` remain `Yojson.Safe.t` because they come from already-typed `to_yojson` calls on `anthropic_message`, `anthropic_tool`, `anthropic_tool_choice`. The alternative is to make them fully typed (e.g., `messages : anthropic_message list`) but that requires `anthropic_message` to also have `[@@deriving to_yojson]` which Task 5 addresses. Consider making them fully typed if Task 5 exposes the JSON record types.

`make_request_body` becomes: build the `request_body` record, call `request_body_to_yojson`.

**Important:** `[@yojson.option]` omits the field when `None`, which matches the current behavior of the `opt` helper. Empty `tools` list should also be omitted (currently `Some []` → omitted). Handle this by mapping `Some [] -> None` before constructing the record.

**Step: Run tests, commit.**

---

### Task 7: convert_response.ml — Derive `of_yojson` for response types

**Files:**
- Modify: `lib/ai_provider_anthropic/convert_response.ml`
- Modify: `lib/ai_provider_anthropic/convert_response.mli`

**Depends on:** Task 2 (typed anthropic_usage)

**What changes:** Define typed records for each Anthropic response content block:

```ocaml
type text_block = { text : string } [@@deriving of_yojson]

type tool_use_block = {
  id : string;
  name : string;
  input : Yojson.Safe.t;
} [@@deriving of_yojson]

type thinking_block = {
  thinking : string;
  signature : string option; [@default None]
} [@@deriving of_yojson]

type content_block = {
  type_ : string; [@key "type"]
  text : string option; [@default None]
  id : string option; [@default None]
  name : string option; [@default None]
  input : Yojson.Safe.t option; [@default None]
  thinking : string option; [@default None]
  signature : string option; [@default None]
} [@@deriving of_yojson]

type anthropic_response = {
  id : string option; [@default None]
  model : string option; [@default None]
  content : content_block list;
  stop_reason : string option; [@default None]
  usage : Convert_usage.anthropic_usage;
} [@@deriving of_yojson]
```

**Strategy choice:** Two approaches:
1. **Flat record** with all optional fields + manual dispatch on `type_` — simpler, less type-safe
2. **Separate records per type** with a discriminator parser — more type-safe

Use approach 1 for the content block (since the discriminator is in the JSON `type` field) and parse to the SDK `Content.t` variant via pattern matching on `type_`. Use approach 2 for the top-level response.

**Step: Run tests, commit.**

---

### Task 8: convert_stream.ml — Derive `of_yojson` for SSE event types

**Files:**
- Modify: `lib/ai_provider_anthropic/convert_stream.ml`

**Depends on:** Tasks 2 and 7

**What changes:** Define typed records for each SSE event shape:

```ocaml
type content_block_start_data = {
  index : int;
  content_block : content_block_info;
} [@@deriving of_yojson]

and content_block_info = {
  type_ : string; [@key "type"]
  id : string option; [@default None]
  name : string option; [@default None]
} [@@deriving of_yojson]

type text_delta = { text : string } [@@deriving of_yojson]
type input_json_delta = { partial_json : string } [@@deriving of_yojson]
type thinking_delta = { thinking : string } [@@deriving of_yojson]

type content_block_delta_data = {
  index : int;
  delta : delta_info;
} [@@deriving of_yojson]

and delta_info = {
  type_ : string; [@key "type"]
  text : string option; [@default None]
  partial_json : string option; [@default None]
  thinking : string option; [@default None]
} [@@deriving of_yojson]

type content_block_stop_data = {
  index : int;
} [@@deriving of_yojson]

type message_delta_wrapper = {
  delta : message_delta;
  usage : Convert_usage.anthropic_usage option; [@default None]
} [@@deriving of_yojson]

and message_delta = {
  stop_reason : string option; [@default None]
} [@@deriving of_yojson]

type error_data = {
  type_ : string; [@key "type"] [@default "unknown"]
  message : string; [@default ""]
} [@@deriving of_yojson]
```

The event type dispatching (`match evt.event_type with`) stays manual since it's a separate SSE field, but the JSON parsing within each branch becomes typed.

**Step: Run tests, commit.**

---

### Task 9: ui_message_chunk.ml — Derive `to_yojson` for UIMessage chunks

**Files:**
- Modify: `lib/ai_core/ui_message_chunk.ml`
- Modify: `lib/ai_core/ui_message_chunk.mli`

**What changes:** This is the biggest single change — 24 manual `Assoc` constructions. Define a JSON record type for each variant and derive `to_yojson`:

```ocaml
(* JSON records for each chunk type *)
type start_json = {
  type_ : string; [@key "type"]
  message_id : string option; [@key "messageId"] [@yojson.option]
  message_metadata : Yojson.Safe.t option; [@key "messageMetadata"] [@yojson.option]
} [@@deriving to_yojson]

type finish_json = {
  type_ : string; [@key "type"]
  finish_reason : string option; [@key "finishReason"] [@yojson.option]
  message_metadata : Yojson.Safe.t option; [@key "messageMetadata"] [@yojson.option]
} [@@deriving to_yojson]

(* ... etc for all 24 variants ... *)
```

Then `to_yojson` maps each variant to the appropriate record → `xxx_json_to_yojson`.

**Critical:** All camelCase field names must use `[@key]` annotations:
- `message_id` → `[@key "messageId"]`
- `tool_call_id` → `[@key "toolCallId"]`
- `tool_name` → `[@key "toolName"]`
- `input_text_delta` → `[@key "inputTextDelta"]`
- `finish_reason` → `[@key "finishReason"]`
- `error_text` → `[@key "errorText"]`
- `source_id` → `[@key "sourceId"]`
- `media_type` → `[@key "mediaType"]`
- `message_metadata` → `[@key "messageMetadata"]`
- `data_type` → removed (computed as `"data-{data_type}"`)

**Important:** The SSE snapshot tests (`test_sse_snapshots.ml`) verify byte-exact JSON output. Any field ordering change will break them. `ppx_deriving_yojson` emits fields in declaration order, so declare record fields in the same order as the current manual `Assoc` lists.

**Also remove:** Helper functions `obj`, `some`, `opt_string`, `opt_json` — no longer needed.

**Step: Run tests (especially SSE snapshots), commit.**

---

### Task 10: server_handler.ml — Derive `of_yojson` for request parsing

**Files:**
- Modify: `lib/ai_core/server_handler.ml`

**What changes:** Define typed records for the incoming chat request:

```ocaml
type message_part = {
  type_ : string; [@key "type"]
  text : string option; [@default None]
} [@@deriving of_yojson]

type chat_message = {
  role : string;
  content : string option; [@default None]
  parts : message_part list option; [@default None]
} [@@deriving of_yojson]

type chat_request = {
  messages : chat_message list;
} [@@deriving of_yojson]
```

Replace `extract_text_from_message` and `parse_messages_from_body` with typed parsing:

```ocaml
let extract_text_from_message (msg : chat_message) =
  match msg.parts with
  | Some parts ->
    parts
    |> List.filter_map (fun (p : message_part) ->
      match p.type_, p.text with
      | "text", Some t -> Some t
      | _ -> None)
    |> String.concat ""
  | None ->
    Option.value ~default:"" msg.content
```

**Step: Run tests, commit.**

---

## Verification Checklist

After all tasks:
1. `dune build` — zero warnings, zero errors
2. `dune runtest --force` — all 228 tests pass
3. SSE snapshot tests pass byte-for-byte
4. `grep -r 'Yojson.Safe.Util' lib/` — only in files with legitimate dynamic parsing
5. `grep -r '`Assoc' lib/` — only in: (a) anthropic_tool_choice custom encoding, (b) cache_control custom breakpoint encoding, (c) any genuinely dynamic JSON
6. No `Yojson.Safe.t` in type definitions where the shape is known (except tool args/results which are user-defined)
