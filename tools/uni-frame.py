#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
entry = root / 'vendor/uni-frame/tools/app.py'
if not entry.is_file():
    raise SystemExit('Run git submodule update --init --recursive first')
subprocess.run([sys.executable, str(entry), '--project', str(root), *sys.argv[1:]], check=True)
