open Melange_json.Primitives

(* Identity serializers for raw JSON fields (Yojson.Basic.t) *)
type json_value = Yojson.Basic.t

let json_value_to_json (x : json_value) : Yojson.Basic.t = x
let json_value_of_json (x : Yojson.Basic.t) : json_value = x

(* Content blocks *)

type text_block = { text : string } [@@json.allow_extra_fields] [@@deriving json]

type thinking_block = {
  thinking : string;
  signature : string;
}
[@@json.allow_extra_fields] [@@deriving json]

type tool_use_block = {
  id : string;
  name : string;
  input : json_value;
}
[@@json.allow_extra_fields] [@@deriving json]

type tool_result_block = {
  tool_use_id : string;
  content : string;
  is_error : bool; [@json.default false]
}
[@@json.allow_extra_fields] [@@deriving json]

type content_block =
  | Text of text_block
  | Thinking of thinking_block
  | Tool_use of tool_use_block
  | Tool_result of tool_result_block

(* Wire types for serialization — include the "type" discriminator field *)

type text_block_wire = {
  type_ : string; [@json.key "type"]
  text : string;
}
[@@deriving to_json]

type thinking_block_wire = {
  type_ : string; [@json.key "type"]
  thinking : string;
  signature : string;
}
[@@deriving to_json]

type tool_use_block_wire = {
  type_ : string; [@json.key "type"]
  id : string;
  name : string;
  input : json_value;
}
[@@deriving to_json]

type tool_result_block_wire = {
  type_ : string; [@json.key "type"]
  tool_use_id : string;
  content : string;
  is_error : bool; [@json.default false]
}
[@@deriving to_json]

(* Flat wire type for deserialization — all fields optional except discriminator *)
type content_block_wire = {
  type_ : string; [@json.key "type"]
  text : string option; [@json.default None]
  thinking : string option; [@json.default None]
  signature : string option; [@json.default None]
  id : string option; [@json.default None]
  name : string option; [@json.default None]
  input : json_value option; [@json.default None]
  tool_use_id : string option; [@json.default None]
  content_str : string option; [@json.key "content"] [@json.default None]
  is_error : bool; [@json.default false]
}
[@@json.allow_extra_fields] [@@deriving of_json]

let content_block_to_json = function
  | Text { text } -> text_block_wire_to_json { type_ = "text"; text }
  | Thinking { thinking; signature } ->
    thinking_block_wire_to_json { type_ = "thinking"; thinking; signature }
  | Tool_use { id; name; input } ->
    tool_use_block_wire_to_json { type_ = "tool_use"; id; name; input }
  | Tool_result { tool_use_id; content; is_error } ->
    tool_result_block_wire_to_json { type_ = "tool_result"; tool_use_id; content; is_error }

let content_block_of_json json =
  let w = content_block_wire_of_json json in
  match w.type_ with
  | "text" ->
    (match w.text with
    | Some text -> Text { text }
    | None -> failwith "text block missing 'text' field")
  | "thinking" ->
    (match w.thinking, w.signature with
    | Some thinking, Some signature -> Thinking { thinking; signature }
    | _ -> failwith "thinking block missing required fields")
  | "tool_use" ->
    (match w.id, w.name, w.input with
    | Some id, Some name, Some input -> Tool_use { id; name; input }
    | _ -> failwith "tool_use block missing required fields")
  | "tool_result" ->
    (match w.tool_use_id, w.content_str with
    | Some tool_use_id, Some content -> Tool_result { tool_use_id; content; is_error = w.is_error }
    | _ -> failwith "tool_result block missing required fields")
  | other -> failwith ("unknown content block type: " ^ other)

(* Usage *)

type usage = {
  input_tokens : int; [@json.default 0]
  output_tokens : int; [@json.default 0]
  cache_read_input_tokens : int; [@json.default 0]
  cache_creation_input_tokens : int; [@json.default 0]
}
[@@json.allow_extra_fields] [@@deriving json]

(* API message (nested inside assistant messages) *)

type api_message = {
  id : string;
  model : string;
  role : string;
  content : content_block list;
  stop_reason : string option; [@json.default None]
  usage : usage;
}
[@@json.allow_extra_fields] [@@deriving json]

(* Top-level message types *)

type system_message = {
  subtype : string;
  session_id : string option; [@json.default None]
  cwd : string option; [@json.default None]
  tools : string list; [@json.default []]
  model : string option; [@json.default None]
  permission_mode : string option; [@json.default None] [@json.key "permissionMode"]
  claude_code_version : string option; [@json.default None]
  uuid : string option; [@json.default None]
}
[@@json.allow_extra_fields] [@@deriving json]

type assistant_message = {
  message : api_message;
  parent_tool_use_id : string option; [@json.default None]
  session_id : string option; [@json.default None]
  uuid : string option; [@json.default None]
}
[@@json.allow_extra_fields] [@@deriving json]

type result_message = {
  subtype : string;
  is_error : bool; [@json.default false]
  duration_ms : float option; [@json.default None]
  duration_api_ms : float option; [@json.default None]
  num_turns : int option; [@json.default None]
  session_id : string option; [@json.default None]
  total_cost_usd : float option; [@json.default None]
  result : string option; [@json.default None]
  uuid : string option; [@json.default None]
}
[@@json.allow_extra_fields] [@@deriving json]

type user_message = {
  content : json_value;
  uuid : string option; [@json.default None]
  parent_tool_use_id : string option; [@json.default None]
}
[@@json.allow_extra_fields] [@@deriving json]

(* Control protocol types *)

type control_request = {
  request_id : string;
  request : json_value;
}
[@@json.allow_extra_fields] [@@deriving json]

type control_response = {
  request_id : string;
  error : string option; [@json.default None]
  result : json_value option;
     [@json.default None]
     [@to_json
       fun x ->
         match x with
         | None -> `Null
         | Some v -> v]
     [@of_json
       fun x ->
         match x with
         | `Null -> None
         | v -> Some v]
}
[@@json.allow_extra_fields] [@@deriving json]

(* Configuration types *)

type agent_definition = {
  description : string;
  prompt : string option; [@json.default None]
  tools : string list option; [@json.default None]
  model : string option; [@json.default None]
}
[@@deriving json]

type mcp_stdio_server = {
  command : string;
  args : string list;
  env : (string * string) list option; [@json.default None]
}
[@@deriving json]
