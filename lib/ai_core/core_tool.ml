type t = {
  description : string option;
  parameters : Yojson.Basic.t;
  execute : Yojson.Basic.t -> Yojson.Basic.t Lwt.t;
}

let safe_parse_json_args s = try Yojson.Basic.from_string s with Yojson.Json_error _ -> `String s
