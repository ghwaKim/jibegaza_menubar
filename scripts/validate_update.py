"""Check the exact bundle, appcast and archive that will be published."""
import base64
import pathlib
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile


def validate(archive, feed, source_plist):
    namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    with zipfile.ZipFile(archive) as bundle:
        info = plistlib.loads(bundle.read("Jibegaza MenuBar.app/Contents/Info.plist"))
    source = plistlib.loads(source_plist.read_bytes())
    for key in ("CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString", "SUPublicEDKey", "SUFeedURL"):
        if not info.get(key) or info[key] != source.get(key):
            raise ValueError(f"Bundle/source mismatch: {key}")
    if len(base64.b64decode(info["SUPublicEDKey"], validate=True)) != 32:
        raise ValueError("Invalid update public key")
    items = ET.parse(feed).findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Expected one update in this release feed")
    item = items[0]
    if item.findtext(namespace + "version") != info["CFBundleVersion"]:
        raise ValueError("Feed build does not match bundle")
    enclosure = item.find("enclosure")
    if enclosure is None or int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("Archive size does not match feed")
    expected_url = ("https://github.com/ghwaKim/jibegaza_menubar/releases/download/v"
                    + info["CFBundleShortVersionString"] + "/" + archive.name)
    if enclosure.get("url") != expected_url:
        raise ValueError("Unexpected update download URL")
    signature = enclosure.get(namespace + "edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Missing or invalid archive signature")
    return signature


if __name__ == "__main__":
    archive, feed, source = map(pathlib.Path, sys.argv[1:])
    signature = validate(archive, feed, source)
    tool = pathlib.Path(__file__).resolve().parent / "verify_update.swift"
    public_key = plistlib.loads(source.read_bytes())["SUPublicEDKey"]
    subprocess.run(["swift", str(tool), str(archive), public_key, signature], check=True)
    print("Update bundle, feed, and embedded public-key signature verified.")
