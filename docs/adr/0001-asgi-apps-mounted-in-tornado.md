---
status: accepted
---

# ASGI apps are mounted in Tornado through a Mopidy bridge

Extensions register ASGI apps with a new `http:asgi` registry key, with
`name` and `factory: (config, core) -> ASGIApp`. The public type is a plain
ASGI callable, so no framework is part of the extension API. Mopidy uses
Starlette internally. In Mopidy 4.x, Tornado stays the outer server on one
port, and a Mopidy-owned bridge mounts each ASGI app at `/<name>/`, including
WebSockets and lifespan events. Mopidy's own endpoints also become an ASGI
app behind this bridge. Tornado apps (`http:app`) keep working, and they can
be removed in Mopidy 5, which then only replaces the outer server.

We chose this because 63 known extensions use `http:app` with Tornado
request handlers, and 16 of them use `WebSocketHandler`. Tornado has no
released ASGI support, and running Tornado WebSocket handlers under an ASGI
server is much harder than the reverse. See
[the research report](../research/http-asgi-migration.md).

## Considered options

- **ASGI server on the outside, with Tornado's `ASGIAdapter` for Tornado
  apps.** Rejected: the adapter is an unmerged draft PR with HTTP support
  only, so all Tornado apps with WebSockets would break.
- **Tornado and an ASGI server on two ports.** Rejected: users and web
  clients would see new URLs and cross-origin rules in 4.x, and then again
  when Tornado is removed.
- **Drop Tornado apps in 4.x.** Rejected: it breaks 63 known extensions.
- **Let the `http:app` factory return an ASGI app or Tornado rules.**
  Rejected: a separate key keeps the types clean and makes the removal of
  `http:app` in Mopidy 5 simple.
- **Starlette types in the public API.** Rejected: putting Tornado in the
  public API is the reason this migration is hard.

## Consequences

- The Tornado-to-ASGI WebSocket bridge does not exist yet. A prototype must
  show that it works before the rest is built.
- `http:app` is first deprecated in the docs only. A runtime warning comes in
  a later 4.x release.
