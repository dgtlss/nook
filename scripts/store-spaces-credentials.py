"""Interactively store a bucket-scoped publishing key without echoing secrets."""
import getpass
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
key = getpass.getpass('Spaces access key ID (hidden): ')
secret = getpass.getpass('Spaces secret access key (hidden): ')
if not key.strip() or not secret.strip():
    raise SystemExit('Both values are required; nothing was saved.')
subprocess.run(['/usr/bin/swift', str(root / 'tools/spaces-keychain.swift'), 'store'],
               input=json.dumps(dict(accessKeyId=key.strip(), secretAccessKey=secret.strip())),
               text=True, check=True)
