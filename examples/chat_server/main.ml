(** Chat server example using the Core SDK.

    Serves a chat endpoint compatible with useChat() from @ai-sdk/react.
    Set ANTHROPIC_API_KEY environment variable before running.

    Usage:
      dune exec examples/chat_server.exe

    Test with curl:
      curl -X POST http://localhost:28601/chat \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"Hello!"}]}'

    Or connect a React frontend using useChat():
      const { messages, input, handleSubmit } = useChat({
        api: 'http://localhost:28601/chat',
      }); *)

let model = Ai_provider_anthropic.model "claude-sonnet-4-6"

let weather_tool : Ai_core.Core_tool.t =
  {
    description = Some "Get the current weather for a city";
    parameters =
      `Assoc
        [
          "type", `String "object";
          "properties", `Assoc [ "city", `Assoc [ "type", `String "string"; "description", `String "The city name" ] ];
          "required", `List [ `String "city" ];
        ];
    execute =
      (fun args ->
        let city = try Yojson.Safe.Util.(member "city" args |> to_string) with _ -> "unknown" in
        Lwt.return
          (`Assoc
             [ "city", `String city; "temperature", `Int 22; "condition", `String "sunny"; "unit", `String "celsius" ]));
  }

let cors_headers =
  [
    "access-control-allow-origin", "*";
    "access-control-allow-methods", "POST, OPTIONS";
    "access-control-allow-headers", "content-type";
    "access-control-expose-headers", "x-vercel-ai-ui-message-stream";
  ]

let error_response status_code msg =
  let body = Cohttp_lwt.Body.of_string msg in
  let headers = Cohttp.Header.of_list (("content-type", "text/plain") :: cors_headers) in
  let response = Cohttp.Response.make ~status:(Cohttp.Code.status_of_code status_code) ~headers () in
  Lwt.return (response, body)

let handler _conn req body =
  let uri = Cohttp.Request.uri req in
  let path = Uri.path uri in
  let meth = Cohttp.Request.meth req in
  Printf.printf "[%s] %s %s\n%!"
    (match meth with
    | `GET -> "GET"
    | `POST -> "POST"
    | `OPTIONS -> "OPTIONS"
    | _ -> "OTHER")
    path (Uri.to_string uri);
  (* Handle CORS preflight *)
  match meth, path with
  | `OPTIONS, "/chat" ->
    let headers = Cohttp.Header.of_list cors_headers in
    let response = Cohttp.Response.make ~status:`No_content ~headers () in
    Lwt.return (response, Cohttp_lwt.Body.empty)
  | _, "/chat" ->
    Lwt.catch
      (fun () ->
        let%lwt response, body =
          Ai_core.Server_handler.handle_chat ~model ~system:"You are a helpful assistant. Be concise."
            ~tools:[ "get_weather", weather_tool ]
            ~max_steps:3 ~send_reasoning:true _conn req body
        in
        (* Add CORS headers to the SSE response *)
        let existing_headers = Cohttp.Response.headers response in
        let merged = List.fold_left (fun h (k, v) -> Cohttp.Header.add h k v) existing_headers cors_headers in
        let response = { response with headers = merged } in
        Lwt.return (response, body))
      (fun exn ->
        let msg = Printexc.to_string exn in
        Printf.eprintf "[ERROR] /chat: %s\n%!" msg;
        error_response 500 msg)
  | _ -> error_response 404 "Not found"

let () =
  let port = 28601 in
  Printf.printf "Starting chat server on http://localhost:%d/chat\n%!" port;
  let server =
    Cohttp_lwt_unix.Server.create ~mode:(`TCP (`Port port)) (Cohttp_lwt_unix.Server.make ~callback:handler ())
  in
  Lwt_main.run server
