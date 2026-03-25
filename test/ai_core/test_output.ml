open Alcotest

(* --- Output.text tests --- *)

let test_text_response_format () =
  let output = Ai_core.Output.text in
  match output.response_format with
  | None -> ()
  | Some _ -> fail "text output should have no response_format"

let test_text_parse_complete () =
  let output = Ai_core.Output.text in
  match output.parse_complete "hello world" with
  | Ok s -> (check string) "text" "hello world" s
  | Error msg -> fail msg

let test_text_parse_partial () =
  let output = Ai_core.Output.text in
  match output.parse_partial "hello" with
  | Some s -> (check string) "partial" "hello" s
  | None -> fail "expected partial"

let test_text_parse_partial_empty () =
  let output = Ai_core.Output.text in
  match output.parse_partial "" with
  | None -> ()
  | Some _ -> fail "expected None for empty"

(* --- Output.object_ tests --- *)

let recipe_schema =
  Yojson.Basic.from_string
    {|{
      "type":"object",
      "properties":{
        "name":{"type":"string"},
        "steps":{"type":"array","items":{"type":"string"}}
      },
      "required":["name","steps"]
    }|}

let test_object_response_format () =
  let output = Ai_core.Output.object_ ~name:"recipe" ~schema:recipe_schema () in
  match output.response_format with
  | Some { Ai_provider.Mode.name; schema } ->
    (check string) "name" "recipe" name;
    (check bool) "has schema" true (schema <> `Null)
  | None -> fail "expected response_format"

let test_object_parse_complete_valid () =
  let output = Ai_core.Output.object_ ~name:"recipe" ~schema:recipe_schema () in
  let json_str = {|{"name":"Pasta","steps":["boil","drain"]}|} in
  match output.parse_complete json_str with
  | Ok (`Assoc _) -> ()
  | Ok json -> fail (Printf.sprintf "expected object, got %s" (Yojson.Basic.to_string json))
  | Error msg -> fail msg

let test_object_parse_complete_invalid_json () =
  let output = Ai_core.Output.object_ ~name:"recipe" ~schema:recipe_schema () in
  match output.parse_complete "not json" with
  | Ok _ -> fail "expected error"
  | Error _ -> ()

let test_object_parse_complete_schema_mismatch () =
  let output = Ai_core.Output.object_ ~name:"recipe" ~schema:recipe_schema () in
  match output.parse_complete {|{"name":"Pasta"}|} with
  | Ok _ -> fail "expected schema validation error"
  | Error msg -> (check bool) "error not empty" true (String.length msg > 0)

let test_object_parse_partial () =
  let output = Ai_core.Output.object_ ~name:"recipe" ~schema:recipe_schema () in
  match output.parse_partial {|{"name":"Past|} with
  | Some (`Assoc pairs) -> (check bool) "has name" true (List.mem_assoc "name" pairs)
  | Some json -> fail (Printf.sprintf "expected object, got %s" (Yojson.Basic.to_string json))
  | None -> fail "expected partial parse"

let test_object_parse_partial_empty () =
  let output = Ai_core.Output.object_ ~name:"recipe" ~schema:recipe_schema () in
  match output.parse_partial "" with
  | None -> ()
  | Some _ -> fail "expected None for empty"

(* --- Output.enum tests --- *)

let test_enum_response_format () =
  let output = Ai_core.Output.enum ~name:"color" [ "red"; "green"; "blue" ] in
  match output.response_format with
  | Some { name; schema } ->
    (check string) "name" "color" name;
    (check bool) "has schema" true (schema <> `Null)
  | None -> fail "expected response_format"

let test_enum_parse_complete_valid () =
  let output = Ai_core.Output.enum ~name:"color" [ "red"; "green"; "blue" ] in
  match output.parse_complete {|{"result":"red"}|} with
  | Ok (`String "red") -> ()
  | Ok json -> fail (Printf.sprintf "unexpected: %s" (Yojson.Basic.to_string json))
  | Error msg -> fail msg

let test_enum_parse_complete_invalid () =
  let output = Ai_core.Output.enum ~name:"color" [ "red"; "green"; "blue" ] in
  match output.parse_complete {|{"result":"yellow"}|} with
  | Ok _ -> fail "expected error"
  | Error _ -> ()

let test_enum_parse_complete_bad_json () =
  let output = Ai_core.Output.enum ~name:"color" [ "red"; "green"; "blue" ] in
  match output.parse_complete {|not json|} with
  | Ok _ -> fail "expected error"
  | Error _ -> ()

let () =
  run "Output"
    [
      ( "text",
        [
          test_case "response_format" `Quick test_text_response_format;
          test_case "parse_complete" `Quick test_text_parse_complete;
          test_case "parse_partial" `Quick test_text_parse_partial;
          test_case "parse_partial empty" `Quick test_text_parse_partial_empty;
        ] );
      ( "object_",
        [
          test_case "response_format" `Quick test_object_response_format;
          test_case "valid complete" `Quick test_object_parse_complete_valid;
          test_case "invalid json" `Quick test_object_parse_complete_invalid_json;
          test_case "schema mismatch" `Quick test_object_parse_complete_schema_mismatch;
          test_case "partial" `Quick test_object_parse_partial;
          test_case "partial empty" `Quick test_object_parse_partial_empty;
        ] );
      ( "enum",
        [
          test_case "response_format" `Quick test_enum_response_format;
          test_case "valid" `Quick test_enum_parse_complete_valid;
          test_case "invalid value" `Quick test_enum_parse_complete_invalid;
          test_case "bad json" `Quick test_enum_parse_complete_bad_json;
        ] );
    ]
