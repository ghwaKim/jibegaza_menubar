"""Preflight for a manually requested Actions release. Never reads signing secrets."""
import json
import os
import pathlib
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

REPOSITORY = "ghwaKim/jibegaza_menubar"


def version_tuple(value):
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", value):
        raise ValueError("Version must be major.minor (for example, 1.4)")
    return tuple(map(int, value.split(".")))


def validate_numbers(version, build, previous_version, previous_build):
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("Build number must be a positive integer")
    if version_tuple(version) <= version_tuple(previous_version):
        raise ValueError("Version must exceed the previous version")
    if int(build) <= int(previous_build):
        raise ValueError("Build number must exceed the previous build")


def api(path):
    return json.loads(subprocess.check_output(["gh", "api", path], text=True))


def main():
    version = os.environ["RELEASE_VERSION"]
    build = os.environ["RELEASE_BUILD_NUMBER"]
    source = plistlib.loads(pathlib.Path("Resources/Info.plist").read_bytes())
    validate_numbers(version, build, source["CFBundleShortVersionString"], source["CFBundleVersion"])
    repo = api(f"repos/{REPOSITORY}")
    if repo["private"]:
        raise ValueError("Update assets must be publicly downloadable; this workflow expects a public repository")
    releases = json.loads(subprocess.check_output(
        ["gh", "api", "--paginate", "--slurp", f"repos/{REPOSITORY}/releases?per_page=100"], text=True))
    for page in releases:
        for release in page:
            if release["tag_name"] == f"v{version}":
                raise ValueError("This release tag already exists (including drafts)")
            if release["draft"] or release["prerelease"]:
                continue
            tag = release["tag_name"]
            if re.fullmatch(r"v[0-9]+\.[0-9]+", tag) and version_tuple(version) <= version_tuple(tag[1:]):
                raise ValueError(f"Version must exceed published release {tag}")
            # Check build numbers too, including releases with nonstandard tag names.
            if any(asset["name"] == "appcast.xml" for asset in release["assets"]):
                with tempfile.TemporaryDirectory() as directory:
                    subprocess.run(["gh", "release", "download", tag, "--repo", REPOSITORY,
                                    "--pattern", "appcast.xml", "--dir", directory], check=True)
                    for item in ET.parse(pathlib.Path(directory) / "appcast.xml").findall("./channel/item"):
                        old_build = item.findtext("{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
                        if old_build is None or not old_build.isdecimal():
                            raise ValueError("Published appcast has an invalid build number")
                        if int(build) <= int(old_build):
                            raise ValueError("Build number must exceed all published update builds")
    print(f"Release v{version} (build {build}) passed preflight.")


if __name__ == "__main__":
    main()
