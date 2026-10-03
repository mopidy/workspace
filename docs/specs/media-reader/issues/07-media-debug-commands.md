# 07: Debug commands for media info, playlist entries and playback targets

**What to build:** Users who debug missing or incorrect track metadata, or a
radio station that does not play, can run one command that prints what the
reader gives for a file or URI. The commands replace
`python3 -m mopidy.audio.scan`, which this ticket deletes.

- A built-in command group, `mopidy media`, next to `mopidy config` and
  `mopidy deps`. It has three subcommands, one for each reader method:
  - `mopidy media info` calls `read_media_info()`.
  - `mopidy media playlist-entries` calls `read_playlist_entries()`.
  - `mopidy media playback-target` calls `find_playback_target()`.
- Each subcommand makes a reader with `create_reader()` from the loaded
  config, and calls the reader method for each argument.
- Each argument is a URI or a file path. An argument that is an existing
  path becomes a `file` URI. Else, an argument with a URI scheme is a URI.
  Else, it is a file path.
- `--timeout` gives the timeout in milliseconds. The default is 5000. For
  `playback-target`, it is the total deadline.

**Output:** Each URI gets a `rich.tree.Tree`, with the URI as the root.

- The keys are the field names of the models, in the field order of the
  models. Only fields with a value are shown. Nested models, such as the
  album and the artists, are subtrees.
- The root URI is never truncated. Other long values stay on one line and
  end with "…".
- A length shows the milliseconds and `m:ss.fff`.
- Embedded images show the size of each image in bytes.
- An error is one red `error` node with the message.

`info`:

```text
file:///music/song1.mp3
├── playable  yes
├── seekable  yes
├── track
│   ├── name        trackname
│   ├── artists
│   │   └── name    name
│   ├── album
│   │   ├── name        albumname
│   │   ├── num_tracks  2
│   │   └── date        2006
│   ├── track_no    1
│   ├── date        2006
│   └── length      4608 (0:04.608)
└── images
    └── 182 bytes
```

`playlist-entries`:

```text
http://example.com/radio.pls
├── entry 1
│   ├── track
│   │   └── name  Radio
│   └── alternatives
│       ├── http://a.example.com/stream
│       └── http://b.example.com/stream
└── entry 2
    └── …
```

`playback-target`:

```text
http://example.com/radio.pls
├── uri    http://b.example.com/stream
├── info   (the subtree of `info`, or "unverified" in yellow)
└── entry  (the subtree of the entry, if there is one)
```

If no playback target is found, the root has one red line: "no playback
target found". The command does not show which URIs it tried. The reader
logs why each URI failed, and `mopidy -vv media playback-target <uri>`
shows these logs.

**Exit codes:**

- `info` and `playlist-entries`: 1 if `MediaReadError` is raised for one or
  more arguments, else 0. A playlist document with no entries prints "no
  playlist entries" and is not an error.
- `playback-target`: 1 if no playback target is found for one or more
  arguments, else 0. An unverified playback target is not an error.
- After an error, the command continues with the next argument.

**Docs and removal:**

- `docs/reference/command.md`, section "Built in commands": the `media`
  command group and its subcommands.
- `docs/usage/troubleshooting.md`, section "Track metadata": tell users to
  run `mopidy media info`.
- A new section in `docs/usage/troubleshooting.md`, "Radio streams": tell
  users to run `mopidy -vv media playback-target <uri>`.
- Delete the `__main__` block of `mopidy.audio.scan`. The deprecated
  `Scanner` API stays until Mopidy 5.0.
- Changelog entries: the new commands, and the removal of
  `python3 -m mopidy.audio.scan`, which names `mopidy media info`.

The old command prints raw GStreamer tags. The new commands print the
results of the reader, which have no raw tags. To see the raw tags, users can
use `gst-discoverer-1.0`, which the troubleshooting page already names.

See [the spec](../spec.md), sections "API contract" and "Language".

**Blocked by:** 02 (The reader with read_media_info), 03 (Deprecate the old
scanner API), 06 (read_playlist_entries and find_playback_target).

**Status:** ready-for-agent

- [ ] Smoke tests call the command functions directly, with
      `Console(record=True)`, and check the exit code and the important
      text. They do not compare the full tree.
  - [ ] `info` on a real audio file in the test data, and on a missing
        file.
  - [ ] `playlist-entries` and `playback-target`, with a reader that has a
        fake media info reader, and with `pytest_httpx`.
- [ ] A file path and a `file` URI give the same output.
- [ ] The reader uses the proxy config from the loaded config.
- [ ] `python3 -m mopidy.audio.scan` is deleted.
- [ ] Docs and changelog entries.
- [ ] All tests, ruff, pyright and ty pass.
