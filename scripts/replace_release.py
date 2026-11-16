"""Replace the latest stable build, retaining its release URL, notes and old update ZIPs."""
import json
import pathlib
import plistlib
import subprocess
import sys

from check_release import REPOSITORY, api, resolve_numbers


def run(*args):
    subprocess.run(["gh", *args], check=True)


def replace(archive, feed, shared_archive, source):
    info = plistlib.loads(source.read_bytes())
    if info.get("JibegazaReleaseChannel") != "stable" or not info.get("JibegazaReplaceExisting"):
        raise ValueError("Expected a stable replacement bundle")
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    tag = f"v{version}"
    release = api(f"repos/{REPOSITORY}/releases/latest")
    if release["tag_name"] != tag or release.get("immutable") or release["draft"] or release["prerelease"]:
        raise ValueError("Only the mutable latest published stable release can be replaced")
    pages = json.loads(subprocess.check_output(
        ["gh", "api", "--paginate", "--slurp", f"repos/{REPOSITORY}/releases?per_page=100"], text=True))
    # The generated bundle already contains the new build. Compare against remote builds,
    # rather than treating this bundle's own build as a previously published build.
    resolve_numbers({"CFBundleShortVersionString": version, "CFBundleVersion": "0"},
                    [r for page in pages for r in page], version, build, "stable", True)
    ref_path = f"repos/{REPOSITORY}/git/refs/tags/{tag}"
    old_ref = api(ref_path)
    if old_ref["object"]["type"] != "commit":
        raise ValueError("Replacement requires a lightweight tag")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if any(a["name"] == archive.name for a in release["assets"]):
        raise ValueError("This build archive already exists; use a new build number")

    # A unique archive keeps the old signed feed usable throughout upload and after
    # replacement (clients may have cached that feed). Never remove old update ZIPs.
    run("release", "upload", tag, str(archive), "--repo", REPOSITORY)
    run("release", "upload", tag, str(shared_archive), "--repo", REPOSITORY, "--clobber")
    if api(ref_path)["object"] != old_ref["object"]:
        raise ValueError("Release tag changed during upload; refusing to move it")
    run("api", "--method", "PATCH", ref_path, "-f", f"sha={commit}", "-F", "force=true")
    run("release", "upload", tag, str(feed), "--repo", REPOSITORY, "--clobber")
    # Do not regenerate the maintainer's release title or notes.
    run("release", "edit", tag, "--repo", REPOSITORY, "--target", commit, "--latest")


if __name__ == "__main__":
    replace(*map(pathlib.Path, sys.argv[1:]))
