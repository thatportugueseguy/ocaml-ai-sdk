open Alcotest

let parses_to input expected =
  match Ai_core.Partial_json.parse input with
  | Some (json, _status) ->
    let actual = Yojson.Basic.to_string json in
    (check string) "json" expected actual
  | None -> fail (Printf.sprintf "failed to parse: %s" input)

let parses_with_status input expected_status =
  match Ai_core.Partial_json.parse input with
  | Some (_, status) ->
    let status_str =
      match status with
      | Ai_core.Partial_json.Successful -> "Successful"
      | Repaired -> "Repaired"
    in
    let expected_str =
      match expected_status with
      | Ai_core.Partial_json.Successful -> "Successful"
      | Repaired -> "Repaired"
    in
    (check string) "status" expected_str status_str
  | None -> fail "expected parse"

let fails_to_parse input =
  match Ai_core.Partial_json.parse input with
  | Some _ -> fail (Printf.sprintf "expected failure for: %s" input)
  | None -> ()

let test_complete_json () =
  parses_to {|{"name":"Alice","age":30}|} {|{"name":"Alice","age":30}|};
  parses_to {|[1,2,3]|} {|[1,2,3]|};
  parses_to {|"hello"|} {|"hello"|};
  parses_to {|42|} {|42|}

let test_status_successful () = parses_with_status {|{"a":1}|} Ai_core.Partial_json.Successful

let test_truncated_object () =
  (* Truncated mid-value *)
  parses_to {|{"name":"Ali|} {|{"name":"Ali"}|};
  (* Truncated after value, before closing brace *)
  parses_to {|{"name":"Alice"|} {|{"name":"Alice"}|}

let test_truncated_after_comma () =
  (* Trailing comma in object — key not started yet *)
  parses_to {|{"name":"Alice",|} {|{"name":"Alice"}|}

let test_truncated_array () =
  parses_to {|[1,2,|} {|[1,2]|};
  parses_to {|[1,2|} {|[1,2]|};
  parses_to {|["hello","wor|} {|["hello","wor"]|}

let test_truncated_nested () =
  parses_to {|{"users":[{"name":"Alice"},{"name":"Bo|} {|{"users":[{"name":"Alice"},{"name":"Bo"}]}|}

let test_status_repaired () = parses_with_status {|{"name":"Ali|} Ai_core.Partial_json.Repaired

let test_empty_input () =
  fails_to_parse "";
  fails_to_parse "   "

let test_garbage () = fails_to_parse "not json at all"

let () =
  run "Partial_json"
    [
      ( "complete",
        [
          test_case "complete json" `Quick test_complete_json;
          test_case "status successful" `Quick test_status_successful;
        ] );
      ( "truncated",
        [
          test_case "object" `Quick test_truncated_object;
          test_case "after comma" `Quick test_truncated_after_comma;
          test_case "array" `Quick test_truncated_array;
          test_case "nested" `Quick test_truncated_nested;
          test_case "status repaired" `Quick test_status_repaired;
        ] );
      "edge", [ test_case "empty" `Quick test_empty_input; test_case "garbage" `Quick test_garbage ];
    ]
