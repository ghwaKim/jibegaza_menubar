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


def resolve_numbers(source, releases, requested_version="", requested_build=""):
    """Use the greatest source/release values; drafts reserve version tags too."""
    previous_version = source["CFBundleShortVersionString"]
    previous_build = int(source["CFBundleVersion"])
    reserved_tags = {release["tag_name"] for release in releases}
    for release in releases:
        tag = release["tag_name"]
        if re.fullmatch(r"v[0-9]+\.[0-9]+", tag):
            if version_tuple(tag[1:]) > version_tuple(previous_version):
                previous_version = tag[1:]
        if release["draft"] or release["prerelease"]:
            continue
        if any(asset["name"] == "appcast.xml" for asset in release["assets"]):
            with tempfile.TemporaryDirectory() as directory:
                subprocess.run(["gh", "release", "download", tag, "--repo", REPOSITORY,
                                "--pattern", "appcast.xml", "--dir", directory], check=True)
                items = ET.parse(pathlib.Path(directory) / "appcast.xml").findall("./channel/item")
                if not items:
                    raise ValueError("Published appcast has no updates")
                namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
                for item in items:
                    old_build = item.findtext(namespace + "version")
                    if old_build is None or not re.fullmatch(r"[1-9][0-9]*", old_build):
                        raise ValueError("Published appcast has an invalid build number")
                    previous_build = max(previous_build, int(old_build))
                    display_version = item.findtext(namespace + "shortVersionString")
                    if display_version and version_tuple(display_version) > version_tuple(previous_version):
                        previous_version = display_version
    major, minor = version_tuple(previous_version)
    version = requested_version.strip() or f"{major}.{minor + 1}"
    build = requested_build.strip() or str(previous_build + 1)
    if f"v{version}" in reserved_tags:
        raise ValueError("This release tag already exists (including drafts)")
    validate_numbers(version, build, previous_version, str(previous_build))
    return version, build


def main():
    source = plistlib.loads(pathlib.Path("Resources/Info.plist").read_bytes())
    repo = api(f"repos/{REPOSITORY}")
    if repo["private"]:
        raise ValueError("Update assets must be publicly downloadable; this workflow expects a public repository")
    pages = json.loads(subprocess.check_output(
        ["gh", "api", "--paginate", "--slurp", f"repos/{REPOSITORY}/releases?per_page=100"], text=True))
    version, build = resolve_numbers(
        source, [release for page in pages for release in page],
        os.environ.get("RELEASE_VERSION", ""), os.environ.get("RELEASE_BUILD_NUMBER", ""))
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a") as output:
            output.write(f"RELEASE_VERSION={version}\nRELEASE_BUILD_NUMBER={build}\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(f"### Release version\n\nv{version} (build {build})\n")
    print(f"Release v{version} (build {build}) passed preflight.")


if __name__ == "__main__":
    main()
