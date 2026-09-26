# Research: migrate mopidy-http from Tornado to ASGI or WSGI

Date: 2026-09-25.
Scope: the bundled HTTP frontend in `mopidy/src/mopidy/_exts/http/` and the
`http:app` and `http:static` extension API.
This document gives facts and options. It does not make the design decision.

Conventions:

- Paths without a host are relative to `~/mopidy-dev/`.
- `site-packages/` means `.venv/lib/python3.14/site-packages/` (Tornado 6.5.8,
  Pykka 4.4.2).
- `sdist:<pkg>/…` means the source distribution of that package from PyPI,
  unpacked and read locally: uvicorn 0.53.0, hypercorn 0.18.0, granian 2.8.3,
  starlette 1.7.0, a2wsgi 1.10.10.
- "Verified by test" means a local test script ran with Python 3.14.7,
  tornado 6.5.8, uvicorn 0.53.0, starlette 1.7.0 and websockets.
  The script is not in the repo.

## Summary

- The compatibility surface is large. The survey found 76 extensions that
  register an HTTP key. 63 use `http:app` and 13 use only `http:static`.
  31 are active (a commit since 2024). Of the 63 `http:app` users, 57 use
  `initialize()` kwargs, 38 use `StaticFileHandler`, 18 use Tornado
  templates, 16 use `WebSocketHandler` and 8 use the IOLoop directly
  (section 3).
- Tornado has no ASGI support in any release. A draft PR
  ([tornadoweb/tornado#3571](https://github.com/tornadoweb/tornado/pull/3571))
  adds an `ASGIAdapter` that runs a Tornado `Application` in an ASGI server,
  for HTTP only. The Tornado maintainer wants WebSockets left out of the
  first version. Tornado 6.6 (alpha on 2026-09-22) does not include it.
- No maintained third-party bridge exists in either direction. The only one
  found (plter/tornado_asgi_handler) is about 50 lines, HTTP only, and not
  updated since 2023. `tornado.wsgi.WSGIContainer` runs WSGI apps in Tornado,
  buffers full bodies, has no WebSocket support, and by default runs on the
  event loop thread.
- Tornado and uvicorn can share one asyncio loop in one non-main thread.
  A small Tornado handler can also mount a Starlette app for HTTP. Both are
  verified by a local test (sections 1.4 and 1.5). A WebSocket bridge between
  Tornado and ASGI must be written from zero.
- uvicorn is the easiest server to embed: `Server.serve(sockets=…)` takes
  pre-bound sockets, skips signal handlers outside the main thread, and stops
  when `should_exit` is set. Traps: it configures logging unless
  `log_config=None`, and it calls `sys.exit()` on startup failure.
  hypercorn fails in a thread unless a `shutdown_trigger` is given. The
  granian embedded server is experimental and not in Debian (section 2).
- Most Mopidy internals are framework-neutral logic in Tornado classes:
  JSON-RPC, CSRF and origin checks, headers, redirects and zeroconf. The hard
  parts are the WebSocket broadcast from the actor thread, the blocking
  `Future.get()` on the event loop thread, the Tornado template for the
  client list, and the tests (section 4).
- The public type `RequestRule` names `tornado.web.RequestHandler`
  (`mopidy/src/mopidy/_exts/http/types.py:14-17`), and the docs call Tornado
  handlers "first class" (`mopidy/docs/reference/http-server.md:58-62`).
  Full backward compatibility therefore means that Tornado must still serve
  those handlers, for example beside a new ASGI entry point.
- Mopidy 4.0.0 already removed `mopidy.http`. The 4 surveyed extensions that
  import `mopidy.http.handlers` are already broken on Mopidy 4 (section 3.2).
- No earlier Mopidy discussion of ASGI, WSGI or replacing Tornado was found.
  Tornado came in 0.19 (2014) to replace CherryPy. Earlier Tornado upgrades
  (5.x) broke Iris and Mopidy's own WebSocket broadcast (section 5).

## 1. Tornado and ASGI/WSGI interop

### 1.1 WSGI in Tornado: `tornado.wsgi.WSGIContainer`

- Only one direction is supported: a WSGI app can run inside Tornado.
  A Tornado `Application` or `RequestHandler` cannot run in a WSGI server
  (`site-packages/tornado/wsgi.py:21-26`).
- The container buffers the full request body into `wsgi.input`
  (`site-packages/tornado/wsgi.py:233`) and the full response body before it
  writes the response (`site-packages/tornado/wsgi.py:163-181`, `:203`).
  There is no streaming in either direction.
- WebSockets and long-polling are not available in WSGI mode
  (`site-packages/tornado/wsgi.py:62-70`).
- Threading: since Tornado 6.3 the constructor takes an `executor`.
  Without it, the WSGI app runs on the event loop thread, one request at a
  time. This default is deprecated and will change to a thread pool in
  Tornado 7.0 (`site-packages/tornado/wsgi.py:102-123`, `:125-131`).
  The app call and each response chunk go through
  `IOLoop.run_in_executor` (`site-packages/tornado/wsgi.py:155-175`).
- Mounting: `tornado.web.FallbackHandler` wraps the container as a normal
  route (`site-packages/tornado/web.py:3242-3268`). Mopidy documents this
  pattern for WSGI apps, and calls WSGI apps "second-class citizens"
  (`mopidy/docs/reference/http-server.md:123-161`).
  Note: the example in that document uses `self.core` inside a plain function
  (`mopidy/docs/reference/http-server.md:151`), so the example does not run as
  written.
- Tornado 6.6.0 (6.6a1 on PyPI since 2026-09-22) does not change WSGI or add
  ASGI. Source: the 6.6.0 release notes
  (<https://github.com/tornadoweb/tornado/blob/master/docs/releases/v6.6.0.rst>),
  which have no ASGI, WSGI or WebSocket items.

### 1.2 ASGI support in Tornado

- Tornado has no ASGI support in any released version.
  The feature request is open since 2019:
  [tornadoweb/tornado#2666 "Add ASGI support"](https://github.com/tornadoweb/tornado/issues/2666).
- In January 2026 the maintainer (bdarnell) accepted a contribution.
  His guidelines in that issue:
  - Start with an `ASGIAdapter` on top of the existing classes.
  - Do not make ASGI the native layer at first.
  - Leave WebSockets out of the first version, because `WebSocketHandler`
    takes the socket out of the `HTTPServer` layer.
- The work is
  [tornadoweb/tornado#3571 "ASGI HTTP support"](https://github.com/tornadoweb/tornado/pull/3571):
  draft, open, last update 2026-03-25. It adds `tornado/asgi.py` with
  `ASGIAdapter(Application)`. This is the direction "Tornado handlers inside
  an ASGI server". It is HTTP only, with no WebSocket support.
  `tornado/asgi.py` is not on the `master` branch (GitHub API returns 404 on
  2026-09-25).
- Consequence: if this PR is merged, an ASGI server could serve existing
  `http:app` Tornado handlers for plain HTTP. `WebSocketHandler` subclasses
  would still need Tornado's own server. There is no date for a release.

### 1.3 Third-party bridges

| Project | Direction | WebSocket | Status |
| --- | --- | --- | --- |
| [plter/tornado_asgi_handler](https://github.com/plter/tornado_asgi_handler) | ASGI app inside Tornado, as a `RequestHandler` | No | Last push 2023-08-14, 8 stars, not on PyPI. About 50 lines. Only `get` and `post`. It sets the ASGI scope `type` to the request protocol, so `https` gives an invalid scope. |
| Tornado PR #3571 | Tornado `Application` inside an ASGI server | No | Draft, see 1.2. |
| [a2wsgi](https://github.com/abersheeran/a2wsgi) | WSGI app inside ASGI, and ASGI app inside WSGI | Closes WebSocket scopes (`sdist:a2wsgi/a2wsgi/wsgi.py:170-172`) | Release 1.10.10 on 2025-06-18, last push 2026-03-22. Packaged in Debian (`python-a2wsgi`, trixie and later). Starlette points to it as the replacement for its deprecated `WSGIMiddleware` (`sdist:starlette/starlette/middleware/wsgi.py:18-23`). |

- The names `tornado-asgi`, `tornado-asgi-handler`, `asgi-tornado` and
  `tornasgi` are not on PyPI (PyPI JSON API returns 404, checked 2026-09-25).
- I found no maintained adapter that runs Tornado `WebSocketHandler` in an
  ASGI server. This is based on the searches above; a more complete search is
  not done (unverified).

### 1.4 Tornado and uvicorn in one event loop

- Since Tornado 6.0, `IOLoop` is a wrapper around the asyncio event loop
  (`site-packages/tornado/ioloop.py:18-22`, `:75`).
- Verified by test: in one non-main thread, with one asyncio loop, these ran
  at the same time:
  - a Tornado `HTTPServer` on sockets from `tornado.netutil.bind_sockets`;
  - `uvicorn.Server.serve(sockets=[sock])` with a Starlette app, on a second
    port;
  - HTTP to both servers and a WebSocket to uvicorn worked;
  - `loop.call_soon_threadsafe(setattr, server, "should_exit", True)` from the
    main thread stopped uvicorn, `serve()` returned, and the thread ended.
- Two servers need two ports (or two sockets). One listening socket cannot
  feed both servers. A single public port needs one server that routes to the
  other, as in 1.5.

### 1.5 Mount an ASGI app inside Tornado with a custom handler

- HTTP: possible with a small `RequestHandler` that builds an ASGI `http`
  scope from `self.request` and maps `http.response.start` and
  `http.response.body` to `set_status`, `add_header`, `write` and `flush`.
  Verified by test: a Starlette app mounted at `/asgi/` in Tornado returned
  the correct response. Limits:
  - Tornado reads the full body before the handler runs, unless the handler
    uses `@tornado.web.stream_request_body`.
  - Tornado sets default headers (`Server`, `Content-Type`, `Date`); the
    handler must clear them.
  - The prefix goes into `root_path` and must be removed from `path`.
- A lower-level design is a `tornado.routing.Router` whose `find_handler`
  returns an `httputil.HTTPMessageDelegate`
  (`site-packages/tornado/routing.py:201-206`). The delegate gets body chunks
  in `data_received` (`site-packages/tornado/httputil.py:688`, `:714`), so
  the request body can stream into ASGI `receive()`. Not built or tested
  here.
- WebSocket: no existing code. `WebSocketHandler.get` checks the headers and
  `check_origin`, then does the handshake itself
  (`site-packages/tornado/websocket.py:230-280`). ASGI lets the app decide:
  the app sends `websocket.accept` (with an optional subprotocol and headers)
  or `websocket.close` before the handshake. A bridge must run the ASGI app
  until the first `send` before it lets Tornado accept, then feed
  `on_message` into `receive()` and map `send` to `write_message` and
  `close`. This is possible in principle but not verified.

## 2. Run an ASGI server in a non-main thread

Common facts:

- In CPython, `loop.add_signal_handler` raises `RuntimeError` outside the main
  thread, because `signal.set_wakeup_fd` raises `ValueError` there
  (`~/.local/share/uv/python/cpython-3.14.7-linux-x86_64-gnu/lib/python3.14/asyncio/unix_events.py`,
  in `add_signal_handler`, "set_wakeup_fd() raises ValueError if this is not
  the main thread").
- Mopidy already runs Tornado this way: a `threading.Thread` subclass creates
  its own asyncio loop (`mopidy/src/mopidy/_exts/http/actor.py:143-156`).

### 2.1 uvicorn

- Documented API: `uvicorn.Config` plus `uvicorn.Server`, and
  `await server.serve()` "from an already running async environment"
  (<https://github.com/Kludex/uvicorn/blob/main/docs/index.md>, lines 135-161).
- Signals: `Server.capture_signals()` does nothing when the current thread is
  not the main thread (`sdist:uvicorn/uvicorn/server.py:331-336`). In the main
  thread it replaces SIGINT and SIGTERM handlers and re-raises the signal
  after shutdown (`sdist:uvicorn/uvicorn/server.py:337-356`).
  So in a Mopidy thread, uvicorn does not touch Mopidy's signal handling.
- Shutdown: set `server.should_exit = True`. `main_loop` checks it every
  0.1 s (`sdist:uvicorn/uvicorn/server.py:242-271`). Then `shutdown()` closes
  the listeners, asks each connection to shut down, waits for connections and
  tasks, with an optional `timeout_graceful_shutdown`, and runs the lifespan
  shutdown (`sdist:uvicorn/uvicorn/server.py:281-329`).
  `force_exit = True` skips the wait.
- Binding: `Config(host=…, port=…)`, `uds=…` or `fd=…`, or pass pre-bound
  sockets to `serve(sockets=[…])` (`sdist:uvicorn/uvicorn/server.py:135-160`).
  Pre-bound sockets let Mopidy bind in the actor constructor and raise
  `FrontendError` there, as it does today
  (`mopidy/src/mopidy/_exts/http/actor.py:52-64`).
- Traps for embedding:
  - `Config.__init__` calls `configure_logging()`
    (`sdist:uvicorn/uvicorn/config.py:303`). With the default `log_config`
    this runs `logging.config.dictConfig` (`:387-398`) and changes the
    process logging setup. Pass `log_config=None`.
  - A startup failure calls `sys.exit(STARTUP_FAILURE)`: lifespan failure
    (`sdist:uvicorn/uvicorn/server.py:115-118`) and bind failure
    (`:189-192`). In a thread, `SystemExit` ends only that thread.
    Mopidy must detect it (for example, check `server.started`).
- Dependencies: `click` and `h11` (`sdist:uvicorn/pyproject.toml:34-38`).
  WebSocket support needs `websockets` or `wsproto`; with neither, uvicorn
  has no WebSocket protocol
  (`sdist:uvicorn/uvicorn/protocols/websockets/auto.py`).
- Status: release 0.53.0 on 2026-09-14, repo pushed 2026-09-24.
  Debian: `python-uvicorn` 0.32.0 in trixie, 0.53.0 in sid
  (<https://sources.debian.org/src/python-uvicorn/>).

### 2.2 hypercorn

- API: `hypercorn.asyncio.serve(app, config, shutdown_trigger=…)`.
  "It is assumed that the event-loop is configured before calling this
  function" (`sdist:hypercorn/src/hypercorn/asyncio/__init__.py:13-47`).
  Docs: <https://github.com/pgjones/hypercorn/blob/main/docs/how_to_guides/api_usage.rst>.
- Signals: if `shutdown_trigger` is `None`, `worker_serve` calls
  `loop.add_signal_handler` for SIGINT, SIGTERM and SIGBREAK and catches only
  `NotImplementedError` (`sdist:hypercorn/src/hypercorn/asyncio/run.py:64-79`).
  In a non-main thread this raises `RuntimeError` (see common facts).
  So an embedded hypercorn must always get a `shutdown_trigger`, for example
  `asyncio.Event().wait`. Not verified by test.
- Binding: `config.bind` takes `host:port`, `unix:` and `fd://N`
  (`sdist:hypercorn/src/hypercorn/config.py:230-245`). The public `serve()`
  does not take socket objects; `worker_serve` does (`run.py:54-59`), but it
  is internal.
- Supports HTTP/2 and WebSocket with `h2` and `wsproto` as hard dependencies
  (`sdist:hypercorn/pyproject.toml:29-38`). Can also serve WSGI apps
  (`mode="wsgi"`).
- Status: release 0.18.0 on 2025-11-08; the repo was last pushed on the same
  day. Debian: `hypercorn` 0.17.3 in trixie and sid.

### 2.3 granian

- Rust server with a Python API. The embeddable server is
  `granian.server.embed.Server(app, interface="asgi")` with async `serve()`
  and `stop()` (`sdist:granian/README.md:607-640`).
  The README marks it "still experimental" and says it has no WSGI support
  and one worker only (`sdist:granian/README.md:611-613`,
  `sdist:granian/granian/server/embed.py:465-467`).
- Signals: the embedded `serve()` does not call `set_main_signals`; only the
  non-embedded server does (`sdist:granian/granian/server/common.py:486`).
- Binding: `address`, `port`, `uds` (`sdist:granian/granian/server/common.py:93-96`).
  I found no pre-bound socket option (unverified).
- Packaging: compiled Rust extension. Not in Debian (no `granian` or
  `python-granian` source package on sources.debian.org, checked
  2026-09-25). Wheel availability on all Mopidy target platforms (for
  example 32-bit ARM) is not checked (unverified).

### 2.4 Summary table

| Server | Embed API | Signal handlers in non-main thread | Pre-bound socket | Debian (trixie) |
| --- | --- | --- | --- | --- |
| uvicorn | `Server.serve()`, documented | Skipped automatically | Yes, `serve(sockets=…)` | 0.32.0 |
| hypercorn | `serve(app, config, shutdown_trigger=…)`, documented | Fails unless `shutdown_trigger` is given | `fd://N` bind string | 0.17.3 |
| granian | `embed.Server`, experimental | Not installed by embed server | Not found | No |
| Tornado (current) | `HTTPServer.add_sockets` | Not installed | Yes | 6.4.2 |

## 3. What third-party extensions use

### 3.1 Method

- Sources:
  - The latest release of each PyPI project whose name starts with `mopidy`
    (164 names from the PyPI simple index), unpacked and searched.
  - 171 GitHub repos, shallow-cloned and searched. They come from PyPI
    project URLs, `website/_ext/*.md` and GitHub code search.
  - The local checkouts `mopidy-*/`. Of these, only
    `mopidy-local/src/mopidy_local/__init__.py:48` (`http:app`) and
    `mopidy-api-explorer/src/mopidy_api_explorer/__init__.py:22`
    (`http:static`) register an HTTP key.
- A regex script found the features. Key hits were then checked by hand, and
  false positives were removed: lines that only import, `mopidy.httpclient`,
  docstrings, and an unrelated "cookie" field.
- Forks and copies are not in the table: bglowacki/iris, mathcals/Iris,
  antoniooodev/SavorSound, Zashas/mopidy-alarmclock, robp2175/mopidy-jukebox,
  very-amused/mopidy-local-old, laurci/IWASAMC.
- How to read the table:
  - A path is relative to the repo root on the default branch. The full URL is
    `<repo>/blob/<default-branch>/<path>`. The default branch is `develop`
    for AlarmClock, MusicBox-Webclient, WebSettings, YouTube and WebLibrary.
  - `sdist:` is a path in the latest PyPI sdist. It is used where the repo
    returns 404.
  - "Last commit" is the HEAD commit date on the default branch.
  - "Req" is the Mopidy version the package requires.
- Limits (unverified):
  - The search does not find features that code reaches only through dynamic
    dispatch.
  - Mopidy 4 support is taken from the version constraint and the website
    `compat` data only. No extension was run on Mopidy 4.
  - Some PyPI projects have no release files, so their source was not
    checked: Arcam, ArduinoLCD_Info, IntergalacticFM (its GitHub HEAD
    registers nothing), Serial, ShivRPi, YamahaMixer.
  - For mopidy-mqtt (odiroot), mopidy-plex (havardgulldahl) and
    mopidy-spotify-web the repos return 404, so only the PyPI release was
    checked.
  - No repo or PyPI project was found for `mopidy-nts`.
  - `mopidy-lastfm` (colonelpanic8, last push 2015) was not checked.

### 3.2 Counts

Scope: 76 extensions (51 on PyPI, 25 only on GitHub).

- **63 register `http:app`.** 12 of them also register `http:static`.
- **13 register only `http:static`.** These need no change if the
  `http:static` contract stays the same.
- **31 are active**: a commit since 2024-01-01 and not archived. Of these,
  27 use `http:app` and 4 use `http:static` only.
- **Mopidy 4 support declared**: Local, API-Explorer, Pibox and eboplayer.
  The website also lists YouTube and Mobile as supported, and Iris as "in
  progress" ([jaedb/Iris#999](https://github.com/jaedb/Iris/issues/999)).

Tornado features used, counted over the 63 `http:app` users. The counts
include the Iris copies (Juliana, Cranberry) and the Darkclient fork.

| Feature | Count |
| --- | --- |
| `initialize()` kwargs | 57 |
| Plain `RequestHandler` subclass | 55 |
| `StaticFileHandler` (use or subclass) | 38 |
| `redirect()` or `RedirectHandler` | 19 |
| Templates (`render`, `get_template_path`, `tornado.template.Loader`) | 18 |
| `WebSocketHandler` (or a WebSocket client) | 16 |
| CORS headers set by hand | 14 |
| `async` or `gen.coroutine` handlers | 11 |
| `check_origin` override | 9 |
| Direct IOLoop use | 8 |
| `flush()` streaming | 7 |
| `tornado.httpclient` | 7 |
| Cookies or secure cookies | 4 (Auto, Transistor, radio-pi, bamp) |
| Imports from `mopidy.http` | 4 (Advanced-Scrobbler, Bookmarks, WebSettings, bamp) |
| `request.files` uploads | 4 |
| `get_current_user` or `@authenticated` | 3 |
| `tornado.locale` | 3 |
| `self.application.settings` or own `tornado.web.Application` | 3 (Auto, Spotmop, bamp) |

Notes:

- The WebSocket count includes Spotmop. Its WebSocket runs on its own
  Tornado server, not through `http:app`.
- 5 extensions call `IOLoop.add_callback` from actor threads to push
  WebSocket messages: Iris, Juliana, Bookmarks, eboplayer and rfid.
- The 4 extensions that import `mopidy.http` are already broken on Mopidy 4:
  Mopidy 4.0.0 removed `mopidy.http` and moved the bundled extensions to the
  private package `mopidy._exts` (`mopidy/docs/changelog/index.md:376-382`,
  under `## v4.0.0` at line 117). `import mopidy.http` fails in the current
  workspace (checked 2026-09-25).
- Mopidy-Bookmarks imports the private `_send_broadcast` from
  `mopidy.http.handlers`.
- mopidy-bamp reads `registry["http:app"]` and `registry["http:static"]` and
  runs its own copy of the Mopidy HTTP frontend. This is the deepest coupling
  found.

What this means for the compatibility surface:

1. Nearly all `http:app` users return `(pattern, HandlerClass, kwargs)`
   tuples with Tornado `RequestHandler` subclasses and `initialize()` kwargs.
   Full backward compatibility means that Tornado must still serve these
   handlers.
2. 16 of 63 use WebSockets. No ASGI bridge for Tornado WebSockets exists
   (section 1). So a pure ASGI server cannot serve these handlers without new
   bridge code.
3. Many use Tornado-only helpers: templates, `tornado.locale`, secure
   cookies with Mopidy's `cookie_secret`, `tornado.httpclient` and the
   IOLoop. The extension can keep these only if Tornado stays installed and
   the handler runs in Tornado.

### 3.3 Table

| Extension | Repo | Registers | Tornado features (first hit) | Last commit | Last PyPI release | Archived | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Mopidy-Advanced-Scrobbler | <https://github.com/djmattyg007/mopidy-advanced-scrobbler> | app `mopidy_advanced_scrobbler/__init__.py#L48` | RequestHandler `web.py#L67`; StaticFileHandler `__init__.py#L69`; initialize `web.py#L59`; CORS `web.py#L83`; `mopidy.http` import `web.py#L10` | 2022-03-05 | 2.1.0 (2021-08-16) | no | Req Mopidy>=3.1.1. Imports `StaticFileHandler`, `check_origin`, `set_mopidy_headers` from `mopidy.http.handlers`. |
| Mopidy-AlarmClock | <https://github.com/DavisNT/mopidy-alarmclock> | app `mopidy_alarmclock/__init__.py#L33` | RequestHandler `http.py#L19`; StaticFileHandler `http.py#L98`; templates `http.py#L10`; initialize `http.py#L20`; redirect `http.py#L28` | 2023-01-29 | 0.1.9 (2020-03-21) | no | No req. Uses `tornado.template.Loader`. Website: Mopidy 4 not supported. |
| Mopidy-API-Explorer | <https://github.com/mopidy/mopidy-api-explorer> | static `src/mopidy_api_explorer/__init__.py#L22` | None | 2026-09-19 | 2.0.0 (2026-04-25) | no | Req mopidy>=4.0.0. |
| Mopidy-Auto | <https://github.com/gotling/mopidy-auto> | app `mopidy_auto/__init__.py#L43` | RequestHandler `web.py#L12`; StaticFileHandler `__init__.py#L53`; templates `web.py#L19`; initialize `web.py#L13`; secure cookies `web.py#L19`; redirect `web.py#L44`; `self.application.settings` `web.py#L16` | 2018-06-16 | 0.5.0 (2018-05-19) | no | Req Mopidy>=1.0. Sets `cookie_secret` in app settings from `initialize()`. |
| Mopidy-Bandcamp | <https://github.com/impliedchaos/mopidy-bandcamp> | app `mopidy_bandcamp/__init__.py#L40` | RequestHandler `web.py#L11`; initialize `web.py#L12` | 2026-08-05 | 1.1.5 (2021-05-13) | no | Req Mopidy>=3.0.0. Website: Mopidy 4 "unreleased". |
| Mopidy-BigScreen | <https://github.com/benreid24/Mopidy-BigScreen> | app `__init__.py#L49`, static `#L42` | RequestHandler `__init__.py#L13`; initialize `#L14` | 2024-02-27 | 0.1.0 (2024-02-27) | no | Req Mopidy>=3.0.0. |
| Mopidy-Bookmarks | <https://github.com/sapristi/mopidy-bookmarks> | app `mopidy_bookmarks/__init__.py#L43` | WebSocket `__init__.py#L56`; initialize `handlers.py#L69`; IOLoop `handlers.py#L57`; `mopidy.http` import `handlers.py#L12` | 2025-03-15 | 0.1.4 (2020-07-31) | no | Req Mopidy>=3.0.0. Subclasses `mopidy.http.handlers.WebSocketHandler` and imports private `_send_broadcast`. |
| Mopidy-ChoosMoos | <https://github.com/doronhorwitz/mopidy-choosmoos> | app `mopidy_choosmoos/__init__.py#L39` | RequestHandler `web.py#L15`; StaticFileHandler `web.py#L92`; WebSocket `web.py#L47`; check_origin `web.py#L51` | 2020-10-23 | 1.0.0 (2020-09-04) | no | Req Mopidy>=3.0. |
| Mopidy-Cranberry | <https://github.com/alkern/cranberry> (404) | app `sdist:mopidy_cranberry/__init__.py#L34` | StaticFileHandler `sdist:…/__init__.py#L7`; initialize `#L54`; AsyncHTTPClient `sdist:…/core.py#L47` | Repo 404 | 0.1.0rc5 (2025-08-10) | Repo 404 | Req Mopidy>=3.0. Derived from Iris. |
| Mopidy-DebugRel | <https://github.com/sapristi/mopidy-debugrel> | app `src/mopidy_debugrel/__init__.py#L76` | RequestHandler `#L16`; initialize `#L17` | 2025-02-26 | 1.0.1 (2025-02-26) | no | Req mopidy>=3.4.1. |
| Mopidy-FileManager | <https://github.com/respeaker/mopidy-filemanager> | app `mopidy_filemanager/__init__.py#L37`, static `#L32` | RequestHandler `file_manager.py#L264`; StaticFileHandler `#L298`; initialize `#L265`; uploads `#L237` | 2016-12-30 | 0.2.0 (2016-11-17) | no | No req. IOLoop use is only in a standalone `main()` (`#L307`). |
| Mopidy-GPIO420 | <https://github.com/v1nc/mopidy-gpio420> | static `mopidy_gpio420/__init__.py#L45` | None | 2016-04-11 | 0.1.0 (2016-04-11) | yes | No req. |
| Mopidy-Iris | <https://github.com/jaedb/Iris> | app `mopidy_iris/__init__.py#L47` | RequestHandler `handlers.py#L177`; StaticFileHandler `__init__.py#L58`; WebSocket `handlers.py#L17`; initialize `handlers.py#L20`; async `handlers.py#L50,#L199,#L238`; IOLoop `handlers.py#L23`, `frontend.py#L27`; AsyncHTTPClient `core.py#L422`; CORS `handlers.py#L179`; check_origin `handlers.py#L26` | 2026-04-02 | 3.70.0 (2025-05-03) | no | Req Mopidy>=3.0. Calls `ioloop.add_callback` from the frontend actor thread. Mopidy 4 work in progress. |
| Mopidy-Jukebox | <https://github.com/kingbutter/mopidy-jukebox> | app `src/mopidy_jukebox/__init__.py#L63`, static `#L54` | RequestHandler `web.py#L91`; initialize `#L92` | 2026-07-28 | 1.0.1 (2026-07-28) | no | Req Mopidy>=3.4. |
| Mopidy-JukeboxLights | <https://github.com/kingbutter/mopidy-jukebox-lights> | app `src/mopidy_jukebox_lights/__init__.py#L52` | RequestHandler `web.py#L179`; initialize `#L257`; redirect `#L267` | 2026-07-28 | 1.0.1 (2026-07-28) | no | Req Mopidy>=3.4. |
| Mopidy-jukePi | <https://github.com/connrs/mopidy-jukepi> (404) | app `sdist:mopidy_jukepi/__init__.py#L33` | RequestHandler `#L55`; StaticFileHandler `#L41`; templates `#L62`; initialize `#L56` | Repo 404 | 1.0.9 (2017-01-18) | Repo 404 | No req. |
| Mopidy-Lagukan | <https://github.com/jacobobryant/mopidy-lagukan> | static `mopidy_lagukan/__init__.py#L31` | None | 2019-10-19 | 0.2.4 (2019-10-02) | no | Req Mopidy>=1.0. |
| Mopidy-Local | <https://github.com/mopidy/mopidy-local> | app `src/mopidy_local/__init__.py#L48` | RequestHandler `web.py#L15`; StaticFileHandler subclass `web.py#L10`; templates `web.py#L20,#L22`; initialize `web.py#L16` | 2026-08-19 | 4.0.1 (2026-08-19) | no | Req mopidy>=4.0.2. Core team. |
| Mopidy-Local-Images | <https://github.com/mopidy/mopidy-local-images> | app `__init__.py#L34` | RequestHandler `web.py#L17`; StaticFileHandler `web.py#L11`; templates `web.py#L23`; initialize `web.py#L19` | 2019-12-08 | 1.0.0 (2015-09-05) | yes | No req. |
| Mopidy-Marceline | <https://github.com/ttoino/mopidy-marceline> | app `mopidy_marceline/__init__.py#L55` | StaticFileHandler subclass `#L16`; `async def get` override `#L17` | 2026-01-02 | 0.0.5 (2025-10-01) | no | Req mopidy>=3.4.1. |
| Mopidy-Market | <https://github.com/stffart/mopidy-market> | app `mopidy_market/__init__.py#L36` | RequestHandler `web.py#L30`; StaticFileHandler `web.py#L20`; templates `web.py#L50`; initialize `web.py#L31`; CORS `web.py#L134`; redirect `__init__.py#L40`; `tornado.locale` `web.py#L8` | 2022-05-05 | 0.8 (2022-05-05) | no | Req Mopidy>=3.0.0. |
| Mopidy-Master | <https://github.com/stffart/mopidy-master> | app `mopidy_master/__init__.py#L32` | RequestHandler `web.py#L13`; WebSocket `web.py#L89`; initialize `web.py#L15`; `gen.coroutine` `web.py#L18`; AsyncHTTPClient `web.py#L30`; CORS `web.py#L63`; flush `web.py#L52` | 2022-05-06 | 1.0.2 (2022-06-01) | no | No req. Also a WebSocket client (`devicesync.py#L69`). |
| Mopidy-Material-Webclient | <https://github.com/matgallacher/Mopidy-Material-Webclient> | app `__init__.py#L40` | RequestHandler `#L55`; StaticFileHandler `#L43`; initialize `#L73` | 2015-12-30 | 0.2.1 (2015-07-19) | no | No req. |
| Mopidy-MFE | <https://github.com/LukeMcDonnell/mopidy-MFE> (404) | static `sdist:mopidy_mfe/__init__.py#L19` | None | Repo 404 | 0.4.9 (2016-06-13) | Repo 404 | No req. |
| Mopidy-Mobile | <https://github.com/tkem/mopidy-mobile> | app `mopidy_mobile/__init__.py#L26` | RequestHandler `web.py#L28`; StaticFileHandler `web.py#L13`; templates `web.py#L40,#L48`; initialize `web.py#L30`; RedirectHandler `__init__.py#L33` | 2025-02-02 | 1.11.0 (2025-02-02) | no | Req Mopidy>=0.19. Website: Mopidy 4 supported. |
| Mopidy-Moparty | <https://github.com/pingiun/mopidy-moparty> | app `mopidy_moparty/__init__.py#L121` | RequestHandler `#L29`; StaticFileHandler `#L90`; initialize `#L34` | 2020-04-07 | 0.3.2 (2020-04-03) | no | Req Mopidy>=3.0.0. |
| Mopidy-Moped | <https://github.com/martijnboland/moped> | static `mopidy_moped/__init__.py#L19` | None | 2017-05-21 | 0.7.1 (2017-05-21) | no | No req. |
| Mopidy-Mopidy | <https://github.com/stffart/mopidy-mopidy> | app `mopidy_mopidy/__init__.py#L36` | RequestHandler `web.py#L13`; WebSocket server `web.py#L43` and client `web.py#L69`; initialize `web.py#L15`; async `web.py#L90`; CORS `web.py#L21` | 2022-05-24 | 1.0 (2022-05-24) | no | No req. |
| Mopidy-Mopify | <https://github.com/dirkgroenen/mopidy-mopify> | app `mopidy_mopify/__init__.py#L49` | RequestHandler `services/autoupdate/update.py#L8`; StaticFileHandler `__init__.py#L65`; WebSocket `services/queuemanager/requesthandler.py#L13`; initialize `update.py#L14`; CORS `update.py#L12`; check_origin `requesthandler.py#L18` | 2023-01-19 | 1.7.3 (2020-04-22) | yes | No req. |
| Mopidy-Mowecl | <https://github.com/sapristi/mopidy-mowecl> | app `mopidy_mowecl/__init__.py#L75` | RequestHandler `file_server.py#L14`, `web_api_extra.py#L10`; StaticFileHandler `__init__.py#L109`; templates `file_server.py#L28`; initialize `file_server.py#L15`; CORS `web_api_extra.py#L13` | 2026-05-20 | 0.6.1 (2025-05-02) | no | Req Mopidy>=3.0. Website: Mopidy 4 not supported. |
| Mopidy-Muse | <https://github.com/cristianpb/muse> | app `mopidy_muse/__init__.py#L77` | RequestHandler `#L27`; StaticFileHandler `#L15`; initialize `#L16` | 2026-01-21 | 0.0.36 (2024-04-07) | no | Req Mopidy>=3.0.0. |
| Mopidy-MusicBox-Darkclient | <https://github.com/stffart/mopidy-musicbox-darkclient> | app `__init__.py#L44` | RequestHandler `web.py#L32`; StaticFileHandler `web.py#L18`; templates `web.py#L72`; initialize `web.py#L33`; redirect `__init__.py#L48`; `tornado.locale` `web.py#L8` | 2022-05-30 | 1.1 (2022-05-30) | no | Fork of MusicBox-Webclient. |
| Mopidy-MusicBox-Webclient | <https://github.com/pimusicbox/mopidy-musicbox-webclient> | app `__init__.py#L41` | RequestHandler `web.py#L28`; StaticFileHandler `web.py#L14`; templates `web.py#L61,#L69`; initialize `web.py#L29`; RedirectHandler `__init__.py#L50` | 2020-06-23 | 3.1.0 (2020-03-22) | no | Req Mopidy>=3.0.0. |
| Mopidy-Party | <https://github.com/Lesterpig/mopidy-party> | app `mopidy_party/__init__.py#L164`, static `#L160` | RequestHandler `#L10`; templates `#L97`; initialize `#L12`; redirect `#L124` | 2025-10-12 | 1.3.0 (2025-10-12) | no | No req. |
| Mopidy-Pibox | <https://github.com/gbannerman/mopidy-pibox> | app `mopidy_pibox/__init__.py#L88` | RequestHandler `api.py#L14`; StaticFileHandler `routing.py#L9`; WebSocket `socket.py#L7`; initialize `api.py#L15`; check_origin `socket.py#L11` | 2026-08-29 | 4.0.1 (2026-08-29) | no | Req mopidy>=4.0.0. |
| Mopidy-Pummeluff | <https://github.com/confirm/mopidy-pummeluff> | app `__init__.py#L80`, static `#L75` | RequestHandler `web.py#L25` | 2022-11-27 | 3.0.0 (2022-11-27) | no | Req Mopidy>=3. |
| Mopidy-Radio-Rough-HTML | <https://github.com/unusualcomputers/unusualcomputers> | app `code/mopidy/mopidyradioroughhtml/mopidy_radio_rough_html/__init__.py#L555` | RequestHandler `#L90`; StaticFileHandler `#L535`; initialize `#L91`; redirect `#L115`; flush `#L107` | 2021-01-04 | 31.41.5926 (2018-08-28) | no | No req. |
| Mopidy-RadioWorld | <https://github.com/anabolyc/Mopidy-RadioWorld> | static `mopidy_radioworld/__init__.py#L33` | None | 2022-05-06 | 0.2.0 (2022-05-06) | yes | Req Mopidy>=3.0.0. |
| Mopidy-Sangu | <https://github.com/smckend/mopidy_sangu> | app `__init__.py#L37`, static `#L45` | RequestHandler `api/admin.py#L8`; initialize `#L9`; CORS `api/vote.py#L39` | 2020-11-16 | 1.2.0 (2020-11-16) | no | Req Mopidy>=3.0.0. |
| Mopidy-SevenSegmentDisplay | <https://github.com/JuMalIO/mopidy-sevensegmentdisplay> | app `__init__.py#L40` | RequestHandler `http.py#L10`; StaticFileHandler `http.py#L111`; `tornado.template.Loader` `http.py#L7`; initialize `http.py#L11`; redirect `http.py#L18` | 2025-04-02 | 0.9.15 (2025-04-02) | no | Req Mopidy>=3.0. |
| Mopidy-Simple-Webclient | <https://github.com/xolox/mopidy-simple-webclient> | static `__init__.py#L24` | None | 2015-06-08 | 0.1.1 (2015-06-08) | no | No req. |
| Mopidy-Slack | <https://github.com/ablanchard/mopidy-slack> | app `mopidy_slack/__init__.py#L82` | RequestHandler `#L18`; initialize `#L19` | 2020-06-10 | 0.1.0 (2020-05-14) | no | Req Mopidy>=3.0.0. |
| Mopidy-Spotmop | <https://github.com/jaedb/spotmop> | app `mopidy_spotmop/__init__.py#L36` | StaticFileHandler `__init__.py#L49`. WebSocket (`pusher.py#L82`) runs on its own `tornado.web.Application(...).listen(port)` (`frontend.py#L45`) | 2017-01-02 | 2.10.1 (2016-09-28) | no | No req. Predecessor of Iris. |
| Mopidy-Transistor | <https://github.com/lukh/mopidy-transistor> | app `mopidy_transistor/__init__.py#L65` | RequestHandler `web/basics.py#L8`; StaticFileHandler `__init__.py#L99`; WebSocket `__init__.py#L85`; templates `web/alarms.py#L11`; initialize `web/alarms.py#L7`; `gen.coroutine` `web/event_source.py#L25`; `IOLoop.instance().add_timeout` `web/settings.py#L452`; secure cookies `web/basics.py#L10`; get_current_user `web/basics.py#L9`; redirect `web/basics.py#L24`; flush/SSE `web/event_source.py#L30`; uploads `web/settings.py#L120` | 2020-03-17 | 0.2.0 (2020-03-17) | no | Req Mopidy>=3.0.1. Widest feature set. |
| Mopidy-WebLibrary | <https://github.com/fbarresi/Mopidy-WebLibrary> | app `__init__.py#L26` | RequestHandler `web.py#L41`; StaticFileHandler `web.py#L26`; templates `web.py#L58`; initialize `web.py#L43`; redirect `__init__.py#L29`; uploads `web.py#L286` | 2020-03-06 | 1.0.0 (2017-03-18) | no | No req. |
| Mopidy-WebSettings | <https://github.com/pimusicbox/mopidy-websettings> | app `mopidy_websettings/__init__.py#L64` | RequestHandler `#L71`; `mopidy.http.handlers.StaticFileHandler` `#L234`; initialize `#L73` | 2024-06-25 | 0.2.3 (2018-02-25) | yes | No req. |
| Mopidy-YaMusic | <https://github.com/stffart/mopidy-yamusic> | app `__init__.py#L32` | RequestHandler `web.py#L14`; initialize `web.py#L32`; `gen.coroutine` `web.py#L41`; AsyncHTTPClient `web.py#L118`; flush (proxy streaming) `web.py#L85` | 2023-08-03 | 2.2.2 (2023-08-03) | no | No req. |
| Mopidy-Yap | <https://github.com/dyj216/mopidy-yap> | app `mopidy_yap/__init__.py#L40`, static `#L36` | WebSocket `websocket.py#L10`; initialize `#L20`; check_origin `#L31`; sync `tornado.httpclient.HTTPClient` `frontend.py#L56` | 2023-12-31 | 0.1.5 (2023-12-31) | no | Req Mopidy>=3.0. |
| Mopidy-YouTube | <https://github.com/natumbri/mopidy-youtube> | app `mopidy_youtube/__init__.py#L45` | RequestHandler `web.py#L21,#L122`; StaticFileHandler `web.py#L16`; templates `web.py#L70,#L82`; initialize `web.py#L22`; `@gen.coroutine` with `yield self.flush()` `web.py#L131-151` | 2026-05-04 | 4.0.2 (2026-05-04) | no | Req Mopidy>=3.1. Website: Mopidy 4 supported. |
| Mopidy-Tubeify | <https://github.com/natumbri/mopidy-tubeify> | app `mopidy_tubeify/__init__.py#L42` | RequestHandler `web.py#L9`; initialize `#L10` | 2026-05-01 | 0.1.0 (2022-07-09) | no | Req Mopidy>=3.3.0. Only GitHub HEAD registers, not the PyPI release. |
| mopidy-twitch | <https://github.com/Drizzt321/mopidy-twitch> | app `src/mopidy_twitch/__init__.py#L43` | RequestHandler `http_handlers/_api.py#L15`; StaticFileHandler `__init__.py#L77`; initialize `_api.py#L20`; async `_browser.py#L27`; redirect `_auth.py#L51`; flush `_stream.py#L161` | 2026-03-02 | Not on PyPI | no | Req mopidy>=3.4.1. |
| mopidy-eboplayer | <https://github.com/ErikBongers/mopidy-eboplayer> | app `mopidy_eboplayer/__init__.py#L41` | RequestHandler `actionHandler.py#L12`; StaticFileHandler `web.py#L13`; WebSocket `webSocketHandler.py#L11`; templates `web.py#L59`; initialize `actionHandler.py#L14`; `IOLoop.current()` and `add_callback` `webSocketHandler.py#L9,#L15`; CORS `actionHandler.py#L21`; check_origin `webSocketHandler.py#L17`; redirect `__init__.py#L45` | 2026-08-24 | Not on PyPI | no | Req Mopidy>=4.0.0a1. |
| mopidy-killthedj | <https://github.com/gabsSP1/mopidy-killthedj> | app `__init__.py#L45` | RequestHandler `request_handlers.py#L32`; initialize `#L39`; CORS `#L43` | 2017-03-07 | Not on PyPI | no | No req. |
| mopidy-rfid-frontend | <https://github.com/glogiotatidis/mopidy-rfid-frontend> | static `mopidy_rfid-frontend/__init__.py#L56` | None | 2015-06-04 | Not on PyPI | no | |
| mopidy-btsource | <https://github.com/ismailof/mopidy-btsource> | static `mopidy_btsource/__init__.py#L30` | None | 2016-06-04 | Not on PyPI | no | |
| mopidy-spintune | <https://github.com/jamestowers/mopidy-spintune> | static `mopidy_spintune/__init__.py#L31` | None | 2015-03-10 | Not on PyPI | no | |
| mopidy-rfid | <https://github.com/marten-lucas/mopidy-rfid> | app `src/mopidy_rfid/__init__.py#L56` | RequestHandler `http.py#L23`; StaticFileHandler `#L477`; WebSocket `#L253`; initialize `#L24`; async `#L27`; module-global IOLoop for cross-thread broadcast `#L17-18,#L453`; check_origin `#L264` | 2026-01-19 | Not on PyPI | no | Req Mopidy>=3.0. |
| mopidy-pi-client | <https://github.com/moodytux/mopidy-pi-client> | static `mopidy_pi_client/__init__.py#L33` | None | 2026-09-15 | Not on PyPI | no | |
| mopidy-epaper | <https://github.com/murrayhack/mopidy-epaper> | app `mopidy_epaper/__init__.py#L46` | RequestHandler `http.py#L39`; initialize `#L105` | 2026-09-13 | Not on PyPI | no | Req Mopidy>=3.4. |
| mopidy-dial | <https://github.com/natumbri/mopidy-dial> | app `src/mopidy_dial/__init__.py#L37` | RequestHandler `web.py#L190`; initialize `#L218`; CORS `#L226` | 2026-05-15 | Not on PyPI | no | Req mopidy>=3.4.1. |
| mopidy-o2m | <https://github.com/object2music/o2m> | app `mopidy/mopidy-o2m/mopidy_o2m/__init__.py#L65` | RequestHandler `web.py#L25`; StaticFileHandler `#L70`; initialize `#L33` | 2026-09-21 | Not on PyPI | no | |
| mopidy-partify | <https://github.com/partify/mopidy-partify> | app `__init__.py#L106`, static `#L110` | WebSocket `#L28`; initialize `#L29` | 2015-03-26 | Not on PyPI | no | |
| mopidy-radio-pi | <https://github.com/paulburkinshaw/mopidy-radio-pi> | app `mopidy_radio_pi/__init__.py#L51`, static `#L46` | RequestHandler `app.py#L47`; StaticFileHandler `#L348`; WebSocket `#L283`; templates `#L70`; initialize `#L49`; cookies `#L62,#L89-90`; get_current_user `#L61`; redirect `#L73`; `tornado.locale` `#L11` | 2020-09-13 | Not on PyPI | no | |
| mopidy-omarchy-tidal | <https://github.com/ph0bos/omarchy-tidal> | app `backend/mopidy_omarchy_tidal/__init__.py#L43` | RequestHandler `http.py#L64`; initialize `#L65`; async `#L112`; `IOLoop.current().run_in_executor` `#L89`; AsyncHTTPClient `#L630`; `HTTPError(403)` for cross-origin `#L74` | 2026-09-10 | Not on PyPI | no | |
| mopidy-smartplaylists | <https://github.com/powellc/mopidy-smartplaylists> | app `src/…/__init__.py#L45`, static `#L53` | RequestHandler `web.py#L31`; initialize `web.py#L32` | 2026-06-29 | Not on PyPI | no | Req mopidy>=3.0.0. |
| mopidy-kitchen | <https://github.com/ralfstx/mopidy-kitchen> | app `mopidy_kitchen/__init__.py#L36` | StaticFileHandler subclass `web.py#L17` | 2020-11-28 | Not on PyPI | no | Req Mopidy>=3.0.0. |
| mopidy-musicwall | <https://github.com/rdeamici/mopidy-musicwall> | app `src/…/__init__.py#L36` | RequestHandler `handlers.py#L11`; initialize `#L22`; CORS `#L13` | 2025-09-07 | Not on PyPI | no | Req mopidy>=3.4.1. |
| mopidy-material-client | <https://github.com/rombot9000/mopidy-client> | static `mopidy_material_client/__init__.py#L33` | None | 2026-01-18 | Not on PyPI | no | Req Mopidy>=3.0. |
| mopidy-juliana | <https://github.com/schlunsen/mopidy-juliana> | app `mopidy_juliana/__init__.py#L52` | Same set as Iris: RequestHandler `handlers.py#L177`; WebSocket `#L17`; check_origin `#L26`; async `#L50`; IOLoop `frontend.py#L26`; AsyncHTTPClient `core.py#L414`; CORS; StaticFileHandler | 2020-04-17 | Not on PyPI | no | Derived from Iris. |
| mopidy-foobar | <https://github.com/simonegiacomelli/mopidy-foobar> | static `src/mopidy_foobar/__init__.py#L42` | None | 2025-05-19 | Not on PyPI | no | |
| mopidy-florence-player | <https://github.com/uq-flor-pro/florence-player> | app `__init__.py#L80`, static `#L74` | RequestHandler `web.py#L31`; uploads `web.py#L253` | 2022-08-02 | Not on PyPI | no | |
| mopidy-bamp | <https://github.com/zynga/BossAlienMediaPlayer> | app `mopidy_bamp/mopidy_bamp/__init__.py#L117` | RequestHandler `base_request_handler.py#L8`; StaticFileHandler `__init__.py#L56`; WebSocket via `mopidy.http.handlers` `actor.py#L89`; initialize `base_request_handler.py#L15`; IOLoop `actor.py#L123`; secure cookies `login_request_handler.py#L60`; `@authenticated` `user_request_handlers.py#L17`; changes `self.application.settings` `base_request_handler.py#L19`; own `tornado.web.Application` `actor.py#L115` | 2024-04-09 | Not on PyPI | no | Reads `registry["http:app"]` and `registry["http:static"]` (`__init__.py#L112-113`) and runs its own copy of the Mopidy frontend. |
| mopidy-lux | <https://github.com/dz0ny/mopidy-lux> | app `__init__.py#L29`, static `#L33` | RequestHandler `router.py#L27`; initialize `#L28`; redirect `#L75` | 2014-11-27 | Not on PyPI | no | |
| mopidy-ritsec | <https://github.com/emmaunel/mopidy_ritsec> | app `__init__.py#L30` | StaticFileHandler and RedirectHandler `#L33` | 2020-05-25 | Not on PyPI | no | |
| mopidy-codecontrol | <https://github.com/cstick-ano/mopidy-codecontrol> | app `__init__.py#L76` | RequestHandler `#L12`; initialize `#L13` | 2021-07-30 | Not on PyPI | no | |
| twitch-viewer | <https://github.com/UpDryTwist/twitch-viewer> | app `twitch_viewer/__init__.py#L36` | RequestHandler `web.py#L32`; StaticFileHandler `web.py#L17`; templates `web.py#L61`; initialize `web.py#L34`; redirect `__init__.py#L39` | 2018-01-02 | Not on PyPI | no | |

### 3.4 Checked extensions that register neither key

- Website `_ext` entries: alsamixer, autoplay, beets, cd, dleyna, funkwhale,
  headless, internetarchive, jamendo, jellyfin, listenbrainz, mixcloud,
  mopster, mpd, mpris, nad, orfradio, pandora, pidi, podcast, podcast-itunes,
  radionet, radiopit, raspberry-gpio, scrobbler, somafm, soundcloud, spotify,
  subidy, tidal, tunein, webhooks, webm3u, ytmusic.
- About 65 other `mopidy-*` PyPI projects, for example Emby, Plex, Qobuz,
  MQTT-NG, Touchscreen and TtsGpio.
- Hoerbert and RadioBrowser 3.0.2 contain the registration only in comments
  (template leftovers).

## 4. Mopidy internals that depend on Tornado

All paths are under `mopidy/src/mopidy/_exts/http/`.

| Feature | Where | Tornado API used | What an ASGI version needs |
| --- | --- | --- | --- |
| Public extension type | `types.py:14-17` | `RequestRule` contains `type[tornado.web.RequestHandler]` | A new type for ASGI apps, and a decision on whether `RequestRule` stays. |
| Environment check | `__init__.py:35-40` | Imports `tornado.web` | Import the new server and framework instead, or both. |
| Server start | `actor.py:48-64`, `actor.py:120-156` | `tornado.netutil.bind_sockets`, `HTTPServer.add_sockets`, `IOLoop.current().start()` in a `threading.Thread` | Bind in the constructor (to keep `FrontendError`), run `uvicorn.Server.serve(sockets=…)` or equal in the thread loop. `::` is mapped to `None` to bind all families (`actor.py:48-50`); the new code must keep dual-stack binding. |
| Server stop | `actor.py:89-96`, `actor.py:160-163` | `io_loop.add_callback(io_loop.stop)` | `loop.call_soon_threadsafe` to set `should_exit` (or the server's stop method). Today there is no graceful close and no `join()` of the thread. |
| Routing and prefix | `actor.py:165-197` | Regex URL rules; each app's rules get `/{name}` prepended; capture groups become handler arguments | A router that accepts regex patterns if Tornado rules stay supported. Starlette uses `{param}` path syntax, not regex. |
| Trailing slash | `handlers.py:330-333`, used at `actor.py:192` and `:202` | `@tornado.web.addslash` | A redirect route. Starlette has `redirect_slashes` on the router. |
| JSON-RPC over HTTP | `handlers.py:54-62`, `handlers.py:218-297` | `RequestHandler` with `head`, `post`, `options`, `initialize` | A plain ASGI endpoint. |
| JSON-RPC over WebSocket | `handlers.py:44-53`, `handlers.py:128-190` | `WebSocketHandler`, `set_nodelay`, class-level `clients` set | An ASGI WebSocket endpoint with a client set. |
| Event broadcast | `actor.py:98-117`, `handlers.py:111-144` | `IOLoop.add_callback` from the actor thread, one callback per client | `loop.call_soon_threadsafe` or `asyncio.run_coroutine_threadsafe` to the server loop. Keep the reference to the correct loop (see Mopidy PR #1796 in section 5). |
| Blocking core calls | `jsonrpc.py:340-342`, called from `handlers.py:176` and `:261` | None, but the call runs on the event loop thread | `Future.get()` blocks the loop until core replies. Pykka's `Future.__await__` also calls `get()` after one `yield` (`site-packages/pykka/_future.py:320-323`), so `await` does not help. An ASGI version would need `run_in_executor` or a thread-pool call, or a non-blocking bridge from Pykka futures. The current code has the same limit. |
| CSRF protection | `handlers.py:41-42`, `:233-251`, `:282-297`, `:187-190` | Request headers, `set_status`, `set_header` | Same logic as middleware or in the endpoints: require `Content-Type: application/json`, answer the `OPTIONS` preflight, check `Origin` on WebSocket connect. |
| `allowed_origins` | Config `__init__.py:26-30`, check `handlers.py:198-215` | `tornado.httputil.HTTPHeaders` type only | Framework-neutral logic; change the header type. |
| Mopidy headers | `handlers.py:193-195` | `set_header` | Middleware or per response. |
| Static files for `http:static` | `actor.py:199-211`, `handlers.py:321-327` | `StaticFileHandler` subclass with `default_filename="index.html"` and Mopidy headers | Starlette `StaticFiles(directory=…, html=True)` serves `index.html` for directories (`sdist:starlette/starlette/staticfiles.py:40-55`). Headers and caching behavior differ and need checks (unverified). |
| Mopidy's own static data | `handlers.py:63-69` | `StaticFileHandler` | Same as above. |
| Client list page | `handlers.py:300-318`, `data/clients.html:22-24` | Tornado template (`{% for %}`, `{{ escape() }}`) and `render()` | A small HTML string or another template engine. |
| Default app redirect | `actor.py:213-229` | `tornado.web.RedirectHandler` | A redirect route. |
| Cookie secret | `actor.py:148-151`, `actor.py:231-242` | `cookie_secret` app setting for extensions that use `get_secure_cookie` | Only needed for Tornado handlers. An ASGI version must still pass it to the Tornado part if one remains. |
| Zeroconf | `actor.py:66-87`, `actor.py:91-94` | None | No change. |
| Tests | `mopidy/tests/_exts/http/conftest.py:1-15`, `test_server.py`, `test_handlers.py` | `tornado.testing`, `tornado.httpclient` (32 and 15 matches of `tornado`) | Rewrite with an ASGI test client (for example `starlette.testclient` or `httpx`). |

## 5. Mopidy history

### 5.1 Earlier discussion of replacing Tornado

- I found no earlier issue, PR, changelog entry or forum thread about
  replacing Tornado with ASGI, WSGI, aiohttp, Starlette, FastAPI or uvicorn.
  Checked: GitHub search in `mopidy/mopidy` and the `mopidy` org, the
  Discourse search API, `mopidy/docs`, and `workspace/`.
  Some GitHub searches hit the rate limit, so a small PR can be missing
  (partly unverified).
- Related event loop discussions:
  - [#776 "Consider running tornado's ioloop on gobject's mainloop"](https://github.com/mopidy/mopidy/issues/776)
    (2014, open): prototype to merge the Tornado and GLib loops; no decision.
  - [#777 "Consider using tornado's tcpserver for MPD handling"](https://github.com/mopidy/mopidy/issues/777)
    (2014, closed): jodal preferred to wait for Python 3 and asyncio, and
    noted the need for an asyncio-friendly way to wait on Pykka futures.
  - [#2196 "Initialize an asyncio event loop on application start"](https://github.com/mopidy/mopidy/issues/2196)
    and [PR #2197](https://github.com/mopidy/mopidy/pull/2197)
    (2025, closed, not merged): one app-wide asyncio loop was proposed and
    dropped in favor of one loop per threaded actor.
  - [mopidy-mpd PR #72 "Removed GLib dependency"](https://github.com/mopidy/mopidy-mpd/pull/72)
    (2025, open): adamcik said extensions must not set a process-wide loop,
    and listed "one loop per extension thread", which follows the HTTP
    extension pattern, against one central loop.
  - [#1309 "HTTP/2 support"](https://github.com/mopidy/mopidy/issues/1309)
    (2015, closed): HTTP/2 was blocked on Tornado; the advice was to put
    nginx in front of Mopidy. This is the only place found where a Tornado
    limit was named as a blocker.

### 5.2 History of `http:app` and `http:static`

- Mopidy 0.10 (2012) added the first HTTP frontend with CherryPy and ws4py
  (`mopidy/docs/changelog/0.x.md:1269`, `:1301-1308`).
- [#440](https://github.com/mopidy/mopidy/issues/440) (2013) asked for an
  extension hook to serve web client folders.
- [PR #730 "Add: Tornado framework, dynamic entry points for clients"](https://github.com/mopidy/mopidy/pull/730)
  (merged 2014-05-14) moved to Tornado, described as "py3 and asyncio
  friendly", and added the registry-based web apps.
- Mopidy 0.19.0 (2014-07-21) shipped it: Tornado replaced CherryPy and ws4py
  (`mopidy/docs/changelog/0.x.md:132-135`, `:224-235`).
- [#875](https://github.com/mopidy/mopidy/issues/875) (2014): one failing
  `http:app` factory stopped the whole server; fixed by catching errors per
  app (now `mopidy/src/mopidy/_exts/http/actor.py:186-190`).
- Mopidy 3.0 removed `http/static_dir`, added `http/default_app`, and added
  the cookie secret for `get_secure_cookie()`
  (`mopidy/docs/changelog/3.x.md:380-388`).
- [#1966 "Make it easier to re-use CSRF protection for custom web handlers"](https://github.com/mopidy/mopidy/issues/1966)
  (2021, open): the only open proposal to change the `http:app` contract. It
  proposes a reusable base handler and passing HTTP settings to factories.
  The author notes that backward compatibility needs care.

### 5.3 Earlier Tornado upgrade problems

- 2014: Mopidy tested against several Tornado versions
  ([#798](https://github.com/mopidy/mopidy/issues/798),
  [PR #806](https://github.com/mopidy/mopidy/pull/806)), and lowered the
  minimum to Tornado 2.3 for Debian and Raspbian
  (`mopidy/docs/changelog/0.x.md:110-112`).
- 2015: [PR #1127](https://github.com/mopidy/mopidy/pull/1127) moved
  WebSocket writes to `IOLoop.add_callback`. This broke broadcasts on
  Tornado 2.3 and needed fixes in 1.0.2 and 1.0.3
  (`mopidy/docs/changelog/1.x.md:378-391`).
- 2018: [#1715 "Mopidy doesn't exit with Tornado v5.0+"](https://github.com/mopidy/mopidy/issues/1715),
  fixed by [PR #1716](https://github.com/mopidy/mopidy/pull/1716)
  (`mopidy/docs/changelog/2.x.md:74`).
- 2019: [#1798 "Move to Tornado 5"](https://github.com/mopidy/mopidy/issues/1798)
  had an unchecked item "Check web extensions".
  [PR #1796](https://github.com/mopidy/mopidy/pull/1796) fixed lost WebSocket
  broadcasts, because `IOLoop.current()` in the actor thread made a new loop
  that never ran.
- Extension impact: Iris pinned `tornado<5` and broke when pip installed
  Tornado 5 ([jaedb/Iris#275](https://github.com/jaedb/Iris/issues/275),
  [jaedb/Iris#432](https://github.com/jaedb/Iris/issues/432)).
  This shows that a change of the web framework under `http:app` breaks
  extensions in practice.
- 2019: the Python 3 port added `asyncio.set_event_loop(asyncio.new_event_loop())`
  in the server thread (commit c23fdb007,
  [PR #1821](https://github.com/mopidy/mopidy/pull/1821); now
  `mopidy/src/mopidy/_exts/http/actor.py:144-146`).
- Current minimum: Tornado >= 6.4.2, the Debian stable version
  (`mopidy/pyproject.toml:25`, `mopidy/docs/changelog/index.md:109-110`).

## Open questions

Options found in this research. They are listed with trade-offs only; the
choice is not made here.

| Option | Keeps `http:app` Tornado handlers | Cost and risk |
| --- | --- | --- |
| A. Keep Tornado as the server. Add a new ASGI key that mounts an ASGI app through a Mopidy-owned bridge handler or router (section 1.5). | Yes, with no change. | Mopidy must own and test an ASGI bridge, including WebSockets, which does not exist yet. Tornado stays a hard dependency. |
| B. ASGI server (for example uvicorn) as the front. Run the Tornado part through Tornado's `ASGIAdapter` when it is released. | HTTP handlers only. `WebSocketHandler` users (16 of 63) break. | Depends on an unmerged upstream draft PR. |
| C. Two servers in one loop and one thread: Tornado for `http:app`, uvicorn for the new API, on two ports. | Yes. | Two ports change the URLs for users and web clients, and CSRF and origin rules apply per port. |
| D. ASGI only, drop Tornado handlers in a major release. | No. | Breaks 63 known extensions, with 27 of them active. |

Open questions:

1. Which new registry key and signature would ASGI apps use, for example
   `http:asgi` with a factory `(config, core) -> ASGIApp`? How would the
   prefix (`root_path`) and the default-app redirect work for it?
2. Can a Tornado `WebSocketHandler` be bridged to an ASGI WebSocket app with
   correct accept, subprotocol and close semantics (section 1.5)? A prototype
   is needed.
3. How should blocking Pykka calls (`Future.get()`) be run from async
   endpoints: a thread pool, or a non-blocking bridge from Pykka futures to
   asyncio? This also applies to the current Tornado code (section 4).
4. Is the Tornado `ASGIAdapter` PR (#3571) likely to be merged, and in which
   Tornado version? The PR is a draft with no update since 2026-03-25.
5. Must Mopidy keep one port for HTTP and WebSocket (as today), or is a
   second port acceptable?
6. Which new dependencies are acceptable for Debian and small ARM devices?
   uvicorn, starlette and a2wsgi are in Debian trixie; granian is not.
   WebSocket support in uvicorn also needs `websockets` or `wsproto`.
7. Should the 4 extensions that import `mopidy.http.handlers` get a public
   replacement, for example for `check_origin` and the CSRF logic? Issue
   [#1966](https://github.com/mopidy/mopidy/issues/1966) asks for this.
8. The WSGI example in `mopidy/docs/reference/http-server.md:145-161` does not
   run (`self.core` in a plain function), and no surveyed extension was found
   to use `WSGIContainer`. Is WSGI support still worth documenting? Not
   verified: the survey regex did not count `WSGIContainer` separately.
