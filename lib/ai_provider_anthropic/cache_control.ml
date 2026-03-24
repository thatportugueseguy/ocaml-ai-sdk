type breakpoint = Ephemeral

let breakpoint_to_yojson = function
  | Ephemeral -> `Assoc [ "type", `String "ephemeral" ]

let breakpoint_of_yojson = function
  | `Assoc fields ->
    (match List.assoc_opt "type" fields with
    | Some (`String "ephemeral") -> Ok Ephemeral
    | _ -> Error "Unknown cache breakpoint type")
  | json -> Error (Printf.sprintf "Expected object for cache breakpoint, got: %s" (Yojson.Safe.to_string json))

type t = { cache_type : breakpoint } [@@deriving yojson]

let ephemeral = { cache_type = Ephemeral }

let to_yojson_fields = function
  | None -> []
  | Some { cache_type } -> [ "cache_control", breakpoint_to_yojson cache_type ]
