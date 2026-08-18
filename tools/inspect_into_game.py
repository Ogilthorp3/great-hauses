import os
import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"

# Send Return twice to proceed through Opponent and Mode
applescript = '''
tell application "Great Hauses Chess"
    activate
end tell
tell application "System Events"
    tell process "Great Hauses Chess"
        set frontmost to true
        delay 0.3
        key code 36 -- Return (Continue to War Mode)
        delay 0.4
        key code 36 -- Return (Start The War)
    end tell
end tell
'''

subprocess.run(["osascript", "-e", applescript])
time.sleep(0.4)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/03_versus_active.png"])
time.sleep(2.0)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/04_in_game_cathedral.png"])
print("[inspect] Captured 03_versus_active.png and 04_in_game_cathedral.png!")
