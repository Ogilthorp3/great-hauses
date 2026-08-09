# Building Great Houses

How to turn this repo into something a friend can double-click — on Windows or macOS.

```bash
./tools/build/build.sh            # windows + macos, both verified
./tools/build/build.sh windows    # just the .exe
./tools/build/build.sh degrade    # just the platform-degradation suite
```

Artifacts land in `../great-houses-dist/` (a sibling of the repo, deliberately **outside**
`res://` — a build dropped inside the project gets swept into the *next* export).

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

**One file: `GreatHouses.exe`.** Nothing else — no `.pck`, no runtime, no installer.

The Windows preset sets `binary_format/embed_pck=true`, so the ~43 MiB game archive is
appended inside the executable (~147 MiB total). This is a deliberate trade:

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
    ../great-houses-dist/windows/GreatHouses.exe
echo "export rc=$?"

# macOS
"$GODOT" --headless --path . --export-release "macOS" \
    ../great-houses-dist/macos/GreatHouses.app
```

`--export-release` returns **0** on success. It also returns 0 in some partial-failure
cases, which is why the build script verifies the artifact afterwards rather than
trusting the exit code alone.

### Verifying a build

```bash
file ../great-houses-dist/windows/GreatHouses.exe
# -> PE32+ executable (GUI) x86-64 ..., for MS Windows

python3 tools/build/pck_list.py ../great-houses-dist/windows/GreatHouses.exe \
    --count-only --assert-present src/houses/houses.json \
                 --assert-absent  test_e2e/artifacts
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
exclude_filter="test_e2e/artifacts/*,tests/*,tools/*,*.md,*.py,*.sh"
```

Each clause is load-bearing. All four of these were found by building and inspecting,
not by reading docs:

**Trap 1 — the `.json` files are invisible to `all_resources`.**
`houses.json`, `banter_lines.json` and `kill_lines.json` are read with
`FileAccess.open()`, not `load()`, and have no `.import` sidecar, so Godot does not
consider them resources. Without `*.json` in `include_filter` they are **silently
omitted** and the shipped game has no houses at all. Verified by asserting them
present in the pck on every build.

**Trap 2 — you cannot exclude `test_e2e/` wholesale.**
`project.godot` autoloads the E2E driver:

```ini
[autoload]
E2EDriver="*res://test_e2e/e2e_driver.gd"
```

Excluding `test_e2e/*` exports and *appears* to work — the game still exits 0 — but the
shipped build prints at boot:

```
ERROR: Attempt to open script 'res://test_e2e/e2e_driver.gd' ... 'File not found'.
ERROR: Failed to instantiate an autoload, can't load from path: ...
```

So the filter excludes only `test_e2e/artifacts/*` (1.9 GB of test screenshots, which
would otherwise be swept in as textures). The driver script itself (~124 KB) ships.
**The real fix is to drop the autoload from `project.godot` for release builds, or move
the driver out of `test_e2e/`** — both belong to whoever owns the test harness, so this
build only documents the wart and guards it: `build.sh` boots the exported macOS app and
fails on `Failed to instantiate an autoload`.

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
`Invalid icon path.` — not a warning. The preset therefore ships `application/icon=""`.
When `assets/branding/icon.ico` lands, change that one line to:

```ini
application/icon="res://assets/branding/icon.ico"
```

…and note it *still* won't be embedded until **rcedit** is configured
(*Editor Settings → Export → Windows → rcedit*). Without rcedit, Godot prints an
informational message and exports fine, but the `.exe` keeps the default Godot icon and
no version metadata. `build.sh` tells you when the icon file appears but the preset
hasn't been pointed at it. Icon and version metadata are **not currently embedded**.

---

## 5. The Grand Maester (Stockfish)

The Maester mode shells out to a UCI engine. The lookup in `src/ai/uci_engine.gd` is
platform-aware and tries, in order:

1. `$GREAT_HOUSES_STOCKFISH` — explicit override (used by the degradation suite)
2. **beside the executable** — `stockfish.exe` next to `GreatHouses.exe`, or in a
   `stockfish/` subfolder
3. `PATH` — scanned directly (no `which` subprocess; `/usr/bin/which` doesn't exist on
   Windows)
4. `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` — Unix only, because a
   double-clicked `.app` inherits a PATH with no Homebrew in it

**For the friend on Windows:** download a Stockfish Windows build from
<https://stockfishchess.org/download/>, rename it `stockfish.exe`, and drop it in the
same folder as `GreatHouses.exe`. That's the whole install.

**If it's absent,** nothing breaks: the Hall of Banners greys out the Grand Maester entry
with *"the Grand Maester is abroad (stockfish not installed)"* and the other opponents
play normally. `UciEngine.install_hint()` returns the per-platform one-liner
("put stockfish.exe next to GreatHouses.exe") if you want to surface it in that message.

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
| Override | `GreatHouses.exe -- --net-port=7800` |
| Protocol version | 1 — mismatched builds refuse to play rather than desync |

**Only the player who HOSTS needs a firewall rule.** The one who joins makes an outbound
connection and needs nothing.

On the first host attempt Windows pops *"Allow GreatHouses to communicate on these
networks"* — tick **Private networks** and accept. That is usually the entire setup. To
pre-create the rule instead (elevated PowerShell):

```powershell
New-NetFirewallRule -DisplayName "Great Houses (host)" -Direction Inbound `
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

- **The `.exe` has never been executed.** There is no Windows machine here and **Wine is
  not installed** (it was not installed, to avoid a large unrequested toolchain). What is
  proven: `--export-release` exits 0, `file` reports *PE32+ executable (GUI) x86-64*, the
  size is sane (147 MiB), and the embedded PCK index contains the expected 302 files and
  none of the excluded ones. Everything past process start — rendering, input, audio,
  actual gameplay — is **unverified on Windows**.
- **The multiplayer path has not been exercised across two machines**, and no firewall
  rule has been tested on real Windows. The port number is read from the netcode source,
  not observed on the wire.
- **Windows Stockfish has not been run.** The lookup order is unit-tested on macOS
  (including the `stockfish.exe` filename and the beside-the-executable directories), but
  no `stockfish.exe` has actually been spawned. Note that `OS.execute_with_pipe` may flash
  a console window on Windows when it spawns the engine — unconfirmed either way.
- **Icon and version metadata are absent** from the `.exe` (no rcedit, no icon file yet).
- The macOS `.app` is ad-hoc signed only — **not** notarized, so other Macs will need
  right-click → Open.
