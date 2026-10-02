# 01: Split the GStreamer code by side

**What to build:** A prefactor with no change in behavior. Before the
reader is added, the GStreamer code is in the correct places:

- The playback engine stays in the private GStreamer package of
  `mopidy.audio`.
- The scanner pipeline and the conversion from GStreamer tags to `Track`
  go to a private GStreamer package in `mopidy.media`.
- The GStreamer helpers that both sides use go to a private module under
  `mopidy._lib`: signal handling, proxy setup, clock time conversions and
  tag list conversion.

`mopidy.audio.scan` and `mopidy.audio.tags` keep working exactly as before,
without warnings, by using the moved code. `mopidy.media` has no public API
yet.

Start with the tests that the `scanner-interface` branch adds for the audio
APIs that nothing asserted. Then take the move commits from that branch, and
change where the code goes. The branch is a source of code. It does not
decide the design.

See [the spec](../spec.md), section "Modules", and ADR-0002.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The tests for the current scanner and tag API behavior exist, and
      they pass before and after the move.
- [ ] Only the playback engine is in the GStreamer package of
      `mopidy.audio`.
- [ ] Nothing in `mopidy.audio` imports from `mopidy.media`, and nothing in
      `mopidy.media` imports from `mopidy.audio`, except the old public
      modules `mopidy.audio.scan` and `mopidy.audio.tags`.
- [ ] Tests mirror the new source locations.
- [ ] Code is moved without other changes, unless a change is necessary.
- [ ] All tests, ruff, pyright and ty pass.
