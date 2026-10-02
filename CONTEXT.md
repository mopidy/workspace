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
as long as the process.
_Avoid_: Audio engine, audio backend, player

**Audio**:
Mopidy's current playback engine, `mopidy.audio`. `GstAudio` implements it
with GStreamer.

**Stream metadata**:
Metadata that the playback engine reports while it plays, and that can
change during playback, such as the ICY title of a radio stream. Only the
playback engine gives stream metadata. The scanner does not.
_Avoid_: Tags

**Stream title**:
The field of the stream metadata that tells what plays now, for example the
current song on a radio stream.

**Scanner**:
The component that reads metadata from one URI without playing it. A scanner
keeps no state between scans. It is separate from the playback engine. The
scanner interface, parse, expand and resolve are in `mopidy.media`.
_Avoid_: Discoverer, prober

**Playlist format**:
A text format that lists URIs: M3U, PLS, XSPF, ASX or URI list.

**Playlist document**:
Content in a playlist format at a URI, local or remote. It is read-only. It
is not a playlist: a playlist belongs to a backend, which can save or delete
it.
_Avoid_: Playlist file, remote playlist, playlist

**Playlist entry**:
One item in a playlist document. It has a track with the metadata of the
entry, and one or more alternatives. The URI of the track is the first
alternative.

**Alternative**:
One of the URIs of a playlist entry. All alternatives of an entry give the
same content, in order of preference. Only XSPF and ASX can give more than
one alternative.
_Avoid_: Source, mirror, location

**Parse**:
Read a playlist document from bytes into playlist entries, without I/O.

**Expand**:
Fetch a playlist document from a URI and parse it into playlist entries.

**Resolve**:
Find a stream URI from a URI that can be a playlist document. Resolve
expands nested playlist documents, tries the alternatives of each entry in
order, and stops at the first URI that the scanner reports as audio.
_Avoid_: Unwrap, translate

**Stream URI**:
A URI that the playback engine can play directly. It is not a playlist
document.
