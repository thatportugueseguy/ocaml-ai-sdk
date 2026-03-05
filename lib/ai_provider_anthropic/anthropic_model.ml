(** Check for unsupported features and emit warnings. *)
let check_unsupported (opts : Ai_provider.Call_options.t) =
  let warnings = ref [] in
  let warn feature = warnings := Ai_provider.Warning.Unsupported_feature { feature; details = None } :: !warnings in
  (match opts.frequency_penalty with
  | Some _ -> warn "frequency_penalty"
  | None -> ());
  (match opts.presence_penalty with
  | Some _ -> warn "presence_penalty"
  | None -> ());
  (match opts.seed with
  | Some _ -> warn "seed"
  | None -> ());
  (* Warn if thinking is enabled with temperature/top_p/top_k *)
  let anthropic_opts = Anthropic_options.of_provider_options opts.provider_options in
  (match anthropic_opts with
  | Some { thinking = Some t; _ } when t.Thinking.enabled ->
    (match opts.temperature with
    | Some _ ->
      warnings :=
        Ai_provider.Warning.Unsupported_feature
          {
            feature = "temperature with thinking";
            details = Some "Anthropic does not support temperature when thinking is enabled";
          }
        :: !warnings
    | None -> ())
  | _ -> ());
  List.rev !warnings

let create ~config ~model =
  let module M = struct
    let specification_version = "V3"
    let provider = "anthropic"
    let model_id = model

    let generate (opts : Ai_provider.Call_options.t) =
      let warnings = check_unsupported opts in
      (* Extract system message *)
      let system, remaining = Convert_prompt.extract_system opts.prompt in
      (* Convert messages *)
      let messages = Convert_prompt.convert_messages remaining in
      (* Convert tools *)
      let tools, tool_choice = Convert_tools.convert_tools ~tools:opts.tools ~tool_choice:opts.tool_choice in
      (* Get Anthropic-specific options *)
      let anthropic_opts =
        match Anthropic_options.of_provider_options opts.provider_options with
        | Some o -> o
        | None -> Anthropic_options.default
      in
      (* Build request body *)
      let body =
        Anthropic_api.make_request_body ~model ~messages ?system ~tools ?tool_choice ?max_tokens:opts.max_output_tokens
          ?temperature:opts.temperature ?top_p:opts.top_p ?top_k:opts.top_k ~stop_sequences:opts.stop_sequences
          ?thinking:anthropic_opts.thinking ~stream:false ()
      in
      (* Make request *)
      let extra_headers = opts.headers in
      let%lwt response = Anthropic_api.messages ~config ~body ~extra_headers ~stream:false in
      match response with
      | `Json json ->
        let result = Convert_response.parse_response json in
        Lwt.return { result with warnings = warnings @ result.warnings }
      | `Stream _ ->
        (* Should not happen for non-streaming *)
        Lwt.fail_with "unexpected streaming response for non-streaming request"

    let stream (opts : Ai_provider.Call_options.t) =
      let warnings = check_unsupported opts in
      (* Extract system message *)
      let system, remaining = Convert_prompt.extract_system opts.prompt in
      (* Convert messages *)
      let messages = Convert_prompt.convert_messages remaining in
      (* Convert tools *)
      let tools, tool_choice = Convert_tools.convert_tools ~tools:opts.tools ~tool_choice:opts.tool_choice in
      (* Get Anthropic-specific options *)
      let anthropic_opts =
        match Anthropic_options.of_provider_options opts.provider_options with
        | Some o -> o
        | None -> Anthropic_options.default
      in
      (* Build request body *)
      let body =
        Anthropic_api.make_request_body ~model ~messages ?system ~tools ?tool_choice ?max_tokens:opts.max_output_tokens
          ?temperature:opts.temperature ?top_p:opts.top_p ?top_k:opts.top_k ~stop_sequences:opts.stop_sequences
          ?thinking:anthropic_opts.thinking ~stream:true ()
      in
      (* Make request *)
      let extra_headers = opts.headers in
      let%lwt response = Anthropic_api.messages ~config ~body ~extra_headers ~stream:true in
      match response with
      | `Stream line_stream ->
        let sse_events = Sse.parse_events line_stream in
        let parts = Convert_stream.transform sse_events ~warnings in
        Lwt.return { Ai_provider.Stream_result.stream = parts; warnings; raw_response = None }
      | `Json _ ->
        (* Should not happen for streaming *)
        Lwt.fail_with "unexpected non-streaming response for streaming request"
  end in
  (module M : Ai_provider.Language_model.S)
