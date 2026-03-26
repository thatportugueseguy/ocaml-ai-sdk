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

(* --- Output.array tests --- *)

let element_schema =
  Yojson.Basic.from_string
    {|{"type":"object","properties":{"name":{"type":"string"},"age":{"type":"integer"}},"required":["name","age"]}|}

let test_array_response_format () =
  let output = Ai_core.Output.array ~name:"people" ~element_schema () in
  match output.response_format with
  | Some { name; schema } ->
    (check string) "name" "people" name;
    let schema_str = Yojson.Basic.to_string schema in
    (check bool) "has elements" true (String.length schema_str > 0)
  | None -> fail "expected response_format"

let test_array_parse_complete_valid () =
  let output = Ai_core.Output.array ~name:"people" ~element_schema () in
  match output.parse_complete {|{"elements":[{"name":"Alice","age":30},{"name":"Bob","age":25}]}|} with
  | Ok (`List elements) -> (check int) "count" 2 (List.length elements)
  | Ok _ -> fail "expected list"
  | Error msg -> fail msg

let test_array_parse_complete_invalid_element () =
  let output = Ai_core.Output.array ~name:"people" ~element_schema () in
  match output.parse_complete {|{"elements":[{"name":"Alice"}]}|} with
  | Ok _ -> fail "expected error for invalid element"
  | Error _ -> ()

let test_array_parse_complete_not_object () =
  let output = Ai_core.Output.array ~name:"people" ~element_schema () in
  match output.parse_complete {|[1,2,3]|} with
  | Ok _ -> fail "expected error"
  | Error _ -> ()

let test_array_parse_complete_no_elements () =
  let output = Ai_core.Output.array ~name:"people" ~element_schema () in
  match output.parse_complete {|{"other":"field"}|} with
  | Ok _ -> fail "expected error"
  | Error _ -> ()

let test_array_parse_partial_drops_last_on_repair () =
  let output = Ai_core.Output.array ~name:"people" ~element_schema () in
  match output.parse_partial {|{"elements":[{"name":"Alice","age":30},{"name":"Bo|} with
  | Some (`List elements) -> (check int) "count after drop" 1 (List.length elements)
  | Some _ -> fail "expected list"
  | None -> fail "expected partial"

let test_array_parse_partial_keeps_all_on_successful () =
  let output = Ai_core.Output.array ~name:"people" ~element_schema () in
  match output.parse_partial {|{"elements":[{"name":"Alice","age":30},{"name":"Bob","age":25}]}|} with
  | Some (`List elements) -> (check int) "count" 2 (List.length elements)
  | Some _ -> fail "expected list"
  | None -> fail "expected partial"

let test_array_parse_partial_skips_invalid () =
  let output = Ai_core.Output.array ~name:"people" ~element_schema () in
  match output.parse_partial {|{"elements":[{"name":"Alice","age":30},{"name":"Bob"}]}|} with
  | Some (`List elements) -> (check int) "valid only" 1 (List.length elements)
  | Some _ -> fail "expected list"
  | None -> fail "expected partial"

let test_array_parse_partial_empty () =
  let output = Ai_core.Output.array ~name:"people" ~element_schema () in
  match output.parse_partial "" with
  | None -> ()
  | Some _ -> fail "expected None"

(* --- Output.choice tests --- *)

let test_choice_response_format () =
  let output = Ai_core.Output.choice ~name:"color" [ "red"; "green"; "blue" ] in
  match output.response_format with
  | Some { name; _ } -> (check string) "name" "color" name
  | None -> fail "expected response_format"

let test_choice_parse_complete_valid () =
  let output = Ai_core.Output.choice ~name:"color" [ "red"; "green"; "blue" ] in
  match output.parse_complete {|{"result":"red"}|} with
  | Ok (`String "red") -> ()
  | Ok json -> fail (Printf.sprintf "unexpected: %s" (Yojson.Basic.to_string json))
  | Error msg -> fail msg

let test_choice_parse_complete_invalid () =
  let output = Ai_core.Output.choice ~name:"color" [ "red"; "green"; "blue" ] in
  match output.parse_complete {|{"result":"yellow"}|} with
  | Ok _ -> fail "expected error"
  | Error _ -> ()

let test_choice_parse_complete_bad_json () =
  let output = Ai_core.Output.choice ~name:"color" [ "red"; "green"; "blue" ] in
  match output.parse_complete {|not json|} with
  | Ok _ -> fail "expected error"
  | Error _ -> ()

let test_choice_parse_partial_exact_match () =
  let output = Ai_core.Output.choice ~name:"sentiment" [ "positive"; "negative"; "neutral" ] in
  match output.parse_partial {|{"result":"positive"}|} with
  | Some (`String "positive") -> ()
  | Some json -> fail (Printf.sprintf "unexpected: %s" (Yojson.Basic.to_string json))
  | None -> fail "expected match"

let test_choice_parse_partial_unambiguous_prefix () =
  let output = Ai_core.Output.choice ~name:"sentiment" [ "positive"; "negative"; "neutral" ] in
  match output.parse_partial {|{"result":"pos|} with
  | Some (`String "positive") -> ()
  | Some json -> fail (Printf.sprintf "unexpected: %s" (Yojson.Basic.to_string json))
  | None -> fail "expected unambiguous match"

let test_choice_parse_partial_ambiguous_prefix () =
  let output = Ai_core.Output.choice ~name:"sentiment" [ "positive"; "negative"; "neutral" ] in
  match output.parse_partial {|{"result":"n|} with
  | None -> ()
  | Some _ -> fail "expected None for ambiguous"

let test_choice_parse_partial_no_match () =
  let output = Ai_core.Output.choice ~name:"color" [ "red"; "green"; "blue" ] in
  match output.parse_partial {|{"result":"yellow"}|} with
  | None -> ()
  | Some _ -> fail "expected None for no match"

let test_enum_alias () =
  let output = Ai_core.Output.enum ~name:"color" [ "red"; "green"; "blue" ] in
  match output.parse_complete {|{"result":"red"}|} with
  | Ok (`String "red") -> ()
  | _ -> fail "enum alias should work like choice"

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
      ( "array",
        [
          test_case "response_format" `Quick test_array_response_format;
          test_case "valid complete" `Quick test_array_parse_complete_valid;
          test_case "invalid element" `Quick test_array_parse_complete_invalid_element;
          test_case "not object" `Quick test_array_parse_complete_not_object;
          test_case "no elements" `Quick test_array_parse_complete_no_elements;
          test_case "partial drops last on repair" `Quick test_array_parse_partial_drops_last_on_repair;
          test_case "partial keeps all on successful" `Quick test_array_parse_partial_keeps_all_on_successful;
          test_case "partial skips invalid" `Quick test_array_parse_partial_skips_invalid;
          test_case "partial empty" `Quick test_array_parse_partial_empty;
        ] );
      ( "choice",
        [
          test_case "response_format" `Quick test_choice_response_format;
          test_case "valid" `Quick test_choice_parse_complete_valid;
          test_case "invalid value" `Quick test_choice_parse_complete_invalid;
          test_case "bad json" `Quick test_choice_parse_complete_bad_json;
          test_case "partial exact match" `Quick test_choice_parse_partial_exact_match;
          test_case "partial unambiguous prefix" `Quick test_choice_parse_partial_unambiguous_prefix;
          test_case "partial ambiguous prefix" `Quick test_choice_parse_partial_ambiguous_prefix;
          test_case "partial no match" `Quick test_choice_parse_partial_no_match;
          test_case "enum alias" `Quick test_enum_alias;
        ] );
    ]
