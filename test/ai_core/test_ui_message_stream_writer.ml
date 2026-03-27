open Alcotest

(** Helper: collect all chunks from a stream into a list *)
let collect stream = Lwt_main.run (Lwt_stream.to_list stream)

let test_write_single_chunk () =
  let stream =
    Ai_core.Ui_message_stream_writer.create_ui_message_stream
      ~execute:(fun writer ->
        Ai_core.Ui_message_stream_writer.write writer
          (Ai_core.Ui_message_chunk.Text_delta { id = "t1"; delta = "hello" });
        Lwt.return_unit)
      ()
  in
  let chunks = collect stream in
  (* Start + Text_delta + Finish *)
  (check int) "3 chunks" 3 (List.length chunks);
  (match List.nth chunks 0 with
   | Ai_core.Ui_message_chunk.Start { message_id = None; _ } -> ()
   | _ -> fail "expected Start");
  (match List.nth chunks 1 with
   | Ai_core.Ui_message_chunk.Text_delta { id = "t1"; delta = "hello" } -> ()
   | _ -> fail "expected Text_delta");
  (match List.nth chunks 2 with
   | Ai_core.Ui_message_chunk.Finish { finish_reason = None; _ } -> ()
   | _ -> fail "expected Finish")

let test_write_multiple_chunks () =
  let stream =
    Ai_core.Ui_message_stream_writer.create_ui_message_stream
      ~execute:(fun writer ->
        let write = Ai_core.Ui_message_stream_writer.write writer in
        write (Ai_core.Ui_message_chunk.Text_start { id = "t1" });
        write (Ai_core.Ui_message_chunk.Text_delta { id = "t1"; delta = "hi" });
        write (Ai_core.Ui_message_chunk.Text_end { id = "t1" });
        Lwt.return_unit)
      ()
  in
  let chunks = collect stream in
  (* Start + 3 text chunks + Finish *)
  (check int) "5 chunks" 5 (List.length chunks)

let test_empty_execute () =
  let stream =
    Ai_core.Ui_message_stream_writer.create_ui_message_stream
      ~execute:(fun _writer -> Lwt.return_unit)
      ()
  in
  let chunks = collect stream in
  (* Start + Finish only *)
  (check int) "2 chunks" 2 (List.length chunks);
  (match List.nth chunks 0 with
   | Ai_core.Ui_message_chunk.Start _ -> ()
   | _ -> fail "expected Start");
  (match List.nth chunks 1 with
   | Ai_core.Ui_message_chunk.Finish _ -> ()
   | _ -> fail "expected Finish")

let test_message_id_in_start () =
  let stream =
    Ai_core.Ui_message_stream_writer.create_ui_message_stream
      ~message_id:"msg_persist_123"
      ~execute:(fun _writer -> Lwt.return_unit)
      ()
  in
  let chunks = collect stream in
  (match List.nth chunks 0 with
   | Ai_core.Ui_message_chunk.Start { message_id = Some "msg_persist_123"; _ } -> ()
   | _ -> fail "expected Start with message_id")

let () =
  run "Ui_message_stream_writer"
    [
      ( "write",
        [
          test_case "single chunk" `Quick test_write_single_chunk;
          test_case "multiple chunks" `Quick test_write_multiple_chunks;
          test_case "empty execute" `Quick test_empty_execute;
          test_case "message_id in start" `Quick test_message_id_in_start;
        ] );
    ]
