# Great Hauses — v0.1.0

**Gritty medieval battle chess.** Chess rules, exactly. But every piece rides for a
Great Haus, every capture is fought as a duel in slow motion, and the last king to
fall is burned off the board by a dragon.

Built with Godot 4.7.1. Runs on macOS and Windows.

> ### ⚠ Release status: NOT YET SHIPPABLE — the artifact must be re-exported
>
> The `.exe` and `.app` currently sitting in `great-houses-dist/` were exported at
> **06:47 on 2026-08-09, before the haus-pack refactor landed**. Their embedded
> package still contains the deleted `src/houses/houses.json` and **none** of
> `hauses/index.json` or the nine `haus.json` packs — verified by parsing the
> shipped binary, not inferred. The friend-facing zip
> `for-a-friend/GreatHauses-windows-v0.1.0.zip` wraps that same stale binary.
>
> **A player running it today would get the previous game.** Re-export before
> sending anything to anyone:
>
> ```bash
> ./tools/build/build.sh          # both presets + all gates
> cd ../great-houses-dist/for-a-friend
> cp ../windows/GreatHauses.exe .
> zip -9 -X GreatHauses-windows-v0.1.0.zip GreatHauses.exe README.txt && rm GreatHauses.exe
> ```
>
> The freshness gate now reports this correctly, including the `hauses/` tree it was
> previously blind to. Everything else in this document describes the source tree,
> which is complete.

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

**Six opponents, plus a human.**

| Opponent | What it is |
|---|---|
| Engine — Casual / Seasoned / Master | The built-in chess AI at three strengths. Always available. |
| Pure Oracle | A local LLM plays on its own judgement. |
| Counseled Oracle | The LLM proposes; **Stockfish reviews at depth 12**. If the proposal drops ≥150 centipawns against best, the LLM is sent back to reconsider (twice). Exhausted counsel plays Stockfish's *third*-ranked move — the quiet save. |
| Oracle + Grand Maester | Stockfish builds four candidate lines (MultiPV 4, depth 14) and the LLM **chooses among them** and says why. |
| Play a Friend | Head-to-head over the network. |

**Undo.** HUD button and Cmd/Ctrl+Z. Three per game in tournament play.

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

Same Wi-Fi works with no configuration at all. Across the internet, the sane path is
Tailscale on both machines and the `100.x.y.z` address — no port forwarding, no router
changes. **See the caveat about the ACL line below: on this tailnet that is not
zero-configuration.** Port-forwarding UDP 7777 is the fallback.

---

## Write your own haus

The full guide is [`docs/HAUS-PACK.md`](docs/HAUS-PACK.md); `hauses/_template/` is a
commented starting point and `hauses/_examples/ravenmark/` is a complete worked
example, including a ~200-line GDScript that builds a helm and a crest if you have no
modelling tool.

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

- **Your horse is a horse.** `coat` must be a colour horses come in. Haus identity is
  worn on the caparison, not grown on the animal.
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

## Honest caveats

Ordered by how likely they are to bite you.

1. **The Windows `.exe` has never been executed on Windows. Not once, by anybody.**
   It is built and verified on a Mac. What is actually proven: it is a valid PE32+
   GUI x86-64 binary, and its embedded package was parsed file-by-file to confirm it
   contains the haus packs, the branding, the music and the multiplayer code and none
   of the test harness. Everything from the window opening onward — graphics, sound,
   input, the game — is unobserved on Windows.

2. **Tailnet play needs an ACL line that the tailnet owner must add.** This is not
   optional and it is not discoverable from inside the game. `tailnet/acl.hujson` is
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

3. **The Hall of Banners still says "Nine banners. One throne."** — a hardcoded
   subtitle in `src/ui/house_select.gd:474`. Install a tenth haus and it hangs under
   a caption that says nine. Cosmetic; one line.

4. **`tests/test_banter.gd` asserts a roster of exactly nine.** Install a pack into
   your real `user://hauses/` and that suite goes red for a *roster* reason rather than
   a real one.

5. **The example pack's helm is unproven on screen.** `hauses/_examples/ravenmark/`
   ships a generated `pawn_helm.glb` whose winding was measured and corrected after a
   proof screenshot showed bare skulls — but the proof was never re-rendered. The mesh
   measures in-family with the shipped helms; "it renders" is inference, not evidence.
   Affects the example pack's own art only, nothing in the format or the loader.

6. **Match load stalls ~180 ms warm, ~550 ms cold.** Located and measured, not fixed —
   the dominant cost sits behind a beat this work did not own. (The earlier
   "120–152 ms" figure was an instrument artifact: the frame clock was reset by a
   coroutine before the sampler saw the frame carrying the scene swap.)

7. **Two opponents degrade rather than appear.** The Stockfish-backed modes grey out
   with a reason when no `stockfish` binary is found — put one next to the executable
   to wake them. The Oracle modes need a local LLM server that only exists on the
   author's machine. Both were tested to degrade politely; neither should ever hang.

8. **Performance numbers from this machine are contended.** A second Godot instance on
   the same GPU costs this game most of its frame budget, and two separate audits
   mistook that contention for a defect in the game. Absolute frame timings taken here
   are not comparable to a quiet machine; the deterministic counters (draw calls,
   primitives) are unaffected.

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
