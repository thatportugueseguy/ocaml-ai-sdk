(** Melange bindings for [@ai-sdk/react] v3.0.118.

    Provides OCaml bindings for the [useChat] and [useCompletion] React hooks
    from Vercel's AI SDK.

    {b Modules:}
    - {!Types} — Shared types ([ui_message], [chat_status], message parts, etc.)
    - {!Use_chat} — The [useChat] hook for conversational UIs
    - {!Use_completion} — The [useCompletion] hook for text completion

    @see <https://ai-sdk.dev/docs/ai-sdk-ui> AI SDK UI documentation *)

module Types = Types
module Use_chat = Use_chat
module Use_completion = Use_completion
