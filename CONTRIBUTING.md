# Contributing to Great Hauses

This repo is **private**. Contributors have **read** access and contribute by
**fork + pull request** — nobody but the owner pushes to
`Ogilthorp3/great-hauses` directly, and `main` is never pushed to from a fork.

## 1. Fork and clone

```bash
gh repo fork Ogilthorp3/great-hauses --clone --remote
cd great-hauses
```

Your fork is private too, and `--remote` wires `upstream` back to
`Ogilthorp3/great-hauses`. Without the `gh` CLI: hit **Fork** on
<https://github.com/Ogilthorp3/great-hauses>, clone your copy, then
`git remote add upstream https://github.com/Ogilthorp3/great-hauses.git`.

Keep current with `git fetch upstream && git rebase upstream/main`.

## 2. Prerequisites

| Need | Why |
|---|---|
| **Godot 4.7** (Mobile renderer) | the project targets `4.7` — see `project.godot`. macOS: `brew install --cask godot` |
| Blender | only if you touch `tools/props/` (prop generators) |
| `python3` | the `tools/*.py` helpers |

Open the project:

```bash
open -n /Applications/Godot.app --args --path "$PWD"
```

Use `open -n`. A GUI app launched straight from a shell gets no input focus —
the window renders but nothing is clickable, which looks exactly like a broken
build.

## 3. Branch

Cut from `main`: `feat/<slug>` for features, `fix/<slug>` for fixes.

## 4. The gate — run E2E before you open the PR

```bash
./test_e2e/run_e2e.sh              # full suite — exit 0 is the only green
./test_e2e/run_e2e.sh boot duel    # subset while iterating
```

The suite runs the headless test suites *and* windowed in-engine scenarios with
synthesized input. **A real game window will open** — don't touch the mouse or
keyboard while it's up, or you'll fight the driver and fail the run. Each launch
uses an isolated `$HOME`, so your real `user://` save data is never touched.

A change that hasn't been through a green run is not ready for review. Paste the
suite's summary line into the PR.

If you touched anything that ships, also read `docs/BUILDING.md` and run
`./tools/build/build.sh all` — the export has its own freshness gate.

## 5. What never goes in a commit

`.godot/`, `test_e2e/artifacts/` and `__pycache__/` are gitignored — keep them
that way. Build artifacts belong in `../great-houses-dist/`, deliberately
**outside** `res://`, because a build dropped inside the project gets swept into
the next export. Never commit an exported binary.

## 6. Assets and licenses

Every asset pack carries its license beside it (`assets/*/License*.txt`,
`LICENSE-*.txt`) — KayKit, Quaternius CC0, Kenney, and the custom props. If you
add an asset, add its license file and record its provenance (source URL / asset
id) **in the same commit**. Do not import code or assets from NonCommercial
(CC BY-NC-SA) sources into this project.

## 7. Issues

GitHub Issues is the live queue. `ISSUES.md` is the historical record from
before this repo had a remote — read it for context, file new work as an issue.

## 8. Open the PR

```bash
git push -u origin feat/<slug>
gh pr create --repo Ogilthorp3/great-hauses --base main --fill
```

Target `main` on `Ogilthorp3/great-hauses`. Fill in the template — the E2E
checkbox is the one that matters.
