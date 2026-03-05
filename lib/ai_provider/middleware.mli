(** Middleware for cross-cutting concerns (logging, caching, retries).

    Wraps generate/stream functions with additional behavior. *)

module type S = sig
  val wrap_generate : generate:(Call_options.t -> Generate_result.t Lwt.t) -> Call_options.t -> Generate_result.t Lwt.t

  val wrap_stream : stream:(Call_options.t -> Stream_result.t Lwt.t) -> Call_options.t -> Stream_result.t Lwt.t
end

(** Apply middleware to a language model, producing a new wrapped model. *)
val apply : (module S) -> Language_model.t -> Language_model.t
