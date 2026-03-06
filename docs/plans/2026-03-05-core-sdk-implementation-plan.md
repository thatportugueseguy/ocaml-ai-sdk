# Core SDK Implementation Plan

**Goal:** Implement `ai_core` library with `generate_text`, `stream_text`, UIMessage stream protocol, and cohttp server handler for frontend interop with `useChat()`.

**Design doc:** `docs/plans/2026-03-05-core-sdk-design.md`

**Resolved decisions:**
- Multi-step tool loops in stream_text: YES
- Structured output (Output API): defer to v2
- Cohttp server handler: YES
- ID generation: simple counter per stream (txt_1, txt_2)
- Smooth streaming: defer to v2

---

## Task Dependency Graph

```
Group 1: Foundation Types
  1.1 Core_tool, Text_stream_part, Generate_text_result types
  1.2 Ui_message_chunk type + JSON serialization
  1.3 Ui_message_stream (SSE encoding + headers)
    │
Group 2: Core Functions
  2.1 Prompt_builder (string→messages, tool result appending)
  2.2 generate_text (with multi-step tool loop)
  2.3 stream_text (with multi-step tool loop)
    │
Group 3: Frontend Interop
  3.1 Stream_text_result.to_ui_message_stream transform
  3.2 Server handler (handle_chat)
    │
Group 4: Integration
  4.1 E2E tests with mock provider
  4.2 SSE wire format snapshot tests
  4.3 Final cleanup
```
