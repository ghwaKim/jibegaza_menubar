"""Shared stable/testing release locations. The testing tag is a persistent feed endpoint."""
REPOSITORY = "ghwaKim/jibegaza_menubar"
TESTING_TAG = "testing"
BASE_URL = f"https://github.com/{REPOSITORY}/releases"


def release_config(version, build, channel):
    if channel not in ("stable", "testing"):
        raise ValueError("Release channel must be stable or testing")
    testing = channel == "testing"
    return {
        "tag": TESTING_TAG if testing else f"v{version}",
        "archive": f"Jibegaza-MenuBar-{version}" + (f"-test-build{build}" if testing else "") + ".zip",
        "feed": f"{BASE_URL}/download/{TESTING_TAG}/appcast.xml" if testing else f"{BASE_URL}/latest/download/appcast.xml",
    }


def display_label(version, channel, build_mode):
    if channel not in ("stable", "testing") or build_mode not in ("test", "release"):
        raise ValueError("Invalid channel or build mode")
    if build_mode == "test":
        return "(Local beta)"
    return f"v{version}" + (" (beta)" if channel == "testing" else "")
