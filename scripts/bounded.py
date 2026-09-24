"""One process group, one hard ten-minute ceiling, no retries."""
import os, signal, subprocess, sys
process = subprocess.Popen(sys.argv[1:], start_new_session=True)
try:
    raise SystemExit(process.wait(timeout=600))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
    print('Stopped at the 600-second stage limit. Remaining validation is unresolved.', flush=True)
    raise SystemExit(124)
