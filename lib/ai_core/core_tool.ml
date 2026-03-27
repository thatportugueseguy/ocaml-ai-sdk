type t = {
  description : string option;
  parameters : Yojson.Basic.t;
  execute : Yojson.Basic.t -> Yojson.Basic.t Lwt.t;
  needs_approval : (Yojson.Basic.t -> bool Lwt.t) option;
}

let create ?description ?needs_approval ~parameters ~execute () = { description; parameters; execute; needs_approval }

let create_with_approval ?description ~parameters ~execute () =
  { description; parameters; execute; needs_approval = Some (fun _ -> Lwt.return_true) }

let safe_parse_json_args s = try Yojson.Basic.from_string s with Yojson.Json_error _ -> `String s
