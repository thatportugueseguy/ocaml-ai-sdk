(** Melange bindings for the [useCompletion] hook from [@ai-sdk/react].

    The [useCompletion] hook manages text completion with streaming support,
    input state, and form helpers.

    {[
      let () =
        let h = Use_completion.use_completion () in
        Js.log (Use_completion.completion h);
        Use_completion.complete h "Write a poem about OCaml"
    ]}

    @see <https://ai-sdk.dev/docs/ai-sdk-ui/completion> useCompletion documentation *)

(** The return value of the [useCompletion] hook. *)
type t

(** {1 Reading state} *)

val completion : t -> string
val input : t -> string
val is_loading : t -> bool
val error : t -> Js.Exn.t option

(** {1 Actions} *)

(** Send a prompt to the completion API. *)
val complete : t -> string -> unit

(** Send a prompt with additional request options. *)
val complete_with_options : t -> string -> Types.chat_request_options -> unit

(** Abort the current request. *)
val stop : t -> unit

(** Update the completion text locally. *)
val set_completion : t -> string -> unit

(** Update the input value. *)
val set_input : t -> string -> unit

(** An input/textarea-ready onChange handler. *)
val handle_input_change : t -> Dom.event -> unit

(** Form submission handler (resets input and triggers completion). *)
val handle_submit : t -> unit

(** Form submission handler with an event object. *)
val handle_submit_with_event : t -> Dom.event -> unit

(** {1 Options} *)

type options

(** Create options for [useCompletion]. All parameters are optional.
    [streamProtocol] should be ["data"] or ["text"]. *)
val make_options :
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
  options

(** {1 Hook} *)

(** Call [useCompletion()] with default options. *)
val use_completion : unit -> t

(** Call [useCompletion(options)] with custom options. *)
val use_completion_with : options -> t
