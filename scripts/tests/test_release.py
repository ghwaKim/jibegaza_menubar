import base64
import importlib.util
import json
import os
import pathlib
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPTS = pathlib.Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


numbers = module("check_release")
metadata = module("validate_update")


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        # Tests calling main must not modify the real Actions job's env/summary files.
        environment = patch.dict(os.environ, {"GITHUB_ENV": "", "GITHUB_STEP_SUMMARY": "", "RELEASE_CHANNEL": "stable"})
        environment.start()
        self.addCleanup(environment.stop)

    def test_release_numbers_must_increase(self):
        numbers.validate_numbers("1.10", "10", "1.9", "9")
        for version, build in [("1.9", "10"), ("1.8", "10"), ("1.10", "9"),
                               ("1.10", "0"), ("1.10;bad", "10"), ("01.10", "10")]:
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                numbers.validate_numbers(version, build, "1.9", "9")

    def test_preflight_rejects_existing_releases_and_accepts_first_release(self):
        with patch.dict(os.environ, {"RELEASE_VERSION": "1.4", "RELEASE_BUILD_NUMBER": "5"}), \
             patch.object(numbers, "api", return_value={"private": False}), \
             patch.object(numbers.subprocess, "check_output", return_value="[[]]") as request:
            numbers.main()
            for release in [
                {"tag_name": "v1.4", "draft": True, "prerelease": False, "assets": []},
                {"tag_name": "v1.5", "draft": False, "prerelease": False, "assets": []},
            ]:
                request.return_value = json.dumps([[release]])
                with self.subTest(release=release), self.assertRaises(ValueError):
                    numbers.main()

    def test_preflight_rejects_build_regression_in_published_appcast(self):
        release = {"tag_name": "v1.3", "draft": False, "prerelease": False,
                   "assets": [{"name": "appcast.xml"}]}

        def download(command, **kwargs):
            target = pathlib.Path(command[command.index("--dir") + 1])
            (target / "appcast.xml").write_text(
                '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                '<channel><item><sparkle:version>6</sparkle:version></item></channel></rss>')

        with patch.dict(os.environ, {"RELEASE_VERSION": "1.4", "RELEASE_BUILD_NUMBER": "5"}), \
             patch.object(numbers, "api", return_value={"private": False}), \
             patch.object(numbers.subprocess, "check_output", return_value=json.dumps([[release]])), \
             patch.object(numbers.subprocess, "run", side_effect=download), \
             self.assertRaises(ValueError):
            numbers.main()

    def test_first_release_uses_source_and_allows_partial_overrides(self):
        source = {"CFBundleShortVersionString": "1.3", "CFBundleVersion": "4"}
        self.assertEqual(numbers.resolve_numbers(source, []), ("1.4", "5"))
        self.assertEqual(numbers.resolve_numbers(source, [], "2.0", ""), ("2.0", "5"))
        self.assertEqual(numbers.resolve_numbers(source, [], "", "20"), ("1.4", "20"))
        self.assertEqual(numbers.resolve_numbers(source, [], "  ", "  "), ("1.4", "5"))

    def test_automatic_version_uses_numeric_max_and_reserves_draft_tags(self):
        source = {"CFBundleShortVersionString": "1.3", "CFBundleVersion": "4"}
        releases = [{"tag_name": tag, "draft": draft, "prerelease": False, "assets": []}
                    for tag, draft in [("v1.9", False), ("v1.11", True), ("v1.10", False)]]
        self.assertEqual(numbers.resolve_numbers(source, releases), ("1.12", "5"))
        source["CFBundleShortVersionString"] = "2.0"
        source["CFBundleVersion"] = "50"
        self.assertEqual(numbers.resolve_numbers(source, releases), ("2.1", "51"))

    def test_automatic_build_reads_published_feed_and_rejects_invalid_feed(self):
        source = {"CFBundleShortVersionString": "1.3", "CFBundleVersion": "4"}
        release = {"tag_name": "legacy", "draft": False, "prerelease": False,
                   "assets": [{"name": "appcast.xml"}]}
        feed = ('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                '<channel><item><sparkle:version>42</sparkle:version>'
                '<sparkle:shortVersionString>1.10</sparkle:shortVersionString></item></channel></rss>')

        def download(command, **kwargs):
            target = pathlib.Path(command[command.index("--dir") + 1])
            (target / "appcast.xml").write_text(feed)

        with patch.object(numbers.subprocess, "run", side_effect=download):
            self.assertEqual(numbers.resolve_numbers(source, [release]), ("1.11", "43"))
            with self.assertRaises(ValueError):
                numbers.resolve_numbers(source, [release], "", "42")
            feed = feed.replace("version>42", "version>bad")
            with self.assertRaises(ValueError):
                numbers.resolve_numbers(source, [release])

    def test_main_exports_automatic_numbers_for_later_workflow_steps(self):
        with tempfile.TemporaryDirectory() as directory:
            env_file = pathlib.Path(directory) / "env"
            summary_file = pathlib.Path(directory) / "summary"
            with patch.dict(os.environ, {"RELEASE_VERSION": "", "RELEASE_BUILD_NUMBER": "",
                                        "GITHUB_ENV": str(env_file), "GITHUB_STEP_SUMMARY": str(summary_file)}), \
                 patch.object(numbers, "api", return_value={"private": False}), \
                 patch.object(numbers.subprocess, "check_output", return_value="[[], []]"):
                numbers.main()
            source = plistlib.loads(pathlib.Path("Resources/Info.plist").read_bytes())
            version, build = numbers.resolve_numbers(source, [])
            self.assertEqual(env_file.read_text(), f"RELEASE_VERSION={version}\nRELEASE_BUILD_NUMBER={build}\n")
            self.assertIn(f"v{version} (build {build})", summary_file.read_text())

    def test_testing_channel_keeps_version_and_increments_build(self):
        source = {"CFBundleShortVersionString": "1.3", "CFBundleVersion": "4"}
        release = {"tag_name": "testing", "draft": False, "prerelease": True,
                   "assets": [{"name": "appcast.xml"}]}

        def download(command, **kwargs):
            target = pathlib.Path(command[command.index("--dir") + 1])
            (target / "appcast.xml").write_text(
                '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                '<channel><item><sparkle:version>5</sparkle:version>'
                '<sparkle:shortVersionString>1.4</sparkle:shortVersionString></item></channel></rss>')

        self.assertEqual(numbers.resolve_numbers(source, [], channel="testing"), ("1.4", "5"))
        with patch.object(numbers.subprocess, "run", side_effect=download):
            self.assertEqual(numbers.resolve_numbers(source, [release], channel="testing"), ("1.4", "6"))
            # The final release retains 1.4, and must have a build newer than the test app.
            self.assertEqual(numbers.resolve_numbers(source, [release], channel="stable"), ("1.4", "6"))
            with self.assertRaises(ValueError):
                numbers.resolve_numbers(source, [release], requested_build="5", channel="testing")
            stable = {"tag_name": "v1.4", "draft": False, "prerelease": False, "assets": []}
            self.assertEqual(numbers.resolve_numbers(source, [release, stable], channel="testing"), ("1.5", "6"))

    def test_feed_must_match_exact_bundle_and_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            archive = root / "Jibegaza-MenuBar-1.4.zip"
            source = root / "Info.plist"
            feed = root / "appcast.xml"
            info = {"CFBundleIdentifier": "com.jibegaza.menubar", "CFBundleVersion": "5",
                    "CFBundleShortVersionString": "1.4", "SUPublicEDKey": base64.b64encode(bytes(32)).decode(),
                    "SUFeedURL": "https://github.com/ghwaKim/jibegaza_menubar/releases/latest/download/appcast.xml"}
            source.write_bytes(plistlib.dumps(info))
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("Jibegaza MenuBar.app/Contents/Info.plist", plistlib.dumps(info))
            signature = base64.b64encode(bytes(64)).decode()
            xml = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
                <sparkle:version>5</sparkle:version><enclosure
                url="https://github.com/ghwaKim/jibegaza_menubar/releases/download/v1.4/{archive.name}"
                length="{archive.stat().st_size}" sparkle:edSignature="{signature}"/>
                </item></channel></rss>'''
            feed.write_text(xml)
            self.assertEqual(metadata.validate(archive, feed, source), signature)
            for bad in [xml.replace("version>5", "version>6"),
                        xml.replace("releases/download", "wrong/download"),
                        xml.replace(f'length="{archive.stat().st_size}"', 'length="1"'),
                        xml.replace(signature, "")]:
                feed.write_text(bad)
                with self.subTest(feed=bad), self.assertRaises(ValueError):
                    metadata.validate(archive, feed, source)
            feed.write_text(xml)
            info["SUPublicEDKey"] = base64.b64encode(bytes([1]) * 32).decode()
            source.write_bytes(plistlib.dumps(info))
            with self.assertRaises(ValueError):
                metadata.validate(archive, feed, source)


if __name__ == "__main__":
    unittest.main()
