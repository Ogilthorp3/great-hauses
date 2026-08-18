"""author_dragon_flight.py — give the wyrm a flight cycle worth watching.

Run:  blender -b -P tools/blender/author_dragon_flight.py -- [--out <file.glb>]

WHY (Bert, 2026-08-18: "make it fly like a butterfly and sting like a bee").
The shipped `Fast_Flying` is 25 keys over one second with **LINEAR**
interpolation. Measured off the GLB: the shoulder (`Wing1.*`) swings 104
degrees about its local X, so those keys are ~4 degrees apart with a VELOCITY
CORNER at every one of them — a direction change every 2.4 frames at 60 fps,
and every 1.6 frames once the cinematic drives it at speed 1.5. That stepping
is the mechanical quality; it is not the poses, which are good.

So this tool does not re-pose the animal. It RE-TIMES and RE-SAMPLES the
poses the asset's author already made, into a new action called `Soar`:

  THE BEE — the downstroke is compressed. A smooth monotone time warp
    (u = t + k·sin(2πt)/2π, k = 0.55) runs the original clip fast through
    the power stroke and slow through the recovery, so the wing SNAPS down
    and FLOATS up instead of ticking round like a metronome. The warp is
    smooth, so unlike a piecewise remap it introduces no new velocity break.

  THE BUTTERFLY — overlap. Each joint outward along the wing samples the
    original clip slightly LATER than the one inboard of it (shoulder leads,
    then forearm, then hand, then the membrane spars). The wing stops moving
    as one rigid plate and starts trailing through the stroke, which is the
    single biggest readability win on a creature this size.

  AND NO CORNERS — 60 keys per cycle with Bezier handles instead of 25
    linear ones, so there is at most one key per rendered frame.

IT DOES NOT TOUCH dragon.glb. The first cut of this tool re-exported the
whole asset and a before/after diff caught it compressing EVERY existing clip
to 40 % of its duration — Perch_Idle 4.00 s -> 1.60 s, Roar 1.67 -> 0.67 —
because glTF samples at the scene's fps and the source was authored at 24
while the dense new cycle needs 60. The ashfall ceremony is choreographed
against those measured lengths (BREATH_LUNGE_END, ROAR_CLIP_LEN,
RISE_CLIP_SETTLED...), so that export would have broken the endgame.

So the output is an ANIMATION-ONLY companion file — the armature and this one
action, no meshes — which DragonRig merges into the live AnimationPlayer as
an AnimationLibrary at runtime. dragon.glb keeps every byte it has, and the
new cycle can be sampled at whatever rate it needs.
"""

import math
import os
import sys

import bpy

SRC_CLIP = "Fast_Flying"
NEW_CLIP = "Soar"
CYCLE_FRAMES = 60          # one beat, at 60 fps == 1.00 s (same as the source)
WARP_K = 0.55              # snap of the downstroke; 0 = unchanged, <1 monotone
START_PHASE = 0.25         # the source's stroke top (measured: peak @ 0.25 s)

## How far behind the shoulder each joint runs, in fractions of a cycle.
## Outboard joints trail — this is the whip.
LAG = [
    (("Wing1.L", "Wing1.R"), 0.000),
    (("Wing2.L", "Wing2.R"), 0.030),
    (("Wing3.L", "Wing3.R"), 0.055),
    (("Finger1.L", "Finger1.R", "Finger2.L", "Finger2.R",
      "Finger3.L", "Finger3.R", "Finger4.L", "Finger4.R"), 0.075),
]


def warp(t):
    """Smooth monotone time warp: fast through the power stroke, slow back."""
    return t + WARP_K * math.sin(2.0 * math.pi * t) / (2.0 * math.pi)


def action_fcurves(act):
    """Blender 4.4+ moved an Action's curves under layers/strips/channelbags
    (the 'slotted action' rework); 5.2 removed `Action.fcurves` outright.
    Support both so this tool is not pinned to one Blender."""
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in getattr(layer, "strips", []):
            for cb in getattr(strip, "channelbags", []):
                out.extend(cb.fcurves)
    return out


def assign(arm, act):
    """Assign an action, and pick up its slot on the versions that need one."""
    arm.animation_data.action = act
    slots = getattr(act, "slots", None)
    if slots and hasattr(arm.animation_data, "action_slot"):
        try:
            arm.animation_data.action_slot = slots[0]
        except (TypeError, RuntimeError):
            pass


def find_armature():
    for ob in bpy.data.objects:
        if ob.type == 'ARMATURE':
            return ob
    raise SystemExit("no armature in the imported file")


def find_action(fragment):
    for act in bpy.data.actions:
        if fragment in act.name:
            return act
    raise SystemExit("action %r not found (have: %s)"
                     % (fragment, [a.name for a in bpy.data.actions]))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    here = os.path.dirname(os.path.abspath(__file__))
    default = os.path.normpath(os.path.join(
        here, "..", "..", "assets", "custom-props", "dragon.glb"))
    out_default = os.path.normpath(os.path.join(
        here, "..", "..", "assets", "custom-props", "dragon_soar.glb"))
    out_path = argv[argv.index("--out") + 1] if "--out" in argv else out_default

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=default)

    arm = find_armature()
    src = find_action(SRC_CLIP)
    scene = bpy.context.scene
    scene.render.fps = 60

    if arm.animation_data is None:
        arm.animation_data_create()
    assign(arm, src)

    # The source's own span, in its own frames.
    f0, f1 = src.frame_range
    span = max(f1 - f0, 1.0)

    lag_of = {}
    for names, lag in LAG:
        for n in names:
            lag_of[n] = lag
    groups = {}
    for pb in arm.pose.bones:
        groups.setdefault(lag_of.get(pb.name, 0.0), []).append(pb.name)

    # Sample: for each output frame, read each lag-group at its own warped,
    # lagged time in the SOURCE clip.
    samples = {pb.name: [] for pb in arm.pose.bones}
    for i in range(CYCLE_FRAMES + 1):
        t = float(i) / CYCLE_FRAMES                     # 0..1 of the new cycle
        for lag, names in groups.items():
            phase = (START_PHASE + warp(t) - lag) % 1.0
            scene.frame_set(int(round(f0 + phase * span)))
            for n in names:
                pb = arm.pose.bones[n]
                samples[n].append((
                    pb.rotation_quaternion.copy(),
                    pb.location.copy(),
                    pb.scale.copy()))

    # Write them into a fresh action.
    if NEW_CLIP in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[NEW_CLIP])
    act = bpy.data.actions.new(NEW_CLIP)
    act.use_fake_user = True
    assign(arm, act)
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'

    for i in range(CYCLE_FRAMES + 1):
        frame = 1 + i
        scene.frame_set(frame)
        for pb in arm.pose.bones:
            rot, loc, scl = samples[pb.name][i]
            pb.rotation_quaternion = rot
            pb.location = loc
            pb.scale = scl
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("location", frame=frame)
            pb.keyframe_insert("scale", frame=frame)

    # No corners: smooth handles everywhere.
    for fc in action_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.handle_left_type = 'AUTO_CLAMPED'
            kp.handle_right_type = 'AUTO_CLAMPED'
        fc.update()

    print("[flight] authored %r: %d keys/bone over %d frames @ %d fps"
          % (NEW_CLIP, CYCLE_FRAMES + 1, CYCLE_FRAMES, scene.render.fps))
    print("[flight] actions now: %s" % sorted(a.name for a in bpy.data.actions))

    # Ship the ARMATURE AND THIS ACTION ONLY. Every mesh goes, and every
    # other action goes, so nothing here can restate — or mistime — what
    # dragon.glb already says.
    for ob in [o for o in bpy.data.objects if o.type != 'ARMATURE']:
        bpy.data.objects.remove(ob, do_unlink=True)
    for a in list(bpy.data.actions):
        if a.name != NEW_CLIP:
            a.use_fake_user = False
            bpy.data.actions.remove(a)
    assign(arm, act)
    scene.frame_set(1)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=False,
        export_apply=False,
        export_animations=True,
        export_animation_mode='ACTIVE_ACTIONS',
        export_bake_animation=True,
    )
    print("[flight] exported %s" % out_path)


if __name__ == "__main__":
    main()
