import os
import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"

applescript = '''
tell application "Great Hauses Chess"
    activate
end tell
tell application "System Events"
    tell process "Great Hauses Chess"
        set frontmost to true
        delay 0.5
        -- Press Enter to confirm opponent
        key code 36
        delay 0.8
        -- Press Enter to start war
        key code 36
    end tell
end tell
'''
subprocess.run(["osascript", "-e", applescript])
print("[drive] Sent Enter keys...")

time.sleep(3.0)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/3d_gameplay_cathedral.png"])
print("[drive] Captured 3d_gameplay_cathedral.png!")
