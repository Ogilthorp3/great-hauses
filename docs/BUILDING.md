# Building Great Hauses

How to turn this repo into something a friend can double-click — on Windows or macOS.

## The rebuild command

**This is the one to run. Nothing else is a release build.**

```bash
cd /Users/bert/Projects/godot-lab/great-houses-chess
./tools/build/build.sh all
```

That single command does, in order, and stops at the first failure:

| Step | What it proves |
|---|---|
| toolchain check | editor version == export-template version |
| concurrent-e2e guard | no test suite is racing the export (see Trap 3) |
| `--import` | **exit code checked** — a failed import ships missing meshes |
| Windows export | exit code checked, then `file` == PE32+ GUI x86-64, size sane |
| pck assertions | the three `FileAccess` `.json` files are IN, `test_e2e/` is OUT |
| **freshness gate** | **no exported source is newer than the artifact** |
| macOS export | same, plus a headless boot that catches a dropped autoload |
| degradation suite | Maester + Oracle grey out instead of crashing or hanging |

Sub-targets when you don't need all of it:

```bash
./tools/build/build.sh windows      # just the .exe (+ its verification)
./tools/build/build.sh macos        # just the .app
./tools/build/build.sh degrade      # just the platform-degradation suite
./tools/build/build.sh freshness    # is the shipped .exe older than src/? (no Godot needed)
```

Artifacts land in `../great-houses-dist/` (a sibling of the repo, deliberately **outside**
`res://` — a build dropped inside the project gets swept into the *next* export).

### The staleness gate — why `freshness` exists

**Scar, 2026-08-09.** A `GreatHauses.exe` sat in `great-houses-dist/` with **seven source
files newer than it**, including the entire branding set. Every check we had was green:
`file` said PE32+, the size was right, the pck index held all the expected paths. The
artifact was simply a *photograph of an older tree*, and it was one step from being sent
to a friend — who would have run a build with no heraldry in it.

An export is a photograph. `verify_freshness` asserts the shutter fired **after** the last
edit to anything the photograph should contain, and it now runs automatically at the end
of both exports. It compares `src/`, `scenes/`, `assets/`, `hauses/`, `project.godot` and
`export_presets.cfg` against the artifact's mtime, skipping `*.md`/`*.py`/`*.sh` and the
`hauses/_template/` + `hauses/_examples/` subtrees because those mirror `exclude_filter`
and are never shipped.

> **Second catch, same day.** `hauses/` was **not** in that root list when a Great Haus
> became a folder — so the entire nine-haus roster, twenty files of shipped game content,
> could change without the gate noticing. A gate that watches four of the five directories
> it ships is a gate that says GREEN over a stale artifact. Whenever a new *top-level*
> directory starts shipping, it must be added to `verify_freshness` in the same commit.

On failure it names the offending files and exits 1:

```
[build] FAIL: STALE ARTIFACT — these exported sources are NEWER than the artifact:
         src/net/net_protocol.gd
         src/board/piece_view.gd
       The export ran BEFORE these edits. Re-run it; do not ship this.
```

To check an artifact you did **not** just build (e.g. one already zipped and about to be
sent):

```bash
./tools/build/build.sh freshness --artifact ../great-houses-dist/windows/GreatHauses.exe
```

### Packaging for the friend

```bash
cd ../great-houses-dist/for-a-friend
cp ../windows/GreatHauses.exe .
zip -9 -X GreatHauses-windows-v0.1.0.zip GreatHauses.exe README.txt
rm GreatHauses.exe          # keep only the zip under version-of-record
```

`README.txt` next to the zip is the friend-facing copy: how to run it, the two dialogs
Windows shows and what to click, UDP 7777, how to join a host, why the Grand Maester and
the DS4-Oracle are greyed out, and the disclosure that the binary has never been run on
Windows. Re-zip whenever the `.exe` is rebuilt — the zip does **not** update itself, and
`build.sh freshness` does not police it.

---

## 1. Prerequisites

| Thing | Version | Notes |
|---|---|---|
| Godot | **4.7.1.stable** | `/Applications/Godot.app/Contents/MacOS/Godot` |
| Export templates | **4.7.1.stable** | must match the editor *exactly* — see below |
| Python 3 | any 3.x | only for `tools/build/pck_list.py` (stdlib only) |

### Installing the export templates

Without templates you get `Cannot export project ... no export template found`, which is
not obviously a "you forgot to download 1.3 GB" message. The editor can fetch them
(*Editor → Manage Export Templates → Download and Install*), or do it by hand:

```bash
curl -L -o templates.tpz \
  https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz
unzip -q templates.tpz -d /tmp/godot-tpl
mkdir -p "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable"
cp -R /tmp/godot-tpl/templates/. \
  "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable/"
```

**The version string must match exactly.** Godot looks for a directory named after the
first four dot-fields of its own version:

```
editor:  4.7.1.stable.official.a13da4feb
                └───┬───┘
directory:      4.7.1.stable            <- and templates/version.txt must say the same
```

A `4.7.2` editor will not use `4.7.1` templates and the error it prints will send you
looking in the wrong place. `build.sh` checks this for you and says so in one line.

---

## 2. What the friend actually needs

**One file: `GreatHauses.exe`.** Nothing else — no `.pck`, no runtime, no installer.

What actually gets *sent* is
`../great-houses-dist/for-a-friend/GreatHauses-windows-v0.1.0.zip` (~78 MiB): that one
`.exe` plus a `README.txt`. The zip exists only because the `.exe` compresses ~47% and
because a bare unsigned `.exe` arriving by itself is the most alarming thing you can put
in someone's downloads folder.

The Windows preset sets `binary_format/embed_pck=true`, so the ~45 MiB game archive is
appended inside the executable (~149 MiB total). This is a deliberate trade:

- **Embedded (what we ship):** impossible for the friend to separate the game from its
  data, or to unzip only half of it. One file, one double-click.
- **Paired (`.exe` + `.pck`):** ~8 MiB smaller to re-send after a code-only change, and
  the `.pck` can be patched independently. Switch by setting
  `binary_format/embed_pck=false` in `export_presets.cfg`; then you must send **both**
  files, side by side, and the `.pck` must keep the `.exe`'s basename.

Two things to warn them about:

1. **SmartScreen.** The binary is unsigned, so Windows shows
   *"Windows protected your PC"* → **More info** → **Run anyway**. Signing needs a
   real code-signing certificate (`codesign/enable` in the preset); we don't have one.
2. **The window is 1920×1080** by default and stretches; it is not a tiny window.

---

## 3. Building by hand

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
cd <repo root>

# ALWAYS import first, and ALWAYS check the exit code — a failed import
# produces an export that silently ships missing meshes.
"$GODOT" --headless --path . --import
echo "import rc=$?"

# Windows
"$GODOT" --headless --path . --export-release "Windows Desktop" \
    ../great-houses-dist/windows/GreatHauses.exe
echo "export rc=$?"

# macOS
"$GODOT" --headless --path . --export-release "macOS" \
    ../great-houses-dist/macos/GreatHauses.app
```

`--export-release` returns **0** on success. It also returns 0 in some partial-failure
cases, which is why the build script verifies the artifact afterwards rather than
trusting the exit code alone.

**Exporting by hand skips the freshness gate.** If you run the raw commands above, run
`./tools/build/build.sh freshness` afterwards, or you can produce exactly the stale
artifact that scar at the top of this file is about.

### Verifying a build

```bash
file ../great-houses-dist/windows/GreatHauses.exe
# -> PE32+ executable (GUI) x86-64 ..., for MS Windows

python3 tools/build/pck_list.py ../great-houses-dist/windows/GreatHauses.exe \
    --count-only --assert-present hauses/index.json \
                 --assert-present hauses/winterfang/haus.json \
                 --assert-present src/houses/coats.json \
                 --assert-absent  test_e2e/artifacts \
                 --assert-absent  hauses/_examples/
```

`pck_list.py` parses the real Godot PCK index out of the shipped artifact (standalone
`.pck`, embedded-in-`.exe`, or inside a `.app` bundle). It is the difference between
"the export said OK" and "the file the friend runs contains what we think it does".

---

## 4. How the export is configured — and four traps

Both presets share these filters:

```ini
export_filter="all_resources"
include_filter="*.json,*.txt,*LICENSE*"
exclude_filter="test_e2e/*,tests/*,tools/*,hauses/_template/*,hauses/_examples/*,*.md,*.py,*.sh,assets/branding/*.ico,assets/branding/*.icns"
```

> `test_e2e/*` (not just `test_e2e/artifacts/*`) since 2026-08-09: the E2E harness used to
> be an autoload in `project.godot`, so a ~90 KB `.gdc` of *test code* shipped inside the
> player's pck. It is registered at runtime now (`src/main.gd::_install_e2e_harness`), only
> for an `--e2e` launch, and the whole directory is excluded from every export.
> The `.ico`/`.icns` clauses drop the *source* icon files: both are embedded into the
> binary by the exporter, so shipping them again inside the pck is pure dead weight.

Each clause is load-bearing. All four of these were found by building and inspecting,
not by reading docs:

**Trap 1 — the `.json` files are invisible to `all_resources`.**
`hauses/index.json`, each pack's `hauses/<id>/haus.json`, `src/houses/coats.json`,
`banter_lines.json` and `kill_lines.json` are read with
`FileAccess.open()`, not `load()`, and have no `.import` sidecar, so Godot does not
consider them resources. Without `*.json` in `include_filter` they are **silently
omitted** and the shipped game has no hauses at all. Verified by asserting them
present in the pck on every build.

> This trap got *wider* on 2026-08-09, when a Great Haus became a folder. The roster
> used to be one file (`src/houses/houses.json`, now deleted); it is now
> `hauses/index.json` plus one `haus.json` per pack, discovered at runtime. Ten
> FileAccess-read files where there was one — all riding on the same `*.json` clause.

**Trap 2 — `test_e2e/` used to be un-excludable (FIXED 2026-08-09).**
`project.godot` autoloaded the E2E driver:

```ini
[autoload]
E2EDriver="*res://test_e2e/e2e_driver.gd"
```

so excluding `test_e2e/*` exported and *appeared* to work — the game still exited 0 —
but the shipped build printed at boot:

```
ERROR: Attempt to open script 'res://test_e2e/e2e_driver.gd' ... 'File not found'.
ERROR: Failed to instantiate an autoload, can't load from path: ...
```

The filter therefore excluded only `test_e2e/artifacts/*`, and the driver script itself
(~90 KB compiled) shipped inside the player's pck.

**Resolved:** the autoload is gone. `src/main.gd::_install_e2e_harness` registers the
driver at runtime instead, under two conditions a release build can never both meet — a
`--e2e…` flag on the command line, AND the file existing in this build — so
`exclude_filter` now drops `test_e2e/*` wholesale and a release boot has no autoload to
fail on. `build.sh` still boots the exported macOS app and fails on `Failed to
instantiate an autoload`, and the pck assertions now require `test_e2e/` to be **absent**
rather than present.

**Trap 3 — the macOS build forces a project setting.**
The official template archive ships **only** a universal macOS binary (no x86_64-only or
arm64-only variant), and Godot refuses a universal/arm64 export unless ETC2 ASTC import
is on. That is why `project.godot` carries:

```ini
[rendering]
textures/vram_compression/import_etc2_astc=true
```

Removing it breaks the Mac build with
*"Cannot export for universal or arm64 if ETC2 ASTC texture format is disabled."*
It costs an extra ASTC variant per texture at import time; the Windows preset sets
`texture_format/etc2_astc=false`, so none of that reaches the `.exe`.

**Trap 4 — the icon must exist or the export dies.**
`application/icon` pointing at a missing file fails the whole export with
`Invalid icon path.` — a hard error, not a warning. So the preset can only name an icon
that is actually on disk; while the branding assets were still in flight this shipped as
`application/icon=""`, and it must go back to `""` if the files are ever renamed.

Both are now wired to the branding agent's assets:

```ini
[preset.0.options]  application/icon="res://assets/branding/GreatHauses.ico"    # Windows
[preset.1.options]  application/icon="res://assets/branding/GreatHauses.icns"   # macOS
```

Contrary to a lot of older advice, **rcedit is not required.** Godot 4.7 stamps the
Windows icon and version metadata into the PE itself. Verified by diffing the exported
`.exe` against the stock template: the `.ico`'s bytes and the UTF-16 string
`Great Hauses` are present in the exported PE image and absent from the template
(which carries `Godot Engine` instead). The macOS `.icns` is copied to
`Contents/Resources/icon.icns` byte-for-byte — SHA-256 verified against the source.

The `.ico`/`.icns` are *packaging inputs*, not runtime assets, so `exclude_filter` keeps
them out of the pck (they are read from disk at export time). That saves ~1.8 MiB in
every shipped build.

**Trap 5 — never export while the e2e suite is running.**
`test_e2e/artifacts/` lives inside `res://`, and `run_scenario` does `rm -rf` on a
scenario's directory before refilling it. Godot applies `exclude_filter` by **walking the
live filesystem**, so a directory being deleted out from under that walk can escape the
filter entirely. A build run during a suite shipped three banter screenshots into the
pck — one of them 0 bytes, caught mid-write — even though `test_e2e/artifacts/*` is in
`exclude_filter` and the other several thousand screenshots were correctly excluded.

`build.sh` refuses to export when it sees a live `--e2e=` scenario process or writes
under `test_e2e/artifacts/` in the last 20 seconds (`ALLOW_CONCURRENT_E2E=1` overrides).
The pck assertions are the backstop that caught it in the first place. The permanent fix
is to move the artifacts directory outside `res://`, which belongs to whoever owns
`run_e2e.sh`.

---

## 5. The Grand Maester (Stockfish)

The Maester mode shells out to a UCI engine. The lookup in `src/ai/uci_engine.gd` is
platform-aware and tries, in order:

1. `$GREAT_HOUSES_STOCKFISH` — explicit override (used by the degradation suite)
2. **beside the executable** — `stockfish.exe` next to `GreatHauses.exe`, or in a
   `stockfish/` subfolder
3. `PATH` — scanned directly (no `which` subprocess; `/usr/bin/which` doesn't exist on
   Windows)
4. `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` — Unix only, because a
   double-clicked `.app` inherits a PATH with no Homebrew in it

**For the friend on Windows:** download a Stockfish Windows build from
<https://stockfishchess.org/download/>, rename it `stockfish.exe`, and drop it in the
same folder as `GreatHauses.exe`. That's the whole install.

**If it's absent,** nothing breaks: the Hall of Banners greys out the Grand Maester entry
with *"the Grand Maester is abroad (stockfish not installed)"* and the other opponents
play normally. `UciEngine.install_hint()` returns the per-platform one-liner
("put stockfish.exe next to GreatHauses.exe") if you want to surface it in that message.

---

## 6. The DS4-Oracle on someone else's PC

The Oracle is an LLM served on Bert's MBP over an SSH tunnel
(`http://127.0.0.1:18000`). On the friend's machine nothing is listening there, so the
Hall greys the entry out with *"the Oracle sleeps (tunnel down?)"*. This is expected and
requires no configuration.

The failure that mattered was **hanging**, not greying out: a refused connection returns
in milliseconds, but a black-holed address returns nothing at all. Both paths are
covered by `tools/build/test_platform_degradation.gd`, which points the Oracle at a
refused port and at an unroutable TEST-NET address and asserts it honours its timeout
and still hands back a legal fallback move instead of freezing the game.

Point it somewhere else with `DS4_CHESS_URL=http://host:port`.

---

## 7. Multiplayer through the Windows Firewall

From `src/net/net_protocol.gd` (the netcode agent's choice):

| | |
|---|---|
| Transport | `ENetMultiplayerPeer` — **UDP** |
| Default port | **7777** (`NetProtocol.DEFAULT_PORT`) |
| Override | `GreatHauses.exe -- --net-port=7800` |
| Protocol version | 1 — mismatched builds refuse to play rather than desync |

**Only the player who HOSTS needs a firewall rule.** The one who joins makes an outbound
connection and needs nothing.

On the first host attempt Windows pops *"Allow GreatHauses to communicate on these
networks"* — tick **Private networks** and accept. That is usually the entire setup. To
pre-create the rule instead (elevated PowerShell):

```powershell
New-NetFirewallRule -DisplayName "Great Hauses (host)" -Direction Inbound `
  -Protocol UDP -LocalPort 7777 -Action Allow -Profile Private
```

Reaching each other:

- **Same Wi-Fi** — the host reads their LAN address off the Hall's network panel and
  sends it; no router configuration needed.
<!-- ip-allow: RFC 6598 CGNAT range — the shared address SPACE Tailscale allocates from, quoted here so a reader can recognise which of their addresses is the tailnet one. Not an endpoint, nothing resolves it. -->
- **Over the internet** — the host is on a tailnet, so the `100.64.0.0/10` address the
  panel lists works from anywhere with **no port forwarding and no firewall change**.
  Prefer this.
- **Port forwarding** is the last resort: forward UDP 7777 to the host machine.

The code comment says "TCP/UDP"; ENet is UDP-only, so a UDP rule is what matters. If a
connection still fails after allowing UDP, allowing TCP 7777 too costs nothing.

---

## 8. What has *not* been verified

Honest list, because "it builds" is not "it runs":

- **The `.exe` has never been executed — not once, on any Windows machine.** There is no
  Windows box here and **Wine is not installed** (deliberately, to avoid a large
  unrequested toolchain). What *is* proven, as of the 2026-08-09 06:47 build
  (sha256 `9845d36f…b567a`, 156,653,304 bytes): `--export-release` exits 0, `file` reports
  *PE32+ executable (GUI) x86-64*, the embedded PCK index holds **320 files** — including
  the three `FileAccess`-read `.json` files, all eight branding textures as imported
  `.ctex`, and all four `src/net/*.gdc` — and **zero** `test_e2e/` paths. Everything past
  process start — the window opening, rendering, input, audio, actual gameplay — is
  **unverified on Windows**.
- **The build is not byte-reproducible.** Two exports of the same commit, minutes apart,
  produced different sha256 sums (measured 2026-08-09 — PE headers carry a timestamp).
  That hash therefore identifies *the artifact that was zipped and sent*, and is worth
  checking against the zip's contents; it is **not** a claim that rebuilding reproduces
  it. Use `build.sh freshness` to answer "is this artifact current?", never a hash diff.
- **The netcode hardening is verified on macOS only.** The P1 request-clock, the
  `hello_admission` / `seat_admission` RPC gates and the six UX fixes are covered by the
  macOS suites and are present in the shipped pck as bytecode; none of them has executed
  on Windows.
- **The multiplayer path has not been exercised across two machines**, and no firewall
  rule has been tested on real Windows. The port number is read from the netcode source,
  not observed on the wire.
- **Windows Stockfish has not been run.** The lookup order is unit-tested on macOS
  (including the `stockfish.exe` filename and the beside-the-executable directories), but
  no `stockfish.exe` has actually been spawned. Note that `OS.execute_with_pipe` may flash
  a console window on Windows when it spawns the engine — unconfirmed either way.
- **The icon has been proven present in the PE image, not proven to render.** The `.ico`
  bytes and the version string are in the exported binary (see Trap 4), but nobody has
  seen Explorer or the taskbar draw it.
- The macOS `.app` is ad-hoc signed only — **not** notarized, so other Macs will need
  right-click → Open.
