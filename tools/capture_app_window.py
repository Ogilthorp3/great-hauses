import subprocess
import time

ARTIFACTS_DIR = "/Users/bert/.gemini/antigravity-cli/brain/dc426532-efa9-4364-92c2-5a53db738eb2/inspection"

# Activate Great Hauses
subprocess.run(["osascript", "-e", 'tell application id "haus.sanctum.greathauses" to activate'])
time.sleep(0.5)

subprocess.run(["screencapture", "-x", f"{ARTIFACTS_DIR}/symmetric_versus_screen.png"])
print("[inspect] Captured frontmost window to symmetric_versus_screen.png!")
