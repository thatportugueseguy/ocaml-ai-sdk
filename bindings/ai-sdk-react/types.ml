(** Shared types for @ai-sdk/react bindings *)

(** {1 Chat Status} *)

type chat_status =
  [ `submitted
  | `streaming
  | `ready
  | `error
  ]

(** {1 Message Role} *)

type role =
  [ `system
  | `user
  | `assistant
  ]

(** {1 UI Message Parts} *)

type text_ui_part

external text_ui_part_text : text_ui_part -> string = "text" [@@mel.get]

external text_ui_part_state : text_ui_part -> string option = "state" [@@mel.get] [@@mel.return nullable]

type reasoning_ui_part

external reasoning_ui_part_text : reasoning_ui_part -> string = "text" [@@mel.get]

external reasoning_ui_part_state : reasoning_ui_part -> string option = "state" [@@mel.get] [@@mel.return nullable]

type tool_ui_part

external tool_ui_part_tool_call_id : tool_ui_part -> string = "toolCallId" [@@mel.get]
external tool_ui_part_state : tool_ui_part -> string = "state" [@@mel.get]

external tool_ui_part_tool_name : tool_ui_part -> string option = "toolName" [@@mel.get] [@@mel.return nullable]

external tool_ui_part_title : tool_ui_part -> string option = "title" [@@mel.get] [@@mel.return nullable]

external tool_ui_part_input : tool_ui_part -> Js.Json.t option = "input" [@@mel.get] [@@mel.return nullable]

external tool_ui_part_output : tool_ui_part -> Js.Json.t option = "output" [@@mel.get] [@@mel.return nullable]

external tool_ui_part_error_text : tool_ui_part -> string option = "errorText" [@@mel.get] [@@mel.return nullable]

external tool_ui_part_provider_executed : tool_ui_part -> bool option = "providerExecuted"
[@@mel.get] [@@mel.return nullable]

type source_url_ui_part

external source_url_ui_part_source_id : source_url_ui_part -> string = "sourceId" [@@mel.get]
external source_url_ui_part_url : source_url_ui_part -> string = "url" [@@mel.get]

external source_url_ui_part_title : source_url_ui_part -> string option = "title" [@@mel.get] [@@mel.return nullable]

type source_document_ui_part

external source_document_ui_part_source_id : source_document_ui_part -> string = "sourceId" [@@mel.get]

external source_document_ui_part_media_type : source_document_ui_part -> string = "mediaType" [@@mel.get]

external source_document_ui_part_title : source_document_ui_part -> string = "title" [@@mel.get]

external source_document_ui_part_filename : source_document_ui_part -> string option = "filename"
[@@mel.get] [@@mel.return nullable]

type file_ui_part

external file_ui_part_media_type : file_ui_part -> string = "mediaType" [@@mel.get]
external file_ui_part_url : file_ui_part -> string = "url" [@@mel.get]

external file_ui_part_filename : file_ui_part -> string option = "filename" [@@mel.get] [@@mel.return nullable]

type step_start_ui_part

(** A single part of a UI message. Use {!part_type} to determine the variant,
    then cast with the appropriate [as_*] function. *)
type ui_message_part

external part_type : ui_message_part -> string = "type" [@@mel.get]

external as_text : ui_message_part -> text_ui_part = "%identity"
external as_reasoning : ui_message_part -> reasoning_ui_part = "%identity"
external as_tool_call : ui_message_part -> tool_ui_part = "%identity"
external as_source_url : ui_message_part -> source_url_ui_part = "%identity"
external as_source_document : ui_message_part -> source_document_ui_part = "%identity"
external as_file : ui_message_part -> file_ui_part = "%identity"
external as_step_start : ui_message_part -> step_start_ui_part = "%identity"

(** Pattern match on a message part by its type string.
    Tool parts match both ["dynamic-tool"] and ["tool-*"] prefixed types
    (e.g. ["tool-get_weather"] for static tools). *)
let classify (part : ui_message_part) =
  let t = part_type part in
  if String.equal t "text" then `Text (as_text part)
  else if String.equal t "reasoning" then `Reasoning (as_reasoning part)
  else if String.equal t "dynamic-tool" then `Tool_call (as_tool_call part)
  else if String.length t > 5 && String.equal (String.sub t 0 5) "tool-" then `Tool_call (as_tool_call part)
  else if String.equal t "source-url" then `Source_url (as_source_url part)
  else if String.equal t "source-document" then `Source_document (as_source_document part)
  else if String.equal t "file" then `File (as_file part)
  else if String.equal t "step-start" then `Step_start (as_step_start part)
  else `Unknown t

(** {1 UI Message} *)

type ui_message

external ui_message_id : ui_message -> string = "id" [@@mel.get]
external ui_message_role : ui_message -> string = "role" [@@mel.get]
external ui_message_parts : ui_message -> ui_message_part array = "parts" [@@mel.get]

external ui_message_metadata : ui_message -> Js.Json.t option = "metadata" [@@mel.get] [@@mel.return nullable]

let ui_message_role_typed (msg : ui_message) : role =
  match ui_message_role msg with
  | "system" -> `system
  | "user" -> `user
  | "assistant" -> `assistant
  | _ -> `user

(** {1 Chat Request Options} *)

type chat_request_options

external make_chat_request_options :
  ?headers:string Js.Dict.t -> ?body:Js.Json.t -> ?metadata:Js.Json.t -> unit -> chat_request_options = ""
[@@mel.obj]

(** {1 Error helpers} *)

type error = Js.Exn.t
