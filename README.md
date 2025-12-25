# mopidy-workspace

Experimental development environment setup for Mopidy using
[uv](https://docs.astral.sh/uv/).

## Usage

Clone this repo:

```sh
gh repo clone mopidy/workspace ~/mopidy-dev
```

Clone Mopidy itself:

```sh
cd ~/mopidy-dev/
gh repo clone mopidy/mopidy
```

Clone any extensions you want to work on into the `ext/` directory:

```sh
cd ~/mopidy-dev/ext/
gh repo clone mopidy/mopidy-alsamixer
gh repo clone mopidy/mopidy-api-explorer
gh repo clone mopidy/mopidy-beets
gh repo clone mopidy/mopidy-local
gh repo clone mopidy/mopidy-mpd
gh repo clone mopidy/mopidy-mpris
gh repo clone mopidy/mopidy-nad
gh repo clone mopidy/mopidy-pandora
gh repo clone mopidy/mopidy-orfradio
gh repo clone mopidy/mopidy-scrobbler
gh repo clone mopidy/mopidy-soundcloud
gh repo clone mopidy/mopidy-spotify
```

> [!WARNING]
> Make sure the extensions are added to the top-level `pyproject.toml`. They
> should be listed both in `project.dependencies` and `tool.uv.sources`.

Then, use `uv` to install everything:

```sh
cd ~/mopidy-dev/
uv sync --all-packages --all-groups --all-extras --reinstall
```

And use `uv` to run `mopidy`. A good sanitity check is to begin with `mopidy deps`:

```sh
uv run mopidy deps
```

Whenever you make changes in any of the cloned repos, `uv` will detect it and
update the installation whenever needed, making sure you're always running the
latest code from across the repos.

> [!NOTE]
> Further simplifications and streamlining of the above process are welcome!
