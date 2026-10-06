# CLAW Mobile Assistant Redesign

## Product goal

CLAW is a mobile-first 24-hour personal AI assistant. The host app is the assistant brain and control center; CLAW TALK keyboard is an equally important high-frequency sensing, writing, and execution surface.

## Core architecture

1. **Memory Core** is the canonical source of truth for long-term knowledge.
2. **Conversation Timeline** stores structured per-person chat history and source provenance.
3. **Context Builder** assembles only the memories relevant to the current person, task, and surface.
4. **Assistant Conversation** is shared between the host app and keyboard quick assistant.
5. **Skills** define reusable prompt/workflow behavior; the first evolution loop learns from adoption/edit feedback without downloading or executing arbitrary Swift code.
6. **Memory Exchange** imports/exports Markdown, JSON/JSONL, and a packaged .clawmemory archive.

## Keyboard design

The keyboard must not materially cover the host chat screen.

- compact panel: about 140 pt
- standard panel: about 175 pt
- expanded keyboard maximum: about 210 pt
- help-reply uses reply cards and explicit screenshot entry
- super-talk shows source text and optimized result
- AI is a compact quick-assistant view; long sessions continue in the host app
- current chat target remains visible and isolated from other contacts

## Host app design

The primary CLAW host surface is an AI assistant conversation window, with access to people, memory, today/secretary state, and settings/data tools. Existing ClawTalk data management becomes a supporting tool instead of the primary product surface.

## Memory and privacy

- internal store: structured local database abstraction with SQLite-ready schema
- global and contact scopes are separated
- every derived memory retains provenance and confidence
- imported memories are previewed, deduplicated, conflict-checked, and then committed
- raw screenshots remain evidence; structured messages are the canonical conversation representation

## Exchange formats

- Markdown: default human/agent interchange
- JSON/JSONL: structured machine interchange
- .clawmemory: full backup/migration package

## Compatibility

- minimum iOS version remains iOS 15
- reuse current App Group and existing services where practical
- no secrets or signing material are committed
- dynamic skills are interpreted data/workflows, not downloaded executable Swift code

