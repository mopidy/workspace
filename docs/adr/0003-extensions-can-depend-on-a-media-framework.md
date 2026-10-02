---
status: accepted
---

# Extensions can depend on a specific media framework

An extension can work with only one media framework. Mopidy can have hooks
that are specific to one media framework, but each such hook is marked as
specific to that framework, and it is not part of the general playback
engine or scanner interfaces.

We chose this so that experiments can continue while the general interfaces
get stricter. Mopidy-Spotify is an example: it plays through the GStreamer
element `spotifyaudiosrc` from gst-plugins-rs, and it gets the element
through `set_source_setup_callback()`. If all extensions must use only the
general interfaces, Mopidy-Spotify must change before any other media
framework can be used.
