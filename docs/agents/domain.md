# Domain Docs

How the engineering skills should consume the domain documentation for Mopidy and its extensions. Core and all extensions share one context. Paths are relative to the workspace root, `~/mopidy-dev/`.

## Before exploring, read these

- **`workspace/CONTEXT.md`**: the glossary for Mopidy core and all extensions.
- **`workspace/docs/adr/`**: read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

```text
~/mopidy-dev/
└── workspace/
    ├── CONTEXT.md
    └── docs/adr/
        ├── 0001-<decision>.md
        └── 0002-<decision>.md
```

Do not put `CONTEXT.md` or ADRs in `mopidy/` or `mopidy-*/`.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
