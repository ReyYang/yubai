#!/usr/bin/env python3
"""Run one selected shard with a process deadline and an explicit exit marker."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys


def main() -> int:
    selectors = json.loads(os.environ["YUBAI_TEST_SELECTORS"])
    if not selectors or any("ScreenGalleryTests" in item or not item.startswith(("YubaiCoreTests", "YubaiUITests/")) for item in selectors):
        raise ValueError("A tests shard needs explicit non-gallery selectors")
    build = Path("build")
    build.mkdir(exist_ok=True)
    (build / "test-exit-status").unlink(missing_ok=True)
    command = ["xcodebuild", "-project", "Yubai.xcodeproj", "-scheme", "Yubai", "-configuration", "Debug",
               "-destination", "id=" + os.environ["SIM_UDID"], "-parallel-testing-enabled", "NO",
               "-resultBundlePath", "build/Yubai.xcresult", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO",
               "test", *("-only-testing:" + item for item in selectors)]
    with (build / "xcodebuild-test.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            status = process.wait(timeout=30 * 60)
        except subprocess.TimeoutExpired:
            print("Shard exceeded 30 minutes; terminating xcodebuild.", file=sys.stderr)
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            status = 124
    (build / "test-exit-status").write_text(str(status))
    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    sys.exit(main())
