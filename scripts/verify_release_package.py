"""Build and verify real release archives offline using a public RFC 8032 test key.

Never reads production signing keys, modifies the real plist or publishes anything.
Both PR and release CI run this so packaging/signature failures block PR checks.
"""
import base64
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def verify():
    with tempfile.TemporaryDirectory(prefix="jibegaza-package-check-") as directory:
        workspace = Path(directory) / "repo"
        workspace.mkdir()
        for name in ("scripts", "Sources", "Tests", "Resources", "Assets"):
            shutil.copytree(ROOT / name, workspace / name, ignore=shutil.ignore_patterns("__pycache__"))
        for name in ("Package.swift", "Package.resolved"):
            shutil.copy(ROOT / name, workspace / name)
        # Reuse downloaded dependencies, but not compiler outputs tied to source paths.
        # Never share a mutable build database with the developer's working copy.
        build_cache = workspace / ".build"
        build_cache.mkdir()
        for name in ("artifacts", "checkouts", "repositories"):
            if (ROOT / ".build" / name).exists():
                shutil.copytree(ROOT / ".build" / name, build_cache / name, symlinks=True)
        state = ROOT / ".build/workspace-state.json"
        if state.exists():
            (build_cache / state.name).write_text(state.read_text().replace(str(ROOT / ".build"), str(build_cache)))
        source = workspace / "Resources/Info.plist"
        info = plistlib.loads(source.read_bytes())
        # RFC 8032 section 7.1, test vector 1: intentionally public, never a release key.
        seed = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
        public = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        private_file = Path(directory) / "test-key"
        private_file.write_bytes(base64.b64encode(seed))
        private_file.chmod(0o600)
        info["SUPublicEDKey"] = base64.b64encode(public).decode()
        major, minor = map(int, info["CFBundleShortVersionString"].split("."))
        base_build = int(info["CFBundleVersion"])
        base = plistlib.dumps(info)
        for channel, replacement in (("stable", False), ("testing", False), ("stable", True)):
            source.write_bytes(base)
            version = info["CFBundleShortVersionString"] if replacement else f"{major}.{minor + 1}"
            env = dict(os.environ, RELEASE_CHANNEL=channel, RELEASE_VERSION=version,
                       RELEASE_BUILD_NUMBER=str(base_build + 1),
                       RELEASE_REPLACE_EXISTING=str(replacement).lower(),
                       SPARKLE_PRIVATE_KEY_FILE=str(private_file))
            # Isolate generate_appcast's cache between modes (same build, different channel).
            updates = workspace / "dist/updates"
            if updates.exists():
                shutil.rmtree(updates)
            subprocess.run(["zsh", "scripts/build_app.sh", "--release"], cwd=workspace, env=env, check=True)
            generated = plistlib.loads(source.read_bytes())
            archive = generated["JibegazaUpdateArchive"]
            update_directory = updates / str(base_build + 1)
            zips = list(update_directory.glob("*.zip"))
            if [p.name for p in zips] != [archive]:
                raise ValueError("Expected one combined release ZIP")
            shared = workspace / "dist" / archive
            digest = lambda p: hashlib.sha256(p.read_bytes()).digest()
            if digest(shared) != digest(zips[0]):
                raise ValueError("Direct installation and Sparkle archives must be identical")
            print(f"Verified {channel}, replacement={replacement}: app + guide ZIP and signed feed", flush=True)


if __name__ == "__main__":
    verify()
