---
name: prune-prose
description: Rules for pruning source comments, CHANGELOG entries and docs. Use when /simplify runs, or when the user asks for a comment or doc cleanup ("棚卸し", "prune the comments", "tidy the docs").
---

# prune-prose

## Source comments (`.mbt`, and `CHANGELOG.md`)

1. Short beats long. Cap at 5 lines outside sample code.
2. No issue numbers. References live in commits and PRs.
3. Don't say what the code already says. A short note that makes complex
   logic readable, or an example of the state being handled, is fine.
4. A public API block keeps its doc comment and its usage example — trim
   those, never delete them.

```moonbit
// bad — the code already says this
// add two numbers
let c = a + b
```

## Docs (`website/`, `docs/`, `README*.md`)

1. Lead with the main usage. Edge cases are a footnote, not the body.
2. Sample code must actually run. `just docs-check` is what says so — keep
   each block's fence as it is (` ```moonbit `, ` ```moonbit no-check `,
   ` ```mbt-example `), because the fence is what selects it.

Out of scope: `docs/roadmap.md` and `AGENTS.md`, whose issue links are their
content.
