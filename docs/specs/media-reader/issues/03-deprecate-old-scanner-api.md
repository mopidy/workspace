# 03: Deprecate the old scanner API

**What to build:** Extension developers who use `mopidy.audio.scan` or
`mopidy.audio.tags` get a deprecation warning that names the new
`mopidy.media` API. The old API still gives the same results as on `main`,
and still raises `ScannerError`, until Mopidy 5.0.

- The old modules stay on the private GStreamer layer of `mopidy.media`,
  because their results have raw GStreamer tags.
- The old API must not change the design of the new one.
- Changelog and API docs say what is deprecated and what to use in its
  place.

See [the spec](../spec.md), section "Modules".

**Blocked by:** 02 (The reader with read_media_info).

**Status:** ready-for-agent

- [ ] Each deprecated class and function warns, and the message names the
      replacement in `mopidy.media`.
- [ ] The tests from ticket 01 still pass, and they also check the warnings.
- [ ] No bundled extension uses the deprecated API.
- [ ] Changelog and docs entries.
- [ ] All tests, ruff, pyright and ty pass.
