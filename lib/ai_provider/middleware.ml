module type S = sig
  val wrap_generate : generate:(Call_options.t -> Generate_result.t Lwt.t) -> Call_options.t -> Generate_result.t Lwt.t

  val wrap_stream : stream:(Call_options.t -> Stream_result.t Lwt.t) -> Call_options.t -> Stream_result.t Lwt.t
end

let apply (module Mw : S) (model : Language_model.t) : Language_model.t =
  let (module M : Language_model.S) = model in
  (module struct
    let specification_version = M.specification_version
    let provider = M.provider
    let model_id = M.model_id
    let generate opts = Mw.wrap_generate ~generate:M.generate opts
    let stream opts = Mw.wrap_stream ~stream:M.stream opts
  end)
