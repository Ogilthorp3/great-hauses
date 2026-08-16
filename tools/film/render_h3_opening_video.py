#!/usr/bin/env python3
"""
tools/film/render_h3_opening_video.py
Renders the full Civilization-Style Opening Cinematic Video using MiniMax H3
via ComfyUI and encodes it into Godot-compatible video streams (OGV / MP4 / WEBM).

Usage:
  python3 tools/film/render_h3_opening_video.py
"""

import os
import sys
import json
import time
import uuid
import urllib.request
import urllib.error
import subprocess
from pathlib import Path

COMFY = os.environ.get("COMFYUI_URL", "http://127.0.0.1:8000")
MODELS = Path(os.environ.get("COMFY_MODELS", Path.home() / "Documents/ComfyUI/models"))

CIVILIZATION_PROMPT = (
    "Cinematic high-fantasy epic opening shot, Civilization style. "
    "A vast gothic cathedral throne hall at dusk, glowing stained glass, "
    "torchlight illuminating towering heraldic banners of warring medieval houses. "
    "A majestic dark dragon roosts among high vaulted stone arches, breathing soft embers. "
    "The camera swoops down across a massive polished obsidian chessboard where golden "
    "and silver armored knights clash in dramatic slow motion, cinematic 8k masterpiece, "
    "volumetric lighting, photorealistic depth, epic grand atmosphere."
)


def pick_dit() -> str:
    bf16 = MODELS / "diffusion_models" / "minimax_h3_fl2va_pruned_bf16.safetensors"
    int8 = MODELS / "diffusion_models" / "minimax_h3_fl2va_pruned_int8_convrot.safetensors"
    if bf16.exists():
        return bf16.name
    if int8.exists():
        return int8.name
    sys.exit(f"H3 FL2VA weights missing under {MODELS}/diffusion_models/")


def build_workflow(prompt: str, width: int = 1280, height: int = 720, frames: int = 73, seed: int = 42, dit: str = "") -> dict:
    te = "qwen3vl_32b_h3_ultra_uncensored_heretic_int8_convrot.safetensors"
    return {
        "1": {
            "class_type": "UNETLoader",
            "inputs": {"unet_name": dit, "weight_dtype": "default"},
        },
        "2": {
            "class_type": "CLIPLoader",
            "inputs": {
                "clip_name": te,
                "type": "minimax",
                "device": "default",
            },
        },
        "3": {
            "class_type": "VAELoader",
            "inputs": {"vae_name": "minimax_h3_video_vae_fp16.safetensors"},
        },
        "4": {
            "class_type": "VAELoader",
            "inputs": {"vae_name": "minimax_h3_audio_vae_fp32.safetensors"},
        },
        "7": {
            "class_type": "MiniMaxH3ImageToVideo",
            "inputs": {
                "clip": ["2", 0],
                "vae": ["3", 0],
                "prompt": prompt,
                "width": width,
                "height": height,
                "length": frames,
            },
        },
        "8": {
            "class_type": "MiniMaxH3SigmaShift",
            "inputs": {
                "model": ["1", 0],
                "shift_video": 12.0,
                "shift_audio": 3.0,
            },
        },
        "9": {
            "class_type": "BasicGuider",
            "inputs": {"model": ["8", 0], "conditioning": ["7", 0]},
        },
        "10": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "res_multistep"}},
        "11": {
            "class_type": "BasicScheduler",
            "inputs": {
                "model": ["8", 0],
                "scheduler": "simple",
                "steps": 16,
                "denoise": 1.0,
            },
        },
        "12": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "13": {
            "class_type": "SamplerCustomAdvanced",
            "inputs": {
                "noise": ["12", 0],
                "guider": ["9", 0],
                "sampler": ["10", 0],
                "sigmas": ["11", 0],
                "latent_image": ["7", 1],
            },
        },
        "14": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["13", 0], "vae": ["3", 0]},
        },
        "15": {
            "class_type": "VAEDecodeAudio",
            "inputs": {"samples": ["13", 0], "vae": ["4", 0]},
        },
        "16": {
            "class_type": "CreateVideo",
            "inputs": {"images": ["14", 0], "fps": 24.0, "audio": ["15", 0]},
        },
        "17": {
            "class_type": "SaveVideo",
            "inputs": {
                "video": ["16", 0],
                "filename_prefix": "great_hauses_civilization_intro",
                "format": "mp4",
                "codec": "h264",
            },
        },
    }


def post_prompt(workflow: dict) -> str:
    body = json.dumps({"prompt": workflow, "client_id": uuid.uuid4().hex}).encode()
    req = urllib.request.Request(
        f"{COMFY}/prompt",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read())
    if data.get("error"):
        raise RuntimeError(data["error"])
    return data["prompt_id"]


def poll_history(prompt_id: str, timeout_s: int = 1800) -> dict:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{COMFY}/history/{prompt_id}", timeout=30) as r:
                hist = json.loads(r.read())
            if prompt_id in hist:
                return hist[prompt_id]
        except Exception:
            pass
        time.sleep(3)
    raise TimeoutError(f"H3 video {prompt_id} did not finish within {timeout_s}s")


def find_mp4(hist: dict) -> Path:
    outputs = hist.get("outputs") or {}
    for node in outputs.values():
        for key in ("gifs", "videos", "images"):
            for item in node.get(key) or []:
                fn = item.get("filename")
                sub = item.get("subfolder") or ""
                folder = item.get("type") or "output"
                if fn and str(fn).endswith(".mp4"):
                    root = Path.home() / "Documents" / "ComfyUI" / folder
                    return root / sub / fn if sub else root / fn
    raise FileNotFoundError(f"no mp4 in H3 history: {list(outputs)}")


def transcode_to_godot(mp4: Path, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    ogv_out = out_dir / "opening_intro.ogv"
    
    # Encode to Ogg Theora with Vorbis audio for Godot's VideoStreamTheora
    cmd = [
        "ffmpeg", "-y", "-i", str(mp4),
        "-c:v", "theora", "-q:v", "7",
        "-c:a", "libvorbis", "-q:a", "5",
        str(ogv_out)
    ]
    print(f"Transcoding {mp4} -> {ogv_out}...")
    subprocess.run(cmd, check=True)
    return ogv_out


def main():
    dit = pick_dit()
    print(f"=== Great Hauses — MiniMax H3 Video Renderer ===")
    print(f"Model: {dit}")
    print(f"Comfy: {COMFY}")
    print(f"Prompt: {CIVILIZATION_PROMPT}")

    wf = build_workflow(CIVILIZATION_PROMPT, width=1280, height=720, frames=49, seed=42, dit=dit)
    pid = post_prompt(wf)
    print(f"Queued job: {pid} (Rendering video on Metal GPU...)")
    
    hist = poll_history(pid)
    mp4 = find_mp4(hist)
    print(f"MiniMax H3 Video Rendered: {mp4}")

    proj_dir = Path("/Users/bert/Projects/great-hauses-core/assets/cinematics")
    ogv_file = transcode_to_godot(mp4, proj_dir)
    print(f"✓ Video ready for Godot: {ogv_file}")


if __name__ == "__main__":
    main()
