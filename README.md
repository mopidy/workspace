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

## Nix development shell

The optional Nix flake supplies Python interpreters and native dependencies for
the existing uv and tox workflow. It does not package Mopidy or manage Python
project dependencies.

Enter the shell from the workspace checkout, then use the shared uv workspace
and project tox configuration as usual:

```sh
cd ~/mopidy-dev/workspace
nix develop

cd ..
uv sync --all-packages --all-groups --all-extras

cd mopidy
tox -e 3.13

cd ../mopidy-spotify
tox -e 3.13
```

To use the shell from another checkout with
[direnv](https://direnv.net/), pin the upstream flake revision in `.envrc`:

```sh
use flake github:mopidy/workspace/<full-sha-you-want-to-pin>
```

Then approve it:

```sh
direnv allow
```

Update the revision explicitly when you want to adopt newer workspace changes.

The shell provides supported Python versions, uv, tox, build tools, and the
GLib, GObject introspection, GStreamer, Cairo, and X11 environment needed to
build and test Mopidy projects. It also passes the required native environment
variables into tox's isolated environments. On NixOS, tox runs in a small FHS
compatibility environment so native tools installed from PyPI work without
host-wide `nix-ld`. Run `nix flake check` in `~/mopidy-dev/workspace` to test GI
and GStreamer discovery.

## Contributing

Further simplifications and streamlining of this development environment are
welcome.
