type t = {
  text_stream : string Lwt_stream.t;
  full_stream : Text_stream_part.t Lwt_stream.t;
  usage : Ai_provider.Usage.t Lwt.t;
  finish_reason : Ai_provider.Finish_reason.t Lwt.t;
  steps : Generate_text_result.step list Lwt.t;
  warnings : Ai_provider.Warning.t list;
}
