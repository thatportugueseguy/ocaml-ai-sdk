open Melange_json.Primitives

type request_body_json = {
  system : string option; [@json.default None]
} [@@json.allow_extra_fields] [@@deriving of_json]

let mock_text_response =
  Ai_provider_anthropic.Convert_response.anthropic_response_json_to_json
    {
      id = Some "msg_test";
      model = Some "claude-sonnet-4-6";
      content =
        [ { type_ = "text"; text = Some "Hello from Claude!"; id = None; name = None; input = None; thinking = None; signature = None } ];
      stop_reason = Some "end_turn";
      usage = { input_tokens = 10; output_tokens = 5; cache_read_input_tokens = None; cache_creation_input_tokens = None };
    }

let mock_tool_response =
  Ai_provider_anthropic.Convert_response.anthropic_response_json_to_json
    {
      id = Some "msg_tool";
      model = Some "claude-sonnet-4-6";
      content =
        [
          { type_ = "text"; text = Some "Let me search."; id = None; name = None; input = None; thinking = None; signature = None };
          {
            type_ = "tool_use";
            text = None;
            id = Some "tc_1";
            name = Some "search";
            input = Some (`Assoc [ "query", `String "test" ]);
            thinking = None;
            signature = None;
          };
        ];
      stop_reason = Some "tool_use";
      usage = { input_tokens = 20; output_tokens = 15; cache_read_input_tokens = None; cache_creation_input_tokens = None };
    }

let make_config response =
  let fetch ~url:_ ~headers:_ ~body:_ = Lwt.return response in
  Ai_provider_anthropic.Config.create ~api_key:"sk-test" ~fetch ()

let make_opts ?(prompt_text = "Hello") () =
  Ai_provider.Call_options.default
    ~prompt:
      [
        Ai_provider.Prompt.User
          { content = [ Text { text = prompt_text; provider_options = Ai_provider.Provider_options.empty } ] };
      ]

let test_generate_text () =
  let config = make_config mock_text_response in
  let model = Ai_provider_anthropic.Anthropic_model.create ~config ~model:"claude-sonnet-4-6" in
  let opts = make_opts () in
  let result = Lwt_main.run (Ai_provider.Language_model.generate model opts) in
  (match result.content with
  | [ Ai_provider.Content.Text { text } ] -> Alcotest.(check string) "text" "Hello from Claude!" text
  | _ -> Alcotest.fail "expected single text");
  Alcotest.(check string) "finish" "stop" (Ai_provider.Finish_reason.to_string result.finish_reason);
  Alcotest.(check int) "input tokens" 10 result.usage.input_tokens

let test_generate_tool_call () =
  let config = make_config mock_tool_response in
  let model = Ai_provider_anthropic.Anthropic_model.create ~config ~model:"claude-sonnet-4-6" in
  let opts = make_opts () in
  let result = Lwt_main.run (Ai_provider.Language_model.generate model opts) in
  Alcotest.(check int) "2 content" 2 (List.length result.content);
  Alcotest.(check string) "finish" "tool_calls" (Ai_provider.Finish_reason.to_string result.finish_reason)

let test_generate_with_system () =
  let fetch_called = ref false in
  let fetch ~url:_ ~headers:_ ~body =
    fetch_called := true;
    let json = Yojson.Basic.from_string body in
    let r = request_body_json_of_json json in
    (* Verify system was included in request *)
    Alcotest.(check (option string)) "system in body" (Some "Be helpful") r.system;
    Lwt.return mock_text_response
  in
  let config = Ai_provider_anthropic.Config.create ~api_key:"sk-test" ~fetch () in
  let model = Ai_provider_anthropic.Anthropic_model.create ~config ~model:"claude-sonnet-4-6" in
  let opts =
    Ai_provider.Call_options.default
      ~prompt:
        [
          Ai_provider.Prompt.System { content = "Be helpful" };
          Ai_provider.Prompt.User
            { content = [ Text { text = "Hi"; provider_options = Ai_provider.Provider_options.empty } ] };
        ]
  in
  let _result = Lwt_main.run (Ai_provider.Language_model.generate model opts) in
  Alcotest.(check bool) "fetch called" true !fetch_called

let test_warns_frequency_penalty () =
  let config = make_config mock_text_response in
  let model = Ai_provider_anthropic.Anthropic_model.create ~config ~model:"claude-sonnet-4-6" in
  let opts = { (make_opts ()) with frequency_penalty = Some 0.5 } in
  let result = Lwt_main.run (Ai_provider.Language_model.generate model opts) in
  Alcotest.(check bool) "has warnings" true (List.length result.warnings > 0)

let test_model_accessors () =
  let config = make_config mock_text_response in
  let model = Ai_provider_anthropic.Anthropic_model.create ~config ~model:"claude-sonnet-4-6" in
  Alcotest.(check string) "provider" "anthropic" (Ai_provider.Language_model.provider model);
  Alcotest.(check string) "model_id" "claude-sonnet-4-6" (Ai_provider.Language_model.model_id model);
  Alcotest.(check string) "spec" "V3" (Ai_provider.Language_model.specification_version model)

let () =
  Alcotest.run "Anthropic_model"
    [
      ( "generate",
        [
          Alcotest.test_case "text" `Quick test_generate_text;
          Alcotest.test_case "tool_call" `Quick test_generate_tool_call;
          Alcotest.test_case "with_system" `Quick test_generate_with_system;
          Alcotest.test_case "warns_frequency_penalty" `Quick test_warns_frequency_penalty;
        ] );
      "accessors", [ Alcotest.test_case "model_accessors" `Quick test_model_accessors ];
    ]
