(** Convert Anthropic API responses to SDK format. *)

(** Map Anthropic stop reasons to SDK finish reasons. *)
val map_stop_reason : string option -> Ai_provider.Finish_reason.t

(** Parse a full Anthropic Messages API response into a Generate_result. *)
val parse_response : Yojson.Safe.t -> Ai_provider.Generate_result.t
