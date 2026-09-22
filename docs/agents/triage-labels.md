# Triage Labels

The skills speak in terms of five canonical triage state roles and two category roles. This file maps those roles to what the `mopidy` GitHub organization uses. The same mapping applies in every repo.

## State roles

Each triaged issue has at most one state label.

| Role in mattpocock/skills | In our tracker                  | Meaning                                  |
| ------------------------- | ------------------------------- | ---------------------------------------- |
| `needs-triage`            | label `needs-triage`            | Maintainer needs to evaluate this issue  |
| `needs-info`              | label `needs-info`              | Waiting on reporter for more information |
| `ready-for-agent`         | label `ready-for-agent`         | Fully specified, ready for an AFK agent  |
| `ready-for-human`         | label `ready-for-human`         | Requires human implementation            |
| `wontfix`                 | close with `--reason "not planned"`, no label | Will not be actioned       |

If a state label does not exist in a repo yet, create it with the same name, color, and description as in `mopidy/mopidy` before you apply it.

## Category roles

Categories are GitHub issue types, not labels.

| Role in mattpocock/skills | In our tracker        |
| ------------------------- | --------------------- |
| `bug`                     | issue type `Bug`      |
| `enhancement`             | issue type `Feature`  |

The issue type `Task` is for internal work that is neither a bug nor a feature.

## Other labels

- `A-<area>` labels mark the code area. They are per repo. Apply one if it fits; do not create new ones without asking.
- Keep `good first issue` and `breaking change` where they apply.

## Out-of-scope records

Do not write `.out-of-scope/` records. The "not planned" close reason on GitHub is the only record of a rejected feature request. To check for a prior rejection, search the closed issues: `gh search issues --repo mopidy/<repo> --state closed 'reason:"not planned"' <terms>`.
