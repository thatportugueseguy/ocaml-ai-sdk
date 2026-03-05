(** Transform Anthropic SSE events into SDK stream parts. *)

(** Transform SSE events into SDK stream parts.
    Manages content block state for accumulating tool call args. *)
val transform : Sse.event Lwt_stream.t -> warnings:Ai_provider.Warning.t list -> Ai_provider.Stream_part.t Lwt_stream.t
