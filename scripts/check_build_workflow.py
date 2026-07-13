#!/usr/bin/env python3
"""Guard the architecture matrices and release contract in build.yml."""

from pathlib import Path
import re
import sys


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/build.yml"
text = WORKFLOW.read_text(encoding="utf-8")
errors: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def job(name: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [a-zA-Z0-9_-]+:\n|\Z)", text
    )
    require(match is not None, f"missing {name} job")
    return match.group(0) if match else ""


def require_explicit_shells(name: str, block: str, shell: str) -> None:
    steps = re.findall(r"(?ms)^      - .*?(?=^      - |\Z)", block)
    run_steps = [step for step in steps if re.search(r"(?m)^        run:", step)]
    require(bool(run_steps), f"{name} must contain run steps")
    for step in run_steps:
        step_name = re.search(r"(?m)^      - name: (.+)$", step)
        label = step_name.group(1) if step_name else "unnamed step"
        require(
            f"        shell: {shell}\n" in step,
            f"{name} step '{label}' must explicitly use {shell}",
        )


for legacy_job in (
    "build-windows-x64",
    "build-windows-arm64",
    "build-linux-x64",
    "build-linux-arm64",
):
    require(f"  {legacy_job}:\n" not in text, f"legacy job {legacy_job} must stay removed")

windows = job("build-windows")
require("runs-on: ${{ matrix.runner }}" in windows, "Windows must use its matrix runner")
require("fail-fast: false" in windows, "Windows matrix must not cancel its other architecture")
require(
    re.search(
        r"(?ms)          - arch: x64\n"
        r"            runner: windows-latest\n"
        r"            flutter_setup: action\n"
        r"            native_cache_path: build/windows/x64/_deps\n",
        windows,
    )
    is not None,
    "Windows x64 matrix configuration changed",
)
require(
    re.search(
        r"(?ms)          - arch: arm64\n"
        r"            runner: windows-11-arm\n"
        r"            flutter_setup: git\n"
        r"            native_cache_path: \|\n"
        r"              build/windows/arm64/_deps\n"
        r"              build/windows/arm64/mpv-dev-arm64\n",
        windows,
    )
    is not None,
    "Windows arm64 matrix configuration changed",
)
for expected in (
    "if: matrix.flutter_setup == 'action'",
    "if: matrix.flutter_setup == 'git'",
    "git clone --depth 1 --branch 3.44.0",
    "flutter pub get --enforce-lockfile --no-example",
    "--dart-define=SENTRY_DIST=github-windows-${{ matrix.arch }}",
    "--split-debug-info=debug-info/windows-${{ matrix.arch }}",
    "name: windows-${{ matrix.arch }}-build",
    "path: build/windows/${{ matrix.arch }}/runner/Release/",
):
    require(expected in windows, f"Windows matrix missing: {expected}")
require(
    "if: matrix.arch == 'arm64' && steps.windows-native-cache.outputs.cache-hit != 'true'"
    in windows,
    "7-Zip installation must remain ARM-only and cache-aware",
)
require(
    re.search(
        r"(?ms)^    permissions:\n      contents: read\n    strategy:", windows
    )
    is not None,
    "Windows build permissions must remain contents: read",
)
require_explicit_shells("build-windows", windows, "pwsh")

linux = job("build-linux")
require("runs-on: ${{ matrix.runner }}" in linux, "Linux must use its matrix runner")
require("fail-fast: false" in linux, "Linux matrix must not cancel its other architecture")
require(
    re.search(
        r"(?ms)          - arch: x64\n"
        r"            runner: ubuntu-latest\n"
        r"            flutter_channel: stable\n"
        r"            pkg_config_arch: x86_64-linux-gnu\n",
        linux,
    )
    is not None,
    "Linux x64 matrix configuration changed",
)
require(
    re.search(
        r"(?ms)          - arch: arm64\n"
        r"            runner: ubuntu-24.04-arm\n"
        r"            flutter_channel: master\n"
        r"            pkg_config_arch: aarch64-linux-gnu\n",
        linux,
    )
    is not None,
    "Linux arm64 matrix configuration changed",
)
for expected in (
    "channel: ${{ matrix.flutter_channel }}",
    'flutter-version: "3.44.0"',
    "flutter pub get --enforce-lockfile --no-example",
    "lib/${{ matrix.pkg_config_arch }}/pkgconfig",
    "--dart-define=SENTRY_DIST=github-linux-${{ matrix.arch }}",
    "--split-debug-info=debug-info/linux-${{ matrix.arch }}",
    "BUILD_DIR=\"$BUNDLE_DIR\"",
    "ARCH_SUFFIX=${{ matrix.arch }}",
    "name: linux-${{ matrix.arch }}",
):
    require(expected in linux, f"Linux matrix missing: {expected}")
require(
    re.search(
        r"(?ms)^    permissions:\n"
        r"      id-token: write\n"
        r"      attestations: write\n"
        r"      contents: read\n"
        r"    strategy:",
        linux,
    )
    is not None,
    "Linux build attestation permissions changed",
)
require_explicit_shells("build-linux", linux, "bash")

package_windows = job("package-windows")
require("needs: build-windows" in package_windows, "Windows packaging must fan in the matrix")
for artifact in (
    "windows-x64-build",
    "windows-arm64-build",
    "windows-x64-portable",
    "windows-arm64-portable",
    "windows-installer",
):
    require(f"name: {artifact}" in package_windows, f"Windows packaging lost {artifact}")

release = job("create-release")
require(
    "needs: [build-android, build-ios, build-macos, build-windows, package-windows, build-linux]"
    in release,
    "release dependencies must include both architecture matrices and Windows packaging",
)
for artifact in (
    "android-apk",
    "ios-ipa",
    "macos-dmg",
    "windows-x64-portable",
    "windows-arm64-portable",
    "windows-installer",
    "linux-x64",
    "linux-arm64",
):
    require(f"name: {artifact}" in release, f"release download lost {artifact}")

release_if = re.search(r"(?m)^    if: (.+)$", release)
require(release_if is not None, "release job must have an explicit condition")
release_condition = release_if.group(1) if release_if else ""
for build_input in (
    "build_android",
    "build_ios",
    "build_macos",
    "build_windows",
    "build_linux",
):
    require(
        f"&& inputs.{build_input}" in release_condition,
        f"release publication must require {build_input}",
    )

guard_name = "Refuse to overwrite a published release"
require(guard_name in release, "release job must reject published tag reuse")
require(
    'gh api "repos/$GITHUB_REPOSITORY/releases/tags/$VERSION"' in release,
    "published release guard must query the exact version tag",
)
require(
    '"$RELEASE_DRAFT" != "true"' in release,
    "published release guard must allow only draft releases",
)
require(
    "HTTP 404" in release and "Failed to check whether release" in release,
    "published release guard must distinguish missing releases and fail closed",
)
guard_position = release.find(guard_name)
download_position = release.find("Download Android artifacts")
require(
    guard_position >= 0 and download_position >= 0 and guard_position < download_position,
    "published release guard must run before artifact downloads",
)
require(
    "tag_name: ${{ steps.version.outputs.version }}" in release,
    "release must explicitly use the pubspec version as its tag",
)

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)

print("build workflow architecture matrix checks passed")
