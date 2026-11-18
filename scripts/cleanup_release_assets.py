"""Keep one installation ZIP after verifying the published feed and build."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import unquote
import xml.etree.ElementTree as ET

REPO = "ghwaKim/jibegaza_menubar"
ARCHIVE = re.compile(r"Jibegaza-MenuBar-(\d+\.\d+)(?:-(test-)?build(\d+))?\.zip")
SHARE = re.compile(r"Jibegaza\.MenuBar\.v(\d+\.\d+)(\.beta)?\.zip")


def canonical(name):
    # GitHub replaces spaces and strips parentheses from uploaded asset names.
    return name.replace(" ", ".").replace("(", "").replace(")", "")


def obsolete_assets(release, feed, tag, archive, build):
    testing = tag == "testing"
    if (release.get("tagName") != tag or bool(release.get("isPrerelease")) != testing
            or release.get("isDraft")):
        raise ValueError("Cleanup requires the intended published release")
    current = SHARE.fullmatch(archive)
    if (not current or bool(current[2]) != testing
            or (not testing and tag != f"v{current[1]}")):
        raise ValueError("Unexpected installation ZIP name")
    assets = release["assets"]
    names = {asset["name"] for asset in assets if asset.get("state") == "uploaded"}
    if archive not in names or "appcast.xml" not in names:
        raise ValueError("Current installation ZIP and feed must be uploaded before cleanup")
    items = ET.fromstring(feed).findall("./channel/item")
    enclosures = ET.fromstring(feed).findall("./channel/item/enclosure")
    expected = f"https://github.com/{REPO}/releases/download/{tag}/{archive}"
    namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    if (len(items) != 1 or items[0].findtext(namespace + "version") != str(build)
            or len(enclosures) != 1 or unquote(enclosures[0].get("url", "")) != expected):
        raise ValueError("Published feed does not point exclusively to the current archive")
    for name in names:
        match = ARCHIVE.fullmatch(name)
        if match and match[3] and int(match[3]) > int(build):
            raise ValueError("A newer archive exists; refusing stale cleanup")
    def belongs(name):
        match = ARCHIVE.fullmatch(name) or SHARE.fullmatch(canonical(name))
        return match and (testing or match[1] == current[1])
    return sorted(name for name in names if name != archive and belongs(name))


def cleanup(tag, archive, build):
    release = json.loads(subprocess.check_output([
        "gh", "release", "view", tag, "--repo", REPO,
        "--json", "tagName,isPrerelease,isDraft,assets"], text=True))
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "appcast.xml"
        subprocess.run(["gh", "release", "download", tag, "--repo", REPO,
                        "--pattern", "appcast.xml", "--output", str(path)], check=True)
        obsolete = obsolete_assets(release, path.read_bytes(), tag, archive, build)
    for name in obsolete:
        print(f"Deleting obsolete release asset: {name}", flush=True)
        subprocess.run(["gh", "release", "delete-asset", tag, name,
                        "--repo", REPO, "--yes"], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("archive")
    parser.add_argument("build")
    args = parser.parse_args()
    cleanup(args.tag, args.archive, args.build)
