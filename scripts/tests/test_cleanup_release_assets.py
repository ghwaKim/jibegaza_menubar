import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cleanup", Path(__file__).resolve().parents[1] / "cleanup_release_assets.py")
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class CleanupTests(unittest.TestCase):
    archive = "Jibegaza.MenuBar.v1.4.beta.zip"

    def release(self, *extra):
        return dict(tagName="testing", isPrerelease=True, isDraft=False, assets=[
            dict(name=n, state="uploaded") for n in [self.archive, "appcast.xml", *extra]])

    def feed(self, archive=None, build=7, tag="testing"):
        return f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>{build}</sparkle:version><enclosure url="https://github.com/{cleanup.REPO}/releases/download/{tag}/{archive or self.archive}"/></item></channel></rss>'

    def test_refuses_missing_current_assets_stale_feed_and_newer_build(self):
        missing = self.release()
        missing["assets"] = missing["assets"][1:]
        for release, feed in [
            (missing, self.feed()),
            (self.release(), self.feed("old.zip")),
            (self.release(), self.feed(build=8)),
            (self.release("Jibegaza-MenuBar-1.4-test-build8.zip"), self.feed()),
            ({**self.release(), "isPrerelease": False}, self.feed()),
        ]:
            with self.assertRaises(ValueError):
                cleanup.obsolete_assets(release, feed, "testing", self.archive, 7)

    def test_keeps_current_files_and_unrelated_assets(self):
        old = "Jibegaza-MenuBar-1.4-test-build6.zip"
        self.assertEqual(cleanup.obsolete_assets(self.release(old, "notes.txt", "other.zip"), self.feed(), "testing", self.archive, 7), [old])

    def test_stable_cleanup_removes_legacy_update_zip_only_after_new_feed_is_live(self):
        archive = "Jibegaza.MenuBar.v1.4.zip"
        release = dict(tagName="v1.4", isPrerelease=False, isDraft=False, assets=[
            dict(name=n, state="uploaded") for n in [archive, "appcast.xml",
                "Jibegaza-MenuBar-1.4.zip", "Jibegaza-MenuBar-1.4-build11.zip", "unrelated.zip"]])
        expected = ["Jibegaza-MenuBar-1.4-build11.zip", "Jibegaza-MenuBar-1.4.zip"]
        self.assertEqual(cleanup.obsolete_assets(release, self.feed(archive, 12, "v1.4"), "v1.4", archive, 12), expected)
        with self.assertRaises(ValueError):
            cleanup.obsolete_assets(release, self.feed(archive, 11, "v1.4"), "v1.4", archive, 12)
