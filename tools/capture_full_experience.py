import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"

# 1. Kill old and open fresh
subprocess.run(["pkill", "-f", "Great Hauses Chess"])
time.sleep(0.5)
subprocess.run(["open", "-a", "/Applications/GreatHauses.app"])
time.sleep(2.5)

# 2. Advance through House Select -> Opponent -> Mode -> Start War
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
time.sleep(1.2)

# 3. Capture Symmetric Versus Screen
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/01_versus_screen.png"])
print("[inspect] Captured 01_versus_screen.png!")

# 4. Wait for transition into Cathedral Cinematic Intro
time.sleep(6.2) # Let VS screen charge and transition
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/02_cathedral_exterior_spires.png"])
print("[inspect] Captured 02_cathedral_exterior_spires.png!")

# 5. Nave flight under chandeliers
time.sleep(3.8)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/03_nave_vaulted_flight.png"])
print("[inspect] Captured 03_nave_vaulted_flight.png!")

# 6. Organ Balustrade Perch & Roar
time.sleep(3.0)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/04_organ_loft_perch_roar.png"])
print("[inspect] Captured 04_organ_loft_perch_roar.png!")

# 7. Board arrival & active gameplay
time.sleep(2.5)
subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/05_gameplay_board_ready.png"])
print("[inspect] Captured 05_gameplay_board_ready.png!")
