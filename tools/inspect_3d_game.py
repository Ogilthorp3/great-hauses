import os
import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"
os.makedirs(ARTIFACTS_DIR, exist_ok=True)

# Click script to select opponent, select mode, start game
applescript = '''
tell application "System Events"
    tell process "Great Hauses Chess"
        set frontmost to true
        delay 0.3
        key code 36 -- Return (Continue to War Mode)
        delay 0.5
        key code 36 -- Return (Start The War)
    end tell
end tell
'''

subprocess.run(["osascript", "-e", applescript])
# 1. Capture Street Fighter Versus Screen
time.sleep(0.5)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/01_street_fighter_vs.png"])
print("[inspect] Captured 01_street_fighter_vs.png")

# 2. Wait for 3D Cathedral Game to load
time.sleep(2.0)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/02_cathedral_front_view.png"])
print("[inspect] Captured 02_cathedral_front_view.png")

# 3. Rotate camera up to look at cathedral vaults & rose window
rotate_up = '''
tell application "System Events"
    tell process "Great Hauses Chess"
        set frontmost to true
        -- Right drag up to look at cathedral ceiling
        set win to window 1
        set {xPos, yPos} to position of win
        set {width, height} to size of win
    end tell
end tell
'''
time.sleep(1.0)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/03_cathedral_view_final.png"])
print("[inspect] All visual inspection captures complete!")
