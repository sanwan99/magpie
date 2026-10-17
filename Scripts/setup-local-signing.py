#!/usr/bin/env python3
"""Create one local signing identity, or verify it without changing the keychain."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile

NAME = "Magpie Local Development"
STATE = Path.home() / "Library/Application Support/Magpie/Signing/identity.json"


def run(*args, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True)


def verify(state):
    fingerprint = state["sha1"]
    if not re.fullmatch(r"[A-F0-9]{40}", fingerprint):
        raise RuntimeError("Invalid local signing identity metadata")
    identities = run("/usr/bin/security", "find-identity", "-v", "-p", "codesigning", state["keychain"]).stdout
    if not re.search(rf'\b{fingerprint}\s+"{re.escape(NAME)}"', identities):
        raise RuntimeError("Magpie signing identity is unavailable. Restore/unlock its keychain; do not replace it with an ad-hoc identity.")
    print(f"Signing identity ready: {NAME} ({fingerprint})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--create", action="store_true", help="Explicitly create a new local identity in the login keychain")
    args = parser.parse_args()
    if STATE.exists():
        verify(json.loads(STATE.read_text()))
        return
    if not args.create:
        raise RuntimeError("No optional local identity is configured. Default ad-hoc builds need none; use --create only if you want a stable personal identity.")
    keychain = run("/usr/bin/security", "default-keychain", "-d", "user").stdout.strip().strip('"')
    if not keychain.endswith("/login.keychain-db"):
        raise RuntimeError("Expected the user login keychain; no keychain changes made.")
    existing = run("/usr/bin/security", "find-certificate", "-c", NAME, keychain, check=False)
    if existing.returncode == 0:
        raise RuntimeError("A matching certificate already exists but metadata is missing; inspect it before creating another identity.")
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="magpie-signing-") as directory:
        root = Path(directory)
        config = root / "certificate.conf"
        config.write_text(f'''[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = {NAME}
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
''')
        key, cert, bundle = root / "key.pem", root / "certificate.pem", root / "identity.p12"
        run("/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256", "-nodes", "-days", "3650",
            "-config", str(config), "-keyout", str(key), "-out", str(cert))
        password = secrets.token_hex(24)
        password_file = root / "export-password"
        password_file.write_text(password)
        run("/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(cert),
            "-name", NAME, "-out", str(bundle), "-passout", "file:" + str(password_file))
        # Temporary key material is mode 0600 and removed after import. The key is non-extractable;
        # only Apple's codesign executable is pre-authorized to use this newly imported key.
        run("/usr/bin/security", "import", str(bundle), "-k", keychain, "-f", "pkcs12", "-P", password, "-x", "-T", "/usr/bin/codesign")
        # Trust this certificate for code signing in the user domain only, not TLS or system roots.
        run("/usr/bin/security", "add-trusted-cert", "-r", "trustRoot", "-p", "codeSign", "-k", keychain, str(cert))
        fingerprint = run("/usr/bin/openssl", "x509", "-in", str(cert), "-noout", "-fingerprint", "-sha1").stdout.split("=", 1)[1].strip().replace(":", "")
        state = {"name": NAME, "sha1": fingerprint, "keychain": keychain}
        STATE.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        STATE.write_text(json.dumps(state, indent=2) + "\n")
        STATE.chmod(0o600)
        verify(state)
        print(f"Identity metadata: {STATE}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit((error.stderr or error.stdout or "Signing setup failed").strip())
    except (RuntimeError, KeyError, ValueError) as error:
        raise SystemExit(str(error))
