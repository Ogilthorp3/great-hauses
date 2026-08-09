# Great Hauses — v0.1.0

**Gritty medieval battle chess.** Chess rules, exactly. But every piece rides for a
Great Haus, every capture is fought as a duel in slow motion, and the last king to
fall is burned off the board by a dragon.

Built with Godot 4.7.1. Runs on macOS and Windows.

> ### ⚠ Release status: the source tree is ready. The BINARIES ARE NOT BUILT.
>
> Read this before you send anything to anybody.
>
> The `.exe` and `.app` sitting in `great-houses-dist/` are from **06:47 on
> 2026-08-09** — before the haus-pack refactor and before the rename. They are not
> merely old, they are wrong: I re-parsed the shipped Windows binary today and
> `hauses/index.json` and every `haus.json` are **MISSING** from it. That build
> cannot find a single haus. Its filename is the old spelling too
> (`GreatHouses.exe`).
>
> **I could not re-export them.** `tools/build/build.sh` is blocked by the shell
> allowlist in `~/.config/lean-ctx/config.toml`, which lists `Godot`, `run_e2e.sh`,
> `run_net_e2e.sh` and `run_perf.sh` but not `build.sh`. That is your security
> control, so I left it alone rather than editing it or hand-running the export
> commands around it. **One command unblocks it:**
>
> ```bash
> lean-ctx allow build.sh
> ./tools/build/build.sh          # both presets + every gate
> ```
>
> Everything else in this document describes the source tree, which is complete and
> whose full e2e suite is green. The friend-facing `README.txt` is already rewritten
> and correct; only the zip is waiting on the binary.

---

## What's in it

**Nine Great Hauses, and a tenth is a folder away.** Winterfang, Goldclaw, Hartcrown,
Ashwyrm, Tidegrip, Thornvale, Duskfire, Swiftcrest, Silverbrook — each with its own
banner, heraldic colours, motto, seat, horse coat, sigil, helm and crest, and its own
voice when it taunts you. None of them are hardcoded: a haus is a **directory with a
`haus.json` in it**, and the game discovers them at runtime from `res://hauses/` and
from `user://hauses/` alike. Yours loads by exactly the same path theirs do.

**A tournament for the throne.** Single-elimination, nine contenders: a play-in, the
quarterfinals, the semifinals, the grand final. You fight one match per round — three
wins takes the throne. The rest of the bracket resolves without you, and if you fall,
a rival is crowned anyway. The bracket persists to disk, so a tournament survives
quitting the game.

**Duels.** A capture isn't a piece vanishing. The two pieces fight, the camera drops
into it, and time slows. The loser is removed.

**A dragon ends it.** Checkmate is not a dialog box.

**Undo.** HUD button and Cmd/Ctrl+Z. Three per game in tournament play.

**Promotion is a choice.** A pawn that reaches the last rank opens a panel showing
all four pieces — Queen, Rook, Bishop, Knight — as the **actual models**, in your
haus's own colours and kit, and you take one by clicking it, by its letter (Q R B N),
or by walking the row with ← → and Enter. Esc, or twenty seconds of silence, takes
the queen. This is not decoration: a knight can give check from a square a queen
cannot, and promoting to a rook is sometimes the only way to avoid **stalemating**
your opponent — both of which the promotion suite proves on one position, and the
`promote` e2e walks through the real click path. It works against the engine, against
the Oracle and against a friend, the piece you pick is the piece the host validates,
and taking the move back gives you your pawn.

**Draws.** Stalemate, insufficient material, fifty quiet moves and threefold
repetition all end the war with their own words on the card and no dragon — nobody
was beaten, so nobody burns — and the rival haus now has something to say about it.
In a tournament a drawn match does not advance you, and **the card says so** instead
of quietly eliminating you. The Trial by Fire minigame that will properly settle a
draw drops into one function (`game.gd::settle_tournament_draw`).

**A medieval score.** Menu and gameplay playlists that crossfade rather than cut,
stingers over the duels, and separate victory / defeat / championship fanfares.

---

## How to play it

### macOS

```bash
open great-houses-dist/macos/GreatHauses.app
```

The bundle is **ad-hoc signed only and not notarized**, so on any Mac other than the
one that built it the first launch needs **right-click → Open** — double-clicking
gives a refusal with no override button on it.

### Windows

Unzip, double-click `GreatHauses.exe`. One self-contained file, no installer, nothing
written outside its own folder; delete the file to uninstall.

Windows will show **"Windows protected your PC"** on first launch — click *More info*
→ *Run anyway*. That dialog means SmartScreen has never seen this file before, not
that it found anything in it. Signing it away costs a few hundred dollars a year for
a code-signing certificate.

### From source

Open the project folder in Godot 4.7.1 and press Play; the main scene is
`res://scenes/main.tscn`.

Build both platform artifacts, with every gate, via `./tools/build/build.sh`, and run
the end-to-end suite with `./test_e2e/run_e2e.sh` (see `docs/BUILDING.md`).

---

## How to play a friend

Both of you need the **same build**; the protocol version is checked at connect and a
mismatch says so in plain words.

1. One of you picks a haus, chooses **Play a Friend** → **Host a Match**, picks a
   side, and clicks *Open the Gates*.
2. The host panel lists its addresses, best-first, and each line says what it is good
   for. Copy one and send it.
3. The other clicks **Join a Match** and pastes the whole line — including the trailing
   words. The parser finds the address and echoes back what it understood.

**Port UDP 7777, inbound, on the host only.** Joining needs nothing open. On Windows
the firewall prompt appears when you host: tick *Private networks*, leave *Public*
unticked. Clicking Cancel there fails later in a way that looks exactly like a wrong
address.

**Same Wi-Fi** works with no configuration at all — this is the path that needs
nothing from anybody.

**Tailnet** is the sane cross-internet path: Tailscale on both machines, use the
`100.x.y.z` address, no port forwarding and no router changes. **But see caveat 2 —
on your tailnet this is not zero-configuration, and the failure looks like a typo.**

**Port-forwarding** UDP 7777 on the host's router is the fallback of last resort.

### If a match stalls, the way out differs in two places

This bit an earlier draft of the friend README and is worth knowing yourself:

| where you are | the way out |
|---|---|
| Hall of Banners, waiting for a join | the panel's **✕ Cancel — back to the banners** button (`src/ui/house_select.gd:759`) |
| in a match, friend goes quiet | **Esc**, or the panel's **Return to the Hall of Banners** button (`src/game.gd:1839`) |

There is no Cancel button during a match. In-match you first get a label reading
*"your friend's game stopped answering"*, then a panel saying your move was never
played and you may keep waiting or go home. If your friend comes back before you
leave, the panel clears itself and play resumes.

---

## Write your own haus in twenty minutes

The full guide is [`docs/HAUS-PACK.md`](docs/HAUS-PACK.md); `hauses/_template/` is a
commented starting point and [`hauses/_examples/ravenmark/`](hauses/_examples/ravenmark/)
is a complete worked example, including a ~200-line GDScript (`make_props.gd`) that
builds a helm and a crest if you have no modelling tool.

The short version: copy `hauses/_template/`, rename it, edit `haus.json`, drop the
folder into `user://hauses/`, start the game.

| platform | `user://hauses/` is |
|---|---|
| macOS | `~/Library/Application Support/Godot/app_userdata/Great Hauses/hauses/` |
| Windows | `%APPDATA%\Godot\app_userdata\Great Hauses\hauses\` |

```jsonc
{
  "format": 1,
  "id": "ravenmark",                    // the ONLY required field
  "name": "Haus Ravenmark",
  "archetype": "raven",                 // picks the voice it taunts in
  "seat": "The Drowned Rookery",
  "motto": "We remember.",
  "colors": { "primary": "#2b2b38", "secondary": "#d8d4c8", "accent": "#c9b06a" },
  "tints":  { "kit": "#4a6f8c" },       // THE JERSEY — the one loud colour
  "coat": "black"                       // your horse is a horse
}
```

Everything except `id` degrades to a documented default **with a warning naming the
field**, so a half-finished pack still loads and still tells you what it fell back to.
A pack that is genuinely broken is refused by name (`HAUS PACK REFUSED <dir>`, with
the error) and the other hauses load anyway.

Two rules a pack cannot talk its way out of, both earned over four rounds of art work:

- **Your horse is a horse.** `coat` must be a colour horses come in — `bay`,
  `dark_bay`, `black`, `chestnut`, `liver_chestnut`, `dun`, `dapple_grey`,
  `white_grey`, `drowned_grey`. Haus identity is worn on the caparison, not grown on
  the animal.
- **Haus colour goes on kit, and nothing else.** Steel, leather, wood, stone, skin,
  bone and hide keep their own colours; crowns stay metal; sigils carry artwork. You
  may only declare materials prefixed with your own id, and you may not declare a
  surface whose name says *steel* or *leather* or *bone* to be kit. This is what stops
  a haus from being a monochrome plastic army.

Check a pack before you ship it:

```bash
Godot --headless -s res://tools/validate_house_pack.gd -- <dir>
```

---

## The opponents

Seven entries in the Hall, from `src/ui/house_select.gd:54-65`.

### The three engine tiers — always available, no dependencies

| Opponent | What it is |
|---|---|
| **Engine — Casual** | The built-in chess AI, gentlest setting. |
| **Engine — Seasoned** | The same AI, thinking harder. |
| **Engine — Master** | The same AI at full strength. |

These are the game's own engine. They need nothing installed and they are the three
you hand to a friend.

### The Oracle — three modes, two dependencies

The Oracle is a local LLM. All three modes need a model server; the two counselled
modes additionally need a `stockfish` binary on the box. Mechanics below are read out
of `src/ai/ds4_opponent.gd`, not remembered.

| Mode | What it actually does |
|---|---|
| **Pure Oracle** | The LLM alone, max thinking. It plays on its own judgement, and it will blunder like something with an imagination. |
| **Counseled Oracle** | The LLM proposes; **Stockfish reviews the proposal at depth 12** against its own best. A proposal losing more than **150 centipawns** sends the LLM back to think again, up to **2** extra times (`MAX_RECONSIDERATIONS`). If counsel is exhausted, it plays Stockfish's **3rd-ranked** move — the quiet save — and the HUD says so in a softer line. |
| **Oracle + Grand Maester** | Stockfish builds **4 candidate lines (MultiPV 4, depth 14)** with evals and one-line summaries; the **LLM picks one** and gives a short in-character reason. If the LLM is unreachable inside its budget it plays Stockfish's top move. Always strong. |

**How they degrade:** no `stockfish` → counseled and maester fall back to pure
behaviour (logged), and the UI greys the maester entry out with a reason. No model
server → the Oracle entries grey out. Both paths were tested to degrade politely;
neither should ever hang. Drop `stockfish` next to the executable to wake them.

### Play a Friend

Head-to-head over the network — see above.

---

## Honest caveats

Ordered by how likely they are to bite you.

1. **The binaries are not built, and `build.sh` is blocked.** See the box at the top.
   Until `lean-ctx allow build.sh` is run and the build re-executed, there is nothing
   shippable on disk — what is there is missing the entire haus roster.

2. **The Windows `.exe` has never been executed on Windows. Not once, by anybody.**
   It is built and verified on a Mac. What gets proven at build time: it is a valid
   PE32+ GUI x86-64 binary, and its embedded package is parsed file-by-file to confirm
   it contains the haus packs, the branding, the music and the multiplayer code and
   none of the test harness. Everything from the window opening onward — graphics,
   sound, input, the game — is unobserved on Windows.

3. **Tailnet play needs an ACL line that you must add yourself.** This is not optional
   and it is not discoverable from inside the game. `tailnet/acl.hujson` is
   default-deny with tag-based rules, so a guest device carries no tag, matches no
   accept rule, and cannot reach port 7777 — the join times out with the ordinary
   "could not reach" message *even though Tailscale itself is working perfectly*. Add
   to the `acls` block, scoped to the game port and removed after game night:

   ```jsonc
   {
     "action": "accept",
     "src":    ["autogroup:shared"],        // or the invited user
     "dst":    ["tag:sanctum-admin:7777"],
   }
   ```

4. **The `ds4-suite` live check depends on a local model server — and it is slow, but
   it did NOT time out.** I want to correct a claim that was handed to me: the story
   going in was that this step times out against a dead server. Today's run says
   otherwise, and the log is the authority:

   ```
   live endpoint reachable at http://127.0.0.1:18000/v1/chat/completions — running live move test
   live: the Oracle played e2e4 (llm, 94.4s)
   ```

   The server answered. **One move took 94.4 seconds.** That single call is why
   `ds4-suite` is the slowest step in the suite — ~97 s of the 466 s total, against
   ~56 s for the next slowest (`showcase`). So: not a timeout, not a hang, just a
   local model thinking hard on a Mac.

   Two consequences worth knowing. First, this step's duration is a property of
   *your machine*, not the game — on a box with no server at `127.0.0.1:18000` it
   takes the unreachable path instead. Second, the same run exercised the stumble
   path for real: the endpoint returned unusable replies four times running and the
   Oracle fell back to a random legal move, with a warning. That is asserted
   behaviour and it passed — but it is a fair picture of what a Pure Oracle game
   can feel like.

5. **The Hall of Banners still says "Nine banners. One throne."** — a hardcoded
   subtitle in `src/ui/house_select.gd:474`. Install a tenth haus and it hangs under
   a caption that says nine. Cosmetic; one line.

6. **`tests/test_banter.gd` asserts a roster of exactly nine.** Install a pack into
   your real `user://hauses/` and that suite goes red for a *roster* reason rather than
   a real one.

7. **`tests/test_house_packs.gd` is not wired into `run_e2e.sh`.** It exists and it
   passes when run directly, but the gate does not call it. One line in the `tests`
   block to fix.

8. **The example pack's helm is unproven on screen.** `hauses/_examples/ravenmark/`
   ships a generated `pawn_helm.glb` whose winding was measured and corrected after a
   proof screenshot showed bare skulls — but the proof was never re-rendered. The mesh
   measures in-family with the shipped helms; "it renders" is inference, not evidence.
   Affects the example pack's own art only, nothing in the format or the loader.

9. **Match load stalls ~180 ms warm, ~550 ms cold.** Located and measured, not fixed —
   the dominant cost sits behind a beat this work did not own. (The earlier
   "120–152 ms" figure was an instrument artifact: the frame clock was reset by a
   coroutine before the sampler saw the frame carrying the scene swap.)

10. **Your old tournament save is orphaned.** The rename moved the `user://` data
    directory from `Great Houses/` to `Great Hauses/`. Nothing migrates it. A
    tournament in progress before the rename will not be found; the game starts clean.
    Move the folder by hand if you care about that bracket.

11. **Performance numbers from this machine are contended.** A second Godot instance on
    the same GPU costs this game most of its frame budget, and two separate audits
    mistook that contention for a defect. Absolute frame timings taken here are not
    comparable to a quiet machine; the deterministic counters (draw calls, primitives)
    are unaffected. **No perf numbers are claimed in this document** — `run_perf.sh`
    was not run.

---

## Verifying a build yourself

Never trust an export's exit code. The two gates that exist because they each caught a
real defect:

```bash
./tools/build/build.sh freshness       # is the artifact older than its own sources?
python3 tools/build/pck_list.py <artifact> --count-only \
    --assert-present hauses/index.json --assert-absent test_e2e/
```

The freshness gate exists because a `GreatHauses.exe` once sat one step from being
sent to a friend with the entire branding set newer than it — `file` was happy, the
size was right, every content assertion passed. **An export is a photograph.** All the
checks in the world confirm the photograph is well-formed; only the timestamps tell
you it is a photograph of *this* tree.

The pck gate exists because the JSON the game reads with `FileAccess` — every
`haus.json`, `index.json`, `coats.json`, the banter and kill lines — has no `.import`
sidecar, so `export_filter="all_resources"` cannot see it. Those files ship only
because `include_filter` names them. That is exactly the trap the current stale
binary fell into.

---

## The final e2e run

`./test_e2e/run_e2e.sh`, full sequence, foreground, 2026-08-09 13:37:32 →
**466 s, exit 0, 32 of 32 steps PASS.** Logs:
`test_e2e/artifacts/runs/20260809-133732/`. Nothing else was rendering on this GPU
for the duration — I checked for co-tenant Godot processes before starting and
launched nothing beside it.

| step | result | detail |
|---|---|---|
| preflight | PASS | imported=65 scenes · headless boot clean |
| engine-tests | PASS | TOTAL: 79 · PASSED: 79 · FAILED: 0 |
| tournament-suite | PASS | exit 0 |
| cinematics-suite | PASS | exit 0 |
| ds4-suite | PASS | exit 0 · 93 checks, 0 failures · ~97 s (the slow one — see caveat 4) |
| uci-suite | PASS | exit 0 |
| music-suite | PASS | exit 0 |
| banter-suite | PASS | exit 0 |
| dragon-suite | PASS | exit 0 |
| duel-facing-suite | PASS | exit 0 |
| costumes-suite | PASS | exit 0 |
| net-suite | PASS | exit 0 |
| boot | PASS | 13 steps |
| orientation | PASS | 8 steps |
| board-truth | PASS | 11 steps |
| board-moves | PASS | 9 steps |
| move | PASS | 12 steps |
| duel | PASS | 15 steps |
| castle | PASS | 13 steps |
| enpassant | PASS | 13 steps |
| promote | PASS | 12 steps |
| slowmo | PASS | 12 steps |
| music | PASS | 17 steps |
| banter | PASS | 15 steps |
| dragon-live | PASS | 21 steps |
| tournament | PASS | 20 steps |
| oracle-mock | PASS | 13 steps |
| oracle-modes | PASS | 12 steps |
| undo | PASS | 21 steps |
| net-hall | PASS | 13 steps |
| fullgame | PASS | 11 steps |
| showcase | PASS | 22 steps |

**Not run, and why:**

- `perf` — opt-in by design, and this box is a GPU co-tenant with your live
  `.play-oracle` build. A frame number taken here would be a number about
  contention. No perf figure is claimed anywhere in this document.
- `run_net_e2e.sh` — the two-instance head-to-head runner is a separate script that
  needs two windows side by side.
- `tests/test_house_packs.gd` — exists and passes when run directly, but
  `run_e2e.sh` does not call it (caveat 7).
