(** Tool definition for function calling. *)

type t = {
  name : string;
  description : string option;
  parameters : Yojson.Basic.t;  (** JSON Schema *)
}
