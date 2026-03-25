(** JSON wire types for the Claude Code CLI streaming protocol. *)

(** Alias for raw JSON values that pass through serialization unchanged. *)
type json_value = Yojson.Basic.t

(** {1 Content blocks} *)

type text_block = { text : string }
type thinking_block = {
  thinking : string;
  signature : string;
}

type tool_use_block = {
  id : string;
  name : string;
  input : Yojson.Basic.t;
}

type tool_result_block = {
  tool_use_id : string;
  content : string;
  is_error : bool;
}

type content_block =
  | Text of text_block
  | Thinking of thinking_block
  | Tool_use of tool_use_block
  | Tool_result of tool_result_block

val content_block_of_json : Yojson.Basic.t -> content_block

val content_block_to_json : content_block -> Yojson.Basic.t

(** {1 Usage} *)

type usage = {
  input_tokens : int;
  output_tokens : int;
  cache_read_input_tokens : int;
  cache_creation_input_tokens : int;
}

val usage_of_json : Yojson.Basic.t -> usage
val usage_to_json : usage -> Yojson.Basic.t

(** {1 API message} *)

type api_message = {
  id : string;
  model : string;
  role : string;
  content : content_block list;
  stop_reason : string option;
  usage : usage;
}

val api_message_of_json : Yojson.Basic.t -> api_message
val api_message_to_json : api_message -> Yojson.Basic.t

(** {1 Top-level message types} *)

type system_message = {
  subtype : string;
  session_id : string option;
  cwd : string option;
  tools : string list;
  model : string option;
  permission_mode : string option;
  claude_code_version : string option;
  uuid : string option;
}

val system_message_of_json : Yojson.Basic.t -> system_message

val system_message_to_json : system_message -> Yojson.Basic.t

type assistant_message = {
  message : api_message;
  parent_tool_use_id : string option;
  session_id : string option;
  uuid : string option;
}

val assistant_message_of_json : Yojson.Basic.t -> assistant_message

val assistant_message_to_json : assistant_message -> Yojson.Basic.t

type result_message = {
  subtype : string;
  is_error : bool;
  duration_ms : float option;
  duration_api_ms : float option;
  num_turns : int option;
  session_id : string option;
  total_cost_usd : float option;
  result : string option;
  uuid : string option;
}

val result_message_of_json : Yojson.Basic.t -> result_message

val result_message_to_json : result_message -> Yojson.Basic.t

type user_message = {
  content : Yojson.Basic.t;
  uuid : string option;
  parent_tool_use_id : string option;
}

val user_message_of_json : Yojson.Basic.t -> user_message

val user_message_to_json : user_message -> Yojson.Basic.t

(** {1 Control protocol} *)

type control_request = {
  request_id : string;
  request : Yojson.Basic.t;
}

val control_request_of_json : Yojson.Basic.t -> control_request

val control_request_to_json : control_request -> Yojson.Basic.t

type control_response = {
  request_id : string;
  error : string option;
  result : Yojson.Basic.t option;
}

val control_response_of_json : Yojson.Basic.t -> control_response

val control_response_to_json : control_response -> Yojson.Basic.t

(** {1 Configuration types} *)

type agent_definition = {
  description : string;
  prompt : string option;
  tools : string list option;
  model : string option;
}

val agent_definition_of_json : Yojson.Basic.t -> agent_definition

val agent_definition_to_json : agent_definition -> Yojson.Basic.t

type mcp_stdio_server = {
  command : string;
  args : string list;
  env : (string * string) list option;
}

val mcp_stdio_server_of_json : Yojson.Basic.t -> mcp_stdio_server

val mcp_stdio_server_to_json : mcp_stdio_server -> Yojson.Basic.t
