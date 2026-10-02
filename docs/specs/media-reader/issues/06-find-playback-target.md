# 06: read_playlist_entries and find_playback_target, used by the stream extension

**What to build:** Users can play a radio station whose first mirror is
down, and HLS stations. Extension developers can find the playback target
for a URI in one call.

- `Reader.read_playlist_entries`, `Reader.find_playback_target` and
  `PlaybackTarget` in `mopidy.media`.
- The reader keeps an HTTP connection pool with the Mopidy proxy config.
- Find playback target reads the HTTP headers first, never reads the body
  of an audio stream, tries the alternatives of each entry and then the
  next entry, goes into nested playlist documents, and stops at a URI that
  it has seen before and at the deadline.
- The stream extension uses find playback target in `lookup()` and
  `translate_uri()`. `lookup()` still gives one track under the original
  URI. The private loop and the parsers of the stream extension are deleted.
- Changelog entries for the new API, and for the changes in what the stream
  extension plays.

The rules are in [the spec](../spec.md), sections "Read playlist entries"
and "Find playback target". The test seams are in the section "Testing
Decisions".

**Blocked by:** 02 (The reader with read_media_info), 04
(parse_playlist_entries).

**Status:** ready-for-agent

- [ ] Tests use a fake media info reader and `pytest_httpx`, and cover:
  - [ ] a playlist document where the first entry fails and the second
        works;
  - [ ] an entry with two alternatives where the first fails;
  - [ ] nested playlist documents;
  - [ ] a playlist document that refers to itself;
  - [ ] the deadline;
  - [ ] an HTTP audio stream whose body is not read;
  - [ ] HLS over HTTP goes to read media info, not to parse;
  - [ ] a URI that is not a playlist document and that cannot be read gives
        an unverified playback target;
  - [ ] a URI that gives nothing gives `None`.
- [ ] Read playlist entries raises `MediaReadError` for schemes other than
      `file`, `http` and `https`, and when the fetch fails.
- [ ] The stream extension tests only check that `lookup()` and
      `translate_uri()` use find playback target correctly.
- [ ] All tests, ruff, pyright and ty pass.
