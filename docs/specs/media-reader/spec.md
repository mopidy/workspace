# Spec: the reader in mopidy.media

Status: draft, local only. Not published as GitHub issues yet.
Labels when published: `ready-for-agent`, `A-audio`.

Terms are from [the glossary](../../../CONTEXT.md), section "Audio and media".
Decisions are in [ADR-0002](../../adr/0002-separate-playback-engine-and-media-info-reader.md),
[ADR-0003](../../adr/0003-extensions-can-depend-on-a-media-framework.md) and
[ADR-0004](../../adr/0004-mopidy-owns-the-reader.md). Background is in
[the research report](../../research/audio-engines-gstreamer-ffmpeg-mpv.md).

Tickets:

1. [Split the GStreamer code by side](issues/01-split-gstreamer-code.md)
2. [The reader with read_media_info](issues/02-reader-read-media-info.md).
   Blocked by 1.
3. [Deprecate the old scanner API](issues/03-deprecate-old-scanner-api.md).
   Blocked by 2.
4. [parse_playlist_entries](issues/04-parse-playlist-entries.md)
5. [The m3u extension reads playlists with parse_playlist_entries](issues/05-m3u-parse-playlist-entries.md).
   Blocked by 4.
6. [read_playlist_entries and find_playback_target](issues/06-find-playback-target.md).
   Blocked by 2 and 4.
7. [Debug commands for media info, playlist entries and playback targets](issues/07-media-debug-commands.md).
   Blocked by 2, 3 and 6.

## Problem Statement

Extension developers who need metadata for a URI, or who need to find what
to play from a radio URL, have no good public API.

- The scanner is part of `mopidy.audio`, next to the playback engine. Its
  result contains raw GStreamer tags. Every caller must convert GStreamer
  tags to a `Track`, and must know GStreamer tag names to read images.
- The code that goes from a playlist document to a playback target is private
  to the stream extension. Mopidy-TuneIn has a copy of it, with its own
  parsers and format detection. The m3u extension has a third M3U parser.
  Bugs and fixes must be made in each copy.
- The parsers lose information. XSPF keeps only the first location of a
  track. ASX makes one entry for each alternative. Entry names and lengths
  are not read. The M3U parser gives the segments of an HLS playlist as
  entries.
- The stream extension follows only the first entry of a playlist document.
  If that entry fails, nothing plays, even if the next entry works.
- The stream extension scans first and downloads later. A scan of a radio
  stream must buffer audio, and a scan of a PLS URL fails after it reads
  the text.

For the Mopidy maintainers, the scanner API ties Mopidy to GStreamer. No
other media framework, such as FFmpeg or mpv, can implement it, because the
result contains GStreamer tags.

## Solution

A new public package, `mopidy.media`, has one object, the reader, which
reads media and playlist documents without playing them. A caller makes a
reader from the config and uses three methods, named for the goal of the
caller:

- read media info: the media info of one URI;
- read playlist entries: the playlist entries of a playlist document;
- find playback target: the URI to play now, from a URI that can be a
  playlist document, nested to any depth.

A pure function, parse playlist entries, gives the playlist entries from
bytes, for callers that do their own I/O.

The results use Mopidy models only: `Track`, and new small models. No
GStreamer types or tag names are part of the API. The part that depends on
the media framework, the media info reader, is inside the reader. GStreamer
implements it now. Other media frameworks can implement it later.

The old scanner API keeps working until Mopidy 5.0, with deprecation
warnings.

## User Stories

1. As an extension developer, I want one public package for reading media
   without playing it, so that I do not have to copy code from the stream
   extension.
2. As an extension developer, I want to read the metadata of a local file
   as a `Track`, so that I do not have to convert GStreamer tags.
3. As an extension developer, I want the duration of the media as the
   track length, so that I can show it and filter short files.
4. As an extension developer, I want to know if the media decoded as
   audio, so that I can skip files that are not audio.
5. As an extension developer, I want to know if the media allows seeking,
   so that I can decide if a stream is live.
6. As an extension developer, I want the embedded images of a file as
   bytes, so that I can store cover art without knowing GStreamer tag
   names.
7. As an extension developer, I want tags that are not valid to be left
   out, so that one bad tag does not stop the media info read.
8. As an extension developer, I want one error type when a URI cannot be
   read or a timeout occurs, so that my error handling is simple.
9. As an extension developer, I want to read the entries of a playlist
   document at an HTTP or file URI, so that I can add them to the tracklist.
10. As an extension developer, I want the name and length of each entry,
    when the playlist document has them, so that the tracklist shows useful
    names before playback.
11. As an extension developer, I want all alternative URIs of an entry in
    XSPF and ASX, so that I can fall back when the first URI fails.
12. As an extension developer, I want one entry for each item in the
    playlist document, not one for each alternative, so that the tracklist
    does not get duplicates.
13. As an extension developer, I want relative entries to become absolute
    URIs, so that I can use them directly.
14. As an extension developer, I want to parse bytes that I already have,
    with my own base URI and encoding, so that I can use the parser with my
    own file I/O.
15. As an extension developer, I want the format to be found from the
    content, so that a file with a wrong extension or a server with a wrong
    `Content-Type` still works.
16. As an extension developer, I want to give the media type and URI as
    hints, so that the parser tries the most probable format first.
17. As an extension developer, I want HLS and DASH to give no entries, so
    that they go to the playback engine as streams and not as lists of
    segments.
18. As an extension developer, I want to find the playback target from a radio
    station URL in one call, so that my `translate_uri()` is short.
19. As an extension developer, I want find playback target to try each alternative
    and then each entry in order, so that a station with one broken mirror
    still plays.
20. As an extension developer, I want find playback target to follow nested
    playlist documents, so that a PLS that points to an M3U still works.
21. As an extension developer, I want find playback target to stop at a URI
    that it has seen before, so that a playlist document that refers to
    itself does not loop.
22. As an extension developer, I want find playback target to stop at one total
    deadline, so that a slow server does not block my backend.
23. As an extension developer, I want find playback target to give the
    media info of the playback target, so that I can show metadata and
    decide on buffering.
24. As an extension developer, I want find playback target to give the playlist
    entry that the playback target came from, so that I can use its name if the
    stream has none.
25. As an extension developer, I want find playback target to return nothing, and
    not raise, when it finds no stream, so that I only check for one value.
26. As an extension developer, I want find playback target to log why each URI
    failed, so that users can debug a station that does not play.
27. As an extension developer, I want find playback target to give a URI that it
    could not read but that is not a playlist document as an unverified
    playback target, so that the playback engine can still try it.
28. As an extension developer, I want find playback target to look at the HTTP
    headers first, so that it does not scan a playlist document with the
    media framework.
29. As an extension developer, I want find playback target never to download the
    body of an audio stream, so that a radio stream does not fill memory.
30. As an extension developer, I want to make one reader and keep it, so
    that HTTP connections are reused between calls.
31. As an extension developer, I want to close the reader, also with
    `with`, so that its connections are released when my backend stops.
32. As an extension developer, I want a default timeout when I make the
    reader, so that I set my config value one time.
33. As an extension developer, I want the reader to use the Mopidy proxy
    config, so that it works behind a proxy without extra code.
34. As an extension developer, I want to call the reader from many threads,
    so that I can use it from actors and from a CLI command.
35. As an extension developer, I want to use the reader without actors, so
    that a CLI command such as a library scan can use it.
36. As an extension developer, I want the old scanner API to keep working
    until Mopidy 5.0, with deprecation warnings, so that I have time to
    change my extension.
37. As an extension developer, I want the deprecation warnings to name the
    new API, so that I know what to change to.
38. As a user, I want a radio station whose first mirror is down to play
    from the next mirror, so that my favorite station still works.
39. As a user, I want HLS radio stations to play, so that modern stations
    work in Mopidy.
40. As a user, I want the m3u extension to read playlist documents in other
    formats, such as PLS and XSPF, so that playlists from other players
    work.
41. As a user, I want the m3u extension to keep writing simple M3U, so that
    other players can read the playlists that Mopidy saves.
42. As a user, I want the m3u extension to keep its current rules for
    relative paths and encodings, so that my existing playlists still work.
43. As a user, I want a command that prints the media info of a file or URI
    as Mopidy reads it, so that I can debug missing or incorrect metadata.
44. As a user, I want a command that prints the playback target of a radio
    station URI, so that I can debug a station that does not play.
45. As a Mopidy maintainer, I want the reader API to contain no GStreamer
    types or tag names, so that FFmpeg or mpv can implement it later.
46. As a Mopidy maintainer, I want the part that depends on the media
    framework to be one small interface, the media info reader, so that a
    second implementation is a contained change.
47. As a Mopidy maintainer, I want the media info reader interface to stay
    private until there is a way to plug in other implementations, so that
    we do not support an interface that nobody can use.
48. As a Mopidy maintainer, I want `mopidy.audio` to contain only the
    playback engine, so that the separation in ADR-0002 is visible in the
    code.
49. As a Mopidy maintainer, I want `mopidy.audio` and `mopidy.media` not to
    import from each other, so that each can change without the other.
50. As a Mopidy maintainer, I want one parser for playlist documents in
    Mopidy, so that fixes are made in one place.
51. As a Mopidy maintainer, I want the stream extension to use only the
    public reader API, so that it is an example for other extensions.
52. As a Mopidy maintainer, I want the reader to decide "playlist document
    or not" with Mopidy's own parser, so that the result does not depend on
    which formats a media framework detects.

## Implementation Decisions

### Modules

- **`mopidy.media`** (new, public): the reader, the result models, the
  parse playlist entries function, the error type, and the factory.
- **Media info reader interface** (new, in `mopidy.media`, not exported and
  not documented): one method that gives the media info of one URI. It is
  the seam for media frameworks and for tests.
- **GStreamer media info reader** (new, private to `mopidy.media`): the
  current GStreamer scanner pipeline and the conversion from GStreamer tags
  to `Track`, moved from `mopidy.audio`.
- **Shared GStreamer helpers** (new, private, under `mopidy._lib`): signal
  handling, proxy setup, clock time conversions and tag list conversion,
  which the playback engine and the media info reader both use.
- **`mopidy.audio`**: keeps only the playback engine. It does not export
  any reader or scanner names.
- **Deprecated shims**: `mopidy.audio.scan` and `mopidy.audio.tags` keep
  their current API until Mopidy 5.0. They use the private GStreamer
  media info reader layer, because their result has raw GStreamer tags. They
  still raise `ScannerError`. They must not change the design of the new
  API.
- **Stream extension**: uses only find playback target, in `lookup()` and
  `translate_uri()`. Its private unwrap code and parsers are deleted.
- **File extension**: uses read media info in `lookup()`.
- **m3u extension**: uses parse playlist entries to read playlists, with its own
  base directory and encoding rules. Writing does not change.

`mopidy.audio` and `mopidy.media` do not import from each other, except the
deprecated shims.

### API contract

- `create_reader(config, *, timeout) -> Reader`. The only public way to
  make a reader. It always uses the GStreamer media info reader. `timeout` is
  a `DurationMs`, and it is the default for each method. For find playback target,
  it is the total deadline. Methods do not take a timeout yet.
- `Reader.read_media_info(uri) -> MediaInfo`. Reads only that URI. Raises
  `MediaReadError` if the URI cannot be opened or read, or on a timeout.
  Accepts every scheme that the media info reader supports.
- `Reader.read_playlist_entries(uri) -> tuple[PlaylistEntry, ...]`. Fetches a
  playlist document from `file`, `http` or `https`, and parses it one level
  deep. The HTTP `Content-Type` is the media type hint. Raises
  `MediaReadError` for other schemes and when the fetch fails. Does not
  read media info of the entries.
- `Reader.find_playback_target(uri) -> PlaybackTarget | None`. See "Find
  playback target" below.
- `Reader.close()`, and context manager support.
- `parse_playlist_entries(data, *, base_uri, encoding="utf-8", media_type=None,
  uri=None) -> tuple[PlaylistEntry, ...]`. No I/O.
- `MediaInfo`: `track: Track`, `playable: bool`, `seekable: bool`,
  `images: tuple[EmbeddedImage, ...]`.
  - `track.uri` is the URI that was read. `track.length` is the duration,
    or `None`.
  - `playable` means that the media info reader decoded audio. It does not
    mean that the playback engine can play the URI.
  - Tags that are not valid are left out.
- `EmbeddedImage`: `data: bytes`. It is a model, so that fields such as the
  image type can be added later.
- `PlaylistEntry`: `track: Track`, `alternatives: tuple[Uri, ...]`. There
  is at least one alternative, and `track.uri` is the first alternative.
- `PlaybackTarget`: `uri: Uri`, `info: MediaInfo | None`,
  `entry: PlaylistEntry | None`. `info` is `None` for an unverified playback target.
  `entry` is the entry in the last playlist document, or `None` if the
  first URI was the stream.
- `MediaReadError`: a subclass of `MopidyException`. It is not a subclass
  of `ScannerError`.
- All models are immutable Mopidy models. `MediaInfo` and `PlaybackTarget`
  are working names. They can change when the names for stream metadata
  from the playback engine are designed.
- The reader is safe to call from many threads.

### Reader life cycle

- Each caller makes its own reader and keeps it. Backends make it when they
  start, and close it in `on_stop()`. Mopidy does not give a reader to
  backends.
- The reader keeps an HTTP connection pool with the Mopidy proxy config.
  It does not cache results.
- For tests, the reader can receive a media info reader (and an HTTP client)
  in a constructor that is not public.

### Parse playlist entries

- Formats: M3U (with and without the `#EXTM3U` header), PLS, XSPF, ASX, ASX
  reference and URI list.
- The content decides the format. The media type and the URI are hints for
  which detector to try first. Use the media types and file extensions that
  Mopidy-TuneIn maps today as hints. A wrong hint does not change the
  result.
- HLS (content with `#EXT-X-` tags) and DASH give no entries. Content that
  is not a playlist document gives no entries.
- Relative entries are joined with `base_uri`.
- Decode with `encoding`, and replace bytes that do not decode.
- Entry metadata goes into the `Track`: name and length from `#EXTINF`, PLS
  `TitleN` and `LengthN`, XSPF `title` and `duration`, ASX `title` and
  `duration`.
- XSPF: all locations of one track are alternatives of one entry. ASX: all
  refs of one entry are alternatives of one entry. Find out if nested ASX
  documents use `entryref`. Today the parser reads `entry` with an `href`.

### Find playback target

- `http` and `https`: send GET and read the response headers.
  - A playlist media type: read the body and parse the entries.
  - An audio media type, HLS or DASH: stop before the body, and read
    media info.
  - Not clear: read the body and parse the entries. If there are no
    entries, read media info.
  - Do not use HEAD.
- `file`: parse the content first. If there are no entries, read media info.
- Other schemes: only read media info.
- If the metadata is playable, that URI is the stream.
- If there are entries, try the alternatives of each entry in order, then
  the next entry. Go into nested playlist documents.
- Stop at a URI that was seen before, and at the deadline.
- If the content does not parse as a playlist document and the media info
  read fails, return that URI with `info=None`, as an unverified playback
  target. This keeps the current behavior of the stream extension.
- Return `None` if nothing is found. Do not raise for URIs that cannot be
  read. Log why each one failed.

### Behavior changes

- The stream extension treats only playable media as a stream. Before, it
  also accepted media types that were not `text/*` or `application/*`. So
  `audio/x-mpegurl` and `audio/x-scpls` are now parsed as playlist
  documents.
- The stream extension now falls back to the next alternative and the next
  entry, plays HLS, and reads the headers before it reads media info.
- The stream extension `lookup()` still gives one track under the original
  URI. It does not add all entries to the tracklist.
- The m3u extension can read PLS, XSPF and ASX content.
- Each behavior change gets a changelog entry.

### Language

Docstrings, log messages and the changelog use the glossary terms. They do
not use "scanner", "scan", "unwrap", "expand", "resolve" or bare "playlist"
for a playlist document in the new API. They use American spelling and
simple, literal English.

## Testing Decisions

A good test checks behavior that a caller can see through a public API. It
does not check which private functions run, or in which order. A test must
still pass after a refactor that keeps the behavior.

Seams, from the highest down:

1. **The public `mopidy.media` API** is the main seam.
   - Parse playlist entries is tested directly: bytes in, entries out. This covers
     all formats, names, lengths, alternatives, relative URIs, encodings,
     HLS and DASH, and that a wrong hint does not change the result.
   - Read media info is tested end to end through `create_reader()`, with
     real GStreamer on the audio and text files in the test data. Prior
     art: the current scanner tests.
   - The reader life cycle: `create_reader()`, `close()` and the context
     manager.
2. **The media info reader seam** is the test double for read playlist
   entries and find playback target. Tests make a reader with a fake media
   info reader that gives a chosen media info, or raises `MediaReadError`,
   for each URI. HTTP is faked at the httpx transport with `pytest_httpx`.
   Prior art: the current stream extension playback tests, which use
   `pytest_httpx`. Cases:
   - a playlist document where the first entry fails and the second works;
   - an entry with two alternatives where the first fails;
   - nested playlist documents;
   - a playlist document that refers to itself;
   - the deadline;
   - an HTTP audio stream whose body is not read;
   - HLS over HTTP goes to read media info, not to parse;
   - a URI that is not a playlist document and that cannot be read, which
     gives an unverified playback target;
   - a URI that gives nothing, which gives `None`.
3. **Extensions** are thin.
   - The stream extension tests check only that `lookup()` and
     `translate_uri()` use find playback target correctly, with a patched reader.
   - The m3u extension tests stay as they are. They test through the
     playlists provider. One new test reads a playlist with PLS content.
   - The file extension tests check `lookup()` on real files.
4. **Deprecated shims** keep their current tests on real files. These
   tests show that the results are the same as on `main`, and that the
   shims warn.

## Out of Scope

- Stream metadata from the playback engine, such as ICY titles. It is
  designed separately.
- GStreamer types in the `Audio` interface: tags, the source setup
  callback, the `audio/output` config value and `prepare_change`.
- The rule for which media info reader goes with which playback engine.
- A way to plug in other media info readers, and making the media info reader
  interface public.
- Giving a reader to backends from Mopidy.
- A cache of playlist documents.
- XSPF identifiers and content resolution.
- The `have-type` handler in the GStreamer scanner that never runs.
- Changes in Mopidy-Local and Mopidy-TuneIn. They move to the new API after
  a Mopidy release that has it.
- Document titles of playlist documents.

## Further Notes

- The `scanner-interface` branch is a source of code, but it does not
  decide the design. Tickets 01 and 02 take code from it.
- Mopidy 4.1 is not released. The new API can change without deprecation
  until it is released.
- The review of the `scanner-interface` branch found these facts:
  - The GStreamer scanner gives no media type for local files.
  - On a VBR MP3 without a Xing header, it gives a duration that is much
    too long.
  - The GStreamer typefinders do not detect PLS or ASX.

  These facts are why the reader detects playlist documents with Mopidy's
  own parser. The duration problem is not fixed by this spec.
