import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"

# Run the MatchupSplash scene directly in Godot
godot_bin = "/Applications/Godot.app/Contents/MacOS/Godot"
proc = subprocess.Popen([
    godot_bin,
    "--path", "/Users/bert/Projects/great-hauses-core",
    "scenes/matchup_splash.tscn",
    "--windowed",
    "--resolution", "1600x1000"
])

time.sleep(1.8) # Wait for cards animation to settle
subprocess.run(["osascript", "-e", 'tell application "Godot" to activate'])
time.sleep(0.4)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/symmetric_versus_screen.png"])
print("[inspect] Captured symmetric_versus_screen.png!")

time.sleep(1.0)
proc.terminate()
