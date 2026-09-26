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
