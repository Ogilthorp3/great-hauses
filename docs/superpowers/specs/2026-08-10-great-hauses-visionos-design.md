# Great Hauses on Apple Vision Pro — Design

**Date:** 2026-08-10
**Status:** Approved for planning
**Target:** Fully immersive visionOS app (CompositorServices), Apple Vision Pro, device-only

Every claim below cites a file:line or a command output. Claims that could not be
reproduced from disk are marked as unknowns in §10 rather than asserted.

---

## 1. Decision

Port Great Hauses to visionOS as a **fully immersive** app — not a flat window, not a
bounded volume.

| Target | Renderer | Hands | Verdict |
|---|---|---|---|
| Flat window | Godot, mono | gaze+pinch → synthesized touch | Buys nothing a Mac window doesn't. Rejected. |
| Bounded volume | RealityKit **replaces Godot's** | ARKit hand data may be Full-Space-only — unproven | Loses Godot's renderer and all text GLSL shaders. Rejected. |
| **Fully immersive** | **Godot's own Metal driver** | `.indirectPinch` + hand trackers | **Chosen.** |

The volume path was the research synthesis's recommendation. Rejected because it replaces
Godot's renderer, and because the chosen interaction — two-handed grab-to-resize — needs
hand joints, which Apple's ARKit documentation restricts to the Full Space. The volume may
be unable to do the one thing this design is built around.

---

## 2. Engine and toolchain (built and verified 2026-08-10)

No **current** Godot release can export visionOS. 4.5.1 and 4.5.2-stable did ship
`templates/visionos.zip`; it disappeared in 4.6 and is still absent in 4.6.3, 4.7 and
4.7.1, because the `## visionOS (Classical) ##` packaging block in
`godot-build-scripts/build-release.sh` is commented out
([issue #115415](https://github.com/godotengine/godot/issues/115415), open since
2026-01-27, which itself records "Not reproducible in: 4.5.1-stable"). Building from
source is mandatory.

**Source:** `rsanchezsaez/godot` branch `apple/visionos-xr-9-developer-capture` @
`c1df64224a` — the top of Apple's nine-branch stack. Only the base (PR #109975) is merged
upstream into 4.8, and merged-upstream gives stereo rendering plus a head pose and **no
input at all**. The stack adds keyboard, spatial pinch, audio lifecycle, hand + PSVR2
trackers, immersion features and developer capture.

**Built artifacts** (`/Users/bert/Projects/godot-visionos/bin/`):

| Artifact | Size | Build time |
|---|---|---|
| `godot.macos.editor.arm64` | 123 MB | 162 s |
| `libgodot.visionos.template_debug.arm64.a` | 198 MB | 120 s |
| `libgodot.visionos.template_release.arm64.a` | 175 MB | 108 s |
| `godot_visionos.zip` (export template) | 96.1 MB | not timed |

Editor reports `4.7.beta.custom_build.c1df64224`. macOS editor flags:
`vulkan=no metal=yes opengl3=no accesskit=no angle=no` — macOS defaults to Vulkan via
MoltenVK, which we neither have nor want.

**Constraints — all currently satisfied. Do not "upgrade" past them.**

- Xcode **26.6**, visionOS SDK **26.5** (`xcrun --sdk xros --show-sdk-version`). Engine
  targets `-mtargetos=xros26.0` (`platform/visionos/detect.py:107,113`). Keep the headset
  on visionOS 26.x — not because 27 is proven hostile, but because no 27 SDK is installed
  and we have no evidence either way (§10).
- **Metal only.** `detect.py` force-disables Vulkan (`:150-152`) and OpenGL (`:169-171`).
- **arm64 device only in practice.** `detect.py:49` defaults to arm64 and only arm64 gets
  `-arch` flags (`:119-128`); `:62` still accepts x86_64, but that is simulator-only, and
  the simulator force-disables Metal (`:154-156`), leaving no rendering driver. **Every
  test is on hardware.**
- **Mobile renderer.** In immersive mode the display server warns and force-falls back:
  `platform/visionos/display_server_visionos.mm:46-50`. On the upstream base path, without
  that guard, Forward+ renders nothing silently. The project already sets
  `renderer/rendering_method="mobile"`.
- Near plane **≥ 0.1 m**, a CompositorServices floor with no workaround.
- Signing: Team `GJ994MN2YF`. Godot emits an `.xcodeproj`; the last mile is Xcode.

### 2.1 Immersion style — decided

**`app_role = Immersive`, `immersion_style = Full`.** The Great Hall (`src/env/great_hall.gd`)
is a lit interior; passthrough fights it. A passthrough/tabletop mode would require
`great_hall` to be runtime-hideable and the environment swappable — that is build 2, not a
config flip.

**Both export options default to the wrong value** (`export_plugin.cpp:60-61`: `app_role`
defaults to `0` = Window, `immersion_style` to `1` = Mixed). Set both explicitly in the
preset **and assert them in the build gate**, or the app ships as a flat window.

### 2.2 Engine patch we must carry

`platform/visionos/app_visionos.swift:192-204` — the three guards inside
`for event in spatialEventCollection` use `return`, not `continue`. One rejected event
aborts the whole collection and can drop the **other hand's** event in the same update,
which directly breaks two-handed manipulation (§4.3). Patch `return` → `continue` on all
three guards and carry it as a named patch in the series (§13).

---

## 3. Scale — a world you can resize

Authored at `TILE_SIZE = 1.0`, `BOARD_SIZE = 8` (`src/board/board_view.gd:23-24`), piece
heights 0.78–1.26 (`src/board/piece_assets.gd:72-79`). In XR one unit is one metre, so as
authored the board is **8 m across with chest-high pieces**.

A **content root** holds board + pieces + dragon and scales **0.1× to 1.0×**:
`0.1×` → 80 cm board, 8–13 cm pieces; `1.0×` → 8 m battlefield.

- **Default on launch: 0.25×** (2 m board, ~25 cm pieces) — legible seated, no room needed.
- Zoom pivots about the **board centre**, not the hand midpoint, so scaling never slides
  the board out from under the player.
- Continuous but **rate-limited to 2×/second**, snapping to detents at 0.1 / 0.25 / 0.5 /
  1.0 within 5%.
- Scale, board anchor and immersion style persist to `user://settings.json` (the file
  `music_manager.gd:29` already read-merge-writes).

**Scale the content, never `XROrigin3D.world_scale`.** This is load-bearing:
`modules/visionos_xr/visionos_xr_interface.mm:761-763` validates the *scaled* near plane
against the CompositorServices floor, so `world_scale = 0.1` with a 0.1 m near plane
**fails at runtime**. Content scaling has no such interaction.

**Audit method for the 10× range:** grep `src/cinematics/`, `src/minigame/`, `src/env/`
for literal `Vector3(`/float world extents; convert each to a multiple of
`content_root.scale.x`. Add a headless test instantiating each effect at 0.1 / 0.55 / 1.0
asserting its AABB scales linearly. `GLOW_SIZE := 3.0` (`duel_director.gd:1120`, consumed
`:1181`) is the worked example.

---

## 4. Input

### 4.1 What visionOS delivers

`app_visionos.swift:191` installs `layerRenderer.onSpatialEvent`; `:193` filters to
`event.kind == .indirectPinch`; `:197` and `:201` require `selectionRay` and
`inputDevicePose`. That is the native look-and-pinch gesture.

It reaches GDScript as `InputEventSpatial` (`platform/visionos/input_event_spatial.h:35`),
registered end-to-end: `platform/visionos/api/api.cpp:39-42`
`GDREGISTER_CLASS(InputEventSpatial)` → `register_platform_apis.gen.cpp` →
`main/main.cpp:845`.

| Field | Meaning |
|---|---|
| `index` (`:61`) | event id (`event.id.hashValue`, `app_visionos.swift:207`) |
| `phase` (`:52-56`) | `PHASE_ACTIVE` / `PHASE_CANCELLED` / `PHASE_ENDED` |
| `chirality` (`:67`) | `CHIRALITY_LEFT` / `CHIRALITY_RIGHT` |
| `selection_ray_origin` / `_direction` | gaze-derived ray, **at pinch time only** |
| `input_device_pose_position` / `_rotation` | that hand's pose |

There is **no `PHASE_BEGAN`**. The first `ACTIVE` for an `index` is the begin; `ENDED`
closes it. State is tracked per `index`.

Second channel: `visionOSHandTracker` (`modules/visionos_xr/visionos_xr_hand_tracker.h:68`)
publishes both hands as stock `XRHandTracker`s (`:58-59`, added at `.mm:100,105`) carrying
Godot's 26-joint set — **25 joints mapped** from ARKit (`joint_from_arkit`, `:98-155`;
ARKit's enum has 27 names, of which `forearm_wrist` and `forearm_arm` are dropped).
`visionOSControllerTracker` (`:107`) exposes PSVR2 Sense controllers as `XRControllerTracker`.

### 4.2 Piece selection — look and pinch

Raycast `selection_ray_origin` + `_direction` against the board plane.

The game has **zero physics bodies** — verified: `grep -rln 'RigidBody3D|StaticBody3D|
CharacterBody3D|CollisionShape3D|Area3D|RayCast3D' src/ scenes/` returns nothing.
`world_to_square()` (`src/board/board_view.gd:83-87`) is reused unchanged. The change is
confined to `pick_square()` (`:94-106`), which today derives its ray from the viewport
camera via `project_ray_origin`/`project_ray_normal` and instead takes the selection ray.

**Mode 1 (pinch-then-pinch) is the committed default** — identical at 0.1× and 1.0×, needs
no continuous hand tracking, survives tracking loss. **Mode 2 (pinch-and-carry)** is an
experiment behind a `user://settings.json` flag, evaluated on device after build 1.

### 4.3 Board manipulation — two hands

| Gesture | Derived from |
|---|---|
| Zoom (0.1×–1.0×) | change in distance between the two hand poses |
| Rotate | change in yaw of the vector between them |
| Move | translation of their midpoint |

Requires the §2.2 engine patch, or one hand's events get dropped.

**Arbitration.** A pinch whose selection ray hits the board plane within bounds →
*piece intent*. A pinch that misses the board, or a second pinch beginning within 150 ms of
an existing carry → *world intent*. World transform requires **both** hands `PHASE_ACTIVE`
simultaneously; a single off-board pinch does nothing. Classification is latched until both
hands reach `PHASE_ENDED`.

### 4.4 The hover loss

Continuous gaze is never delivered — verified by exhaustion: `grep -rniE '\bgaze\b|
eye_tracking' platform/visionos/ modules/visionos_xr/` returns **zero hits**. Only the ray
at pinch time exists. The `square_hovered` glyph-ring cannot follow the eyes.

**Resolution:** hand-proximity hover is active when content scale **≥ 0.5×** and the index
fingertip (`HAND_JOINT_INDEX_FINGER_TIP`, `visionos_xr_hand_tracker.h:119`) is within
**0.15 m** of the board plane in content-scaled units. Otherwise the ring shows only the
selected square. Hover clears within one frame of `has_tracking_data` going false.

### 4.5 The intent layer

Mouse (macOS) and `InputEventSpatial` (visionOS) both emit `Intent` records
`{kind, square, ray_origin, ray_dir, hand, phase}` consumed by `board_view` and the HUD
panels. **This is a deliverable of §4, not a testing footnote** — it is what keeps the
macOS e2e suite alive (§9).

---

## 5. Camera and cinematics

### 5.0 Camera-owner inventory

Every site below makes a `Camera3D` current or reads the viewport camera. All must be
classified before §5.2 is written.

| Owner | Site | Disposition |
|---|---|---|
| `OrbitCamera` | `src/camera/orbit_camera.gd`, `scenes/game.tscn:38-45` | **Delete** → `XROrigin3D` + `XRCamera3D` |
| `DuelDirector` CineCam | created `duel_director.gd:126-130` (deliberately `current = false` at `:130`); takes viewport `_cam_take_viewport()` `:927-945` (`current = true` `:940`); releases `_cam_restore()` `:971-978` | **Invert** (§5.2) |
| `DragonSpectator` ceremony cam | `dragon_spectator.gd:316-317`, `:339`, `:1615-1659` | **Invert** — 1,807 lines, larger than the duel director |
| Trial by Fire transmutation | `trial_by_fire.gd:332-340` (`_arena_pitch = -0.90`, `_arena_distance = 11.2`) | **Invert** (§5.3) |
| `PromotionPicker` card cams | `promotion_picker.gd:303-314`, `SubViewport` + `own_world_3d` | **Keep** — viewport-scoped, and the model for §6 |
| `CostumePreview` | `costume_preview.gd:492-494`, `:611-617` | SubViewport-scope or cut from build 1 |
| Viewport-camera *readers* | `board_view.gd:97`, `piece_view.gd:1319`, `cine_caption.gd:103` | Return `XRCamera3D`; audit for screen-space assumptions |

Camera inversion spans `src/cinematics/` (4,635 lines) **and** `src/minigame/trial_by_fire.gd`.
**It is three inversions, not one.**

### 5.1 The rig

XR bring-up is four calls, every one a silent failure if missed:
`XRServer.find_interface("visionOSXR")` → `.initialize()` (it does **not** auto-initialize,
`visionos_xr_interface.mm:194`) → `get_viewport().use_xr = true` → `XROrigin3D.current = true`.
`XRCamera3D` near plane pinned ≥ 0.1 m. Hand and controller trackers initialize with the
interface (`:246-256`) and are reached as `XRServer.get_tracker("/user/hand_tracker/left")`.

### 5.2 The duel director — staging, not camerawork

**In XR the game may never move the player's camera.** Not a preference; camera motion the
body did not initiate is the direct cause of simulator sickness.

Keep the existing composition solver as a pure function `duel_pose(attacker, victim) ->
Transform3D` (the camera transform it computes today). Add a `DuelStage: Node3D` that
reparents the two fighters for the cinematic's duration. Each frame:

```
stage_xform = head_pose * VIEW_OFFSET * duel_pose(a, b).affine_inverse()
```

`VIEW_OFFSET` is a constant comfortable framing (forward 1.6 m content-scaled, −8° pitch).
`DuelStage.global_transform` is critically damped toward `stage_xform` (≥ 300 ms) so head
motion does not whip the tableau; it latches on the first frame and re-solves only if the
head yaws > 25°.

| Today | In XR |
|---|---|
| Swoop camera to a low duel angle | Stage the duel at the player's eye-line |
| Slow-motion `Engine.time_scale` | **Unchanged.** No sickness risk. |
| Checkmate orbit around the dying king | The **king rotates**; the player does not |
| Impact camera shake | Light flash + sound sting + particle burst |
| Board punch | Damped, brief world-space effect; never the view |
| Championship "park the camera" | Stage the tableau in front of the player and hold |

**Test:** extend `tests/test_cinematics.gd:588-607` — inject a fixed synthetic head pose,
run the solver, assert both fighters unproject inside the same screen rect the old CineCam
produced. Headless and CI-able on macOS.

### 5.3 Trial by Fire

The transmutation inverts like the duel director: the **arena rises and rakes to meet the
fixed head pose**, rather than a rig descending onto the arena. `_arena_pitch` /
`_arena_distance` (`trial_by_fire.gd:148-149`, sourced `:334-339`) become a target
transform for the arena root. `transforming` (`:138`) already gates input during the cut
and stays. Its raw `_input` (`:817`) / `_unhandled_input` (`:832`) and `_notification`
(`:436`) move to the intent layer and §5.5.

### 5.4 Placement, recenter, tracking loss

- **Initial placement.** On the first frame of valid tracking, place `content_root`
  head-forward 1.2 m, yaw-aligned to the head, at y = eye − 0.55 m (tabletop) or floor
  (battlefield). Without this the board spawns at the origin — possibly inside the player.
- **Recenter.** Two-hand pinch held 1.0 s with no relative motion re-anchors `content_root`
  and all HUD panels to the current head pose. Also the only recovery from a bad room setup.
- **Tracking loss.** When `has_tracking_data` goes false or `PHASE_CANCELLED` arrives: the
  hover ring clears within one frame; an in-flight carry **cancels to origin**; no `Intent`
  from a ray older than 100 ms is accepted. **A move must never be committed by a dropout.**

### 5.5 App lifecycle

Handle `NOTIFICATION_APPLICATION_PAUSED`/`RESUMED` and `FOCUS_OUT`/`IN` at one owner
(`src/session.gd`): pause the tree, suspend `Music`, and **snapshot/restore
`Engine.time_scale`** — retained slow-motion would otherwise resume at a wrong scale.
Cancel in-flight Oracle requests on pause and re-request on resume; a paused headset must
not burn the budget. Removing the headset tears down and rebuilds the immersive space —
placement must **re-run**, not restore stale anchors. Today only `trial_by_fire.gd:436` and
`uci_engine.gd:265` implement `_notification`.

### 5.6 Boot in immersive

Godot's boot splash is a windowed-2D concept; CompositorServices has no window. Disable it
explicitly. Entry sequence: enter space → hold clear for one frame of valid tracking →
place `content_root` (§5.4) → fade the hall in over 400 ms → `Music.play_menu()` (today
fired unconditionally at `main.gd:60`).

---

## 6. HUD

World-space `SubViewport` panels on quads, in the world, **not head-locked**.

**Interactive surfaces — all of them:** `src/ui/house_select.gd`,
`src/ui/promotion_picker.gd`, plus three Buttons built in `src/game.gd` — `UndoButton`
(`:1850`), `ContinueButton` (`:1964`), `NetPanelButton` (`:2005`) — plus
`src/minigame/trial_by_fire.gd`, which consumes raw input directly. All move onto the
intent layer.

**Ray→Control mechanism.** A `SubViewport` does not accept a 3D ray. Per panel: intersect
the selection ray with the quad → UV → viewport-local `Vector2` →
`SubViewport.push_input()` with a synthesized `InputEventMouseMotion`/`Button`. This is the
same `Input` seam the e2e driver already drives, which is why one intent layer serves both.

**Placement policy.** HUD panels are **not** children of `content_root` — fixed metric size
at fixed distance (1.0 m, panel height 0.35 m) so they stay legible across the 10× range.
Yaw-billboard only; never pitch, never roll, never head-lock. Re-anchored by recenter (§5.4).

**Already correct:** `promotion_picker.gd:303-314` renders each card into a `SubViewport`
with `own_world_3d = true`. That is the pattern; do not rewrite it.

### 6.1 Audio spatialization

Every audio node is a non-positional `AudioStreamPlayer` (`music_manager.gd:103-113`,
`:189`). In an immersive app that is head-locked and reads flat.

Score, stings and fanfares **stay** `AudioStreamPlayer` — head-locked is correct for score.
**Diegetic** sound (kills, dragon fire, wyrm clock, arena ignition) moves to
`AudioStreamPlayer3D` parented into `content_root`, with `unit_size` driven from content
scale or the 0.1× diorama is inaudible. `duel_director.gd:634` already enumerates all three
player types for its pitch-bend, so the conversion is transparent to it. **Untested:**
whether Godot's visionOS audio path renders 3D busses correctly on device (§10).

### 6.2 Esc with no keyboard

| Site | Meaning | XR affordance |
|---|---|---|
| `duel_director.gd:536` | skip a cinematic | two-hand pinch-hold 0.5 s = SKIP |
| `dragon_spectator.gd:1051` | skip the ceremony | same |
| `game.gd:1520-1525` | leave a finished/stalled game | world-space **Return to the Hall** button |
| `promotion_picker.gd:159` | dismiss to default (queen) | a **Default** card on the picker |
| `trial_by_fire.gd:867-873` | quit / back out of the arena | HUD button; `embedded` (`:156`) already distinguishes |

The key path stays for `--e2e` and macOS. `KEY_Z`+cmd (undo, `game.gd:1504`) is mirrored by
`UndoButton`; `KEY_R` / `KEY_ENTER` (`:1512-1519`) **need buttons or they are unreachable**.

---

## 7. Network and the Oracle

- The endpoint is **already** configurable: `chat_url()` (`src/ai/ds4_opponent.gd:152-158`)
  resolves env `DS4_CHESS_URL` → `endpoint_override` → `DEFAULT_CHAT_URL` (`:56`,
  `http://127.0.0.1:18000/v1/chat/completions`); `normalize_chat_url()` (`:141-149`) accepts
  base/`/v1`/full forms. The work is (a) changing the default and (b) **a way to set it with
  no environment and no keyboard** — a world-space settings panel writing `oracle_url` into
  `user://settings.json`, read at boot into `endpoint_override`.
- **There is no local engine on device.** `UciEngine` spawns external Stockfish via
  `OS.execute_with_pipe` (`uci_engine.gd:153`); a sandboxed visionOS app cannot fork a
  helper and no arm64 Stockfish ships. `find_stockfish()` returns `""`, `main.gd:148-149`
  greys out Maester mode, and the default `MODE_PURE` (`ds4_opponent.gd:116`) fallback is a
  **random legal move**, loudly flagged (`:254-260`, `last_source = "fallback"`).
  **Decision: accept the flagged random fallback for build 1 and surface it** — the wyrm
  already reacts (`oracle_stumbled`). Shipping an in-process engine is build 2.
- **Bound the stall.** `MOVE_TIMEOUT_S := 120.0` (`:64`) is the ceiling; `_llm_uci_loop`
  (`:265-296`) passes the remaining budget per request, and `game.gd:873` awaits
  `choose_move()` inline. A black-holed LAN address freezes a turn for **two minutes inside
  a headset**. Set a device budget of **10 s total** (matching Banter's 8 s bound,
  `banter.gd:92`) as a `user://settings.json` key.
- Multiplayer (`src/net/`) is out of scope for build 1.

### 7.1 `user://` on device

`user://` is the app sandbox container. `user://tournament.json` (`tournament.gd:19`) and
`user://settings.json` (`music_manager.gd:29`) persist normally. `user://net_prefs.cfg`
(`main.gd:32`) is moot with net out of scope. **`user://hauses/` DLC drop-in
(`houses.gd:35`) has no delivery mechanism on visionOS** — there is no file manager. Build 1
ships the nine `res://` hauses only; the DLC path stays macOS/Windows-only until a sideload
route exists. **This is a feature regression and is stated, not discovered.**

---

## 8. Performance

Stereo doubles fragment cost **and** the target moves from 60 Hz (16.67 ms/frame,
`docs/PERF.md:10`) to 90 Hz (11.1 ms). Every number in `docs/PERF.md` is therefore roughly
a **third**-budget — about 5.6 ms of the old 16.67 ms workload. The two effects compound.

In our favour: Mobile renderer already in use, ETC2/ASTC on, and shadows already cut to a
single split (`perf(shadows): one split, not four` — primitives 1,018,039 → 454,242, −55.4%,
−5.12 ms; the shadow pass had been 3.6× the main pass, `docs/PERF.md:200-201`). Foveation
comes free via `MTLRasterizationRateMap`.

**MSAA:** was broken on the upstream base path; the unblocking change is **already in this
build** (stack layer 1, `apple/visionos-xr-1-msaa-depth-resolve`, `0dcf0f112d`), and no
MSAA-disabling code exists in `platform/visionos/` or `modules/visionos_xr/`. Status here is
**untested, not known-broken**. Keep it off until measured on device.

Existence proof the target is reachable: Coulombe's *Cascade Countdown* holds a measured
90 FPS on this same immersive path.

---

## 9. Testing

- **Headless suites** (`tests/`, 15 files) stay the regression net for the chess engine,
  tournament, hauses and Trial by Fire — but **two are camera-coupled and must be rewritten
  in the same PR that inverts the camera**: `test_cinematics.gd:367-388` (asserts camera
  shake is restored — shake is deleted; replace with an assertion that no camera property
  was touched) and `:602-607` (hangs banner-station unprojection off `orbit_camera.gd`
  defaults; re-anchor on a synthetic head pose). Everything else keeps passing unchanged.
- **`test_e2e/` stays on the macOS build, unchanged, as the regression net.** Its assertions
  are screen-geometry and rendered-pixel censuses against a fixed player camera
  (`e2e_driver.gd`; scenarios `board-truth`, `orientation`, `promote`); an immersive app has
  no window, no canvas transform, no 2D framebuffer and no default player camera.
  **The macOS target is not legacy — it is the only CI-testable target, and the port must
  not regress it.**
- **There is no CI for the visionOS target.** No simulator (no rendering driver), no
  headless XR. The device gate is the written manual checklist in §12.
- The **build gate** must learn the visionOS preset and assert §2.1's two export options.

---

## 10. Risks and honest unknowns

1. **We are early.** No Godot chess or board game has publicly shipped on visionOS.
2. **The engine branch is unmerged.** Eight of Apple's nine branches are open PRs; a Godot
   maintainer has already questioned `InputEventSpatial` versus `XRControllerTracker`. We
   pin the commit and carry patches as a series (§13).
3. **Branch is 4.7.0-beta**, the project is 4.7.1-stable.
4. **visionOS 27 is unevaluated.** Apple's "use the visionOS 26 SDK" statement comes from
   the *RealityKit plugin* docs — a different path from ours. We have no 27 SDK installed
   and no evidence for or against. Staying on 26.x is the conservative choice, not a
   demonstrated requirement.
5. **Comfort is unproven.** The staging inversion is sound in theory; only wearing it proves it.
6. **10× scale range** is the largest unbounded work item.
7. **3D audio on the visionOS path is untested** (§6.1).
8. **Accessibility is out of scope, as a decision.** Build 1 is gesture-only: no VoiceOver,
   no Dwell Control, no switch input. Seated-vs-standing is handled by recenter (§5.4) rather
   than height calibration. Hand dominance is not configurable. Named gaps, not unknowns.

---

## 11. Out of scope for build 1

Multiplayer, developer capture, App Store distribution, visionOS 27, the RealityKit/volume
path, `user://hauses/` DLC on device, and any behaviour change to the Windows/macOS builds.

---

## 12. Definition of done — device gate

With no CI on the target, acceptance is written down. Build 1 ships when, **on hardware**:

1. The hall renders ≥ 90 FPS sustained for 60 s at 1.0× with a full 32-piece board.
2. A full game is completable using only gestures — no keyboard.
3. A duel, a checkmate and a Trial by Fire run end-to-end with **zero camera motion the
   player did not initiate**.
4. 20 minutes of continuous wear with no reported discomfort.
5. `tools/build/build.sh all` still passes for Windows and macOS.
6. `tests/` green.
7. `test_e2e` green on macOS.

**EETISMAD:** E2E-tested (macOS suite + this device checklist) · In docs (`docs/BUILDING.md`
with the pinned engine commit and Xcode/SDK versions) · Merged · And Deployed to the headset.

---

## 13. Fork maintenance and durability

`/Users/bert/Projects/godot-visionos` is a clone of `rsanchezsaez/godot` at `c1df64224a`
with **no Sanctum remote**, and its build script currently lives in a session scratchpad.
That is orphan config — the build is not reproducible from a tracked repo.

Before implementation starts: push the fork to a private `sanctum-godot-visionos` remote;
land the build script in this repo under `tools/build/`; record the pinned commit and the
Xcode/SDK versions in `docs/BUILDING.md`; and carry local changes — starting with the §2.2
`continue` patch — as a **named patch series** so an upstream rebase is mechanical.
