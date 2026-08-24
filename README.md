# Great Hauses Chess

A medieval 3D chess game built in Godot 4 — classical FIDE tournament rules
underneath, real-time cinematics on top. Dynamic camera direction tracks every
clash, banners move along the stone hall, and a dragon spectates from the
rafters.

Ships on macOS, Windows, iPad (TestFlight) and visionOS as an Immersive Space.

## Why it exists

Every home server cluster needs a hobby. This one plays chess. When the Sanctum
cluster is not routing prompts or watching the heat-pump logs, it takes the
other side of the board — the same council of local and hosted models that runs
the haus, playing through a calibrated Stockfish ladder from a forgiving
~1000 Elo up to full NNUE.

The engine is split headless-core / presentation, so the rules and the search
run without a renderer attached and the cinematics are a client of them rather
than tangled through them.

## Layout

| Path | What |
|---|---|
| `src/` | headless core — rules, search, match state |
| `scenes/` | Godot scenes, the presentation layer |
| `hauses/` | the playable houses and their piece sets |
| `assets/` | models, music, branding (see licensing below) |
| `dlc/` | downloadable content packs |
| `docs/` | design and integration notes |
| `INTEGRATION-*.md` | per-feature integration notes (dragon, music, costumes, multiplayer, branding) |

Requires **Godot 4.7**. Open `project.godot`.

Release history is in [RELEASE-NOTES.md](./RELEASE-NOTES.md); known issues in
[ISSUES.md](./ISSUES.md); contribution guidance in
[CONTRIBUTING.md](./CONTRIBUTING.md).

## Licensing

This repository is **mixed-licence and has no single repo-level LICENSE file
yet** — that decision is open. Please do not assume the code is open source.

Third-party assets already carry their own terms, per directory:

- `assets/kaykit-adventurers/License.txt`, `assets/kaykit-skeletons/License.txt`
- `assets/quaternius-animals/LICENSE-horse.txt`
- `assets/music/licenses/` and `assets/music/CREDITS.md`
- `assets/branding/LICENSE-branding.txt` — branding is proprietary

Honour those individually. If you want to reuse anything here, ask first.

## Security

Found something that exposes a player, a build pipeline, or the signing chain?
Please report it privately — `security@sanctum.run` — rather than opening a
public issue.
