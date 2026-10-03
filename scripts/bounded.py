"""Run one CI stage in its own process group with a hard ceiling and no retries.

Usage: bounded.py [--limit SECONDS] command ...   (default 600 seconds)
"""
import os, signal, subprocess, sys

args = sys.argv[1:]
limit = 600
if args[:1] == ['--limit']:
    limit, args = int(args[1]), args[2:]
process = subprocess.Popen(args, start_new_session=True)
try:
    raise SystemExit(process.wait(timeout=limit))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
    print(f'Stopped at the {limit}-second stage limit. Remaining validation is unresolved.', flush=True)
    raise SystemExit(124)
