# Issue tracker: GitHub

Issues and specs live as GitHub issues in the `mopidy` GitHub organization. Each repo in the workspace has its own issues. Use the `gh` CLI for all operations.

## Which repo

- Put an issue in the repo that owns the code: `mopidy/mopidy` for core, `mopidy/mopidy-<name>` for an extension, `mopidy/workspace` for the development setup.
- For work that spans several repos, create the parent issue in `mopidy/mopidy`. Create one child issue in each affected repo and set it as a sub-issue of the parent with `--parent <parent URL>`.
- Always pass `-R mopidy/<repo>` to `gh`. Do not let `gh` infer the repo from `git remote -v`: in some checkouts, `origin` is a personal fork.
- Refer to issues as `mopidy/<repo>#<number>` or by URL, because a bare `#42` is ambiguous across repos.

## Conventions

- **Create an issue**: `gh issue create -R mopidy/<repo> --type <Bug|Feature|Task> --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view -R mopidy/<repo> <number> --comments --json title,body,labels,issueType,parent,subIssues,blockedBy,comments`.
- **List issues**: `gh issue list -R mopidy/<repo> --state open --json number,title,body,labels,issueType,comments --jq '[.[] | {number, title, body, type: .issueType.name, labels: [.labels[].name], comments: [.comments[].body]}]'` with `--label`, `--type`, and `--state` filters as needed.
- **Comment on an issue**: `gh issue comment -R mopidy/<repo> <number> --body "..."`
- **Apply / remove labels**: `gh issue edit -R mopidy/<repo> <number> --add-label "..."` / `--remove-label "..."`
- **Set the issue type**: `gh issue edit -R mopidy/<repo> <number> --type <Bug|Feature|Task>`
- **Close**: `gh issue close -R mopidy/<repo> <number> --reason <completed|"not planned"|duplicate> --comment "..."`

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view -R mopidy/<repo> <number> --comments` and `gh pr diff -R mopidy/<repo> <number>` for the diff.
- **List external PRs for triage**: `gh pr list -R mopidy/<repo> --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`, all with `-R mopidy/<repo>`.

GitHub shares one number space across issues and PRs in a repo, so `mopidy/<repo>#42` may be either: resolve with `gh pr view` and fall back to `gh issue view`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue in the repo that owns the code (see "Which repo").

## When a skill says "fetch the relevant ticket"

Run `gh issue view -R mopidy/<repo> <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. Create it in the repo that owns the work, or in `mopidy/mopidy` if the work spans repos: `gh issue create -R mopidy/<repo> --label wayfinder:map`.
- **Child ticket**: an issue created with `--parent <map URL>`, in the repo that owns the ticket's code. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's native issue dependencies. Add an edge with `gh issue edit -R mopidy/<repo> <child> --add-blocked-by <blocker URL>`, or `--blocked-by` on `gh issue create`. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open sub-issues (`gh issue view <map URL> --json subIssues`), drop any with an open blocker (`blockedBy`) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <ticket URL> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <ticket URL> --body "<answer>"`, then `gh issue close <ticket URL>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
