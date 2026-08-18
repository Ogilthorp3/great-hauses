import os
import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"
os.makedirs(ARTIFACTS_DIR, exist_ok=True)

subprocess.run(["pkill", "-9", "-f", "Great Hauses"])
time.sleep(1.0)

print("[test] Launching app...")
subprocess.run(["open", "-a", "/Applications/GreatHauses.app"])
time.sleep(2.5)

# Skip intro by pressing Space
applescript = '''
tell application "Great Hauses Chess"
    activate
end tell
tell application "System Events"
    tell process "Great Hauses Chess"
        set frontmost to true
        key code 49 -- Space to skip intro
        delay 0.5
        key code 36 -- Return to pledge
        delay 0.5
        key code 36 -- Return to choose opponent
        delay 0.5
        key code 36 -- Return to start war
    end tell
end tell
'''
subprocess.run(["osascript", "-e", applescript])
time.sleep(0.4)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/live_01_splash.png"])
print("[test] Captured live_01_splash.png")

time.sleep(2.5)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/live_02_cathedral_gameplay.png"])
print("[test] Captured live_02_cathedral_gameplay.png")
