open Melange_json.Primitives

type breakpoint = Ephemeral

let breakpoint_to_json = function
  | Ephemeral -> `Assoc [ "type", `String "ephemeral" ]

let breakpoint_of_json = function
  | `Assoc fields ->
    (match List.assoc_opt "type" fields with
    | Some (`String "ephemeral") -> Ephemeral
    | _ ->
      raise
        (Melange_json.Of_json_error (Melange_json.Unexpected_variant "Unknown cache breakpoint type")))
  | json ->
    raise
      (Melange_json.Of_json_error
         (Melange_json.Unexpected_variant
            (Printf.sprintf "Expected object for cache breakpoint, got: %s" (Yojson.Basic.to_string json))))

type t = { cache_type : breakpoint } [@@deriving json]

let ephemeral = { cache_type = Ephemeral }

let to_json_fields = function
  | None -> []
  | Some { cache_type } -> [ "cache_control", breakpoint_to_json cache_type ]
