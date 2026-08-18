import os
import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"
os.makedirs(ARTIFACTS_DIR, exist_ok=True)

# 1. Activate Great Hauses Chess and bring window to front
applescript = '''
tell application "Great Hauses Chess"
    activate
end tell
tell application "System Events"
    tell process "Great Hauses Chess"
        set frontmost to true
        delay 0.5
        key code 36 -- Return (Continue to War Mode)
        delay 0.5
        key code 36 -- Return (Start The War)
    end tell
end tell
'''

subprocess.run(["osascript", "-e", applescript])
time.sleep(0.3)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/01_versus_splash.png"])
time.sleep(2.0)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/02_cathedral_gameplay.png"])
print("[inspect] Captured foreground frames successfully!")
