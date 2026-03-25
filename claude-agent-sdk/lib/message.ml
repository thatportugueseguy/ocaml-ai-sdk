open Melange_json.Primitives

type message_envelope = {
  type_ : string; [@json.key "type"] [@json.default ""]
}
[@@json.allow_extra_fields] [@@deriving of_json]

type t =
  | System of Types.system_message
  | Assistant of Types.assistant_message
  | Result of Types.result_message
  | User of Types.user_message
  | Control_request of Types.control_request
  | Control_response of Types.control_response
  | Unknown of Yojson.Basic.t

let of_json json =
  let type_ =
    try (message_envelope_of_json json).type_
    with _ -> ""
  in
  match type_ with
  | "system" -> (try System (Types.system_message_of_json json) with _ -> Unknown json)
  | "assistant" -> (try Assistant (Types.assistant_message_of_json json) with _ -> Unknown json)
  | "result" -> (try Result (Types.result_message_of_json json) with _ -> Unknown json)
  | "user" -> (try User (Types.user_message_of_json json) with _ -> Unknown json)
  | "control_request" -> (try Control_request (Types.control_request_of_json json) with _ -> Unknown json)
  | "control_response" -> (try Control_response (Types.control_response_of_json json) with _ -> Unknown json)
  | _ -> Unknown json

let is_result = function
  | Result _ -> true
  | _ -> false

let result_text = function
  | Result r -> r.result
  | _ -> None

let assistant_text = function
  | Assistant a ->
    let texts =
      List.filter_map
        (function
          | Types.Text { text } -> Some text
          | _ -> None)
        a.message.content
    in
    if texts = [] then None else Some (String.concat "" texts)
  | _ -> None

let session_id = function
  | System s -> s.session_id
  | Assistant a -> a.session_id
  | Result r -> r.session_id
  | _ -> None
