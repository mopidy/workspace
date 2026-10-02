---
status: accepted
---

# The playback engine and the media info reader are separate

The playback engine and the media info reader get one interface each. The
media info reader is part of the reader, in a new public package,
`mopidy.media`, so that `mopidy.audio` contains only the playback engine.
The GStreamer code for each side is private to its package:
`mopidy.audio._gst` and `mopidy.media._gst`. GStreamer helpers that both
sides use are in `mopidy._lib.gst`. `mopidy.audio` and `mopidy.media` do not
import from each other.

GStreamer stays the only media framework for now. The interfaces must not
use GStreamer types or tag names, so that FFmpeg or mpv can implement them
later. `MediaInfoReader` is not public until Mopidy has a way to plug in
other implementations.

We chose this because the two have different life cycles and users. There
is one playback engine for each process, and it lives as long as the
process. A media info reader does one short job for each URI, from many
threads, and the Mopidy-Local CLI uses it without actors. In no media
framework is the best media info reader the same as the player: mpv has no
probe API, and FFmpeg has no player library. So "mpv for playback, FFmpeg
for metadata" is a real combination, and it needs two interfaces. See
[the research report](../research/audio-engines-gstreamer-ffmpeg-mpv.md).

We do not decide yet if a media info reader and a playback engine must come
from the same media framework. The stream extension and Mopidy-TuneIn use
media info to decide what to play and how to buffer, so a media info reader
and a playback engine that do not agree can cause errors. We decide the
pairing rule when there is a second media framework.
