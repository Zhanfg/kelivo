# GitHub Story Serialization

Use this Skill only when the user explicitly asks to export, checkpoint, version, restore, or publish Story Runtime state.

## Rules

1. Treat the local Story serialization bundle as the canonical payload. Do not reconstruct state from visible prose.
2. For export/checkpoint, call the Story export capability first. The resulting JSON is already versioned and checksum-protected.
3. If a GitHub MCP profile exposes repository file tools, store the bundle as a normal repository file such as `story-state/<name>.kelivo-story.json`.
4. Never include provider API keys, MCP OAuth tokens, passwords, or unrelated Kelivo settings in a Story bundle.
5. Before restore, show the target bundle/repository/path to the user and use the Story restore capability only after the host approval gate succeeds.
6. Never bypass Kelivo's native MCP tool approval or route identity checks.
7. Prefer append-only checkpoints or explicit versioned filenames over silently overwriting the only known-good snapshot.
8. A GitHub commit is transport/version control, not the Story database itself. Runtime state remains local until an explicit restore is applied.
