(** Factory for creating model instances from a provider.

    This is the OCaml equivalent of Vercel AI SDK's [ProviderV3]. *)

module type S = sig
  (** Provider name, e.g. ["anthropic"]. *)
  val name : string

  (** Create a language model for the given model ID. *)
  val language_model : string -> Language_model.t
end

(** First-class module wrapper for runtime dispatch. *)
type t = (module S)

val language_model : t -> string -> Language_model.t
val name : t -> string
