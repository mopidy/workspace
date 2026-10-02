# Research: audio engines for Mopidy: GStreamer, FFmpeg and mpv

Date: 2026-10-02.
Scope: the audio layer in `mopidy/src/mopidy/audio/` (the `Audio` actor
interface, `GstAudio`, `GstPipeline`, the scanner and the tag conversion), the
stream extension in `mopidy/src/mopidy/_exts/stream/`, and the extensions that
use these APIs. The question is which interfaces can stay valid if FFmpeg
(libav\*) or mpv (libmpv) becomes a second implementation after GStreamer.
This document gives facts and options. It does not make the design decision.

Conventions:

- Paths without a host are relative to `~/mopidy-dev/`. The Mopidy checkout
  is version `4.0.5.dev48` (working copy, read only).
- "Verified locally" means a local test ran on Debian with GStreamer 1.28.7
  (`gst-inspect-1.0`, `gst-launch-1.0`, PyGObject 3.58.0 in `.venv/`),
  FFmpeg 9.0.2 (libavformat 63.1.102, `ffmpeg` and `ffprobe`) and mpv 0.41.0
  (CLI, with Lua scripts that use the same property API as libmpv). The test
  files and scripts are not in the repo. `gst-discoverer-1.0` is not
  installed, so the Discoverer tests use `GstPbutils.Discoverer` from Python.
- "Local ICY server" means a small Python HTTP server on `127.0.0.1` that
  sends a 128 kbit/s MP3 with `icy-metaint: 8192`, `icy-name: Test Radio` and
  a new `StreamTitle` every 3 seconds. It also serves a `.pls` file and a 302
  redirect.
- Source references use tags that match the local versions:
  `gst:` is <https://gitlab.freedesktop.org/gstreamer/gstreamer/-/blob/1.28.7/subprojects/>,
  `ffmpeg:` is <https://github.com/FFmpeg/FFmpeg/blob/n9.0.2/> (the official
  mirror of git.ffmpeg.org), and `mpv:` is
  <https://github.com/mpv-player/mpv/blob/v0.41.0/>. The mpv manual at
  <https://mpv.io/manual/stable/> is generated from `mpv:DOCS/man/*.rst`.
- "Unverified" marks a statement that this research did not check against a
  source or a test.
- Glossary: this document was written before the terms in `CONTEXT.md`,
  section "Audio and media", were settled. Here, "scanner" means the
  media info reader (today `mopidy.audio.scan.Scanner`), and "resolve" means
  find playback target (today `_unwrap_stream()` in the stream extension).

## Summary

- All three engines can play a URI, pause, seek, report position, report end
  of stream and errors, and give tags. Only GStreamer and mpv are players.
  FFmpeg has no player library. Its only player is `ffplay`, "a very simple
  and portable media player using the FFmpeg libraries and the SDL library"
  (`ffmpeg:doc/ffplay.texi:20`). With FFmpeg, Mopidy must write the decode
  loop, the clock, the output, buffering and gapless logic itself.
- Gapless "next URI" hooks differ in kind. GStreamer `playbin` emits
  `about-to-finish` on a streaming thread, and the application sets the next
  URI in the callback. mpv has no such callback. Gapless in mpv works only
  between playlist entries (`--gapless-audio`, default `weak`), so the next
  URI must be in the mpv playlist before the current file ends. With FFmpeg,
  the "hook" is a point in Mopidy's own decode loop.
- ICY "now playing" titles work in all three (verified locally with the
  local ICY server). The names and the timing differ: GStreamer posts a
  `title` tag (and `organization` from `icy-name`) from the sink, at play
  time. FFmpeg puts `StreamTitle` in `AVFormatContext.metadata` and sets
  `AVFMT_EVENT_FLAG_METADATA_UPDATED` when the demuxer reads it, which is
  ahead of play time. mpv exposes `icy-title` and `icy-name` in the
  `metadata` property.
- Duration of a VBR MP3 without a Xing/VBRI header is a trap in all three.
  For a 60.0 s test file, `ffprobe` and mpv report 177.7 s, and the current
  Mopidy scanner also reports 177.7 s. `GstPbutils.Discoverer` reports
  60.4 s on the same file. All verified locally (section 3.5).
- No engine unwraps PLS, XSPF or ASX playlists as Mopidy needs. GStreamer
  has no typefinder for PLS, XSPF or ASX, and it types a plain `#EXTM3U` file
  as `text/uri-list`. FFmpeg has no PLS, M3U, XSPF or ASX demuxer, and it
  probed a local `.pls` file as `lrc` (lyrics). mpv expands M3U and PLS, but
  not XSPF or ASX. HLS (`.m3u8`) is a demuxer in all three, not a playlist
  (section 4).
- The current scanner is not only a library tool. The stream extension runs
  the scanner inside `translate_uri()`, which is in the playback path, to
  find out if a URL is audio or a playlist
  (`mopidy/src/mopidy/_exts/stream/actor.py:104-119`, `:158`).
- The facts support separate interfaces for the playback engine and the
  scanner: different life cycles (one long-lived player against many short
  jobs), different concurrency (GStreamer and libmpv need one pipeline or
  one core per concurrent job), and the best scanner per engine is a
  different component (Discoverer or `avformat_find_stream_info`, not the
  player). One fact pulls the other way: an mpv-only setup has no separate
  scanner API, so its scanner would be a paused, muted player core (section
  7).
- The current `Audio` interface leaks GStreamer in four places:
  `set_source_setup_callback()` passes a `Gst.Element`, tag keys are
  GStreamer tag names, `audio/output` is a `gst-launch` pipeline string, and
  `prepare_change()` exists because of GStreamer's READY state. Mopidy-Spotify
  depends on the first one, through the GStreamer `spotifyaudiosrc` element
  (section 1).

## 1. What Mopidy uses today

### 1.1 The `Audio` actor interface

The interface is `mopidy/src/mopidy/audio/_api.py`. Its own docstring says
that there is only one implementation, and that the API "will probably" need
changes if more implementations come (`_api.py:17-24`).

| Feature | Where | Engine coupling |
| --- | --- | --- |
| `set_uri(uri, live_stream, download)` | `_api.py:30-46` | `download` maps to `GST_PLAY_FLAG_DOWNLOAD` (`_gst/pipeline.py:313-321`). `live_stream` calls `set_live(True)` on the source element (`_gst/audio.py:133-136`). |
| `set_source_setup_callback(cb)` | `_api.py:48-60` | The callback gets a `Gst.Element`. |
| `set_about_to_finish_callback(cb)` | `_api.py:62-77` | The callback must call `set_uri()` and block. It runs on a GStreamer streaming thread. |
| `get_position()`, `set_position()` | `_api.py:78-85` | Position query on `playbin`. The seek goes to the queue in the audio sink bin (`_gst/pipeline.py:354-367`). |
| `start_playback()`, `pause_playback()`, `stop_playback()` | `_api.py:86-113` | Map to PLAYING, PAUSED and NULL. |
| `prepare_change()` | `_api.py:100-107` | Sets READY. The comment says that GStreamer resets state in READY (`_gst/audio.py:391-400`). |
| `get_current_tags()` | `_api.py:115-123` | Returns converted GStreamer tags. |
| `state` | `_api.py:27` | "The GStreamer state mapped to PlaybackState". |

The `AudioListener` events are `reached_end_of_stream`, `stream_changed`,
`position_changed`, `state_changed` and `tags_changed`
(`mopidy/src/mopidy/audio/_listener.py:26-90`). The `tags_changed` docstring
tells listeners to look up tag keys in the GStreamer documentation
(`_listener.py:86-87`).

The old `appsrc` API is gone. Mopidy 4.0 removed `Audio.emit_data()`,
`Audio.set_appsrc()`, `Audio.set_metadata()` and the buffer helpers, because
only the libspotify-based Mopidy-Spotify used them
(`mopidy/docs/changelog/index.md:379-389`). No checkout in `~/mopidy-dev/`
uses `appsrc` or `emit_data` now (grep over all checkouts).

### 1.2 The GStreamer implementation

- `playbin` (not `playbin3`) with `flags=AUDIO`, `buffer-size` 5 MiB and
  `buffer-duration` 5 s (`_gst/pipeline.py:151-162`).
- A custom audio sink bin: `queue ! volume ! <output bin>`
  (`_gst/pipeline.py:166-210`). The queue gives time between
  `about-to-finish` and the switch (`_gst/pipeline.py:183-192`).
- The output bin parses the `audio/output` config value with
  `Gst.parse_bin_from_description()` behind a `tee`
  (`_gst/pipeline.py:43-104`). The default is `autoaudiosink`
  (`mopidy/src/mopidy/_app/default.conf:14-18`). The Icecast guide tells users
  to put `lamemp3enc ! shout2send …` or a `tee` with two branches in this value
  (`mopidy/docs/guides/icecast.md:20-48`).
- A bus sync handler decodes messages on the posting thread and sends them
  to the actor with `tell()` (`_gst/pipeline.py:212-272`,
  `_gst/audio.py:140-169`). Mopidy does not use a GLib main loop for audio.
  It has one for other uses (`mopidy/src/mopidy/_lib/gi.py:58-61`).
- A pad probe on the output bin turns SEGMENT events into `position_changed`
  (`_gst/pipeline.py:274-311`). Core uses this to finish a seek
  (`mopidy/src/mopidy/core/_playback.py:185-191`).
- Messages used: ASYNC_DONE, BUFFERING, EOS, ERROR, missing-plugin ELEMENT,
  STATE_CHANGED, STREAM_START, TAG, WARNING (`_gst/pipeline.py:236-272`).
- Buffering: pause below 10 %, play again at 100 %, skip for
  `Gst.BufferingMode.LIVE` (`_gst/audio.py:225-246`).
- Tags from `about-to-finish` until STREAM_START are held back, so that the
  tags of the next track do not show on the current track
  (`_gst/audio.py:268-317`).
- A deadlock guard: if `about-to-finish` comes on the actor thread, the
  callback is not run (`_gst/audio.py:109-112`). Core blocks the streaming
  thread with `actor_ref.ask()` until the next URI is set
  (`mopidy/src/mopidy/core/_playback.py:193-207`).
- Software mixer: the `volume` element is controlled through
  `GstSoftwareMixerAdapter` (`_gst/audio.py:72-74`, `:88-89`,
  `_gst/mixer.py:22-50`).
- Proxy settings go into the source element (`audio/_utils.py:45-58`).
- `supported_uri_schemes()` asks the GStreamer registry which URI schemes
  have a source element (`audio/_utils.py:26-42`). The stream extension uses
  it (`_exts/stream/actor.py:50`).
- The JACK sink gets a lower rank (`_gst/audio.py:101-107`).

### 1.3 The scanner and tags

- `Scanner.scan(uri, timeout)` returns `uri, tags, duration, seekable, mime,
  playable` (`mopidy/src/mopidy/audio/scan.py:30-36`, `:47-89`).
- It builds a new `source ! typefind ! decodebin ! fakesink` pipeline per
  scan. The comment says this is "much faster" than reuse
  (`scan.py:92-163`).
- "Playable" means that `decodebin` selected an audio decoder
  (`scan.py:220-244`). `mime` comes from the typefind `have-type` signal
  (`scan.py:166-181`). The scan stops early for `text/*` and
  `application/xml` (`scan.py:327-328`).
- If duration or tags are missing after preroll, the scanner sets PLAYING
  and waits for DURATION_CHANGED, as a workaround for a GStreamer bug
  (`scan.py:349-373`).
- `tags.convert_taglist()` turns a `Gst.TagList` into
  `dict[str, list[Any]]` (`mopidy/src/mopidy/audio/tags.py:34-94`).
  `convert_tags_to_track()` uses GStreamer tag names (`Gst.TAG_ARTIST`, …)
  and falls back to `organization` for the track name (`tags.py:128-205`,
  `:163`). That fallback matches the ICY `icy-name` header (section 2.4).
- Users: Mopidy-File lookup (`mopidy/src/mopidy/_exts/file/library.py:43`,
  `:104-113`), the stream extension (`_exts/stream/actor.py:29-32`), the
  Mopidy-Local scan command (`mopidy-local/src/mopidy_local/commands.py:226-247`,
  which uses `playable` and `duration`) and Mopidy-TuneIn
  (`mopidy-tunein/src/mopidy_tunein/actor.py:43`, `:266-272`, which treats
  "playable and not seekable" as live).

Observation (verified locally): for all 5 local test files, the scanner
returned `mime=None`. The `have-type` handler was not called. For the HTTP
stream it returned `application/x-icy`. The cause was not investigated.

### 1.4 Core and backends

- Core sets the about-to-finish callback (`core/_playback.py:56-57`).
- Core makes the stream title from `tags_changed`: if the `title` tag is not
  the track name, it is the stream title (`mopidy/src/mopidy/core/_actor.py:168-184`).
  Mopidy-MPD and Mopidy-MPRIS read it with `get_stream_title()`
  (`mopidy-mpd/src/mopidy_mpd/protocol/current_playlist.py:302`,
  `mopidy-mpris/src/mopidy_mpris/player.py:246`).
- `PlaybackProvider` has `is_live()`, `should_download()` and
  `on_source_setup(source: Gst.Element)`, and `change_track()` passes them to
  audio (`mopidy/src/mopidy/backend/_playback.py:75-131`).
- Mopidy-Spotify sets properties on the GStreamer `spotifyaudiosrc` element in
  `on_source_setup()`: `bitrate`, `cache-credentials`, `access-token`,
  `cache-files`, `cache-max-size`
  (`mopidy-spotify/src/mopidy_spotify/backend.py:57-68`). This element is in
  gst-plugins-rs (verified locally: `gst-inspect-1.0` lists `spotify:
  spotifyaudiosrc`). FFmpeg and mpv have no such source.

### 1.5 The stream extension

- `lookup()` and `translate_uri()` both call `_unwrap_stream()`
  (`_exts/stream/actor.py:69-119`).
- `_unwrap_stream()` loops: scan the URI; if playable or the MIME type is
  not `text/*` or `application/*`, return it; else download it with httpx
  and parse it as a playlist; take the first entry; repeat until a deadline
  (`_exts/stream/actor.py:122-204`).
- The playlist parser detects M3U (`#EXTM3U`), PLS, ASX reference, ASX and
  XSPF by content, not by `Content-Type`, with a URI list fallback
  (`mopidy/src/mopidy/_exts/stream/parsers.py:8-178`).
- The httpx client follows redirects (`_exts/stream/http.py:17-25`).
- Mopidy-TuneIn has a copy of this logic
  (`mopidy-tunein/src/mopidy_tunein/actor.py:276-`).

## 2. Playback engine

### 2.1 GStreamer (`playbin`, `playbin3`, `uridecodebin`)

- URI playback: set the `uri` property and the state. The state change "will
  take place in the background in a separate thread"
  (<https://gstreamer.freedesktop.org/documentation/playback/playbin3.html>).
- Gapless: `about-to-finish` "is emitted when the current uri is about to
  finish. You can set the uri and suburi to make sure that playback
  continues. This signal is emitted from the context of a GStreamer streaming
  thread" (<https://gstreamer.freedesktop.org/documentation/playback/playbin.html#playbin::about-to-finish>).
  `playbin3` and `uridecodebin3` have the same signal (verified locally with
  `gst-inspect-1.0`).
- `playbin3` has rank none, like `playbin` (verified locally). `GstPlay`, the
  high-level player library, uses `playbin3` by default
  (<https://gstreamer.freedesktop.org/documentation/play/gstplay.html>). The
  `GstPlay` API documentation has no about-to-finish or gapless API (search
  of that page), so `GstPlay` does not fit Mopidy's gapless model.
- Seeking: `seek_simple()` or seek events. Seekability: `GST_QUERY_SEEKING`.
- Volume: the `volume` element or the `playbin` `volume` property. Mopidy
  uses its own element (section 1.2).
- Live and buffering: `playbin` posts BUFFERING messages, and "applications
  need to" pause below 100 % and play at 100 %
  (<https://gstreamer.freedesktop.org/documentation/playback/playbin.html>,
  section "Buffering"). `uridecodebin` decides if a URI is a "stream" from a
  list of schemes and adds `queue2` for stream buffering
  (`gst:gst-plugins-base/gst/playback/gsturidecodebin.c:1371`, `:1468`,
  `:1660`). In GStreamer terms, an HTTP radio stream is not "live":
  Discoverer reported `live=False` for the local ICY stream (verified
  locally). "Live" in GStreamer means a source that does not preroll.
- Stream metadata: TAG messages on the bus. Section 2.4 has the ICY details.
- End of stream and errors: EOS and ERROR messages. ERROR carries a
  `GLib.Error` domain and code. A missing-plugin ELEMENT message tells which
  plugin is missing.
- Output: any sink element or bin, for example `alsasink`, `pulsesink`,
  `pipewiresink`, `autoaudiosink`, `shout2send` (Icecast), and `tee` for many
  outputs (all present locally). Mopidy exposes this as a raw pipeline
  string (section 1.2).
- Custom sources: `source-setup` gives the source element to the
  application. `appsrc` lets the application push buffers.

### 2.2 FFmpeg (libavformat, libavcodec, libswresample, libavfilter, libavdevice)

FFmpeg is a set of libraries. It is not a player. A player built on FFmpeg
has these parts, all in application code:

- Open and read: `avformat_open_input()`, `avformat_find_stream_info()`,
  then `av_read_frame()` in a loop (`ffmpeg:libavformat/avformat.h:2279-2393`).
- Decode with libavcodec. Convert sample format and rate with
  libswresample.
- Output: libavdevice has `alsa`, `oss` and `pulse` output devices. It has no
  PipeWire output device (verified locally with `ffmpeg -devices`). Most
  players use a separate audio library (for example SDL in `ffplay`).
- Clock and position: the application computes position from the timestamps
  of the samples it gave to the output, minus the output latency.
  libavformat has no position query.
- Seeking: `av_seek_frame()` and `avformat_seek_file()`
  (`ffmpeg:libavformat/avformat.h:2409`, `:2438`). `AVFMTCTX_UNSEEKABLE`
  marks a stream that is "definitely not seekable"
  (`ffmpeg:libavformat/avformat.h:1269-1272`).
- Pause: `av_read_pause()` and `av_read_play()` only apply to network
  protocols such as RTSP (`ffmpeg:libavformat/avformat.h:2462-2469`). Pause of
  the output is the application's work.
- Gapless: libavformat adds `AV_PKT_DATA_SKIP_SAMPLES` side data so that the
  decoder can drop encoder delay and padding
  (`ffmpeg:libavformat/demux.c:1536-1557`). Gapless between two files means
  that the application opens the next input before the current one ends and
  keeps the same output open. There is no about-to-finish event. The
  application has full control of this point.
- Volume and software mixing: multiply the samples, or use the libavfilter
  `volume` filter.
- Buffering: no events. The application owns its packet queue and decides
  when to pause for buffering.
- Blocking I/O: `AVFormatContext.interrupt_callback` lets the application
  stop a blocking call (`ffmpeg:libavformat/avformat.h:1576-1586`).
- End of stream and errors: `av_read_frame()` returns `AVERROR_EOF` or an
  error code.
- Output to Icecast: FFmpeg has an `icecast` output protocol and a `tee`
  muxer (verified locally with `ffmpeg -protocols` and `ffmpeg -h muxer=tee`).
- Custom sources: `avio_alloc_context()` with read and seek callbacks
  (`ffmpeg:libavformat/avio.h:398`).

Python access to FFmpeg needs a binding (for example PyAV). This research
did not check bindings. Unverified.

### 2.3 mpv (libmpv client API)

- URI playback: `loadfile <url> [replace|append|…]`. "Technically, this is
  just a playlist manipulation command"
  (`mpv:DOCS/man/input.rst:543-555`).
- Gapless: `--gapless-audio=<no|yes|weak>`, default `weak`. It plays
  "consecutive audio files" without a gap
  (`mpv:DOCS/man/options.rst:2316-2345`). "Consecutive" means playlist
  entries. The manual says that the feature "relies on audio output device
  buffering" if the next file starts slowly (same place).
  `--prefetch-playlist` (default `no`) opens the next entry "as soon as the
  current URL is fully read" (`mpv:DOCS/man/options.rst:4307-4323`).
- Next-URI hook: there is no event that asks for the next URI. The hooks are
  `on_load`, `on_load_fail`, `on_preloaded`, `on_unload`,
  `on_before_start_file` and `on_after_end_file`
  (`mpv:DOCS/man/input.rst:1912-1961`). All of them are about a file that is
  already in the playlist. So the next URI must be appended before the
  current file ends, and it must be removed or replaced if the Mopidy
  tracklist changes. Unverified: how late an append can come and still be
  gapless.
- Seeking: `seek` command, `time-pos` property. `seekable` and
  `partially-seekable` properties (`mpv:DOCS/man/input.rst:3600-3608`).
- Volume: the `volume` property "always controls the internal mixer (aka
  software volume)" since mpv 0.18.1 (`mpv:DOCS/man/options.rst:2126-2132`).
  `ao-volume` is the system volume (`mpv:DOCS/man/input.rst:2624-2632`).
- Buffering: `paused-for-cache` and `cache-buffering-state` (0-100)
  properties (`mpv:DOCS/man/input.rst:2598-2603`). mpv pauses and resumes by
  itself (`--cache-pause`, `mpv:DOCS/man/options.rst:5437`).
- Live streams: for the local ICY stream, `seekable` was `false`, and
  `duration` grew while it played (0.9 s, 1.4 s, 1.9 s, …). Verified locally.
  So `duration` is not a safe "is this endless" signal for live streams.
- Stream metadata: the `metadata` property, a map of key to value
  (`mpv:DOCS/man/input.rst:2389-2428`). The application observes it with
  `mpv_observe_property()` (`mpv:include/mpv/client.h:1227`). Section 2.4.
- End of stream and errors: `MPV_EVENT_END_FILE` with reason `EOF`, `STOP`,
  `QUIT`, `ERROR` or `REDIRECT`, plus an error code for `ERROR`
  (`mpv:include/mpv/client.h:1468-1515`).
- Output: `--ao` drivers `pipewire`, `pulse`, `alsa`, `jack`, `sndio`, `null`
  and `pcm` (verified locally with `mpv --ao=help`). `--audio-device` picks a
  device (`mpv:DOCS/man/options.rst:2022`). Audio filters use libavfilter
  (`--af`). Encoding mode (`--o`, `--of`, `--oac`) writes to a file or URL
  instead of playing (`mpv:DOCS/man/encode.rst`). This research found no mpv
  option that plays to a device and sends to Icecast at the same time.
- Custom sources: `mpv_stream_cb_add_ro()` registers a custom protocol with
  read, seek and close callbacks. The header says "this API is not stable
  yet" (`mpv:include/mpv/stream_cb.h:26-44`, `:233`). Per-file options can be
  set in the `on_load` hook through `file-local-options/<name>`
  (`mpv:DOCS/man/input.rst:1912-1921`).
- mpv uses FFmpeg for demuxing and HTTP. The local ICY server saw the
  User-Agent `libmpv` with the `Icy-MetaData: 1` header (verified locally).

### 2.4 Stream metadata (ICY "now playing")

All three were tested against the local ICY server.

| Engine | How the title is exposed | Key for StreamTitle | Key for `icy-name` | When it is sent |
| --- | --- | --- | --- | --- |
| GStreamer | TAG bus message. `souphttpsrc` sends `application/x-icy` when `iradio-mode` is on (default `true`), and `icydemux` parses the metadata blocks. | `title` (`gst:gst-plugins-good/gst/icydemux/gsticydemux.c:346-353`). `StreamUrl` becomes `homepage` (`:355-360`). | `organization` (`gst:gst-plugins-good/ext/soup/gstsouphttpsrc.c:1768-1774`). `icy-genre` becomes `genre`, `icy-url` becomes `location`. | When the tag event gets to the sink. `gst-launch-1.0 -t` showed `found by element "fakesink0"`, so it follows play time. |
| FFmpeg | The `http` protocol asks for ICY by default (`icy` option, `ffmpeg:libavformat/http.c:183`, `:1637-1638`). It parses each block into its `metadata` dictionary and the `icy_metadata_packet` export option (`http.c:1923-1988`). On each `av_read_frame()`, the demux layer copies the dictionary to `AVFormatContext.metadata` and sets `AVFMT_EVENT_FLAG_METADATA_UPDATED` (`ffmpeg:libavformat/demux.c:1560-1568`). The application must clear the flag (`ffmpeg:libavformat/avformat.h:1680-1695`). `ffplay` prints "New metadata" this way (`ffmpeg:fftools/ffplay.c:3180-3197`). | `StreamTitle` (raw ICY key). | `icy-name`. Also the raw headers in the `icy_metadata_headers` export option (`http.c:184`, `:967-985`). | When the demuxer reads the block. This is before play time, by the size of the application's buffers. |
| mpv | `metadata` property. | `icy-title`. | `icy-name`. | A change was seen while playing. The exact timing against the audio was not checked. Unverified. |

Verified locally: GStreamer gave `organization: Test Radio` and then
`title: Artist - Song 0`, `Song 1`, `Song 2`. `ffmpeg -v verbose` logged
`Metadata update for StreamTitle: …`, and `ffprobe` showed
`tag:icy-name=Test Radio|tag:StreamTitle=Artist - Song 0`. An mpv Lua
observer on `metadata` printed `icy-title=Artist - Song 0 icy-name=Test Radio`
and later `Song 1`.

Consequence: Mopidy core today finds the stream title from the `title` tag
(`core/_actor.py:168-184`). Any second engine needs a mapping from its keys
to Mopidy's keys. For FFmpeg, Mopidy must also delay the event until the
audio is heard.

### 2.5 Comparison

| Feature | GStreamer | FFmpeg | mpv |
| --- | --- | --- | --- |
| Player object | `playbin`, `playbin3`, `GstPlay` | None. Application code. | One mpv core per `mpv_create()` |
| Play, pause, stop | States | Application code | `loadfile`, `pause` property, `stop` |
| Next-URI hook | `about-to-finish` signal, blocking, streaming thread | Application code | None. Append to the playlist before the end. |
| Gapless | Yes, with the hook | Application code. Encoder delay handled by skip-samples side data. | Between playlist entries, `--gapless-audio` |
| Seek and seekable | Seek event, SEEKING query | `av_seek_frame()`, `AVFMTCTX_UNSEEKABLE` | `seek`, `seekable` |
| Position | Position query, SEGMENT events | Application code | `time-pos` |
| Software volume | `volume` element | Sample math or `volume` filter | `volume` property |
| Buffering events | BUFFERING message, application pauses | None | `paused-for-cache`, `cache-buffering-state`, mpv pauses by itself |
| ICY title | `title` tag | `StreamTitle` in metadata, flag on read | `icy-title` in `metadata` |
| End of stream | EOS message | `AVERROR_EOF` | `END_FILE` reason `EOF` |
| Errors | ERROR message, `GLib.Error`, missing-plugin message | `AVERROR` codes | `END_FILE` reason `ERROR`, error code |
| Outputs | Any sink, `tee`, `shout2send` | libavdevice ALSA, OSS, Pulse; or own output library | `--ao` drivers, including PipeWire |
| Output plus Icecast at once | Yes, `tee` | Application code (`tee` muxer and `icecast` protocol exist) | Not found |
| Custom source | `source-setup`, `appsrc`, own elements | `avio_alloc_context()` | `mpv_stream_cb_add_ro()` (not stable) |

## 3. Scanner

### 3.1 GStreamer: Discoverer and Mopidy's own pipeline

- `GstPbutils.Discoverer` has a blocking mode (`discover_uri()`) and a
  non-blocking mode that needs a running GLib main loop
  (<https://gstreamer.freedesktop.org/documentation/pbutils/gstdiscoverer.html>).
- Inside, it uses one `uridecodebin` in one pipeline
  (`gst:gst-plugins-base/gst-libs/gst/pbutils/gstdiscoverer.c:384-395`) and
  processes one URI at a time from a queue (`gstdiscoverer.c:91-98`). For
  parallel scans, Mopidy needs more Discoverer objects.
- It gives duration, seekable (from a SEEKING query, `gstdiscoverer.c:1490-1496`),
  live, stream info with caps, and tags. `DiscovererInfo.get_tags()` is
  deprecated in favor of per-stream tags (local PyGObject warning).
- It has a per-URI timeout and, since 1.24, a `load-serialized-info` signal
  for a cache (Discoverer documentation page).
- Mopidy does not use Discoverer. It has its own pipeline (section 1.3) with
  its own "playable" and MIME logic.

### 3.2 FFmpeg: `avformat_find_stream_info()` and `ffprobe`

- `avformat_open_input()` reads the header and tags. `avformat_find_stream_info()`
  "read[s] packets of a media file to get stream information"
  (`ffmpeg:libavformat/avformat.h:2283-2303`). `probesize` and
  `max_analyze_duration` limit the work (`avformat.h:1500`, `:1508`).
- Duration has a quality field: `duration_estimation_method` is one of
  `AVFMT_DURATION_FROM_PTS` ("accurately estimated"), `FROM_STREAM` or
  `FROM_BITRATE` ("less accurate") (`avformat.h:1297-1299`, `:1749`). When it
  uses the bitrate, libavformat logs "Estimating duration from bitrate, this
  may be inaccurate" (`ffmpeg:libavformat/demux.c:1816`, `:1866`).
- "Is it audio": check for an audio stream and a decoder for its codec.
- `ffprobe` is the CLI form. It costs one process per file (about 48 ms per
  file locally, mostly process start).
- The calls are synchronous. Many scans in parallel means many threads, each
  with its own `AVFormatContext`. Unverified: thread-safety limits.

### 3.3 mpv as a scanner

mpv has no "probe only" API. Local tests with the CLI:

- `--frames=0` exits before the file is loaded, so it gives no metadata.
  `--frames` counts video frames.
- `--end=0` and `--start=100%` load the file, give `duration`,
  `file-format`, `audio-codec-name`, `seekable` and tags, and then exit with
  "Errors when loading file".
- `--pause` gives the same data and then stays open until it is stopped.

So with libmpv, a scanner is a separate core (`mpv_create()`) with
`ao=null`, `pause=yes`, a `loadfile`, a wait for `MPV_EVENT_FILE_LOADED`,
property reads, and `stop`. This loads demuxer and decoder state for each
file. The duration comes from libavformat, so the accuracy is the same as
FFmpeg (section 3.5). Each run took about 60-70 ms locally, mostly process
start.

### 3.4 Live streams in the scanners

For the local ICY stream (verified locally):

| Scanner | Duration | Seekable | Other |
| --- | --- | --- | --- |
| Mopidy scanner | `None` | `False` | `playable=True`, `mime=application/x-icy`, tags `title` and `organization`, 26 ms |
| Discoverer | `GST_CLOCK_TIME_NONE` | `False` | `live=False`, title tag, 20 ms |
| `ffprobe` | not tested for duration | not tested | `tag:icy-name`, `tag:StreamTitle` |
| mpv | grows while it plays | `false` | `demuxer-via-network=true` |

### 3.5 Accuracy: VBR MP3 without a Xing header

Test files (verified locally): 30 s of silence and then 30 s of noise,
encoded with `libmp3lame -q:a 0`. One copy has a Xing header, and one copy
was remuxed with `-write_xing 0`. Real duration: 60.0 s.

| File | Mopidy scanner | Discoverer | `ffprobe` | mpv |
| --- | --- | --- | --- | --- |
| VBR MP3 with Xing | 60.029 s | 60.029 s | 60.000 s | not tested |
| VBR MP3 without Xing | 177.696 s | 60.374 s | 177.696 s (with the "Estimating duration from bitrate" warning) | 2:57 |
| FLAC | 60.000 s | 60.000 s | 60.000 s | 1:00 |
| Ogg Vorbis | 60.000 s | 60.000 s | 60.000 s | not tested |
| HLS (`.m3u8`, local) | 60.031 s | 60.031 s | 60.032 s | 1:00 |

A full decode (`ffmpeg -f null -`) gave 60.029 s in 78 ms. The silent start
has a low bitrate, so an estimate from the first frames is about 3 times too
long. Unverified: why Discoverer gets close to the right value and the
Mopidy scanner does not. One candidate is the Mopidy PLAYING and
DURATION_CHANGED workaround (`scan.py:349-373`), which takes the first new
estimate.

## 4. Resolve

### 4.1 Playlist formats

Verified locally with local files that point to `tone.ogg`, and with the
local HTTP server for `.pls`:

| Input | GStreamer | FFmpeg | mpv | Mopidy parser |
| --- | --- | --- | --- | --- |
| PLS | Error "This appears to be a text file" (scanner). Over HTTP, `playbin` fails with "Could not determine type of stream". | Probed as `lrc` (lyrics) locally. Over HTTP: I/O error. | Expanded. Plays the entry. | Yes |
| M3U (`#EXTM3U`, no HLS tags) | Typed `text/uri-list`. Discoverer: "missing a plug-in". | "Invalid data found" | Expanded | Yes |
| XSPF | Typed `application/xml`. Discoverer: "missing a plug-in". | "Invalid data found" | "Errors when loading file" | Yes |
| ASX | Error "This appears to be a text file" | "Invalid data found" | "Errors when loading file" | Yes (two variants) |
| HLS `.m3u8` | `hlsdemux` and `hlsdemux2` | `hls` demuxer | `hls` via libavformat | No, not needed |

Facts from the sources:

- GStreamer `typefindfunctions` has finders for `application/x-hls`,
  `text/uri-list`, `application/xml` and others, but none for PLS, XSPF or
  ASX playlists (verified locally with `gst-inspect-1.0 typefindfunctions`).
  No GStreamer element unwraps a playlist into a new URI.
- FFmpeg has no PLS, M3U, XSPF or ASX demuxer. Its `hls` demuxer handles
  HLS only (verified locally with `ffmpeg -demuxers`).
- mpv's default `--playlist-exts` is `cue,edl,m3u,m3u8,pls`
  (`mpv:DOCS/man/options.rst:8168`, value verified locally). Playlist
  entries from the network are marked unsafe, and mpv only loads local files
  and HTTP links from them unless `--load-unsafe-playlists` is set
  (`mpv:DOCS/man/options.rst:390-398`). mpv expands a playlist into its own
  playlist, which interacts with Mopidy's tracklist and with the gapless
  playlist model (section 2.3).
- `--ytdl` is on by default in mpv. It can resolve web pages to media URLs
  through an external program. Unverified for radio sites.

### 4.2 Redirects and content type

- All three followed a 302 redirect to the ICY stream (verified locally).
  `souphttpsrc` has `automatic-redirect` (default `true`). FFmpeg's `http`
  protocol has `max_redirects` (default 8). Both verified locally with the
  inspect tools.
- Mopidy's parser detects playlists by content, not by `Content-Type`
  (`parsers.py:8-19`). GStreamer types by content (typefind). FFmpeg probes
  content. Unverified: how much mpv uses the `Content-Type` header for
  playlists.

### 4.3 Consequence

Resolve is not an engine feature in GStreamer or FFmpeg, and mpv
does only part of it. So resolve can stay in Mopidy (today the stream
extension) for all engines. Today it depends on the scanner to tell "audio"
from "not audio" (section 1.5).

## 5. Life cycle and threading

### 5.1 GStreamer

- Streaming threads push data. The bus carries messages to the application.
  An application can use a GLib main loop bus watch, or a sync handler as
  Mopidy does (section 1.2).
- `about-to-finish` and `source-setup` run on streaming threads. Mopidy
  blocks a streaming thread while core picks the next track (section 1.2).
- A playback pipeline lives for the whole Mopidy process. A scan pipeline
  lives for one URI (`scan.py:78-89`).
- Each scan builds and tears down a full pipeline with typefinding and
  plugin lookups. The scanner calls run on the caller's thread (backend actor
  threads, or the Mopidy-Local CLI loop).

### 5.2 FFmpeg

- All calls are synchronous and run on the caller's thread. There is no
  event loop. Blocking network calls stop through `interrupt_callback`.
- A player needs at least a read and decode thread and an output thread (or
  an output callback). Mopidy would own all of these.
- A scan is a short sequence of calls with one `AVFormatContext`. This is
  the cheapest scan of the three: no process, no pipeline, no player core.

### 5.3 mpv

- Each `mpv_create()` makes a player core with its own threads. The event
  loop is "detached from the actual player", so a slow event reader does not
  stop playback (`mpv:include/mpv/client.h:85-97`).
- The application calls `mpv_wait_event()`, or sets
  `mpv_set_wakeup_callback()` and then drains events from its own thread.
  The callback "will be called from foreign threads", and it must not call
  the client API (`client.h:1733-1757`).
- The API is thread-safe, but "everything is serialized through a single
  lock in the playback core" (`client.h:134-139`). Synchronous calls "can
  take an unbounded time (e.g. if network is slow)" (`client.h:99-105`).
- The environment must have `LC_NUMERIC` set to `C` (`client.h:141-148`).
  Unverified: how this interacts with Python's locale handling.
- Parallel scans with mpv need one core per concurrent scan.

### 5.4 Fit with Pykka actors

| Engine | Long-lived playback | Many short scans |
| --- | --- | --- |
| GStreamer | One actor that owns a pipeline. Events from streaming threads go to the actor with `tell()` (today's design). | One pipeline or one Discoverer per concurrent scan. Blocking calls in the caller's thread. |
| FFmpeg | One actor plus Mopidy-owned decode and output threads. | Plain synchronous function per scan. Easy to run in a thread pool. |
| mpv | One actor that owns one core and one event thread. | One core per concurrent scan, or a pool of idle cores. Unverified: memory and start cost per core in libmpv (the CLI start was about 60-70 ms). |

## 6. Mapping of concepts

### 6.1 Concepts that map across all three

| Concept | GStreamer | FFmpeg | mpv |
| --- | --- | --- | --- |
| URI to play | `uri` property | `avformat_open_input(url)` | `loadfile` |
| Play, pause, stop | PLAYING, PAUSED, NULL | Application code | `pause`, `stop` |
| Position | Position query | Application code (sample timestamps) | `time-pos` |
| Duration | Duration query | `AVFormatContext.duration` | `duration` |
| Seekable | SEEKING query | `pb->seekable`, `AVFMTCTX_UNSEEKABLE` | `seekable` |
| Tags as key to values | `GstTagList` | `AVDictionary` | `metadata` map |
| End of stream | EOS | `AVERROR_EOF` | `END_FILE` `EOF` |
| Error | ERROR | `AVERROR` | `END_FILE` `ERROR` |
| Next-track hook | `about-to-finish` | Own loop | Playlist append (different model) |
| Buffering state | BUFFERING percent | Own queue | `cache-buffering-state` |

Tag keys do not map one to one. GStreamer uses its own names (`title`,
`artist`, `album-artist`, `organization`). FFmpeg and mpv use container keys
(for example `StreamTitle` and `icy-title`). A neutral interface needs
Mopidy-owned tag names and a mapping per engine.

### 6.2 Concepts that are GStreamer-specific

- Pipelines, bins, elements, pads, caps and the READY state. `prepare_change()`
  exists because of READY (`_gst/audio.py:391-400`).
- `source-setup` with a `Gst.Element` (Mopidy-Spotify depends on it).
- `appsrc` and pushed raw buffers (removed from Mopidy 4.0).
- The `Gst.TagList` type and GStreamer tag names, including in
  `convert_tags_to_track()` and in the `tags_changed` docs.
- Bus messages, missing-plugin messages and the plugin installer hint.
- `audio/output` as a `gst-launch` description, with `tee` and `shout2send`.
- `supported_uri_schemes()` from the plugin registry.
- The `live_stream` flag as `set_live(True)` on the source, and the
  `download` flag as a `playbin` flag.

### 6.3 What mpv and FFmpeg cannot do that Mopidy uses today

| Mopidy use today | mpv | FFmpeg |
| --- | --- | --- |
| Blocking about-to-finish callback that asks core for the next track (`core/_playback.py:193-207`) | No. Next URI must be in the playlist early. | Possible, in Mopidy's own loop. |
| `spotifyaudiosrc` through `on_source_setup()` | No equivalent element. A custom protocol (`mpv_stream_cb_add_ro()`, not stable) could feed data, but Mopidy-Spotify would need a new audio source. | No equivalent. Custom `AVIOContext` possible. |
| `audio/output` pipeline strings, including `tee` to Icecast | `--ao` plus `--audio-device`. No play-and-encode at once found. | Mopidy must write output and any Icecast path. |
| Tag names that core and extensions read (`title`, `organization`) | Different keys (`icy-title`, `icy-name`) | Different keys (`StreamTitle`, `icy-name`) |
| `live_stream` and `download` buffering modes | No direct match. mpv has cache options (`--cache`, `--cache-secs`, `--cache-pause`). | Application code |
| Missing-plugin hints | No plugin model | No plugin model (build options) |
| `supported_uri_schemes()` | No registry query found. Unverified: `protocol-list` property. | `ffmpeg -protocols` equivalent through `avio_enum_protocols()`. Unverified for Python bindings. |
| Software mixer on a `volume` element | `volume` property (works) | Application code (works) |

## 7. The hypothesis: separate playback engine and scanner interfaces

Facts that support separation:

- Life cycle: playback is one long-lived object per Mopidy process. A scan
  is one short job per URI, and the current scanner already builds a new
  pipeline for each URI (`scan.py:92-93`).
- Concurrency: scans run on many caller threads (file and stream backends,
  the Mopidy-Local CLI, Mopidy-TuneIn). The player is one actor. Discoverer
  and libmpv cores each do one URI at a time.
- Best tool per engine: the best GStreamer scanner (Discoverer, by the VBR
  test) and the best FFmpeg scanner (`avformat_find_stream_info()`) are not
  the playback objects. FFmpeg is a natural scanner and a poor player
  (no player library). mpv is a good player and a poor scanner (no probe
  API). So "mpv for playback, FFmpeg for scanning" is a real combination, and
  it needs two interfaces.
- The scanner has a different set of users: library lookup, the Mopidy-Local
  CLI (no actors, `commands.py:226`), and resolve in the stream
  extension and Mopidy-TuneIn.

Facts that weaken or limit separation:

- mpv uses libavformat for demuxing and HTTP, so an mpv player and an FFmpeg
  scanner agree on formats and durations (same 177.7 s result). A GStreamer
  scanner with an mpv player would not always agree on what is "playable".
- The stream extension uses the scanner as a gate in the playback path
  (`translate_uri()`). The result ("is this audio, is it seekable") is only
  true for the engine that will play it. If the scanner and the player are
  different engines, a URL can pass the scan and fail to play, or the other
  way around.
- Mopidy-TuneIn's `is_live()` uses the scanner's `seekable` result to set
  playback buffering (`mopidy-tunein/src/mopidy_tunein/actor.py:266-272`).
  This couples one scanner result to one player feature.
- Some metadata only exists during playback: ICY titles change over time
  and come from the player (section 2.4). The scanner gives only the first
  title. So "tags" belong to both interfaces, with different meanings
  (file tags against live stream tags).
- With mpv only, a scanner is a paused player core, so the two interfaces
  would share one implementation.

## 8. Options

These are options, not recommendations.

| Option | What it means | Trade-offs |
| --- | --- | --- |
| A. One `Audio` interface, as today | Keep scanner functions next to the actor, both GStreamer only. | Least work. Keeps all GStreamer leaks (section 6.2). A second engine needs a new API anyway. |
| B. Separate playback engine and scanner interfaces, same engine family by default | Two interfaces. Each engine package gives both. Config picks the engine family. | Scan results match the player. Mixed setups stay possible but not the default. |
| C. Separate interfaces, free mix | Any scanner with any player. | Allows "mpv plus FFmpeg". The `translate_uri()` gate and `is_live()` can give wrong answers across engines. |
| D. Also a resolver interface | Move playlist unwrapping from the stream extension into a third, engine-free component that takes a "probe" function. | No engine does it fully (section 4), so this code stays in Mopidy anyway. Mopidy-TuneIn could reuse it instead of a copy. |

Interface points that any option must decide, from section 6:

- Mopidy-owned tag names, and where the engine mapping lives.
- A next-URI model that fits both "blocking callback" (GStreamer) and
  "append before end" (mpv). For example, core could give the next URI
  early, and the GStreamer engine could keep it until `about-to-finish`.
- A replacement for `on_source_setup(Gst.Element)`, for example per-URI
  options (headers, proxy, credentials) as plain data, plus an
  engine-specific escape hatch for Mopidy-Spotify.
- An output config that is not a `gst-launch` string, or that is defined
  per engine.
- Buffering hints (`is_live`, `should_download`) as engine-free hints.

## Open questions

1. Does Mopidy want to keep the blocking about-to-finish model, or move to
   "core gives the next URI early"? The second model fits mpv and FFmpeg,
   but core must then cancel or replace the queued URI when the tracklist
   changes.
2. How late can a `loadfile … append` come in libmpv and still give gapless
   playback? This needs a prototype.
3. Should the stream title come from a separate event (for example
   `stream_title_changed` from the engine), instead of from the `title` tag
   that core compares with the track name (`core/_actor.py:168-184`)? Each
   engine has a different ICY key.
4. Which tag names should be Mopidy's own? `convert_tags_to_track()` and the
   `tags_changed` docs use GStreamer names now.
5. What replaces `on_source_setup()` for Mopidy-Spotify? The only source is
   the GStreamer `spotifyaudiosrc` element.
6. Why does the Mopidy scanner give 177.7 s for a VBR MP3 without a Xing
   header, while Discoverer gives 60.4 s? Should Mopidy switch to
   Discoverer? Why is `mime` `None` for local files (section 1.3)?
7. Is the scanner in the playback path (`translate_uri()` in the stream
   extension) wanted, or should resolve give only a URI and let the
   player fail?
8. Which Python bindings would an FFmpeg or mpv engine use (for example PyAV
   or python-mpv), and are they in Debian? Not researched.
9. Is "play and send to Icecast at the same time" a hard requirement? mpv
   has no documented way to do it.
