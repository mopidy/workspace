# 02: The reader with read_media_info, used by the file and stream extensions

**What to build:** Extension developers can make a reader and read the media
info of a URI. The file extension and the stream extension use it.

- The public `mopidy.media` package has `Reader` with `create`,
  `read_media_info` and `close`, context manager support, `MediaInfo`,
  `EmbeddedImage` and `MediaReadError`.
- The `MediaInfoReader` interface is defined in `mopidy.media`, but not
  exported or documented. The GStreamer code from ticket 01 implements it.
- `Reader` can receive a media info reader in a constructor that is not
  public, for tests. `Reader.create` is the only public way to make one.
- The file extension `lookup()` gives tracks through the reader.
- The stream extension uses `read_media_info` and `playable` in its current
  private loop. Its other behavior stays the same until ticket 06.
- Both extensions keep one reader and close it when they stop.
- Changelog entries: the new API, and that the stream extension now treats
  only playable media as a stream. Before, it also accepted media types that
  were not `text/*` or `application/*`.

The API contract and the rules for read media info are in
[the spec](../spec.md), sections "API contract" and "Reader life cycle".
Use the glossary terms and the language rules in the spec, section
"Language".

**Blocked by:** 01 (Split the GStreamer code by side).

**Status:** ready-for-agent

- [ ] The public names import from `mopidy.media`. `mopidy.audio` exports
      none of them.
- [ ] Read media info of a local MP3, Ogg and FLAC file gives
      `playable=True`, the length and the tags as a `Track`.
- [ ] Read media info of a text file gives `playable=False` or raises
      `MediaReadError`. A missing file raises `MediaReadError`.
- [ ] Embedded images come back as `EmbeddedImage` bytes.
- [ ] Tags that are not valid are left out, and the read does not fail.
- [ ] Tests for `Reader.create`, `close` and the context manager.
- [ ] The file and stream extension tests pass.
- [ ] One name for "decoded audio" (`playable`) in the public and the
      private code.
- [ ] All tests, ruff, pyright and ty pass.
