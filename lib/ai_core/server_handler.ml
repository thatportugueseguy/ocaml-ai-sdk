let po = Ai_provider.Provider_options.empty

(* Extract text from a message — handles both v5 "content" string
   and v6 "parts" array formats from useChat *)
let extract_text_from_message msg =
  let open Yojson.Safe.Util in
  (* Try v6 "parts" array first *)
  match member "parts" msg with
  | `List parts ->
    parts
    |> List.filter_map (fun part ->
      match member "type" part |> to_string_option with
      | Some "text" ->
        (match member "text" part |> to_string_option with
        | Some t -> Some t
        | None -> None)
      | _ -> None)
    |> String.concat ""
  | _ ->
  (* Fall back to v5 "content" string *)
  match member "content" msg |> to_string_option with
  | Some s -> s
  | None -> ""

let parse_messages_from_body body_json =
  let open Yojson.Safe.Util in
  let messages_json = member "messages" body_json |> to_list in
  List.filter_map
    (fun msg ->
      let role = member "role" msg |> to_string in
      let text = extract_text_from_message msg in
      match role with
      | "system" -> Some (Ai_provider.Prompt.System { content = text })
      | "user" -> Some (Ai_provider.Prompt.User { content = [ Text { text; provider_options = po } ] })
      | "assistant" -> Some (Ai_provider.Prompt.Assistant { content = [ Text { text; provider_options = po } ] })
      | _ -> None)
    messages_json

let make_sse_response ?(status = `OK) ?(extra_headers = []) sse_stream =
  let headers = Ui_message_stream.headers @ extra_headers |> Cohttp.Header.of_list in
  let body = Cohttp_lwt.Body.of_stream sse_stream in
  let response = Cohttp.Response.make ~status ~headers () in
  Lwt.return (response, body)

let handle_chat ~model ?tools ?max_steps ?system ?send_reasoning ?provider_options _conn _req body =
  let%lwt body_str = Cohttp_lwt.Body.to_string body in
  let body_json = try Yojson.Safe.from_string body_str with Yojson.Json_error _ -> `Assoc [ "messages", `List [] ] in
  let messages = parse_messages_from_body body_json in
  let messages =
    match system with
    | Some s -> Ai_provider.Prompt.System { content = s } :: messages
    | None -> messages
  in
  let result = Stream_text.stream_text ~model ~messages ?tools ?max_steps ?provider_options () in
  let sse_stream = Stream_text_result.to_ui_message_sse_stream ?send_reasoning result in
  make_sse_response sse_stream
