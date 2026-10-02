# 07: A debug command that reads and prints media info

**What to build:** Users who debug missing or incorrect track metadata can
run one command that prints the media info of a file or URI, as Mopidy
sees it. This command replaces `python3 -m mopidy.audio.scan`, which will be
removed in Mopidy 5.0 with the rest of `mopidy.audio.scan`.

- A built-in `mopidy` subcommand, next to `mopidy config` and `mopidy deps`.
  It loads the config, makes a reader with `create_reader()`, and calls
  `read_media_info()` for each argument.
- Each argument is a URI or a file path. A file path becomes a `file` URI,
  as in the old command.
- For each URI, the command prints the fields of the media info: the
  `Track` fields, `playable`, `seekable`, and the number and size of the
  embedded images. It truncates long values, as the old command does.
- If read media info raises `MediaReadError`, the command prints the URI
  and the error, and continues with the next argument.
- `docs/usage/troubleshooting.md`, section "Track metadata", tells users to
  run the new command.
- The old `python3 -m mopidy.audio.scan` command stays until Mopidy 5.0.
- Changelog entry.

The old command prints raw GStreamer tags. The new command prints the
media info, which has no raw tags. To see the raw tags, users can use
`gst-discoverer-1.0`, which the troubleshooting page already names.

See [the spec](../spec.md), sections "API contract" and "Language".

**Blocked by:** 02 (The reader with read_media_info), 03 (Deprecate the old
scanner API).

**Status:** needs-triage

Open question: the name of the subcommand, for example `mopidy media-info`
or `mopidy read-media-info`.

- [ ] The command prints the media info of a local MP3, Ogg and FLAC file.
- [ ] A file path and a `file` URI give the same output.
- [ ] A missing file prints an error, and the command continues with the
      next argument.
- [ ] The reader uses the proxy config from the loaded config.
- [ ] The troubleshooting docs name the new command.
- [ ] Changelog entry.
- [ ] All tests, ruff, pyright and ty pass.
