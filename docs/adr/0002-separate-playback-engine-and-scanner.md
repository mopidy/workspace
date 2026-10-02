---
status: accepted
---

# The playback engine and the scanner are separate interfaces

The playback engine and the scanner get one interface each. The scanner
interface moves out of `mopidy.audio` into a new public package,
`mopidy.media`, so that `mopidy.audio` contains only the playback engine.
GStreamer stays the only media framework for now. The interfaces must not
use GStreamer types or tag names, so that FFmpeg or mpv can implement them
later.

We chose this because the two have different life cycles and users. There
is one playback engine for each process, and it lives as long as the
process. The scanner does one short job for each URI, from many threads, and
the Mopidy-Local CLI uses it without actors. In no media framework is the
best scanner the same as the player: mpv has no probe API, and FFmpeg has no
player library. So "mpv for playback, FFmpeg for scanning" is a real
combination, and it needs two interfaces. See
[the research report](../research/audio-engines-gstreamer-ffmpeg-mpv.md).

We do not decide yet if a scanner and a playback engine must come from the
same media framework. The stream extension and Mopidy-TuneIn use scan
results to decide what to play and how to buffer, so a scanner and a
playback engine that do not agree can cause errors. We decide the pairing
rule when there is a second media framework.
