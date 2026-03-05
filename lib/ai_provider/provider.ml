module type S = sig
  val name : string
  val language_model : string -> Language_model.t
end

type t = (module S)

let language_model (module P : S) model_id = P.language_model model_id
let name (module P : S) = P.name
