let test_language_model () =
  let model = Ai_provider_anthropic.language_model ~api_key:"sk-test" ~model:"claude-sonnet-4-6" () in
  Alcotest.(check string) "provider" "anthropic" (Ai_provider.Language_model.provider model);
  Alcotest.(check string) "model_id" "claude-sonnet-4-6" (Ai_provider.Language_model.model_id model)

let test_create_provider () =
  let provider = Ai_provider_anthropic.create ~api_key:"sk-test" () in
  Alcotest.(check string) "name" "anthropic" (Ai_provider.Provider.name provider);
  let model = Ai_provider.Provider.language_model provider "claude-opus-4-6" in
  Alcotest.(check string) "model_id" "claude-opus-4-6" (Ai_provider.Language_model.model_id model);
  Alcotest.(check string) "provider" "anthropic" (Ai_provider.Language_model.provider model)

let test_model_shortcut () =
  Unix.putenv "ANTHROPIC_API_KEY" "sk-test-factory";
  let model = Ai_provider_anthropic.model "claude-sonnet-4-6" in
  Alcotest.(check string) "provider" "anthropic" (Ai_provider.Language_model.provider model);
  Alcotest.(check string) "model_id" "claude-sonnet-4-6" (Ai_provider.Language_model.model_id model)

let () =
  Alcotest.run "Factory"
    [
      ( "factory",
        [
          Alcotest.test_case "language_model" `Quick test_language_model;
          Alcotest.test_case "create_provider" `Quick test_create_provider;
          Alcotest.test_case "model_shortcut" `Quick test_model_shortcut;
        ] );
    ]
