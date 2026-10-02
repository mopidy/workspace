---
status: accepted
---

# Mopidy owns the reader and playlist document handling

Mopidy implements the reader, `mopidy.media.Reader`, and `parse_playlist_entries()`
one time, as a public API. Only the media info reader inside the reader comes
from a media framework. The rest is Mopidy code and is not pluggable. The
API must be complete enough that no extension needs its own copy.

The API:

- `create_reader(config, *, timeout)` makes a reader. Each caller makes its
  own reader, keeps it, and closes it with `close()` or `with`.
- `Reader.read_media_info(uri) -> MediaInfo` reads one URI. `MediaInfo` has
  `track`, `playable`, `seekable` and `images` (`EmbeddedImage`). It raises
  `MediaReadError` if the URI cannot be read. It is safe to call from many
  threads.
- `Reader.read_playlist_entries(uri) -> tuple[PlaylistEntry, ...]` fetches a
  playlist document from a `file`, `http` or `https` URI and parses it, one
  level deep. It raises `MediaReadError` if the fetch fails.
- `Reader.find_playback_target(uri) -> PlaybackTarget | None` finds a playback target.
  `PlaybackTarget` has `uri`, `info: MediaInfo | None` and
  `entry: PlaylistEntry | None`. It returns `None` if it finds nothing, and
  does not raise errors for URIs that it cannot read.
- `parse_playlist_entries(data, *, base_uri, encoding="utf-8", media_type=None,
  uri=None)` parses bytes without I/O.
- `PlaylistEntry(track, alternatives)` has all URIs of the entry in
  `alternatives`. `track.uri` is the first alternative.

Rules:

- The content decides the playlist format. The media type and the URI are
  hints for which format to try first.
- HLS and DASH are not playlist formats. `parse_playlist_entries()` gives no entries
  for them, and `find_playback_target()` gives them to the playback engine as playback
  targets.
- For `http` and `https`, `find_playback_target()` reads the response
  headers before it reads media info. A playlist media type means read
  playlist entries. An audio media type means read media info. If the type
  is not clear, it reads the body and tries `parse_playlist_entries()`. It
  reads media info only if there are no entries. It uses GET and stops
  before the body, not HEAD. It never reads the body of an audio stream.
- For `file`, `find_playback_target()` tries `parse_playlist_entries()` on
  the content first.
- For other URI schemes, `find_playback_target()` only reads media info.
- `find_playback_target()` tries the alternatives of each entry in order, then the
  next entry. It goes into nested playlist documents, and stops at a URI
  that it has seen before or at the deadline.

We chose this because no media framework handles playlist documents as
Mopidy needs. GStreamer and FFmpeg cannot read PLS, XSPF or ASX, and mpv
puts M3U and PLS entries into its own playlist. Today the stream extension
has this code, and Mopidy-TuneIn has a copy with its own extra format
detection, because nothing public exists. Mopidy decides "playlist document
or not" with its own parser, because GStreamer detects only some playlist
formats. The order in `find_playback_target()` makes one cheap request before the
expensive scan of a media framework. See
[the research report](../research/audio-engines-gstreamer-ffmpeg-mpv.md),
section 4.
