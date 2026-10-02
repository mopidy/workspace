# Mopidy

Mopidy is a music server that is extended by extensions. This glossary covers
Mopidy core and all extensions.

## HTTP

**HTTP frontend**:
The bundled extension that serves Mopidy's HTTP API, the JSON-RPC WebSocket
and all web apps on one port.
_Avoid_: HTTP server, web server

**Web app**:
Anything an extension mounts under `/<name>/` in the HTTP frontend. A web
client is one kind of web app.
_Avoid_: HTTP app, web application

**Web client**:
A web app that gives users a browser UI to control Mopidy.
_Avoid_: Web UI, frontend

**ASGI app**:
A web app that an extension registers with `http:asgi`. The public type is a
plain ASGI callable, not a class from a framework.

**Tornado app**:
A web app that an extension registers with `http:app`, as a list of Tornado
request handlers.
_Avoid_: Legacy app

**Static app**:
A web app that an extension registers with `http:static`, as a directory of
files.

## Audio and media

**Media framework**:
A third-party library that plays or reads media, such as GStreamer, FFmpeg
or mpv. It is not a Mopidy component. Mopidy uses GStreamer today.
_Avoid_: Audio backend, audio engine

**Playback engine**:
The component that plays URIs to the audio output and reports stream
metadata. There is one playback engine in each Mopidy process, and it lives
as long as the process. It does not read metadata of URIs that it does not
play.
_Avoid_: Audio engine, audio backend, player

**Audio**:
Mopidy's current playback engine, `mopidy.audio`. `GstAudio` implements it
with GStreamer.

**Stream metadata**:
Metadata that the playback engine reports while it plays, and that can
change during playback, such as the ICY title of a radio stream. Only the
playback engine gives stream metadata. The reader does not.
_Avoid_: Tags

**Stream title**:
The field of the stream metadata that tells what plays now, for example the
current song on a radio stream.

**Reader**:
The object that reads media and playlist documents without playing them,
`mopidy.media.Reader`. It has three methods: read metadata, read entries
and find stream. Each caller, for example a backend, makes its own reader
with `create_reader()` and closes it when it stops. A reader keeps an HTTP
connection pool, but it does not cache results.
_Avoid_: Scanner, prober, discoverer

**Metadata reader**:
The part of a reader that a media framework implements:
`MetadataReader`, which gives the media info of one URI. Callers do not use
it directly. It is not public until Mopidy has a way to plug in other
implementations.
_Avoid_: Scanner

**Media info**:
What read metadata gives for one URI, `MediaInfo`: the metadata as a track,
if the reader decoded audio (playable), if the media allows seeking, and
the embedded images. Playable means that the metadata reader decoded audio.
It does not mean that the playback engine can play the URI. It does not
contain raw tags from the media framework.
_Avoid_: Scan result

**Read metadata**:
Get the media info of one URI, `Reader.read_metadata()`. It reads only that
URI. If the URI is a playlist document, the result is not playable. It does
not follow playlist documents.
_Avoid_: Scan

**Playlist format**:
A text format that lists URIs: M3U, PLS, XSPF, ASX, ASX reference or URI
list. HLS and DASH are not playlist formats. They are stream formats that
the playback engine plays.

**Playlist document**:
Content in a playlist format at a URI, local or remote. It is read-only. It
is not a playlist: a playlist belongs to a backend, which can save or delete
it.
_Avoid_: Playlist file, remote playlist, playlist

**Playlist entry**:
One item in a playlist document, `PlaylistEntry`. It has a track with the
metadata of the entry, and one or more alternatives. The URI of the track
is the first alternative.

**Alternative**:
One of the URIs of a playlist entry. All alternatives of an entry give the
same content, in order of preference. Only XSPF and ASX can give more than
one alternative.
_Avoid_: Source, mirror, location

**Parse entries**:
Get the playlist entries from the bytes of a playlist document,
`parse_entries()`. It does no I/O. The content decides the playlist format.
The media type and the URI are only hints for which format to try first.
It gives no entries for content that is not a playlist document, and for
HLS and DASH.
_Avoid_: Parse playlist

**Read entries**:
Fetch a playlist document from a `file`, `http` or `https` URI and parse
its entries, `Reader.read_entries()`. It goes only one level deep. It does
not read the metadata of the entries, and it does not check that they play.
_Avoid_: Expand

**Find stream**:
Get a stream URI from a URI that the user wants to play now,
`Reader.find_stream()`. It reads entries and metadata, nested to any depth,
and tries the alternatives of each entry in order. It gives the stream URI,
its media info and the playlist entry that it came from. It does not raise
an error for a URI that it cannot read: it tries the next one.
_Avoid_: Resolve, unwrap, translate

**Stream URI**:
A URI that the playback engine can play directly, such as an audio file, an
HTTP radio stream or an HLS stream. It is not a playlist document.
