#!/usr/bin/env python3
"""Regression tests for native GPS compiler environment selection.

Dependencies:
- Executes tools/build_native_gps.sh in a temporary repository layout.
- Uses fake uname/xcrun/compiler commands; does not require Xcode or mutate host settings.
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "tools" / "build_native_gps.sh"


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _run_build(*, platform: str, sdkroot: Path, resolved_sdk: Path) -> tuple[list[str], str]:
    with tempfile.TemporaryDirectory(prefix="brur-native-env-") as temp_dir:
        temp = Path(temp_dir)
        repo = temp / "repo"
        tools = repo / "tools"
        native = repo / "native"
        fake_bin = temp / "fake-bin"
        tools.mkdir(parents=True)
        native.mkdir()
        fake_bin.mkdir()
        shutil.copy2(BUILD_SCRIPT, tools / "build_native_gps.sh")

        for name in (
            "gps_core.cpp",
            "gps_runtime.cpp",
            "gps_route_cli.cpp",
            "gps_route_server.cpp",
            "gps_search_server.cpp",
        ):
            (native / name).write_text("// fixture\n", encoding="utf-8")

        log = temp / "compiler.log"
        xcrun_log = temp / "xcrun.log"

        _write_executable(fake_bin / "uname", f"#!/bin/sh\nprintf '%s\\n' '{platform}'\n")
        _write_executable(
            fake_bin / "xcrun",
            "#!/bin/sh\n"
            "printf 'called\\n' >> \"$XCRUN_LOG\"\n"
            "printf '%s\\n' \"$RESOLVED_SDK\"\n",
        )
        _write_executable(
            fake_bin / "fake-cxx",
            "#!/bin/sh\n"
            "printf '%s\\n' \"${SDKROOT:-}\" >> \"$COMPILER_LOG\"\n"
            "out=''\n"
            "prev=''\n"
            "for arg in \"$@\"; do\n"
            "  if [ \"$prev\" = '-o' ]; then out=\"$arg\"; fi\n"
            "  prev=\"$arg\"\n"
            "done\n"
            "[ -z \"$out\" ] || : > \"$out\"\n",
        )

        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{fake_bin}:{env['PATH']}",
                "CXX": "fake-cxx",
                "SDKROOT": str(sdkroot),
                "RESOLVED_SDK": str(resolved_sdk),
                "COMPILER_LOG": str(log),
                "XCRUN_LOG": str(xcrun_log),
            }
        )
        completed = subprocess.run(
            ["/bin/bash", str(tools / "build_native_gps.sh")],
            cwd=repo,
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        compiler_sdkroots = log.read_text(encoding="utf-8").splitlines()
        xcrun_calls = xcrun_log.read_text(encoding="utf-8") if xcrun_log.exists() else ""
        return compiler_sdkroots, xcrun_calls + completed.stdout


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="brur-native-sdk-") as temp_dir:
        temp = Path(temp_dir)
        valid_sdk = temp / "valid-sdk"
        valid_sdk.mkdir()
        stale_sdk = temp / "removed-xcode-sdk"

        compiler_sdkroots, evidence = _run_build(
            platform="Darwin",
            sdkroot=stale_sdk,
            resolved_sdk=valid_sdk,
        )
        assert compiler_sdkroots == [str(valid_sdk)] * 4
        assert "called" in evidence
        assert "replacing stale SDKROOT" in evidence

        explicit_sdk = temp / "explicit-sdk"
        explicit_sdk.mkdir()
        compiler_sdkroots, evidence = _run_build(
            platform="Darwin",
            sdkroot=explicit_sdk,
            resolved_sdk=valid_sdk,
        )
        assert compiler_sdkroots == [str(explicit_sdk)] * 4
        assert "called" not in evidence
        assert "replacing stale SDKROOT" not in evidence

        compiler_sdkroots, evidence = _run_build(
            platform="Linux",
            sdkroot=stale_sdk,
            resolved_sdk=valid_sdk,
        )
        assert compiler_sdkroots == [str(stale_sdk)] * 4
        assert "called" not in evidence
        assert "replacing stale SDKROOT" not in evidence

    print("Native GPS build environment tests: OK")


if __name__ == "__main__":
    main()
