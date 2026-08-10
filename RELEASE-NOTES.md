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

**THE TRIAL BY FIRE — a knockout bracket cannot draw, so the kings settle it.**
In a **tournament**, a **stalemate** or a draw by **insufficient material** no longer
eliminates you by arithmetic. The board you just drew on becomes an arena: the pieces
still standing become the crates, wildfire jars throw cross-shaped blasts that walk a
tile at a time and chain, and **the dragon is the clock** — after seventy seconds the
wyrm wakes and torches the arena inward, ring by ring, until somebody is standing
alone. Last king up takes the round, and the bracket moves on.

It is your own army you are fighting over: the wall between you and the rival king is
made of your own bannermen, and burning them is a choice you get to make. WASD or the
arrows walk, Space sets a jar, **Esc yields the round** (it costs you the match and
nothing else — it will not quit the game). Boons hidden under the crates widen your
blast, give you more jars, or make you faster. The arena is built from *that* war's
position and seeded from its FEN, so the same drawn game always produces the same
maze.

**Where it does NOT run, said plainly:**

- **Single Match.** The rule was "offer it, don't force it", and only half of that
  shipped: a single-match draw keeps the ordinary draw card. The trial's only call
  site is the tournament one, and adding the offer means touching a function that was
  fenced off this phase (see caveat 13, which carries the patch).
- **Play a Friend (online).** The chess is turn-based and host-authoritative; this
  duel is real time. A real-time duel without a synchronised host tick is two
  different fights on two screens, so **it is gated off online** and the ordinary
  draw card is shown. Nothing about it is faked, and no desyncing duel ships.
- **Threefold and fifty-move** are draws by bookkeeping rather than by position, so
  they keep the card too.

If the trial cannot run for any reason at all, the bracket still gets an answer: the
old card, with the rival advancing, and a line saying which reason it was. A
tournament can never hang on this.

**A medieval score.** Menu and gameplay playlists that crossfade rather than cut,
stingers over the duels, and separate victory / defeat / championship fanfares — plus
an original **"medieval music meets Kraftwerk"** track for the Trial by Fire: a D
Dorian lute-and-recorder line over a motorik sequencer, 128 BPM, in three layers that
follow the duel itself. The bare pulse is the fuse; kick, tabor and bass arrive on the
first jar thrown; the lute, recorder and hurdy-gurdy drone come in when the dragon
wakes. All three layers are the same 60.000-second loop playing **at once** in sample
lock — a tier change moves volume only, so it never drops a beat. It is original work
with no licence and no attribution required (`assets/music/trial/`).

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
  bone and hide keep their own colours; sigils carry artwork. You
  may only declare materials prefixed with your own id, and you may not declare a
  surface whose name says *steel* or *leather* or *bone* to be kit. This is what stops
  a haus from being a monochrome plastic army.
- **Your king wears the same crown as everyone else's.** Regalia is a *rank* marker,
  not a haus marker: both kings on the board wear one, so the moment it varies by haus
  it starts naming the wrong haus. It did — five of the nine crowned their kings in a
  navy steel that is Haus Silverbrook's own identity colour, so in Goldclaw vs
  Winterfang the gold king wore blue. There is now one crown, for all nine and for
  yours: a dark tarnished band under polished points, so that whatever value your army
  is, one of the two tones cuts against it.

**On colour and colourblindness, precisely.** The nine are measured under the hall's
real torchlight, on every rank, and held to 12 dE2000 apart. They are **not
colourblind-safe** and the report says so on every run: nine categorical hues cannot
all clear the ~10 dE a viewer needs under all three dichromacies. What holds is that
no pair collapses on every rank at once, that the ladder is spread on lightness, that
the sigils differ in *shape*, and that the pairs which stay weak are named rather than
averaged away — `thornvale/duskfire` under protanopia, and `hartcrown/ashwyrm` plus
`goldclaw/duskfire` on the queen's dark hood specifically.

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

12. **The Trial by Fire has never been played by a human.** Every claim about it in
    this document is a claim about state and pixels, not about hand-feel. It was
    driven in the e2e by *synthesized* key events through the same
    `Input.parse_input_event` path a keyboard uses — which proves the binding, the
    walk, the jar and the death, and proves nothing at all about whether a 0.21 s step
    feels good in the hand, whether the 2.35 s fuse is tense or sluggish, or whether
    the raked arena camera stays legible while you are panicking. **Bert should be the
    one to say.** The one thing that is fun by construction is that the crates are
    your own bannermen.

13. **The single-match offer is not wired, and the winner's card is repaired from the
    wrong side.** Two consequences of one fence: `game.gd::_end_sequence` was
    off-limits this phase, and it (a) only reaches the draw seam inside
    `_in_tournament()`, and (b) hard-codes `_show_match_end(false, …)` for every draw,
    so even a trial the player WINS writes a card offering "Return to the Hall of
    Banners". The seam repairs (b) itself with a deferred fix-up that re-points the
    button at the next round — asserted live by the `trial-win` e2e — but the repair
    belongs one level up. Both are small, and both are in the same function:

    ```gdscript
    # in _end_sequence, for (b):
    var advanced := bool(verdict.get("player_advances", false))
    Session.tournament.report_result(advanced)
    _show_match_end(advanced, RESULT_TEXT.get(result, "The war is over"))
    #                ^^^^^^^^ instead of `false` — then delete the deferred
    #                fix-up in settle_tournament_draw
    ```

    For (a), call the seam for a single-match draw too (behind a prompt, since the
    owner's rule is "offer it, don't force it") and delete the `_is_tournament()`
    guard in `TrialBridge._refuse_reason`.

14. **The trial's music ships as 34.5 MB of WAV.** Correct and licence-free, but
    heavier than it needs to be: `ffmpeg` is not in this machine's shell allowlist, so
    an OGG encode (~10x smaller, no audible cost) could not be made, and hand-rolling
    a resampler in Python to fake a smaller file would have been a silent quality
    decision I had no business making. Runtime memory is already fine — the `.import`
    files use QOA, so the three layers cost 7 MB in RAM, not 34.5. The exact commands
    are in `assets/music/trial/Trial_By_Fire.license.txt`.

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

> **AMENDED 2026-08-09 ~20:25 for the Trial by Fire.** The table below is the
> 13:37:32 full-sequence run. The trial work added two headless suites
> (`minigame-suite`, `trial-wiring-suite`) and three windowed scenarios (`trial`,
> `trial-concede`, `trial-win`), and the suite was re-run **in foreground chunks**
> rather than as one sequence — every step below plus the five new ones came back
> PASS. Run dirs: `20260809-195850` (preflight + all 15 suites), `20260809-201331`,
> `20260809-201442`, `20260809-201636`, `20260809-201929`, `20260809-202259`,
> `20260809-202402`, `20260809-202439`.
>
> **Three caveats on that run, because it was not a quiet machine.** Another agent
> was editing `src/board/**` and `src/cinematics/**` and running its own Godot
> suites on this same working tree throughout:
> 1. `trial-win` failed once on a `piece_view.gd` caught **mid-save**
>    (`_prepare_bolt()` called with one argument against a zero-arg definition). Not
>    my lane and not my change; it passed on re-run once that edit landed.
> 2. `move` and `showcase` each failed once at `input-pipeline` — the synthesized-
>    mouse calibration step, before any scenario logic — under window-focus churn
>    from the co-tenant. Both pass alone.
> 3. `ds4-suite` failed once: its **live** local-LLM call timed out at 120 s under
>    load and fell back, so `source is llm*` read false. It passes standalone (the
>    Oracle answered in 81.8 s). That suite preloads only `src/ai/*` and
>    `src/chess/ChessState.gd`, none of which this work touches.
>
> Every one of those was re-run to green. None of them are perf claims, and no perf
> numbers are claimed here either.

| step | result | detail |
|---|---|---|
| minigame-suite | PASS | exit 0 · 98 checks (27 AI-vs-AI matches) |
| trial-wiring-suite | PASS | exit 0 · 88 checks |
| trial | PASS | 26 steps · real pacing, 88 s duel |
| trial-concede | PASS | 21 steps |
| trial-win | PASS | 22 steps |

The original full-sequence run:

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
