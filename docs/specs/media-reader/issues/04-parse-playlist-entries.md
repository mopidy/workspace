# 04: parse_playlist_entries

**What to build:** Extension developers can get the playlist entries from
the bytes of a playlist document, without I/O.

- `parse_playlist_entries` and `PlaylistEntry` in `mopidy.media`.
- Formats: M3U (with and without the `#EXTM3U` header), PLS, XSPF, ASX,
  ASX reference and URI list.
- The content decides the format. The media type and the URI are hints for
  which detector to try first. Use the media types and file extensions that
  Mopidy-TuneIn maps today as hints.
- HLS and DASH, and content that is not a playlist document, give no
  entries.
- Names and lengths go into the entry's `Track`.
- All XSPF locations of a track, and all ASX refs of an entry, are the
  alternatives of one entry.
- Relative entries are joined with the base URI. Bytes that do not decode
  are replaced.
- Find out if nested ASX documents use `entryref`. Today the parser reads
  `entry` with an `href`.

Start from the parsers in the stream extension, but do not change the
stream extension yet. The rules are in [the spec](../spec.md), section
"Parse playlist entries". If ticket 02 has not landed, create the
`mopidy.media` package. The second of the two tickets to land merges the
package exports.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The tests for the stream extension parsers pass against
      `parse_playlist_entries`, with the changes that this ticket describes.
- [ ] Tests for each format: entries, names, lengths and alternatives.
- [ ] Tests that HLS media playlists, HLS master playlists and DASH give no
      entries.
- [ ] Tests that a wrong media type or URI hint does not change the result.
- [ ] Tests for relative entries and for the encoding.
- [ ] `PlaylistEntry` has at least one alternative, and the track URI is the
      first alternative.
- [ ] All tests, ruff, pyright and ty pass.
