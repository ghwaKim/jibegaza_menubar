"""Remove obsolete testing ZIPs only after the published feed targets this build."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import unquote
import xml.etree.ElementTree as ET

REPO = "ghwaKim/jibegaza_menubar"
ARCHIVE = re.compile(r"Jibegaza-MenuBar-\d+\.\d+-test-build(\d+)\.zip")
SHARE = re.compile(r"Jibegaza\.MenuBar\.v\d+\.\d+\.beta\.zip")


def canonical(name):
    # GitHub replaces spaces and strips parentheses from uploaded asset names.
    return name.replace(" ", ".").replace("(", "").replace(")", "")


def obsolete_assets(release, feed, archive, share):
    if release.get("tagName") != "testing" or not release.get("isPrerelease") or release.get("isDraft"):
        raise ValueError("Cleanup requires the published testing Pre-release")
    current = ARCHIVE.fullmatch(archive)
    if not current or not SHARE.fullmatch(canonical(share)):
        raise ValueError("Unexpected testing archive or shared ZIP name")
    assets = release["assets"]
    names = {asset["name"] for asset in assets if asset.get("state") == "uploaded"}
    if archive not in names or "appcast.xml" not in names or canonical(share) not in {canonical(n) for n in names}:
        raise ValueError("Current archive, shared ZIP and feed must all be uploaded before cleanup")
    enclosures = ET.fromstring(feed).findall("./channel/item/enclosure")
    expected = f"https://github.com/{REPO}/releases/download/testing/{archive}"
    if len(enclosures) != 1 or unquote(enclosures[0].get("url", "")) != expected:
        raise ValueError("Published feed does not point exclusively to the current archive")
    for name in names:
        match = ARCHIVE.fullmatch(name)
        if match and int(match[1]) > int(current[1]):
            raise ValueError("A newer testing archive exists; refusing stale cleanup")
    return sorted(name for name in names if
        (ARCHIVE.fullmatch(name) and name != archive)
        or (SHARE.fullmatch(canonical(name)) and canonical(name) != canonical(share)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    parser.add_argument("share")
    args = parser.parse_args()
    release = json.loads(subprocess.check_output([
        "gh", "release", "view", "testing", "--repo", REPO,
        "--json", "tagName,isPrerelease,isDraft,assets"], text=True))
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "appcast.xml"
        subprocess.run(["gh", "release", "download", "testing", "--repo", REPO,
                        "--pattern", "appcast.xml", "--output", str(path)], check=True)
        obsolete = obsolete_assets(release, path.read_bytes(), args.archive, args.share)
    for name in obsolete:
        print(f"Deleting obsolete testing asset: {name}", flush=True)
        subprocess.run(["gh", "release", "delete-asset", "testing", name,
                        "--repo", REPO, "--yes"], check=True)


if __name__ == "__main__":
    main()
