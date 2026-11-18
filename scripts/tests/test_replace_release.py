import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import replace_release
import cleanup_release_assets
from release_config import release_config


class ReplaceReleaseTests(unittest.TestCase):
    def exercise(self, fail_archive=False, immutable=False, tag_changed=False):
        release = {"tag_name": "v1.4", "draft": False, "prerelease": False,
                   "immutable": immutable, "assets": []}
        old_ref = {"object": {"type": "commit", "sha": "old"}}
        calls = []
        ref_reads = 0

        def api(path):
            nonlocal ref_reads
            if path.endswith("/latest"):
                return release
            ref_reads += 1
            return {"object": {"type": "commit", "sha": "changed"}} if tag_changed and ref_reads > 1 else old_ref

        def run(*args):
            calls.append(args)
            if fail_archive:
                raise subprocess.CalledProcessError(1, args)

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "Info.plist"
            source.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.4", "CFBundleVersion": "11",
                "JibegazaReleaseChannel": "stable", "JibegazaReplaceExisting": True}))
            with patch.object(replace_release, "api", side_effect=api), \
                 patch.object(replace_release, "resolve_numbers"), \
                 patch.object(replace_release.subprocess, "check_output", side_effect=["[[]]", "new"]), \
                 patch.object(replace_release, "run", side_effect=run), \
                 patch.object(cleanup_release_assets, "cleanup") as cleanup:
                try:
                    replace_release.replace(root / "Jibegaza.MenuBar.v1.4.zip", root / "appcast.xml", source)
                    cleanup.assert_called_once_with("v1.4", "Jibegaza.MenuBar.v1.4.zip", "11")
                except (ValueError, subprocess.CalledProcessError) as error:
                    cleanup.assert_not_called()
                    return calls, error
        return calls, None

    def test_replacement_uploads_one_installation_zip_before_feed_and_keeps_notes(self):
        self.assertEqual(release_config("1.4", "11", "stable", True)["archive"], "Jibegaza.MenuBar.v1.4.zip")
        calls, error = self.exercise()
        self.assertIsNone(error)
        self.assertTrue(calls[0][3].endswith("Jibegaza.MenuBar.v1.4.zip"))
        self.assertIn("--clobber", calls[0])
        self.assertTrue(calls[2][3].endswith("appcast.xml"))
        self.assertIn("--clobber", calls[2])
        self.assertFalse(any("delete" in c or "delete-asset" in c or "--generate-notes" in c for c in calls))

    def test_archive_failure_does_not_move_tag_or_replace_feed(self):
        calls, error = self.exercise(fail_archive=True)
        self.assertIsNotNone(error)
        self.assertEqual(len(calls), 1)

    def test_immutable_release_is_rejected_before_upload(self):
        calls, error = self.exercise(immutable=True)
        self.assertIsNotNone(error)
        self.assertEqual(calls, [])

    def test_concurrent_tag_change_does_not_replace_feed(self):
        calls, error = self.exercise(tag_changed=True)
        self.assertIsNotNone(error)
        self.assertEqual(len(calls), 1)
