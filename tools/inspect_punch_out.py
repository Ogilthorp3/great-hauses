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
        delay 0.4
        key code 36 -- Return (Choose Opponent)
        delay 0.6
        key code 36 -- Return (Start War)
    end tell
end tell
'''
subprocess.run(["osascript", "-e", applescript])
time.sleep(0.5)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/punch_out_versus.png"])
print("[inspect] Captured punch_out_versus.png!")
