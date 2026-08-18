import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"

# Kill and open fresh
subprocess.run(["pkill", "-f", "Great Hauses Chess"])
time.sleep(0.5)
subprocess.run(["open", "-a", "/Applications/GreatHauses.app"])
time.sleep(2.5)

# Step 1: Open Opponent Selection -> Mode -> Start War
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
time.sleep(1.2) # Capture Versus screen while active
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/symmetric_versus_screen.png"])
print("[inspect] Captured symmetric_versus_screen.png!")

time.sleep(6.2) # Wait for Versus screen to transition into Cathedral Fly-in

# Stage 1: Exterior Cathedral Spires & Night Sky reveal
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/flyin_01_cathedral_exterior.png"])
print("[inspect] Captured flyin_01_cathedral_exterior.png!")

# Stage 2: Dragon flight down the nave
time.sleep(3.0)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/flyin_02_nave_flight.png"])
print("[inspect] Captured flyin_02_nave_flight.png!")

# Stage 3: Organ loft balustrade perch & roar
time.sleep(2.4)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/flyin_03_organ_perch.png"])
print("[inspect] Captured flyin_03_organ_perch.png!")

# Stage 4: Settling onto chessboard for Round 1
time.sleep(2.0)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/flyin_04_gameplay_ready.png"])
print("[inspect] Captured flyin_04_gameplay_ready.png!")
