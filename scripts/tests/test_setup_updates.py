import base64
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS plutil and zsh")
class SetupUpdatesTests(unittest.TestCase):
    def test_initial_setup_repeat_and_replacement_protection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "scripts").mkdir()
            (root / "Resources").mkdir()
            script = root / "scripts/setup_updates.sh"
            shutil.copyfile(SCRIPTS / "setup_updates.sh", script)
            info = root / "Resources/Info.plist"
            info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.jibegaza.menubar"}))
            key = base64.b64encode(bytes(32)).decode()

            def run(value):
                return subprocess.run(["zsh", str(script), value], capture_output=True, text=True)

            self.assertEqual(run(key).returncode, 0)
            self.assertEqual(plistlib.loads(info.read_bytes())["SUPublicEDKey"], key)
            self.assertEqual(run(key).returncode, 0)
            before = info.read_bytes()
            replacement = base64.b64encode(bytes([1]) * 32).decode()
            result = run(replacement)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Refusing to replace", result.stderr)
            self.assertEqual(info.read_bytes(), before)
            self.assertNotEqual(run("invalid-key").returncode, 0)
            self.assertEqual(info.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
