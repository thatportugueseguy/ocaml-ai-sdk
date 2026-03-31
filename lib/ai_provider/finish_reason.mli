(** Reason why model generation finished. *)

type t =
  | Stop
  | Length
  | Tool_calls
  | Content_filter
  | Error
  | Other of string
  | Unknown

val to_string : t -> string
val of_string : string -> t

(** Wire format for the UIMessage stream protocol.
    Uses hyphens instead of underscores (e.g. ["tool-calls"] not ["tool_calls"])
    to match the upstream AI SDK v6 Zod schema for finish reason values. *)
val to_wire_string : t -> string
