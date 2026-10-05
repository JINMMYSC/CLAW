# CLAW Mobile Assistant Design

## Product goal

CLAW is a mobile-first 24-hour personal AI assistant. The host app is the assistant's brain and control center; CLAW TALK Keyboard is an equally important real-time input/output and sensing surface. The phone is the source of truth for memory. Desktop agents only import selected CLAW memory or export selected memories back to the phone.

## Core architecture

- `CLAW Memory Core`: local-first structured memory store shared by the host app and keyboard extension. Stores people, relationship context, conversation timeline entries, user preferences, tasks, commitments, waiting-for items, and evidence/provenance.
- `ContextBuilder`: retrieves only relevant current context. Retrieval order for reply scenarios is current input/screenshot > selected contact timeline > selected contact profile/relationship memory > global user preferences.
- `AssistantConversationService`: one persisted assistant conversation used by both keyboard quick-assistant and host-app assistant UI.
- `Skill Registry`: declarative skill definitions (prompt, capability, permissions, version, metrics) rather than downloaded executable Swift code.
- `Evolution Feedback`: records which suggestion was used, edited, regenerated, or discarded so prompts/preferences can improve without modifying executable code.

## Conversation/contact model

Each contact keeps a stable ID, display name, avatar, relationship metadata, manual bio, learned profile summary, and a chronological `ConversationMessage` timeline. Screenshot ingestion OCRs text, infers speaker ordering when possible, associates it with the selected/detected contact, deduplicates messages, stores provenance, and updates the timeline. Contacts never leak into each other's context.

## Keyboard UX

Toolbar prioritizes context and action: selected contact, 帮你回, 超会说, AI, then secondary controls. The AI overlay is adaptive rather than fixed at 150pt: compact around 140pt, normal around 175pt, expanded around 210pt. It must not become a half-screen chat surface.

- 帮你回: visible screenshot button, selected contact, concise reply suggestions, one-tap insert.
- 超会说: original text to improved text, style chips, replace/insert action.
- AI: short assistant view showing only recent turns; long-form interaction belongs in the host app.

## Host app UX

The CLAW host surface starts with the assistant conversation, then exposes Today/Secretary, People, Memory, and Data Exchange. The existing raw-data tools remain accessible but stop being the conceptual home page.

## Memory exchange

Internal canonical storage is SQLite. External interchange supports Markdown, JSON, JSONL, and a `.clawmemory` package. Import always follows parse -> classify -> deduplicate -> conflict check -> preview -> commit. Markdown is the default human/agent exchange format, not the internal database.

## Privacy and safety

Collection stays user-controlled. Password fields remain blocked. Sensitive filtering remains in place. The app does not claim system-wide invisible monitoring. Screenshot capture on current iOS is user-triggered through supported system flows. Memory records keep provenance and can be deleted by scope/contact.

## Compatibility

- iOS deployment floor remains iOS 15.
- Existing RIME input-method behavior and signing identifiers remain unchanged.
- App Group remains the sharing seam between host and keyboard.
- Existing ClawTalk, AutoInsight, SmartFreq, voice, and AI provider functionality should be reused rather than rewritten when possible.
Process exited with code 0.