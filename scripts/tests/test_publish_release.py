"""Exercise publication commands offline: no GitHub requests or private keys."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_config", SCRIPTS / "release_config.py")
config_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config_module)


class PublishReleaseTests(unittest.TestCase):
    def test_header_and_shared_filename_labels(self):
        self.assertEqual(config_module.display_label("1.3", "stable", "test"), "(Local beta)")
        self.assertEqual(config_module.display_label("1.4", "testing", "test"), "(Local beta)")
        self.assertEqual(config_module.display_label("1.4", "testing", "release"), "v1.4 (beta)")
        self.assertEqual(config_module.display_label("1.5", "testing", "release"), "v1.5 (beta)")
        self.assertEqual(config_module.display_label("1.4", "stable", "release"), "v1.4")


    def publish(self, channel, exists=False, status="true"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Resources").mkdir()
            (root / "scripts").mkdir()
            for name in ("publish_release.sh", "validate_update.py", "release_config.py", "verify_update.swift"):
                shutil.copy(SCRIPTS / name, root / "scripts" / name)
            config = config_module.release_config("1.4", "5", channel)
            info = {"CFBundleIdentifier": "com.jibegaza.menubar", "CFBundleShortVersionString": "1.4",
                    "CFBundleVersion": "5", "SUFeedURL": config["feed"],
                    "SUPublicEDKey": base64.b64encode(bytes(32)).decode(),
                    "JibegazaReleaseChannel": channel, "JibegazaReleaseTag": config["tag"],
                    "JibegazaUpdateArchive": config["archive"],
                    "JibegazaDisplayVersion": config_module.display_label("1.4", channel, "release")}
            (root / "Resources/Info.plist").write_bytes(plistlib.dumps(info))
            output = root / "dist/updates/5"
            output.mkdir(parents=True)
            archive = output / config["archive"]
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("Jibegaza MenuBar.app/Contents/Info.plist", plistlib.dumps(info))
            shutil.copy(archive, root / "dist" / f"Jibegaza MenuBar {info['JibegazaDisplayVersion']}.zip")
            signature = base64.b64encode(bytes(64)).decode()
            (output / "appcast.xml").write_text(
                '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
                '<sparkle:version>5</sparkle:version>'
                f'<enclosure url="{config_module.BASE_URL}/download/{config["tag"]}/{archive.name}" '
                f'length="{archive.stat().st_size}" sparkle:edSignature="{signature}"/>'
                '</item></channel></rss>')
            binaries = root / "bin"
            binaries.mkdir()
            log = root / "commands"
            (binaries / "gh").write_text(f'#!{sys.executable}\n' + '''import json, os, sys
with open(os.environ["COMMAND_LOG"], "a") as f: f.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1:3] == ["release", "view"]:
    if os.environ["EXISTS"] == "0": sys.exit(1)
    if "--json" in sys.argv: print(os.environ["RELEASE_STATUS"])
''')
            # Signature cryptography is tested separately; these stubs isolate command routing.
            (binaries / "swift").write_text('#!/bin/sh\nexit 0\n')
            (binaries / "git").write_text('#!/bin/sh\necho 1234567890abcdef\n')
            for binary in binaries.iterdir():
                binary.chmod(0o700)
            env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ["PATH"],
                       COMMAND_LOG=str(log), EXISTS="1" if exists else "0", RELEASE_STATUS=status)
            result = subprocess.run(["zsh", str(root / "scripts/publish_release.sh")],
                                    env=env, text=True, capture_output=True)
            commands = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, commands

    def test_first_testing_release_is_prerelease_and_never_latest(self):
        result, commands = self.publish("testing")
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(command for command in commands if command[:2] == ["release", "create"])
        self.assertEqual(create[2], "testing")
        self.assertIn("--prerelease", create)
        for command in commands:
            if command[:2] in (["release", "create"], ["release", "edit"]):
                self.assertIn("--latest=false", command)
                self.assertNotIn("--latest", command)

    def test_existing_testing_release_uploads_archive_before_switching_feed(self):
        result, commands = self.publish("testing", exists=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        uploads = [command for command in commands if command[:2] == ["release", "upload"]]
        self.assertEqual(len(uploads), 3)
        self.assertTrue(uploads[0][3].endswith("-test-build5.zip"))
        self.assertNotIn("--clobber", uploads[0])
        self.assertTrue(uploads[1][3].endswith("Jibegaza MenuBar v1.4 (beta).zip"))
        self.assertTrue(uploads[2][3].endswith("appcast.xml"))
        self.assertIn("--clobber", uploads[2])

    def test_testing_refuses_to_modify_a_non_prerelease(self):
        result, commands = self.publish("testing", exists=True, status="false")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(command[:2] == ["release", "upload"] for command in commands))

    def test_stable_release_is_published_as_latest(self):
        result, commands = self.publish("stable")
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(command for command in commands if command[:2] == ["release", "create"])
        self.assertEqual(create[2], "v1.4")
        self.assertTrue(any(value.endswith("Jibegaza MenuBar v1.4.zip") for value in create))
        self.assertNotIn("--prerelease", create)
        self.assertIn("--latest", commands[-1])
