import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"

# Kill and open fresh
subprocess.run(["pkill", "-f", "Great Hauses Chess"])
time.sleep(0.5)
subprocess.run(["open", "-a", "/Applications/GreatHauses.app"])
time.sleep(2.5)

applescript = '''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    key code 36 -- Return (Choose Opponent)
    delay 0.8
    key code 36 -- Return (Continue to War Mode)
    delay 0.8
    key code 36 -- Return (Start War)
end tell
'''
subprocess.run(["osascript", "-e", applescript])
time.sleep(1.0) # Capture Versus screen
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/symmetric_versus_screen.png"])
print("[inspect] Captured symmetric_versus_screen.png!")
