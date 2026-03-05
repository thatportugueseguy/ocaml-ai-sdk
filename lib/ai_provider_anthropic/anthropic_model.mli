(** Anthropic model implementing [Ai_provider.Language_model.S]. *)

(** Create a language model backed by the Anthropic Messages API. *)
val create : config:Config.t -> model:string -> Ai_provider.Language_model.t
