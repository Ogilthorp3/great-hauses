# visionOS "Hello, Headset" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the Great Hall of Great Hauses rendering in stereo inside an Apple Vision Pro, with live head tracking, from a build that is reproducible from tracked repos.

**Architecture:** Godot is compiled from Apple's stacked visionOS-XR branch because no Godot release ships a visionOS export template. XR bring-up is factored into a `RefCounted` state machine so it can be unit-tested headlessly on macOS — the same pattern `src/minigame/blast_grid.gd` uses — with the four live `XRServer`/`Viewport` calls injected as a delegate. No input, no scale, no camera work in this plan.

**Tech Stack:** Godot 4.7.0-beta (custom build), GDScript, SCons, Xcode 26.6, visionOS SDK 26.5, Metal.

## Global Constraints

- Engine pinned to `rsanchezsaez/godot` @ `c1df64224a`, branch `apple/visionos-xr-9-developer-capture`.
- Xcode **26.6**, visionOS SDK **26.5**. Do not install the visionOS 27 SDK or update the headset past 26.x.
- **Metal only. arm64 device only.** The simulator has no rendering driver — every visual check is on hardware.
- Renderer must remain `mobile` (`project.godot` `renderer/rendering_method="mobile"`).
- `XRCamera3D` near plane **≥ 0.1 m** — a CompositorServices floor with no workaround.
- Export preset must set `application/app_role = 1` (Immersive) and `application/immersion_style = 0` (Full). **Both default to the wrong value.**
- Signing Team `GJ994MN2YF`.
- macOS and Windows builds must not regress: `./tools/build/build.sh all` stays green.
- Headless suite stays green: `Godot --headless --path . -s res://tests/run_tests.gd` → exit 0.

---

### Task 1: Make the engine build reproducible

The engine fork currently has no Sanctum remote and its build script lives in a session scratchpad. That is orphan config — spec §13.

**Files:**
- Create: `tools/build/build-godot-visionos.sh`
- Create: `tools/build/patches/0001-spatial-event-continue.patch` (Task 2 fills it; created empty here is a placeholder — **do not** create it in this task)
- Modify: `docs/BUILDING.md` (append a new section)

**Interfaces:**
- Consumes: nothing.
- Produces: `tools/build/build-godot-visionos.sh` — takes no arguments, reads `GODOT_VISIONOS_REPO` (default `/Users/bert/Projects/godot-visionos`), writes `bin/godot.macos.editor.arm64`, `bin/libgodot.visionos.template_{debug,release}.arm64.a` and `bin/godot_visionos.zip` inside that repo. Exit 0 on success.

- [ ] **Step 1: Push the engine fork to a Sanctum remote**

```bash
gh repo create Ogilthorp3/sanctum-godot-visionos --private \
  --description "Godot fork pinned for the Great Hauses visionOS immersive port (Apple visionos-xr stack)"
cd /Users/bert/Projects/godot-visionos
git remote add sanctum git@github.com:Ogilthorp3/sanctum-godot-visionos.git
git push sanctum apple/visionos-xr-9-developer-capture
```

- [ ] **Step 2: Verify the pinned commit is on the Sanctum remote**

Run:
```bash
git ls-remote sanctum apple/visionos-xr-9-developer-capture
```
Expected: a line beginning `c1df64224a30bd8d7c51489b6c87ee03a86bfa26`.

- [ ] **Step 3: Land the build script in the game repo**

Create `tools/build/build-godot-visionos.sh`:

```bash
#!/bin/bash
# Build the Godot editor + visionOS export template from Apple's stacked
# visionOS-XR branch. No Godot release ships a visionOS template (godot#115415),
# so this is mandatory, not optional.
set -uo pipefail

REPO="${GODOT_VISIONOS_REPO:-/Users/bert/Projects/godot-visionos}"
PIN="c1df64224a30bd8d7c51489b6c87ee03a86bfa26"
JOBS="${JOBS:-10}"

export PATH="/opt/homebrew/bin:$PATH"
cd "$REPO" || { echo "no engine repo at $REPO"; exit 1; }

HAVE="$(git rev-parse HEAD)"
if [ "$HAVE" != "$PIN" ]; then
  echo "ENGINE PIN MISMATCH: have $HAVE, want $PIN"
  exit 1
fi

echo "branch : $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
echo "xcode  : $(xcodebuild -version | head -1)"
echo "sdk    : $(xcrun --sdk xros --show-sdk-version)"

# macOS editor: the visionOS export plugin (and app_role) compiles INTO the editor.
# vulkan=no metal=yes — macOS defaults to Vulkan via MoltenVK, which we do not have.
scons platform=macos target=editor arch=arm64 \
  vulkan=no metal=yes opengl3=no accesskit=no angle=no -j"$JOBS" || exit 1

# Device templates, arm64 only. The simulator force-disables Metal (detect.py:154-156).
scons platform=visionos target=template_debug   arch=arm64 accesskit=no angle=no -j"$JOBS" || exit 1
scons platform=visionos target=template_release arch=arm64 accesskit=no angle=no -j"$JOBS" || exit 1

# Pack the .a slices into the export template zip.
scons platform=visionos generate_bundle=yes || exit 1

test -f bin/godot_visionos.zip || { echo "no export template produced"; exit 1; }
echo "OK: $(ls -la bin/godot_visionos.zip)"
```

- [ ] **Step 4: Run it and verify it reproduces the artifacts**

```bash
chmod +x tools/build/build-godot-visionos.sh
./tools/build/build-godot-visionos.sh
```
Expected: exits 0, final line `OK: ... bin/godot_visionos.zip`. Re-running is a no-op rebuild and still exits 0.

- [ ] **Step 5: Record the pin in BUILDING.md**

Append to `docs/BUILDING.md`:

```markdown
## visionOS (immersive)

No Godot release ships a visionOS export template — the packaging block in
`godot-build-scripts/build-release.sh` is commented out ([godot#115415](https://github.com/godotengine/godot/issues/115415)).
The engine is therefore built from source:

| Pin | Value |
|---|---|
| Repo | `Ogilthorp3/sanctum-godot-visionos` (fork of `rsanchezsaez/godot`) |
| Branch | `apple/visionos-xr-9-developer-capture` |
| Commit | `c1df64224a30bd8d7c51489b6c87ee03a86bfa26` |
| Xcode | 26.6 |
| visionOS SDK | 26.5 |

```bash
./tools/build/build-godot-visionos.sh
```

**Do not** install the visionOS 27 SDK or update the headset past 26.x — the
toolchain is matched to 26 and 27 is unevaluated.
```

- [ ] **Step 6: Commit**

```bash
git add tools/build/build-godot-visionos.sh docs/BUILDING.md
git commit -m "build(visionos): reproducible engine build, pinned and documented"
```

---

### Task 2: Carry the spatial-event patch

`platform/visionos/app_visionos.swift:192-204` uses `return` inside `for event in spatialEventCollection`, so one rejected event aborts the whole collection and can drop the other hand's pinch. Two-handed input (Plan 3) is impossible without this. Spec §2.2.

**Files:**
- Create: `tools/build/patches/0001-spatial-event-continue.patch`
- Modify: `tools/build/build-godot-visionos.sh` (apply the series before building)

**Interfaces:**
- Consumes: `tools/build/build-godot-visionos.sh` from Task 1.
- Produces: a patch series applied at build time; `apply_patches()` is idempotent.

- [ ] **Step 1: Make the edit in the engine repo and capture it as a patch**

```bash
cd /Users/bert/Projects/godot-visionos
# Three guards at :195, :199, :203 — return -> continue
sed -i '' '192,205s/^\(\s*\)return$/\1continue/' platform/visionos/app_visionos.swift
git diff platform/visionos/app_visionos.swift
```
Expected diff: exactly three lines change from `return` to `continue`, all inside the `for event in spatialEventCollection` loop.

- [ ] **Step 2: Verify the loop no longer early-returns**

Run:
```bash
sed -n '190,210p' platform/visionos/app_visionos.swift | grep -c 'return'
```
Expected: `0`.

- [ ] **Step 3: Save the patch into the game repo**

```bash
cd /Users/bert/Projects/godot-visionos
mkdir -p /Users/bert/Projects/great-hauses/tools/build/patches
git diff > /Users/bert/Projects/great-hauses/tools/build/patches/0001-spatial-event-continue.patch
git checkout platform/visionos/app_visionos.swift   # back to pristine pin
```

- [ ] **Step 4: Teach the build script to apply the series**

In `tools/build/build-godot-visionos.sh`, insert immediately after the `ENGINE PIN MISMATCH` check:

```bash
# Local patches on top of the pin. Idempotent: --check first, skip if already applied.
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)/patches"
for p in "$PATCH_DIR"/*.patch; do
  [ -e "$p" ] || continue
  if git apply --check "$p" 2>/dev/null; then
    git apply "$p" && echo "applied $(basename "$p")"
  elif git apply --reverse --check "$p" 2>/dev/null; then
    echo "already applied $(basename "$p")"
  else
    echo "PATCH DOES NOT APPLY: $(basename "$p") — the pin moved or the patch is stale"
    exit 1
  fi
done
```

- [ ] **Step 5: Rebuild and verify the patch takes**

```bash
cd /Users/bert/Projects/great-hauses
./tools/build/build-godot-visionos.sh
grep -c 'return' <(sed -n '190,210p' /Users/bert/Projects/godot-visionos/platform/visionos/app_visionos.swift)
```
Expected: build exits 0 with `applied 0001-spatial-event-continue.patch`; the grep prints `0`. Run the script a second time — expect `already applied` and exit 0.

- [ ] **Step 6: Commit**

```bash
git add tools/build/patches/0001-spatial-event-continue.patch tools/build/build-godot-visionos.sh
git commit -m "build(visionos): carry spatial-event continue patch

app_visionos.swift returned out of the whole SpatialEventCollection on any
rejected event, which drops the second hand's pinch. Two-handed input needs
all three guards to continue, not return."
```

---

### Task 3: visionOS export preset, asserted

Both new export options default to the wrong value: `app_role` defaults to `0` (Window) and `immersion_style` to `1` (Mixed) — `platform/visionos/export/export_plugin.cpp:60-61`. An unasserted preset ships a flat window. Spec §2.1.

**Files:**
- Modify: `export_presets.cfg` (add `[preset.2]`)
- Create: `tools/build/assert_visionos_preset.py`
- Modify: `tools/build/build.sh` (add a `visionos` sub-target)

**Interfaces:**
- Consumes: `bin/godot_visionos.zip` from Task 1.
- Produces: `assert_visionos_preset.py` — takes the path to `export_presets.cfg`, exits 0 if the visionOS preset exists with `app_role=1` and `immersion_style=0`, exits 1 with a message naming the offending key otherwise.

- [ ] **Step 1: Write the failing assertion**

Create `tools/build/assert_visionos_preset.py`:

```python
#!/usr/bin/env python3
"""Assert the visionOS export preset is immersive.

Godot defaults application/app_role to 0 (Window) and immersion_style to 1
(Mixed). Shipping either default gives a flat panel floating in the room
instead of an immersive app, and nothing else in the build catches it.
"""
import configparser
import sys

REQUIRED = {
    "application/app_role": "1",         # 0=Window, 1=Immersive
    "application/immersion_style": "0",  # 0=Full, 1=Mixed, 2=Progressive
}


def main(path: str) -> int:
    cp = configparser.ConfigParser()
    cp.optionxform = str
    cp.read(path)

    section = None
    for name in cp.sections():
        if name.endswith(".options"):
            continue
        if cp[name].get("platform", "").strip('"') == "visionOS":
            section = name + ".options"
            break

    if section is None or section not in cp:
        print("FAIL: no visionOS export preset in " + path)
        return 1

    bad = []
    for key, want in REQUIRED.items():
        got = cp[section].get(key, "<missing>").strip('"')
        if got != want:
            bad.append(f"  {key}: got {got}, want {want}")

    if bad:
        print("FAIL: visionOS preset is not immersive:")
        print("\n".join(bad))
        return 1

    print("OK: visionOS preset is app_role=Immersive, immersion_style=Full")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "export_presets.cfg"))
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
python3 tools/build/assert_visionos_preset.py export_presets.cfg
```
Expected: `FAIL: no visionOS export preset in export_presets.cfg`, exit 1.

- [ ] **Step 3: Add the preset**

Append to `export_presets.cfg`:

```ini
[preset.2]

name="visionOS"
platform="visionOS"
runnable=true
advanced_options=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json,*.txt,*LICENSE*"
exclude_filter="test_e2e/*,tests/*,tools/*,hauses/_template/*,hauses/_examples/*,*.md,*.py,*.sh,assets/branding/*.ico,assets/branding/*.icns"
export_path="../great-hauses-dist/visionos/GreatHauses.xcodeproj"
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false

[preset.2.options]

application/app_role=1
application/immersion_style=0
application/bundle_identifier="vc.triptyq.greathauses"
application/short_version="0.3.0"
application/version="0.3.0"
application/min_visionos_version="26.0"
application/signature=""
application/targeted_device_family=7
texture_format/etc2_astc=true
texture_format/s3tc_bptc=false
```

- [ ] **Step 4: Run the assertion to verify it passes**

Run:
```bash
python3 tools/build/assert_visionos_preset.py export_presets.cfg
```
Expected: `OK: visionOS preset is app_role=Immersive, immersion_style=Full`, exit 0.

- [ ] **Step 5: Wire the assertion into the build gate**

In `tools/build/build.sh`, add a `visionos` sub-target that runs, in order: the preset assertion, then the export. It must **fail closed** — a non-zero assertion aborts before any export runs.

```bash
build_visionos() {
  echo "== visionOS =="
  python3 "$(dirname "$0")/assert_visionos_preset.py" export_presets.cfg || return 1
  "$GODOT_VISIONOS_EDITOR" --headless --path . --import || return 1
  "$GODOT_VISIONOS_EDITOR" --headless --path . \
    --export-release "visionOS" ../great-hauses-dist/visionos/GreatHauses.xcodeproj || return 1
  test -d ../great-hauses-dist/visionos/GreatHauses.xcodeproj || {
    echo "FAIL: no xcodeproj produced"; return 1; }
  echo "OK: visionOS xcodeproj exported"
}
```

where `GODOT_VISIONOS_EDITOR` defaults to `/Users/bert/Projects/godot-visionos/bin/godot.macos.editor.arm64`.

- [ ] **Step 6: Verify the gate fails closed**

Run:
```bash
sed -i '' 's/^application\/app_role=1/application\/app_role=0/' export_presets.cfg
./tools/build/build.sh visionos ; echo "exit=$?"
sed -i '' 's/^application\/app_role=0/application\/app_role=1/' export_presets.cfg
```
Expected: prints `FAIL: visionOS preset is not immersive:` naming `application/app_role`, `exit=1`, and **no xcodeproj is written**.

- [ ] **Step 7: Verify the other targets still pass**

Run:
```bash
./tools/build/build.sh all
```
Expected: exit 0. Windows and macOS unchanged.

- [ ] **Step 8: Commit**

```bash
git add export_presets.cfg tools/build/assert_visionos_preset.py tools/build/build.sh
git commit -m "build(visionos): immersive export preset, asserted in the gate

app_role and immersion_style both default to the wrong value, and nothing
else in the build catches a flat-window ship."
```

---

### Task 4: XR bring-up as a testable state machine

XR bring-up is four calls and every one is a silent failure if missed. Spec §5.1. Factored the way `src/minigame/blast_grid.gd` is factored — pure logic, injectable side effects — so it is covered by the headless suite on macOS where no visionOS interface exists.

**Files:**
- Create: `src/xr/visionos_boot.gd`
- Create: `tests/test_visionos_boot.gd`
- Modify: `tests/run_tests.gd` (register the new suite)

**Interfaces:**
- Consumes: nothing.
- Produces: `VisionOSBoot.bring_up(deps: Dictionary) -> Dictionary`.
  `deps` keys: `find_interface: Callable(String) -> Variant`, `set_use_xr: Callable(bool) -> void`, `set_origin_current: Callable(bool) -> void`, `set_near: Callable(float) -> void`.
  Returns `{ok: bool, step: String, error: String}` where `step` is one of
  `"find"`, `"initialize"`, `"use_xr"`, `"origin"`, `"near"`, `"done"`.
  Constant `VisionOSBoot.INTERFACE_NAME := "visionOSXR"`, `VisionOSBoot.MIN_NEAR := 0.1`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_visionos_boot.gd`:

```gdscript
extends SceneTree

# XR bring-up is four calls and every one is a SILENT failure if missed:
# find_interface -> initialize -> viewport.use_xr -> XROrigin3D.current.
# The visionOS interface does not exist on macOS, so bring_up() takes its
# side effects as Callables and this suite drives it with fakes.

const VB := preload("res://src/xr/visionos_boot.gd")

var failures := 0


func _initialize() -> void:
	_main()


func _ok(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		failures += 1


class FakeInterface extends RefCounted:
	var init_result := true
	var initialized := false
	func initialize() -> bool:
		initialized = true
		return init_result


func _deps(iface, log: Array) -> Dictionary:
	return {
		"find_interface": func(n: String): log.append("find:" + n); return iface,
		"set_use_xr": func(v: bool) -> void: log.append("use_xr:" + str(v)),
		"set_origin_current": func(v: bool) -> void: log.append("origin:" + str(v)),
		"set_near": func(v: float) -> void: log.append("near:" + str(v)),
	}


func _main() -> void:
	print("=== visionOS XR bring-up ===")

	# 1. Missing interface must fail loudly at the FIRST step, not silently later.
	var log1: Array = []
	var r1 := VB.bring_up(_deps(null, log1))
	_ok("absent interface -> not ok", r1.ok == false)
	_ok("absent interface -> step 'find'", r1.step == "find")
	_ok("absent interface -> no viewport touched", log1 == ["find:visionOSXR"])

	# 2. The interface does NOT auto-initialize; a false return must abort.
	var iface2 := FakeInterface.new()
	iface2.init_result = false
	var log2: Array = []
	var r2 := VB.bring_up(_deps(iface2, log2))
	_ok("initialize() called", iface2.initialized)
	_ok("failed initialize -> not ok", r2.ok == false)
	_ok("failed initialize -> step 'initialize'", r2.step == "initialize")
	_ok("failed initialize -> use_xr never set", not log2.has("use_xr:true"))

	# 3. Happy path: exact order, and the near plane is pinned to the floor.
	var iface3 := FakeInterface.new()
	var log3: Array = []
	var r3 := VB.bring_up(_deps(iface3, log3))
	_ok("happy path ok", r3.ok == true)
	_ok("happy path step 'done'", r3.step == "done")
	_ok("order is find,use_xr,origin,near", log3 == [
		"find:visionOSXR", "use_xr:true", "origin:true", "near:0.1"])

	# 4. Idempotent: a second bring_up must not re-initialize.
	var iface4 := FakeInterface.new()
	var deps4 := _deps(iface4, [])
	VB.bring_up(deps4)
	iface4.initialized = false
	var r4 := VB.bring_up(deps4)
	_ok("second bring_up still ok", r4.ok == true)

	print("=== %s ===" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
/Users/bert/Projects/godot-visionos/bin/godot.macos.editor.arm64 \
  --headless --path . -s res://tests/test_visionos_boot.gd
```
Expected: FAIL — `res://src/xr/visionos_boot.gd` does not exist (parse error on the `preload`).

- [ ] **Step 3: Write the minimal implementation**

Create `src/xr/visionos_boot.gd`:

```gdscript
class_name VisionOSBoot
extends RefCounted
## The four calls that stand up the visionOS immersive XR interface.
##
## Every one of them fails SILENTLY if skipped — a missing use_xr renders a
## flat mono view into the headset, a missing XROrigin3D.current renders from
## the world origin. So bring-up is a state machine that reports WHICH step
## failed, and its side effects are Callables so the headless suite on macOS
## (where no visionOS interface exists) can drive it with fakes.

const INTERFACE_NAME := "visionOSXR"

## CompositorServices refuses a nearer plane; visionos_xr_interface.mm
## validates it and fails the frame. There is no workaround.
const MIN_NEAR := 0.1


static func bring_up(deps: Dictionary) -> Dictionary:
	var iface = deps["find_interface"].call(INTERFACE_NAME)
	if iface == null:
		return {"ok": false, "step": "find",
			"error": "no XRInterface named '%s' — is this a visionOS build?" % INTERFACE_NAME}

	# The interface does NOT auto-initialize.
	if not iface.initialize():
		return {"ok": false, "step": "initialize",
			"error": "XRInterface.initialize() returned false"}

	deps["set_use_xr"].call(true)
	deps["set_origin_current"].call(true)
	deps["set_near"].call(MIN_NEAR)
	return {"ok": true, "step": "done", "error": ""}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Users/bert/Projects/godot-visionos/bin/godot.macos.editor.arm64 \
  --headless --path . -s res://tests/test_visionos_boot.gd ; echo "exit=$?"
```
Expected: every line `ok`, final line `=== PASS ===`, `exit=0`.

- [ ] **Step 5: Register the suite in the runner**

In `tests/run_tests.gd`, add `test_visionos_boot` to the suites the runner executes, following the existing registration pattern in `_main()`.

- [ ] **Step 6: Run the whole headless suite**

Run:
```bash
/Users/bert/Projects/godot-visionos/bin/godot.macos.editor.arm64 \
  --headless --path . -s res://tests/run_tests.gd ; echo "exit=$?"
```
Expected: `exit=0`, with the new suite's lines present and no regressions.

- [ ] **Step 7: Commit**

```bash
git add src/xr/visionos_boot.gd tests/test_visionos_boot.gd tests/run_tests.gd
git commit -m "feat(xr): visionOS bring-up state machine, headless-tested

Four calls, each a silent failure if skipped. Side effects are Callables so
the macOS suite can prove the ordering without a visionOS interface."
```

---

### Task 5: Boot into the immersive space

Godot's boot splash is a windowed-2D concept and CompositorServices has no window. `main.gd:60` also fires `Music.play_menu()` unconditionally. Spec §5.6.

**Files:**
- Modify: `project.godot` (splash settings)
- Modify: `src/main.gd:44-70` (`_ready`)
- Create: `src/xr/xr_session.gd`
- Test: `tests/test_visionos_boot.gd` (extend)

**Interfaces:**
- Consumes: `VisionOSBoot.bring_up()` from Task 4.
- Produces: `XRSession.is_immersive() -> bool` (true only on a visionOS build whose bring-up succeeded) and `XRSession.start(tree: SceneTree) -> Dictionary` returning the same shape as `bring_up`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_visionos_boot.gd` inside `_main()`, before the summary print:

```gdscript
	# 5. On a non-visionOS host, is_immersive() must be false and start() must
	#    fail at 'find' — the macOS build must keep booting normally.
	const XS := preload("res://src/xr/xr_session.gd")
	_ok("macOS host is not immersive", XS.is_immersive() == false)
	var r5 := XS.start(self)
	_ok("macOS start() fails at find", r5.ok == false and r5.step == "find")
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
/Users/bert/Projects/godot-visionos/bin/godot.macos.editor.arm64 \
  --headless --path . -s res://tests/test_visionos_boot.gd
```
Expected: FAIL — `res://src/xr/xr_session.gd` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `src/xr/xr_session.gd`:

```gdscript
class_name XRSession
extends RefCounted
## Live wiring for VisionOSBoot. Everything testable lives in visionos_boot.gd;
## this file exists only to bind the four Callables to the real servers, so it
## stays small enough to read in one screen.

const VisionOSBootScript := preload("res://src/xr/visionos_boot.gd")

static var _immersive := false


static func is_immersive() -> bool:
	return _immersive


static func start(tree: SceneTree) -> Dictionary:
	var viewport := tree.root
	var result: Dictionary = VisionOSBootScript.bring_up({
		"find_interface": func(n: String): return XRServer.find_interface(n),
		"set_use_xr": func(v: bool) -> void: viewport.use_xr = v,
		"set_origin_current": func(v: bool) -> void:
			var origin := tree.get_first_node_in_group("xr_origin")
			if origin != null:
				origin.current = v,
		"set_near": func(v: float) -> void:
			var cam := tree.get_first_node_in_group("xr_camera")
			if cam != null:
				cam.near = maxf(cam.near, v),
	})
	_immersive = result.ok
	return result
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Users/bert/Projects/godot-visionos/bin/godot.macos.editor.arm64 \
  --headless --path . -s res://tests/test_visionos_boot.gd ; echo "exit=$?"
```
Expected: all `ok`, `=== PASS ===`, `exit=0`.

- [ ] **Step 5: Disable the boot splash and call bring-up first**

In `project.godot`, under `[application]`:

```ini
boot_splash/show_image=false
boot_splash/bg_color=Color(0, 0, 0, 1)
```

In `src/main.gd`, insert immediately after `_install_e2e_harness()` on line 45:

```gdscript
	# visionOS: stand up XR BEFORE any scene is added, and hold the menu music
	# until we know whether we are immersive (main.gd:60 fires it otherwise).
	var xr := XRSession.start(get_tree())
	if not xr.ok and OS.get_name() == "visionOS":
		push_error("visionOS XR bring-up failed at '%s': %s" % [xr.step, xr.error])
```

- [ ] **Step 6: Verify the macOS build still boots and the suite is green**

Run:
```bash
/Users/bert/Projects/godot-visionos/bin/godot.macos.editor.arm64 \
  --headless --path . -s res://tests/run_tests.gd ; echo "suite=$?"
./tools/build/build.sh all ; echo "build=$?"
```
Expected: `suite=0` and `build=0`. The macOS headless boot check inside `build.sh` must still pass — bring-up failing on macOS is the expected path and must not be fatal.

- [ ] **Step 7: Commit**

```bash
git add project.godot src/main.gd src/xr/xr_session.gd tests/test_visionos_boot.gd
git commit -m "feat(xr): boot into the immersive space, splash disabled

CompositorServices has no window, so the 2D boot splash cannot render.
Bring-up runs before any scene is added; failing on macOS is expected."
```

---

### Task 6: First device build

The end of this plan is a rendered frame on hardware. There is no simulator path — the simulator has no rendering driver. Spec §12 items 1 and 5.

**Files:**
- Modify: `docs/BUILDING.md` (append the device runbook)

**Interfaces:**
- Consumes: everything above.
- Produces: an installed `GreatHauses.app` on the Vision Pro.

- [ ] **Step 1: Export the Xcode project**

```bash
cd /Users/bert/Projects/great-hauses
./tools/build/build.sh visionos
```
Expected: exit 0, `OK: visionOS xcodeproj exported`, and `../great-hauses-dist/visionos/GreatHauses.xcodeproj` exists.

- [ ] **Step 2: Confirm the headset is paired and visible**

```bash
cd ../great-hauses-dist/visionos
xcrun devicectl list devices
```
Expected: an `Apple Vision Pro` row, state `connected`. If absent, pair it in Xcode → Window → Devices and Simulators before continuing.

- [ ] **Step 3: Build and install to the device**

```bash
cd ../great-hauses-dist/visionos
xcodebuild -project GreatHauses.xcodeproj -scheme GreatHauses \
  -destination 'generic/platform=visionOS' \
  -configuration Release \
  DEVELOPMENT_TEAM=GJ994MN2YF \
  -derivedDataPath ./build
xcrun devicectl device install app --device <DEVICE_UDID> \
  ./build/Build/Products/Release-xros/GreatHauses.app
```
Expected: `BUILD SUCCEEDED`, then an install with no error. Take `<DEVICE_UDID>` from Step 2.

- [ ] **Step 4: Launch and observe**

Put the headset on and launch Great Hauses from the Home View.

Expected, in order: no 2D splash panel; the immersive space opens; the Great Hall renders **in stereo with depth**; turning your head moves the view with no lag or judder; the board and pieces are present (at authored scale — an 8 m board is correct here, Plan 3 makes it resizable).

**Stop and diagnose if:** the view is flat/mono (bring-up failed — check `xr.step` in the device log), the app opens as a floating panel (`app_role` is Window — re-run Task 3 Step 6), or the screen is black (Forward+ fell back, or the near plane is < 0.1 m).

- [ ] **Step 5: Capture the device log for the record**

```bash
xcrun devicectl device console --device <DEVICE_UDID> | grep -i "godot\|visionOS XR\|bring-up"
```
Expected: no `push_error` from bring-up; no `WARN` about Forward+.

- [ ] **Step 6: Record the runbook**

Append the exact commands from Steps 1–5 to `docs/BUILDING.md` under the visionOS section added in Task 1, including the device UDID lookup and the three diagnostics from Step 4.

- [ ] **Step 7: Commit**

```bash
git add docs/BUILDING.md
git commit -m "docs(visionos): device build and install runbook"
```

---

## Self-Review

**Spec coverage for this plan's scope:**

| Spec section | Task |
|---|---|
| §2 engine/toolchain, pin, flags | 1 |
| §2.1 immersion style decided + asserted | 3 |
| §2.2 spatial-event patch | 2 |
| §5.1 XR bring-up, four calls, near plane | 4, 5 |
| §5.6 boot in immersive, splash, music hold | 5 |
| §12 items 1, 5 (device render, no macOS/Windows regression) | 3, 5, 6 |
| §13 fork durability, patch series, BUILDING.md | 1, 2, 6 |

**Deferred to later plans, by design:** §3 scale (Plan 3), §4 input (Plan 2), §5.0/5.2/5.3 camera inversions (Plan 4), §5.4 placement/recenter/tracking loss (Plan 3), §5.5 lifecycle and §6/§7 HUD, audio, Esc, Oracle (Plan 5), §9 the two camera-coupled test rewrites (Plan 4, same PR as the inversion).

**Known gap this plan deliberately leaves open:** after Task 6 the game renders but is **unplayable** — there is no input until Plan 2. Task 6 Step 4 checks a rendered frame and head tracking only, not interaction. That is the intended shape of a bring-up plan.
