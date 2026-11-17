#!/usr/bin/env python3
"""Try pinned simslim on a disposable device; retain the selected stock fallback."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def warning(message):
    print("::warning::simslim: " + str(message).replace("\n", " "), flush=True)


def command(args, *, timeout=30, env=None, log=True):
    result = subprocess.run(args, env=env, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout, check=False)
    if log and result.stdout:
        print(result.stdout, end="" if result.stdout.endswith("\n") else "\n", flush=True)
    result.check_returncode()
    return result.stdout.strip()


def keep_arguments(help_text):
    # The owner supplies the release later. Discover its advertised interface
    # instead of guessing category names or adding any disabling flags.
    flag = re.search(r"(?m)^\s*(?:-\w,\s*)?(--keep(?:-categories|-category)?)\b[^\n]*", help_text)
    protected = list(dict.fromkeys(re.findall(
        r"\b(?:accessibility|a11y|ax|keyboards?|text[-_]input|textinput|inputs?|"
        r"dictation|autocorrect|spell[-_]?check(?:er)?)\b", help_text.lower())))
    if flag:
        if not protected:
            raise ValueError("--keep categories are not advertised; cannot preserve XCTest input/accessibility")
        # A string list/CSV can preserve several categories in one flag. A
        # singular category interface is safe only with one advertised match.
        if len(protected) > 1 and not re.search(r"strings|comma|csv|\[\]", flag[0], re.I):
            raise ValueError("Unknown --keep list syntax; cannot preserve all XCTest categories")
        return [flag[1], ",".join(protected)]
    if protected or re.search(r"categor", help_text, re.I):
        raise ValueError("No supported --keep flag for advertised XCTest services/categories")
    return []  # No category interface advertised: use defaults, with no extra flags.


def main():
    candidate = None
    accepted = False
    try:
        version = os.environ.get("SIMSLIM_VERSION", "")
        if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
            raise ValueError("Set SIMSLIM_VERSION to an exact release tag before opting in; using stock simulator")
        stock = os.environ["SIM_UDID"]
        github_env = Path(os.environ["GITHUB_ENV"])
        timeout_value = re.fullmatch(r"(\d+)s?", os.environ["SIMSLIM_BOOT_TIMEOUT"])
        if timeout_value is None or int(timeout_value[1]) < 300:
            raise ValueError("SIMSLIM_BOOT_TIMEOUT must allow at least 300s")
        boot_timeout = int(timeout_value[1])
        with tempfile.TemporaryDirectory(prefix="yubai-simslim-") as directory:
            # An isolated GOBIN prevents a stale/unpinned executable being used
            # if installation fails. Go is supplied by the macOS runner.
            install_env = dict(os.environ, GOBIN=directory)
            package = "github.com/mobai-app/simslim/cmd/simslim@" + version
            print("Installing " + package, flush=True)
            command(["go", "install", package], env=install_env, timeout=180)
            simslim = str(Path(directory) / "simslim")
            help_text = command([simslim, "on", "--help"], timeout=15)
            keep = keep_arguments(help_text)
            print("simslim keeps: " + (keep[-1] if keep else "release defaults (no category interface)"), flush=True)
            devices = json.loads(command(["xcrun", "simctl", "list", "devices", "available", "-j"], log=False))["devices"]
            selected = [(runtime, device) for runtime, rows in devices.items()
                        for device in rows if device["udid"] == stock]
            if len(selected) != 1:
                raise ValueError("Selected stock simulator is unavailable")
            runtime, device = selected[0]
            # Never modify the original device. Even a timeout or a partial
            # simslim failure leaves the next step its untouched stock UDID.
            candidate = command(["xcrun", "simctl", "create", "Yubai simslim " + stock[:8],
                                 device["deviceTypeIdentifier"], runtime])
            if not re.fullmatch(r"[0-9a-fA-F-]{36}", candidate):
                raise ValueError("simctl create did not return a simulator UDID")
            command([simslim, "on", *keep, candidate], timeout=boot_timeout + 60)
            # Verification is informational and bounded; it never changes the
            # simulator choice or the test result, including on older releases.
            try:
                command([simslim, "verify", candidate], timeout=20)
            except (OSError, subprocess.SubprocessError) as error:
                warning("verify unavailable (continuing with slimmed simulator): " + str(error))
            with github_env.open("a") as file:
                file.write("SIM_UDID=" + candidate + "\n")
            accepted = True
            print(f"simslim ready: {candidate}; stock fallback {stock} retained", flush=True)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        warning(str(error) + "; continuing with the selected stock simulator")
    finally:
        if candidate and not accepted:
            for action in ["shutdown", "delete"]:
                try:
                    command(["xcrun", "simctl", action, candidate], timeout=30, log=False)
                except (OSError, subprocess.SubprocessError):
                    if action == "delete":
                        warning("Could not delete unused disposable simulator " + candidate)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
