# mopidy-workspace

Experimental development environment setup for Mopidy using
[uv](https://docs.astral.sh/uv/).

## Usage

Clone this repo:

```sh
gh repo clone mopidy/workspace ~/mopidy-dev
```

Enter the newly created development environment:

```sh
cd ~/mopidy-dev
```

Clone any extensions you want to work on:

```sh
gh repo clone mopidy/mopidy-local
gh repo clone mopidy/mopidy-mpd
gh repo clone mopidy/mopidy-spotify
```

> [!WARNING]
> Make sure the extensions are added to the top-level `pyproject.toml`. They >
> should be listed both in `project.dependencies`, `tool.uv.sources`, and
> `tool.uv.workspace`.

Then, use `uv` to install everything:

```sh
uv sync
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
