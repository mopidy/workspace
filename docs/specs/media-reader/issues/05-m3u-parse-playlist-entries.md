# 05: The m3u extension reads playlists with parse_playlist_entries

**What to build:** Users keep their m3u playlists working as before, and the
m3u extension can also read playlists with PLS, XSPF and ASX content.

- The m3u extension reads playlists with `parse_playlist_entries`, and does
  its own file I/O.
- Relative entries are still joined with the configured base directory, not
  with the directory of the playlist.
- `.m3u8` files are still UTF-8. Other files still use the configured
  default encoding.
- Names still come from `#EXTINF`. If there is none, the name comes from
  the file name.
- The extension still writes only M3U.
- Changelog entry about the new formats.

See [the spec](../spec.md), section "Behavior changes".

**Blocked by:** 04 (parse_playlist_entries).

**Status:** ready-for-agent

- [ ] The m3u extension tests pass without changes to what they assert.
- [ ] A test that a playlist with PLS content is read.
- [ ] The private M3U reader of the extension is deleted. The writer does
      not change.
- [ ] All tests, ruff, pyright and ty pass.
