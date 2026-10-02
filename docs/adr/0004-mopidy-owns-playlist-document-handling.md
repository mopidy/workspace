---
status: accepted
---

# Mopidy owns parse, expand and resolve of playlist documents

Mopidy implements parse, expand and resolve of playlist documents one time,
in `mopidy.media`, as a public API. These are not pluggable. Resolve uses
the scanner interface to find out if a URI is audio, so it works with any
scanner.

The API must be complete enough that no extension needs its own copy. So:

- Expand gives playlist entries, each with a track and all its
  alternatives, as `PlaylistEntry(track: Track, alternatives: tuple[Uri,
  ...])`. The URI of the track is the first alternative.
- Format detection uses the content, and uses the media type and the URI as
  hints for which detector to try first.
- Resolve tries the alternatives of each entry, and then the next entries,
  until the scanner reports audio.
- Parse takes bytes without I/O, so that the m3u extension can use it with
  its own `base_dir` and encoding rules. The m3u extension reads all
  playlist formats, but it writes only M3U.

We chose this because no media framework handles playlist documents as
Mopidy needs. GStreamer and FFmpeg cannot read PLS, XSPF or ASX, and mpv
puts M3U and PLS entries into its own playlist. Today the stream extension
has this code, and Mopidy-TuneIn has a copy with its own extra format
detection, because nothing public exists. See
[the research report](../research/audio-engines-gstreamer-ffmpeg-mpv.md),
section 4.
