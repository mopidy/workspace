# mopidy-workspace

Experimental development environment setup for Mopidy using
[uv](https://docs.astral.sh/uv/).

## Layout

`~/mopidy-dev/` is a plain directory, not a Git repo. Each project is its own
checkout below it, and this repo lives in the `workspace/` subdirectory. Its
`pyproject.toml` and `.mise.toml` are symlinked to the top level, which makes
`~/mopidy-dev/` the uv workspace root.

```text
~/mopidy-dev/
├── workspace/                             # this repo
├── mopidy/                                # Mopidy core
├── mopidy-mpd/                            # one checkout per extension
├── mopidy-spotify/
├── website/                               # and other supporting repos
├── pyproject.toml -> workspace/pyproject.toml
├── .mise.toml -> workspace/.mise.toml
├── uv.lock
└── .venv/
```

Keep this repo in a subdirectory. If you clone it to `~/mopidy-dev/` instead,
its `.gitignore` marks every checkout below as ignored, and editors then gray
out all of your projects and skip them in file search.

## Usage

Create the directory and clone this repo:

```sh
mkdir -p ~/mopidy-dev
gh repo clone mopidy/workspace ~/mopidy-dev/workspace
```

Symlink the shared configuration to the top level:

```sh
cd ~/mopidy-dev/
ln -s workspace/pyproject.toml pyproject.toml
ln -s workspace/.mise.toml .mise.toml
```

> [!NOTE]
> If you use [mise](https://mise.jdx.dev/), trust the new path with
> `mise trust ~/mopidy-dev/.mise.toml`.

Clone Mopidy itself:

```sh
cd ~/mopidy-dev/
gh repo clone mopidy/mopidy
```

Clone any extensions you want to work on into the same directory:

```sh
cd ~/mopidy-dev/
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
> Make sure the extensions are added to `workspace/pyproject.toml`. They
> should be listed both in `project.dependencies` and `tool.uv.sources`.
>
> `tool.uv.workspace.members` picks up any `mopidy-*` directory, so keep the
> directory name lowercase. A repo cloned as `Mopidy-Pandora` does not match.
> Directories that are not workspace members, such as `mopidy-ext-template`,
> must be listed in `tool.uv.workspace.exclude`.

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
