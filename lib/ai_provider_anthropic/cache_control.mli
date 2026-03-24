(** Prompt caching control for Anthropic models. *)

type breakpoint = Ephemeral  (** Cache control type. Currently only [Ephemeral] is supported. *)

type t = { cache_type : breakpoint }

(** Convenience constructor for ephemeral cache control. *)
val ephemeral : t

val to_yojson : t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> (t, string) result

(** Returns JSON fields for cache control. Empty list if [None]. *)
val to_yojson_fields : t option -> (string * Yojson.Safe.t) list
