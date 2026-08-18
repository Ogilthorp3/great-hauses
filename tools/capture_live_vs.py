import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"

applescript = '''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    key code 36 -- Return (Start War)
end tell
'''
subprocess.run(["osascript", "-e", applescript])
time.sleep(1.0)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/symmetric_versus_screen.png"])
print("[inspect] Captured symmetric_versus_screen.png!")
