# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Overview

This is a **uv workspace** for developing [Mopidy](https://mopidy.com/) and its extensions together.

`~/mopidy-dev/` is a plain directory, not a Git repo. Each project below it is its own checkout, so each keeps its own Git status:

- `workspace/` — the workspace repo (`mopidy/workspace`). It holds the shared `pyproject.toml` and `.mise.toml`, which are symlinked into `~/mopidy-dev/`. This makes `~/mopidy-dev/` the uv workspace root and keeps `.venv/` and `uv.lock` there.
- `mopidy/` — the core Mopidy music server (Python, GStreamer-based)
- `mopidy-*/` — Mopidy extensions (mopidy-mpd, mopidy-spotify, mopidy-local, etc.), one checkout each. These and `mopidy/` are the uv workspace members. `mopidy-ext-template/` is excluded.
- `mopidy.js/` — JavaScript client library (TypeScript/npm)
- `website/` — mopidy.com (Jekyll)
- `apt/` — Debian package repository (Jekyll site)
- `infrastructure/` — CI Docker images
- `mopidy-ext-template/` — Copier template for new extensions

Run version control commands for the workspace repo itself from `workspace/`.

## Build & Install

```sh
# Install everything (run from ~/mopidy-dev/)
uv sync --all-packages --all-groups --all-extras --reinstall

# Sanity check
uv run mopidy deps
```

`uv` auto-detects source changes across workspace members — no reinstall needed after editing.

## Testing & Quality (Mopidy core)

All commands run from `mopidy/`:

```sh
# Run all tests
uv run pytest

# Run a single test file or test
uv run pytest tests/core/test_playback.py
uv run pytest tests/core/test_playback.py::TestPlayback::test_play

# Watch tests (re-runs on file changes)
uv run ptw -- tests/

# Type checking (use both)
uv run pyright src
uv run ty check src

# Linting & formatting
uv run ruff check .
uv run ruff format --check --diff .

# Markdown linting (for docs/)
uvx rumdl check docs/

# Build docs
uv run zensical build --clean

# Run all checks via tox
uv run tox
```

## Testing & Quality (Extensions)

Extensions follow the same pattern. From an extension directory (e.g., `mopidy-mpd/`):

```sh
uv run pytest
uv run ruff check .
uv run pyright src
```

## Architecture

Mopidy uses an **actor model** via [Pykka](https://pykka.readthedocs.io/). Key actors:

- **Core** (`mopidy/src/mopidy/core/`) — the main API surface, split into sub-controllers: `_playback.py`, `_tracklist.py`, `_library.py`, `_playlists.py`, `_mixer.py`, `_history.py`. The core actor proxies calls to backend/mixer actors.
- **Audio** (`mopidy/src/mopidy/audio/`) — wraps GStreamer pipeline. `_gst.py` is the GStreamer integration; `_api.py` is the actor interface.
- **Backend** (`mopidy/src/mopidy/backend/`) — abstract interface for music sources. Each extension implements a backend (e.g., mopidy-spotify provides tracks from Spotify). Key interfaces: `_library.py`, `_playback.py`, `_playlists.py`.
- **Mixer** (`mopidy/src/mopidy/mixer/`) — volume control interface.

**Extension system** (`mopidy/src/mopidy/ext/`): Extensions register via `entry_points` in `pyproject.toml` under `mopidy.ext`. The bundled extensions live in `mopidy/src/mopidy/_exts/` (file, http, m3u, softwaremixer, stream).

**Models** (`mopidy/src/mopidy/models/`): Immutable data models (Track, Album, Artist, Playlist, etc.) using Pydantic.

**Config** (`mopidy/src/mopidy/config/`): Configuration system with per-extension config sections.

**CLI** (`mopidy/src/mopidy/_app/cli.py`): Uses cyclopts. Entry point is `mopidy` command.

**Docs**: Built with [Zensical](https://github.com/jodal/zensical) (MkDocs-based). Config in `mopidy/zensical.toml`. API docs auto-generated via mkdocstrings.

## Extension layout convention

Extensions use a flat `src/mopidy_<name>/` layout (underscore, not hyphen). They register via `[project.entry-points."mopidy.ext"]` in their `pyproject.toml`.

## Key conventions

- Python 3.13+, ruff for linting/formatting (select = ALL with specific ignores)
- Google-style docstrings
- Test mirrors source structure: `src/mopidy/core/_playback.py` -> `tests/core/test_playback.py`
- pyright in standard mode for type checking
