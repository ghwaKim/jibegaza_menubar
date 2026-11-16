import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cleanup", Path(__file__).resolve().parents[1] / "cleanup_testing_assets.py")
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class CleanupTests(unittest.TestCase):
    archive = "Jibegaza-MenuBar-1.4-test-build7.zip"
    share = "Jibegaza MenuBar v1.4 (beta).zip"

    def release(self, *extra):
        return dict(tagName="testing", isPrerelease=True, isDraft=False, assets=[
            dict(name=n, state="uploaded") for n in [self.archive, cleanup.canonical(self.share), "appcast.xml", *extra]])

    def feed(self, archive=None):
        return f'<rss><channel><item><enclosure url="https://github.com/{cleanup.REPO}/releases/download/testing/{archive or self.archive}"/></item></channel></rss>'

    def test_refuses_missing_current_assets_stale_feed_and_newer_build(self):
        missing = self.release()
        missing["assets"] = missing["assets"][1:]
        for release, feed in [
            (missing, self.feed()),
            (self.release(), self.feed("old.zip")),
            (self.release("Jibegaza-MenuBar-1.4-test-build8.zip"), self.feed()),
            ({**self.release(), "isPrerelease": False}, self.feed()),
        ]:
            with self.assertRaises(ValueError):
                cleanup.obsolete_assets(release, feed, self.archive, self.share)

    def test_keeps_current_files_and_unrelated_assets(self):
        old = "Jibegaza-MenuBar-1.4-test-build6.zip"
        self.assertEqual(cleanup.obsolete_assets(self.release(old, "notes.txt", "other.zip"), self.feed(), self.archive, self.share), [old])
