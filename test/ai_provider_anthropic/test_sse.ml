let make_line_stream lines =
  let stream, push = Lwt_stream.create () in
  List.iter (fun line -> push (Some line)) lines;
  push None;
  stream

let test_basic_event () =
  let lines = make_line_stream [ "event: message_start"; "data: {\"type\":\"message\"}"; "" ] in
  let events = Ai_provider_anthropic.Sse.parse_events lines in
  let evts = Lwt_main.run (Lwt_stream.to_list events) in
  Alcotest.(check int) "1 event" 1 (List.length evts);
  let evt = List.nth evts 0 in
  Alcotest.(check string) "event type" "message_start" evt.event_type;
  Alcotest.(check string) "data" "{\"type\":\"message\"}" evt.data

let test_comment_ignored () =
  let lines = make_line_stream [ ": this is a comment"; "event: ping"; "data: {}"; "" ] in
  let events = Ai_provider_anthropic.Sse.parse_events lines in
  let evts = Lwt_main.run (Lwt_stream.to_list events) in
  Alcotest.(check int) "1 event" 1 (List.length evts);
  Alcotest.(check string) "event type" "ping" (List.nth evts 0).event_type

let test_multiple_events () =
  let lines =
    make_line_stream
      [ "event: message_start"; "data: {\"a\":1}"; ""; "event: content_block_start"; "data: {\"b\":2}"; "" ]
  in
  let events = Ai_provider_anthropic.Sse.parse_events lines in
  let evts = Lwt_main.run (Lwt_stream.to_list events) in
  Alcotest.(check int) "2 events" 2 (List.length evts)

let test_empty_lines_ignored () =
  let lines = make_line_stream [ ""; ""; "event: ping"; "data: {}"; "" ] in
  let events = Ai_provider_anthropic.Sse.parse_events lines in
  let evts = Lwt_main.run (Lwt_stream.to_list events) in
  Alcotest.(check int) "1 event" 1 (List.length evts)

let () =
  Alcotest.run "SSE"
    [
      ( "parser",
        [
          Alcotest.test_case "basic" `Quick test_basic_event;
          Alcotest.test_case "comment" `Quick test_comment_ignored;
          Alcotest.test_case "multiple" `Quick test_multiple_events;
          Alcotest.test_case "empty_lines" `Quick test_empty_lines_ignored;
        ] );
    ]
