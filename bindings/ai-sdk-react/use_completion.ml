(** Melange bindings for the [useCompletion] hook from [@ai-sdk/react].

    @see <https://ai-sdk.dev/docs/ai-sdk-ui/completion> useCompletion documentation *)

(** {1 Return type} *)

type t

external completion : t -> string = "completion" [@@mel.get]
external input : t -> string = "input" [@@mel.get]
external is_loading : t -> bool = "isLoading" [@@mel.get]
external error : t -> Js.Exn.t option = "error" [@@mel.get] [@@mel.return nullable]

external complete : t -> string -> unit = "complete" [@@mel.send]

external complete_with_options : t -> string -> Types.chat_request_options -> unit = "complete" [@@mel.send]

external stop : t -> unit = "stop" [@@mel.send]
external set_completion : t -> string -> unit = "setCompletion" [@@mel.send]
external set_input : t -> string -> unit = "setInput" [@@mel.send]
external handle_input_change : t -> Dom.event -> unit = "handleInputChange" [@@mel.send]
external handle_submit : t -> unit = "handleSubmit" [@@mel.send]

external handle_submit_with_event : t -> Dom.event -> unit = "handleSubmit" [@@mel.send]

(** {1 Options} *)

type options

(** Create options for [useCompletion]. All parameters are optional.
    [streamProtocol] should be ["data"] or ["text"]. *)
external make_options :
  ?api:string ->
  ?id:string ->
  ?initialInput:string ->
  ?initialCompletion:string ->
  ?credentials:string ->
  ?headers:string Js.Dict.t ->
  ?body:Js.Json.t ->
  ?streamProtocol:string ->
  ?onFinish:(string -> string -> unit) ->
  ?onError:(Js.Exn.t -> unit) ->
  ?experimental_throttle:int ->
  unit ->
  options = ""
[@@mel.obj]

(** {1 Hook} *)

external use_completion_raw : options Js.undefined -> t = "useCompletion" [@@mel.module "@ai-sdk/react"]

(** Call [useCompletion()] with default options. *)
let use_completion () = use_completion_raw Js.Undefined.empty

(** Call [useCompletion(options)] with custom options
    (created via {!make_options}). *)
let use_completion_with options = use_completion_raw (Js.Undefined.return options)
