(** Melange bindings for the [useChat] hook from [@ai-sdk/react].

    @see <https://ai-sdk.dev/docs/ai-sdk-ui/chatbot> useChat documentation *)

open Types

(** {1 Return type} *)

type t

external id : t -> string = "id" [@@mel.get]
external messages : t -> ui_message array = "messages" [@@mel.get]
external status_raw : t -> string = "status" [@@mel.get]
external error : t -> Js.Exn.t option = "error" [@@mel.get] [@@mel.return nullable]

let status (h : t) : chat_status =
  match status_raw h with
  | "submitted" -> `submitted
  | "streaming" -> `streaming
  | "ready" -> `ready
  | "error" -> `error
  | _ -> `ready

external set_messages : t -> ui_message array -> unit = "setMessages" [@@mel.send]

external set_messages_fn : t -> (ui_message array -> ui_message array) -> unit = "setMessages" [@@mel.send]

(** {2 Sending messages} *)

type text_message

external make_text_message : text:string -> text_message = "" [@@mel.obj]

type text_message_with_metadata

external make_text_message_with_metadata : text:string -> ?metadata:Js.Json.t -> unit -> text_message_with_metadata = ""
[@@mel.obj]

external send_message : t -> text_message -> unit = "sendMessage" [@@mel.send]

external send_message_with_metadata : t -> text_message_with_metadata -> unit = "sendMessage" [@@mel.send]

(** Send a simple text string. Convenience wrapper. *)
let send_text (h : t) (text : string) = send_message h (make_text_message ~text)

external send_message_with_options : t -> text_message -> chat_request_options -> unit = "sendMessage" [@@mel.send]

(** {2 Other actions} *)

external regenerate : t -> unit = "regenerate" [@@mel.send]
external stop : t -> unit = "stop" [@@mel.send]
external resume_stream : t -> unit = "resumeStream" [@@mel.send]
external clear_error : t -> unit = "clearError" [@@mel.send]

(** {2 Tool interaction} *)

type tool_output

external make_tool_output : tool:string -> toolCallId:string -> output:Js.Json.t -> tool_output = "" [@@mel.obj]

external add_tool_output : t -> tool_output -> unit = "addToolOutput" [@@mel.send]

type tool_approval_response

external make_tool_approval_response : id:string -> approved:bool -> ?reason:string -> unit -> tool_approval_response
  = ""
[@@mel.obj]

external add_tool_approval_response : t -> tool_approval_response -> unit = "addToolApprovalResponse" [@@mel.send]

(** {1 Options} *)

(** Opaque transport object. Create with {!Default_chat_transport.make}. *)
type transport

type options

external make_options : ?id:string -> ?experimental_throttle:int -> ?resume:bool -> unit -> options = "" [@@mel.obj]

external make_options_with_transport :
  ?id:string -> ?transport:transport -> ?experimental_throttle:int -> ?resume:bool -> unit -> options = ""
[@@mel.obj]

external make_options_with_messages :
  ?id:string -> ?messages:ui_message array -> ?experimental_throttle:int -> ?resume:bool -> unit -> options = ""
[@@mel.obj]

(** Create options with all supported callbacks. *)
external make_options_full :
  ?id:string ->
  ?messages:ui_message array ->
  ?transport:transport ->
  ?onError:(Js.Exn.t -> unit) ->
  ?onToolCall:(Js.Json.t -> unit) ->
  ?onFinish:(Js.Json.t -> unit) ->
  ?onData:(Js.Json.t -> unit) ->
  ?experimental_throttle:int ->
  ?resume:bool ->
  unit ->
  options = ""
[@@mel.obj]

(** {1 Default Chat Transport} *)

module Default_chat_transport = struct
  type t
  type init

  external make_init :
    ?api:string -> ?credentials:string -> ?headers:string Js.Dict.t -> ?body:Js.Json.t -> unit -> init = ""
  [@@mel.obj]

  external create : init -> t = "DefaultChatTransport" [@@mel.new] [@@mel.module "ai"]

  let make ?api ?credentials ?headers ?body () = create (make_init ?api ?credentials ?headers ?body ())

  external as_transport : t -> transport = "%identity"
end

(** {1 Hook} *)

external use_chat_raw : options Js.undefined -> t = "useChat" [@@mel.module "@ai-sdk/react"]

(** Call [useChat()] with no options (uses SDK defaults). *)
let use_chat () = use_chat_raw Js.Undefined.empty

(** Call [useChat(options)] with the given options object. *)
let use_chat_with options = use_chat_raw (Js.Undefined.return options)
