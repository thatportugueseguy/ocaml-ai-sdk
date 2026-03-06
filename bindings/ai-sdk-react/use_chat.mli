(** Melange bindings for the [useChat] hook from [@ai-sdk/react].

    The [useChat] hook manages a chat conversation with an AI model,
    providing message state, streaming status, and actions.

    {[
      let () =
        let h = Use_chat.use_chat () in
        let msgs = Use_chat.messages h in
        Array.iter (fun msg ->
          Js.log (Types.ui_message_id msg)
        ) msgs;
        Use_chat.send_text h "Hello!"
    ]}

    @see <https://ai-sdk.dev/docs/ai-sdk-ui/chatbot> useChat documentation *)

open Types

(** The return value of the [useChat] hook. *)
type t

(** {1 Reading state} *)

val id : t -> string
val messages : t -> ui_message array
val status : t -> chat_status
val error : t -> Js.Exn.t option

(** {1 Setting messages} *)

val set_messages : t -> ui_message array -> unit
val set_messages_fn : t -> (ui_message array -> ui_message array) -> unit

(** {1 Sending messages} *)

type text_message

(** Create a message payload with text only. *)
val make_text_message : text:string -> text_message

type text_message_with_metadata

(** Create a message payload with text and optional metadata. *)
val make_text_message_with_metadata : text:string -> ?metadata:Js.Json.t -> unit -> text_message_with_metadata

(** Send a text message object (created via {!make_text_message}). *)
val send_message : t -> text_message -> unit

(** Send a text message with metadata. *)
val send_message_with_metadata : t -> text_message_with_metadata -> unit

(** Send a simple text string. *)
val send_text : t -> string -> unit

(** Send a message with additional request options. *)
val send_message_with_options : t -> text_message -> chat_request_options -> unit

(** {1 Actions} *)

val regenerate : t -> unit
val stop : t -> unit
val resume_stream : t -> unit
val clear_error : t -> unit

(** {1 Tool interaction} *)

type tool_output

val make_tool_output : tool:string -> toolCallId:string -> output:Js.Json.t -> tool_output

val add_tool_output : t -> tool_output -> unit

type tool_approval_response

val make_tool_approval_response : id:string -> approved:bool -> ?reason:string -> unit -> tool_approval_response

val add_tool_approval_response : t -> tool_approval_response -> unit

(** {1 Options} *)

(** Opaque transport object. Create with {!Default_chat_transport.make}. *)
type transport

type options

val make_options : ?id:string -> ?experimental_throttle:int -> ?resume:bool -> unit -> options

val make_options_with_transport :
  ?id:string -> ?transport:transport -> ?experimental_throttle:int -> ?resume:bool -> unit -> options

val make_options_with_messages :
  ?id:string -> ?messages:ui_message array -> ?experimental_throttle:int -> ?resume:bool -> unit -> options

val make_options_full :
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
  options

(** {1 Default Chat Transport}

    Bindings for [DefaultChatTransport] from the [ai] package. *)
module Default_chat_transport : sig
  type t

  val make : ?api:string -> ?credentials:string -> ?headers:string Js.Dict.t -> ?body:Js.Json.t -> unit -> t

  val as_transport : t -> transport
end

(** {1 Hook} *)

(** Call [useChat()] with default options. *)
val use_chat : unit -> t

(** Call [useChat(options)] with a custom options object. *)
val use_chat_with : options -> t
