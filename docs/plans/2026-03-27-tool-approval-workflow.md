# Tool Approval Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a stateless tool approval workflow matching the upstream AI SDK's `needsApproval` pattern — tools can require human approval before execution, the step loop pauses and emits approval-request chunks, and the frontend re-submits with approval decisions.

**Architecture:** The step loop partitions tool calls into "ready to execute" and "needs approval". When any tool needs approval, the step finishes without executing any tools, emitting `Tool_approval_request` chunks. On re-submit, the server handler parses `approval-responded` parts and either executes (approved) or denies (rejected) the tools. This is stateless — no long-lived connections or `Lwt_mvar`.

**Tech Stack:** OCaml 4.14, Lwt, melange-json-native (typed JSON derivers), Alcotest

---

### Task 1: Add `needs_approval` to `Core_tool.t`

**Files:**
- Modify: `lib/ai_core/core_tool.ml`
- Modify: `lib/ai_core/core_tool.mli`

**Step 1: Write the failing test**

Create test file `test/ai_core/test_core_tool.ml`:

```ocaml
open Alcotest

let test_tool_without_approval () =
  let tool : Ai_core.Core_tool.t =
    Ai_core.Core_tool.create
      ~description:"test"
      ~parameters:(`Assoc [ "type", `String "object" ])
      ~execute:(fun _ -> Lwt.return (`String "ok"))
      ()
  in
  (check bool) "no approval" true (Option.is_none tool.needs_approval)

let test_tool_with_static_approval () =
  let tool =
    Ai_core.Core_tool.create_with_approval
      ~description:"dangerous"
      ~parameters:(`Assoc [ "type", `String "object" ])
      ~execute:(fun _ -> Lwt.return (`String "ok"))
      ()
  in
  (check bool) "has approval" true (Option.is_some tool.needs_approval);
  let needs = Lwt_main.run ((Option.get tool.needs_approval) `Null) in
  (check bool) "always true" true needs

let test_tool_with_dynamic_approval () =
  let tool =
    Ai_core.Core_tool.create
      ~description:"conditional"
      ~parameters:(`Assoc [ "type", `String "object" ])
      ~needs_approval:(fun args ->
        match args with
        | `Assoc props ->
          (match List.assoc_opt "amount" props with
           | Some (`Int n) -> Lwt.return (n > 1000)
           | _ -> Lwt.return_false)
        | _ -> Lwt.return_false)
      ~execute:(fun _ -> Lwt.return (`String "ok"))
      ()
  in
  let needs_high = Lwt_main.run ((Option.get tool.needs_approval) (`Assoc [ "amount", `Int 5000 ])) in
  let needs_low = Lwt_main.run ((Option.get tool.needs_approval) (`Assoc [ "amount", `Int 100 ])) in
  (check bool) "high amount needs approval" true needs_high;
  (check bool) "low amount no approval" false needs_low

let () =
  run "Core_tool"
    [
      "create",
      [
        test_case "without_approval" `Quick test_tool_without_approval;
        test_case "static_approval" `Quick test_tool_with_static_approval;
        test_case "dynamic_approval" `Quick test_tool_with_dynamic_approval;
      ];
    ]
```

**Step 2: Run test to verify it fails**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core/test_core_tool.exe 2>&1
```
Expected: FAIL — `Ai_core.Core_tool.create` and `create_with_approval` don't exist, `needs_approval` field missing.

**Step 3: Add `test_core_tool` to dune**

In `test/ai_core/dune`, add `test_core_tool` to the `names` list.

**Step 4: Implement `Core_tool.t` changes**

`lib/ai_core/core_tool.mli`:
```ocaml
(** Tool definition for the Core SDK.

    Tools have a description, JSON Schema parameters, and an execute function
    that takes JSON args and returns JSON results. Tools can optionally require
    approval before execution via [needs_approval]. *)

type t = {
  description : string option;
  parameters : Yojson.Basic.t;  (** JSON Schema for tool parameters *)
  execute : Yojson.Basic.t -> Yojson.Basic.t Lwt.t;  (** Execute the tool. Args and result are both JSON. *)
  needs_approval : (Yojson.Basic.t -> bool Lwt.t) option;
    (** If [Some f], call [f args] before execution. If [true], emit an approval
        request instead of executing. [None] means execute immediately. *)
}

(** Create a tool. If [~needs_approval] is provided, the tool will require
    approval when the predicate returns [true]. *)
val create :
  ?description:string ->
  ?needs_approval:(Yojson.Basic.t -> bool Lwt.t) ->
  parameters:Yojson.Basic.t ->
  execute:(Yojson.Basic.t -> Yojson.Basic.t Lwt.t) ->
  unit -> t

(** Create a tool that always requires approval before execution. *)
val create_with_approval :
  ?description:string ->
  parameters:Yojson.Basic.t ->
  execute:(Yojson.Basic.t -> Yojson.Basic.t Lwt.t) ->
  unit -> t

(** Parse a JSON string, falling back to [`String s] on parse error. *)
val safe_parse_json_args : string -> Yojson.Basic.t
```

`lib/ai_core/core_tool.ml`:
```ocaml
type t = {
  description : string option;
  parameters : Yojson.Basic.t;
  execute : Yojson.Basic.t -> Yojson.Basic.t Lwt.t;
  needs_approval : (Yojson.Basic.t -> bool Lwt.t) option;
}

let create ?description ?needs_approval ~parameters ~execute () =
  { description; parameters; execute; needs_approval }

let create_with_approval ?description ~parameters ~execute () =
  { description; parameters; execute; needs_approval = Some (fun _ -> Lwt.return_true) }

let safe_parse_json_args s = try Yojson.Basic.from_string s with Yojson.Json_error _ -> `String s
```

**Step 5: Fix existing code that constructs `Core_tool.t` records directly**

The existing test files construct `Core_tool.t` as raw records without `needs_approval`. Add `needs_approval = None` to every existing record literal in:
- `test/ai_core/test_generate_text.ml:82-90` (the `search_tool`)
- `test/ai_core/test_stream_text.ml:84-92` (the `search_tool`)
- Any other test files that construct `Core_tool.t` directly

Search with: `grep -rn "Core_tool.t" test/` and `grep -rn ": Ai_core.Core_tool.t" test/`

**Step 6: Run tests to verify they pass**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core 2>&1
```
Expected: ALL PASS

**Step 7: Commit**

```bash
git add lib/ai_core/core_tool.ml lib/ai_core/core_tool.mli test/ai_core/test_core_tool.ml test/ai_core/dune
git add -u  # catch any test files that needed needs_approval = None
git commit -m "feat(core_tool): add needs_approval field and create/create_with_approval constructors"
```

---

### Task 2: Add `Tool_approval_request` to `Text_stream_part.t`

**Files:**
- Modify: `lib/ai_core/text_stream_part.ml`

**Step 1: Add the variant**

Add to `text_stream_part.ml` after `Tool_result`:
```ocaml
  | Tool_approval_request of {
      tool_call_id : string;
      tool_name : string;
      args : Yojson.Basic.t;
    }
```

**Step 2: Build to check for exhaustiveness warnings**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune build 2>&1
```

Fix any non-exhaustive pattern match warnings (likely in `stream_text_result.ml` `to_ui_message_stream`). For now, add a placeholder match arm that does nothing — the chunk mapping will be implemented in Task 3.

**Step 3: Commit**

```bash
git add lib/ai_core/text_stream_part.ml
git add -u  # any files that needed exhaustiveness fixes
git commit -m "feat(text_stream_part): add Tool_approval_request variant"
```

---

### Task 3: Add `Tool_approval_request` chunk to `Ui_message_chunk`

**Files:**
- Modify: `lib/ai_core/ui_message_chunk.ml`
- Modify: `lib/ai_core/ui_message_chunk.mli`
- Modify: `test/ai_core/test_ui_message_chunk.ml`

**Step 1: Write the failing test**

Add to `test/ai_core/test_ui_message_chunk.ml`:
```ocaml
let test_tool_approval_request () =
  let chunk =
    Ai_core.Ui_message_chunk.Tool_approval_request
      { tool_call_id = "tc_1"; tool_name = "weather"; input = `Assoc [ "city", `String "London" ] }
  in
  let json = Ai_core.Ui_message_chunk.to_json chunk in
  let json_str = Yojson.Basic.to_string json in
  (check string) "type"
    {|{"type":"tool-approval-request","toolCallId":"tc_1","toolName":"weather","input":{"city":"London"}}|}
    json_str
```

**Step 2: Run test to verify it fails**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core/test_ui_message_chunk.exe 2>&1
```

**Step 3: Add the chunk variant and JSON type**

In `ui_message_chunk.mli`, add after `Tool_output_denied`:
```ocaml
  | Tool_approval_request of {
      tool_call_id : string;
      tool_name : string;
      input : Yojson.Basic.t;
    }
```

In `ui_message_chunk.ml`, add the variant in the same position.

Add the JSON serialization type (reuse `tool_input_available_json` since it has the same shape: `type_`, `toolCallId`, `toolName`, `input`):

In `to_json`, add:
```ocaml
  | Tool_approval_request { tool_call_id; tool_name; input } ->
    tool_input_available_json_to_json { type_ = "tool-approval-request"; tool_call_id; tool_name; input }
```

**Step 4: Run tests to verify they pass**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core 2>&1
```

**Step 5: Commit**

```bash
git add lib/ai_core/ui_message_chunk.ml lib/ai_core/ui_message_chunk.mli test/ai_core/test_ui_message_chunk.ml
git commit -m "feat(ui_message_chunk): add Tool_approval_request chunk type"
```

---

### Task 4: Wire `Tool_approval_request` through `stream_text_result.ml`

**Files:**
- Modify: `lib/ai_core/stream_text_result.ml`
- Modify: `test/ai_core/test_to_ui_stream.ml`

**Step 1: Write the failing test**

Add to `test/ai_core/test_to_ui_stream.ml` a test that emits a `Tool_approval_request` stream part and verifies it becomes a `Tool_approval_request` chunk. The test should:
- Create a mock stream that emits `Start`, `Start_step`, `Tool_call_delta`, `Tool_call`, `Tool_approval_request`, `Finish_step`, `Finish`
- Convert to UI stream via `Stream_text_result.to_ui_message_stream`
- Assert the output contains `Tool_input_start`, `Tool_input_available`, `Tool_approval_request` chunks (and NO `Tool_output_*` chunks)

**Step 2: Implement the mapping**

In `stream_text_result.ml` `to_ui_message_stream`, add the match arm:
```ocaml
          | Tool_approval_request { tool_call_id; tool_name; args } ->
            (* Emit Tool_input_start if not already sent *)
            if not (Hashtbl.mem started_tools tool_call_id) then begin
              Hashtbl.replace started_tools tool_call_id tool_name;
              push (Some (Ui_message_chunk.Tool_input_start { tool_call_id; tool_name }))
            end;
            (* Emit Tool_input_available if not already sent *)
            push (Some (Ui_message_chunk.Tool_input_available { tool_call_id; tool_name; input = args }));
            Hashtbl.remove started_tools tool_call_id;
            (* Emit the approval request *)
            push (Some (Ui_message_chunk.Tool_approval_request { tool_call_id; tool_name; input = args }))
```

**Step 3: Run tests**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core 2>&1
```

**Step 4: Commit**

```bash
git add lib/ai_core/stream_text_result.ml test/ai_core/test_to_ui_stream.ml
git commit -m "feat(stream_text_result): map Tool_approval_request to UI chunks"
```

---

### Task 5: Implement approval partitioning in `generate_text.ml`

**Files:**
- Modify: `lib/ai_core/generate_text.ml`
- Modify: `test/ai_core/test_generate_text.ml`

**Step 1: Write the failing tests**

Add to `test/ai_core/test_generate_text.ml`:

```ocaml
(* Mock model that returns a tool call — used with approval tools *)
let make_single_tool_call_model () =
  let module M : Ai_provider.Language_model.S = struct
    let specification_version = "V3"
    let provider = "mock"
    let model_id = "mock-approval"
    let generate _opts =
      Lwt.return
        {
          Ai_provider.Generate_result.content =
            [
              Ai_provider.Content.Text { text = "Let me check." };
              Ai_provider.Content.Tool_call
                {
                  tool_call_type = "function";
                  tool_call_id = "tc_1";
                  tool_name = "dangerous_action";
                  args = {|{"target":"prod"}|};
                };
            ];
          finish_reason = Ai_provider.Finish_reason.Tool_calls;
          usage = { input_tokens = 10; output_tokens = 15; total_tokens = Some 25 };
          warnings = [];
          provider_metadata = Ai_provider.Provider_options.empty;
          request = { body = `Null };
          response = { id = Some "r1"; model = Some "mock-approval"; headers = []; body = `Null };
        }
    let stream _opts =
      let stream, push = Lwt_stream.create () in
      push None;
      Lwt.return { Ai_provider.Stream_result.stream; warnings = []; raw_response = None }
  end in
  (module M : Ai_provider.Language_model.S)

let approval_tool : Ai_core.Core_tool.t =
  Ai_core.Core_tool.create_with_approval
    ~description:"Dangerous"
    ~parameters:(`Assoc [ "type", `String "object" ])
    ~execute:(fun _ -> Lwt.return (`String "executed"))
    ()

let test_approval_stops_loop () =
  let model = make_single_tool_call_model () in
  let result =
    Lwt_main.run
      (Ai_core.Generate_text.generate_text ~model ~prompt:"Do it"
         ~tools:[ "dangerous_action", approval_tool ]
         ~max_steps:3 ())
  in
  (* Should stop after 1 step — tool not executed *)
  (check int) "1 step" 1 (List.length result.steps);
  (check int) "1 tool call" 1 (List.length result.tool_calls);
  (check int) "0 tool results" 0 (List.length result.tool_results);
  (* The step should have tool_calls but no tool_results *)
  let step = List.hd result.steps in
  (check int) "step has 1 tool call" 1 (List.length step.tool_calls);
  (check int) "step has 0 tool results" 0 (List.length step.tool_results)

let test_no_approval_tool_executes_normally () =
  let model = make_tool_model () in
  let no_approval_tool : Ai_core.Core_tool.t =
    Ai_core.Core_tool.create
      ~description:"Search"
      ~parameters:(`Assoc [ "type", `String "object" ])
      ~execute:(fun args ->
        let query = try (query_args_of_json args).query with _ -> "unknown" in
        Lwt.return (`String (Printf.sprintf "Results for: %s" query)))
      ()
  in
  let result =
    Lwt_main.run
      (Ai_core.Generate_text.generate_text ~model ~prompt:"Search"
         ~tools:[ "search", no_approval_tool ]
         ~max_steps:3 ())
  in
  (* Should execute normally — 2 steps *)
  (check int) "2 steps" 2 (List.length result.steps);
  (check int) "1 tool result" 1 (List.length result.tool_results)

let test_dynamic_approval_conditional () =
  let model = make_single_tool_call_model () in
  (* This tool only needs approval when target is "prod" *)
  let conditional_tool =
    Ai_core.Core_tool.create
      ~description:"Conditional"
      ~parameters:(`Assoc [ "type", `String "object" ])
      ~needs_approval:(fun args ->
        match args with
        | `Assoc props ->
          (match List.assoc_opt "target" props with
           | Some (`String "prod") -> Lwt.return_true
           | _ -> Lwt.return_false)
        | _ -> Lwt.return_false)
      ~execute:(fun _ -> Lwt.return (`String "executed"))
      ()
  in
  let result =
    Lwt_main.run
      (Ai_core.Generate_text.generate_text ~model ~prompt:"Do it"
         ~tools:[ "dangerous_action", conditional_tool ]
         ~max_steps:3 ())
  in
  (* target=prod triggers approval, so loop stops *)
  (check int) "1 step" 1 (List.length result.steps);
  (check int) "0 tool results" 0 (List.length result.tool_results)
```

**Step 2: Run tests to verify they fail**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core/test_generate_text.exe 2>&1
```

**Step 3: Implement approval partitioning in `generate_text.ml`**

In the `should_continue` branch (around line 112), before executing tools, add the approval check:

```ocaml
      if should_continue then begin
        (* Check which tools need approval *)
        let%lwt needs_approval =
          Lwt_list.exists_s
            (fun (tc : Generate_text_result.tool_call) ->
              match List.assoc_opt tc.tool_name tools with
              | Some tool ->
                (match tool.Core_tool.needs_approval with
                 | Some check -> check tc.args
                 | None -> Lwt.return_false)
              | None -> Lwt.return_false)
            tool_calls
        in
        if needs_approval then begin
          (* Stop the loop — tools need approval before execution *)
          let step : Generate_text_result.step =
            { text; reasoning; tool_calls; tool_results = []; finish_reason = result.finish_reason; usage = result.usage }
          in
          Option.iter (fun f -> f step) on_step_finish;
          let all_steps = List.rev (step :: steps) in
          let parsed_output = Output.parse_output output all_steps in
          Lwt.return
            {
              Generate_text_result.text = Generate_text_result.join_text all_steps;
              reasoning = Generate_text_result.join_reasoning all_steps;
              tool_calls = List.rev (List.rev_append tool_calls all_tool_calls);
              tool_results = List.rev all_tool_results;
              steps = all_steps;
              finish_reason = result.finish_reason;
              usage = new_usage;
              response = result.response;
              warnings = result.warnings;
              output = parsed_output;
            }
        end
        else begin
          (* Original tool execution code — unchanged *)
          ...
        end
      end
```

**Step 4: Run tests**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core 2>&1
```

**Step 5: Commit**

```bash
git add lib/ai_core/generate_text.ml test/ai_core/test_generate_text.ml
git commit -m "feat(generate_text): stop step loop when tools need approval"
```

---

### Task 6: Implement approval partitioning in `stream_text.ml`

**Files:**
- Modify: `lib/ai_core/stream_text.ml`
- Modify: `test/ai_core/test_stream_text.ml`

**Step 1: Write the failing tests**

Add to `test/ai_core/test_stream_text.ml`:

```ocaml
(* Mock model that streams a tool call needing approval *)
let make_approval_stream_model () =
  let module M : Ai_provider.Language_model.S = struct
    let specification_version = "V3"
    let provider = "mock"
    let model_id = "mock-approval-stream"
    let generate _opts = Lwt.fail_with "not implemented"
    let stream _opts =
      let stream, push = Lwt_stream.create () in
      push (Some (Ai_provider.Stream_part.Stream_start { warnings = [] }));
      push (Some (Ai_provider.Stream_part.Text { text = "Let me check." }));
      push
        (Some
           (Ai_provider.Stream_part.Tool_call_delta
              {
                tool_call_type = "function";
                tool_call_id = "tc_1";
                tool_name = "dangerous_action";
                args_text_delta = {|{"target":"prod"}|};
              }));
      push (Some (Ai_provider.Stream_part.Tool_call_finish { tool_call_id = "tc_1" }));
      push
        (Some
           (Ai_provider.Stream_part.Finish
              { finish_reason = Tool_calls; usage = { input_tokens = 10; output_tokens = 8; total_tokens = Some 18 } }));
      push None;
      Lwt.return { Ai_provider.Stream_result.stream; warnings = []; raw_response = None }
  end in
  (module M : Ai_provider.Language_model.S)

let approval_tool : Ai_core.Core_tool.t =
  Ai_core.Core_tool.create_with_approval
    ~description:"Dangerous"
    ~parameters:(`Assoc [ "type", `String "object" ])
    ~execute:(fun _ -> Lwt.return (`String "executed"))
    ()

let test_approval_stops_stream_loop () =
  let model = make_approval_stream_model () in
  let result =
    Ai_core.Stream_text.stream_text ~model ~prompt:"Do it"
      ~tools:[ "dangerous_action", approval_tool ]
      ~max_steps:3 ()
  in
  let parts = Lwt_main.run (Lwt_stream.to_list result.full_stream) in
  (* Should have Tool_approval_request, NO Tool_result *)
  let has_approval =
    List.exists
      (fun p ->
        match p with
        | Ai_core.Text_stream_part.Tool_approval_request _ -> true
        | _ -> false)
      parts
  in
  let has_tool_result =
    List.exists
      (fun p ->
        match p with
        | Ai_core.Text_stream_part.Tool_result _ -> true
        | _ -> false)
      parts
  in
  (check bool) "has approval request" true has_approval;
  (check bool) "no tool result" false has_tool_result;
  (* Should have 1 step with tool_calls but no tool_results *)
  let steps = Lwt_main.run result.steps in
  (check int) "1 step" 1 (List.length steps);
  let step = List.hd steps in
  (check int) "1 tool call" 1 (List.length step.tool_calls);
  (check int) "0 tool results" 0 (List.length step.tool_results)
```

**Step 2: Run test to verify it fails**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core/test_stream_text.exe 2>&1
```

**Step 3: Implement approval check in `stream_text.ml`**

In the `should_continue` branch (around line 205), before tool execution, add the same approval check pattern as `generate_text.ml`:

```ocaml
        if should_continue then begin
          (* Check if any tools need approval *)
          let%lwt needs_approval =
            Lwt_list.exists_s
              (fun (tc : Generate_text_result.tool_call) ->
                match List.assoc_opt tc.tool_name tools with
                | Some tool ->
                  (match tool.Core_tool.needs_approval with
                   | Some check -> check tc.args
                   | None -> Lwt.return_false)
                | None -> Lwt.return_false)
              tool_calls
          in
          if needs_approval then begin
            (* Emit approval requests for tools that need them *)
            List.iter
              (fun (tc : Generate_text_result.tool_call) ->
                match List.assoc_opt tc.tool_name tools with
                | Some tool when Option.is_some tool.Core_tool.needs_approval ->
                  emit_event
                    (Text_stream_part.Tool_approval_request
                       { tool_call_id = tc.tool_call_id; tool_name = tc.tool_name; args = tc.args })
                | _ -> ())
              tool_calls;
            (* Finish the step and stream without executing tools *)
            let step : Generate_text_result.step =
              { text; reasoning; tool_calls; tool_results = []; finish_reason = fr; usage = step_usage }
            in
            Option.iter (fun f -> f step) on_step_finish;
            emit_event (Text_stream_part.Finish_step { finish_reason = fr; usage = step_usage });
            emit_event (Text_stream_part.Finish { finish_reason = fr; usage = new_total });
            push_full None;
            let all_steps = List.rev (step :: steps) in
            let parsed_output = Output.parse_output output all_steps in
            partial_output_push None;
            Lwt.wakeup_later usage_resolver new_total;
            Lwt.wakeup_later finish_resolver fr;
            Lwt.wakeup_later steps_resolver all_steps;
            Lwt.wakeup_later output_resolver parsed_output;
            (match on_finish with
            | Some f ->
              let all_tool_calls = List.concat_map (fun (s : Generate_text_result.step) -> s.tool_calls) all_steps in
              f
                {
                  Generate_text_result.text = Generate_text_result.join_text all_steps;
                  reasoning = Generate_text_result.join_reasoning all_steps;
                  tool_calls = all_tool_calls;
                  tool_results = [];
                  steps = all_steps;
                  finish_reason = fr;
                  usage = new_total;
                  response = { id = None; model = None; headers = []; body = `Null };
                  warnings = [];
                  output = parsed_output;
                }
            | None -> ());
            Lwt.return_unit
          end
          else begin
            (* Original tool execution code — unchanged *)
            ...
          end
        end
```

Note: The approval request emission iterates tool_calls and only emits `Tool_approval_request` for tools that have `needs_approval`. Tools without it still won't be executed in this step — the whole step pauses. This matches upstream where a mixed step stops entirely.

**Step 4: Run tests**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core 2>&1
```

**Step 5: Commit**

```bash
git add lib/ai_core/stream_text.ml test/ai_core/test_stream_text.ml
git commit -m "feat(stream_text): stop step loop and emit approval requests when tools need approval"
```

---

### Task 7: Parse `approval-responded` in `server_handler.ml`

**Files:**
- Modify: `lib/ai_core/server_handler.ml`
- Modify: `test/ai_core/test_server_handler.ml`

**Step 1: Write the failing tests**

Add to `test/ai_core/test_server_handler.ml` tests for:

1. A tool part with `state: "approval-responded"` and an `approved` field set to `false` should produce a tool result with `is_error = true` and result `"Tool execution denied"` (same as `output-denied`).

2. A tool part with `state: "approval-responded"` and `approved: true` should NOT produce a tool result (the tool hasn't been executed yet — the step loop will execute it on re-run).

The key insight: when `approved: true`, the server handler should still emit a `Tool` message with a special marker so the step loop knows to execute. But actually, looking at the upstream behavior more carefully: when the user approves, the frontend re-sends all messages. The tool part in the re-sent message will have `state: "approval-responded"` with `approved: true`. The server handler should treat this the same as `input-available` — just include the tool call in the assistant message, but don't add a tool result. The step loop will then see the tool call, check `needs_approval` → but this time we need to skip the approval check because the user already approved.

**Revised approach:** Add an `approved` field to `parsed_part`:

In `server_handler.ml` `parsed_part`:
```ocaml
  approved : bool option; [@json.option]
```

Then in `parse_tool_result`:
```ocaml
    | Some Approval_responded, Some tool_call_id, Some tool_name ->
      (match p.approved with
       | Some true ->
         (* Approved — don't add a tool result. The tool call is already in the
            assistant message. But we need to signal that execution should proceed.
            We return a special "approved" tool result that the step loop recognizes. *)
         None  (* No tool result — the step loop will execute this tool *)
       | _ ->
         (* Denied *)
         Some
           {
             Ai_provider.Prompt.tool_call_id;
             tool_name;
             result = `String "Tool execution denied";
             is_error = true;
             content = [];
             provider_options = empty_opts;
           })
```

Wait — this creates a problem. If approved, we need the step loop to execute the tool, but the step loop will check `needs_approval` again and stop. We need a way to tell the step loop "this tool was already approved, skip the approval check."

**Solution:** Add a set of pre-approved tool call IDs passed through the call chain. The server handler collects approved tool call IDs from the message history, and passes them to `stream_text` / `generate_text`. The step loop skips `needs_approval` for those IDs.

This requires:
- `server_handler.ml`: collect approved IDs from parsed messages
- `stream_text.ml` / `generate_text.ml`: accept `?approved_tool_call_ids:string list` parameter
- Step loop: skip approval check for IDs in the list

Actually, a simpler approach: **the server handler just doesn't include `approved-responded` parts as tool results at all**. When the frontend re-sends with approved tools, the tool call is in the assistant message, and there's no tool result — so the step loop treats it like a fresh tool call and tries to execute. But then `needs_approval` fires again...

**Simplest correct approach:** The step loop already has the tool calls from the assistant message. For the re-submission, the `approval-responded` with `approved: true` means "execute this tool." We can:

1. For `approved: true`: return a tool result with a special sentinel, like `result = `String "__approved__"` with `is_error = false`. The step loop sees a tool result already exists and doesn't re-execute.

No — that's wrong. We want the tool to actually execute.

**Final approach (matching upstream):** The upstream SDK handles this at the `generateText` level. When it sees tool calls without tool results in the message history, AND the message history contains approval responses, it knows to execute those tools. The simplest way for us:

- `server_handler` collects approved tool call IDs
- Passes `~approved_tool_call_ids` to `stream_text`/`generate_text`
- The step loop, when checking `needs_approval`, skips the check for pre-approved IDs

This is clean and explicit.

Add to `parsed_part`:
```ocaml
  approved : bool option; [@json.option]
```

Add a helper to extract approved IDs:
```ocaml
let collect_approved_tool_ids (messages : Ai_provider.Prompt.message list) body_json =
  (* Parse approval-responded parts from the raw JSON to get approved IDs *)
  try
    let { messages = raw_msgs } = chat_request_of_json body_json in
    List.concat_map
      (fun (msg : chat_message) ->
        List.filter_map
          (fun (p : parsed_part) ->
            match part_type_of_string p.type_, Option.map tool_state_of_string p.state with
            | Tool_invocation _, Some Approval_responded ->
              (match p.approved, p.tool_call_id with
               | Some true, Some id -> Some id
               | _ -> None)
            | _ -> None)
          msg.parts)
      raw_msgs
  with _ -> []
```

And in `handle_chat`, pass the approved IDs through.

**Step 2: Implement**

Detailed implementation in the test-first order below.

**Step 3: Add `approved` field to `parsed_part` and test parsing**

Test that a JSON message with `"state": "approval-responded", "approved": true` is parsed correctly.

Test that `"state": "approval-responded", "approved": false` produces a denied tool result.

**Step 4: Run tests**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core 2>&1
```

**Step 5: Commit**

```bash
git add lib/ai_core/server_handler.ml lib/ai_core/server_handler.mli test/ai_core/test_server_handler.ml
git commit -m "feat(server_handler): parse approval-responded tool state with approved field"
```

---

### Task 8: Thread `approved_tool_call_ids` through step loops

**Files:**
- Modify: `lib/ai_core/generate_text.ml`
- Modify: `lib/ai_core/generate_text.mli` (if exposed)
- Modify: `lib/ai_core/stream_text.ml`
- Modify: `lib/ai_core/stream_text.mli`
- Modify: `lib/ai_core/server_handler.ml`
- Modify: `test/ai_core/test_generate_text.ml`
- Modify: `test/ai_core/test_stream_text.ml`

**Step 1: Write the failing tests**

Add to `test_generate_text.ml`:
```ocaml
let test_approved_tool_executes () =
  let model = make_tool_model () in
  (* Use a tool that always needs approval, but pass its ID as pre-approved *)
  let result =
    Lwt_main.run
      (Ai_core.Generate_text.generate_text ~model ~prompt:"Do it"
         ~tools:[ "search", approval_tool_that_searches ]
         ~approved_tool_call_ids:[ "tc_1" ]
         ~max_steps:3 ())
  in
  (* Tool was pre-approved, so it should execute *)
  (check int) "2 steps" 2 (List.length result.steps);
  (check int) "1 tool result" 1 (List.length result.tool_results)
```

Where `approval_tool_that_searches` is a tool with `needs_approval = Some (fun _ -> Lwt.return_true)` and an execute that returns search results.

**Step 2: Add `?approved_tool_call_ids` parameter**

In `generate_text.ml` and `stream_text.ml`:
```ocaml
let generate_text ~model ... ?(approved_tool_call_ids = []) ... () =
```

In the approval check:
```ocaml
        let%lwt needs_approval =
          Lwt_list.exists_s
            (fun (tc : Generate_text_result.tool_call) ->
              (* Skip approval check for pre-approved tools *)
              if List.mem tc.tool_call_id approved_tool_call_ids then Lwt.return_false
              else
                match List.assoc_opt tc.tool_name tools with
                | Some tool ->
                  (match tool.Core_tool.needs_approval with
                   | Some check -> check tc.args
                   | None -> Lwt.return_false)
                | None -> Lwt.return_false)
            tool_calls
        in
```

**Step 3: Wire through `server_handler.ml`**

In `handle_chat`, collect approved IDs and pass to `stream_text`:
```ocaml
    let approved_tool_call_ids = collect_approved_tool_ids body_json in
    let result =
      Stream_text.stream_text ~model ~messages ?tools ?max_steps ?output ?provider_options
        ~approved_tool_call_ids ()
    in
```

**Step 4: Run tests**

```bash
cd /home/me/code/opensource/ocaml-ai-sdk && dune runtest test/ai_core 2>&1
```

**Step 5: Commit**

```bash
git add lib/ai_core/generate_text.ml lib/ai_core/generate_text.mli
git add lib/ai_core/stream_text.ml lib/ai_core/stream_text.mli
git add lib/ai_core/server_handler.ml lib/ai_core/server_handler.mli
git add test/ai_core/test_generate_text.ml test/ai_core/test_stream_text.ml
git commit -m "feat: thread approved_tool_call_ids through step loops and server handler"
```

---

### Task 9: Update v2 roadmap

**Files:**
- Modify: `docs/plans/2026-03-26-v2-roadmap.md`

**Step 1: Update status**

Mark item #4 as Done with a summary of what was implemented.

**Step 2: Commit**

```bash
git add docs/plans/2026-03-26-v2-roadmap.md docs/plans/2026-03-27-tool-approval-workflow.md
git commit -m "docs: mark tool approval workflow as done in v2 roadmap"
```
