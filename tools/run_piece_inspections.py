import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"
houses = ["winterfang", "goldclaw", "swiftcrest", "tidegrip", "ashwyrm"]

for hid in houses:
    print(f"[inspect] Rendering piece lineup for Haus {hid}...")
    cmd = [
        "/Applications/Godot.app/Contents/MacOS/Godot",
        "--path", "/Users/bert/Projects/great-hauses-core",
        "--script", "tools/piece_gallery_inspector.gd",
        "--",
        f"--house={hid}"
    ]
    proc = subprocess.Popen(cmd)
    time.sleep(1.2)
    proc.terminate()

print("[inspect] All lineups captured!")
