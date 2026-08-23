#!/usr/bin/env python3
"""Validate Android Bridge release metadata and public artifacts."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

VERSION_PATTERN = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
SHA256_PATTERN = re.compile(r"[0-9a-fA-F]{64}\Z")
TOKEN_PATTERN = re.compile(r"\{\{([A-Z_]+)\}\}")


@dataclass(frozen=True, order=True)
class SemanticVersion:
    major: int
    minor: int
    patch: int

    @property
    def text(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    @property
    def code(self) -> int:
        return self.major * 1_000_000 + self.minor * 1_000 + self.patch


def parse_version(value: str) -> SemanticVersion:
    match = VERSION_PATTERN.fullmatch(value)
    if not match:
        raise ValueError("version must be MAJOR.MINOR.PATCH with strict decimal components")
    version = SemanticVersion(*(int(component) for component in match.groups()))
    if version.minor > 999 or version.patch > 999:
        raise ValueError("version minor and patch must be between 0 and 999")
    if not 1 <= version.code <= 2_100_000_000:
        raise ValueError("derived Android version code must be between 1 and 2100000000")
    return version


def read_version(path: Path) -> SemanticVersion:
    try:
        value = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"cannot read version file: {path}") from error
    if not value.endswith("\n") or value.count("\n") != 1:
        raise ValueError("VERSION must contain exactly one line ending in a newline")
    return parse_version(value[:-1])


def artifact_names(version: SemanticVersion, channel: str) -> dict[str, str]:
    if channel not in {"stable", "rolling"}:
        raise ValueError("channel must be stable or rolling")
    label = version.text if channel == "stable" else "latest"
    macos = f"AndroidBridge-{label}-macOS-arm64.dmg"
    android = f"AndroidBridge-{label}-android.apk"
    names = {
        "macos": macos,
        "macosChecksum": f"{macos}.sha256",
        "macosSbom": f"AndroidBridge-{label}-macOS-arm64.cdx.json",
        "android": android,
        "androidChecksum": f"{android}.sha256",
        "androidSbom": f"AndroidBridge-{label}-android.cdx.json",
        "manifest": "release-manifest.json",
    }
    if channel == "stable":
        names.update({
            "macosAlias": "AndroidBridge-macOS-arm64.dmg",
            "macosAliasChecksum": "AndroidBridge-macOS-arm64.dmg.sha256",
            "androidAlias": "AndroidBridge-android.apk",
            "androidAliasChecksum": "AndroidBridge-android.apk.sha256",
        })
    return names


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _normalized_sha256(value: str, field: str) -> str:
    if not SHA256_PATTERN.fullmatch(value):
        raise ValueError(f"{field} must be a 64-digit hexadecimal SHA-256")
    return value.lower()


def _descriptor(path: Path) -> dict[str, object]:
    if not path.is_file() or path.stat().st_size <= 0:
        raise ValueError(f"required artifact is missing or empty: {path.name}")
    return {"name": path.name, "size": path.stat().st_size, "sha256": sha256_file(path)}


def build_manifest(version: SemanticVersion, names: dict[str, str], directory: Path, signer_sha256: str) -> dict[str, object]:
    signer = _normalized_sha256(signer_sha256, "Android signer")
    macos = _descriptor(directory / names["macos"])
    android = _descriptor(directory / names["android"])
    android["signerSha256"] = signer
    return {
        "schemaVersion": 1,
        "version": version.text,
        "versionCode": version.code,
        "minimumMacOS": "13.0",
        "minimumAndroidSdk": 33,
        "macos": macos,
        "android": android,
    }


def _validate_descriptor(value: object, expected_name: str, directory: Path, signer: bool) -> None:
    if not isinstance(value, dict):
        raise ValueError(f"manifest descriptor for {expected_name} must be an object")
    expected_keys = {"name", "size", "sha256"} | ({"signerSha256"} if signer else set())
    if set(value) != expected_keys or value.get("name") != expected_name:
        raise ValueError(f"manifest descriptor is invalid for {expected_name}")
    size = value.get("size")
    digest = value.get("sha256")
    if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
        raise ValueError(f"manifest size is invalid for {expected_name}")
    if not isinstance(digest, str) or digest != _normalized_sha256(digest, "artifact SHA-256"):
        raise ValueError(f"manifest hash is invalid for {expected_name}")
    if signer:
        signer_digest = value.get("signerSha256")
        if not isinstance(signer_digest, str) or signer_digest != _normalized_sha256(signer_digest, "Android signer"):
            raise ValueError("manifest Android signer is invalid")
    artifact = directory / expected_name
    if not artifact.is_file() or artifact.stat().st_size != size or sha256_file(artifact) != digest:
        raise ValueError(f"manifest artifact does not match file: {expected_name}")


def _validate_checksum(path: Path, artifact: Path) -> None:
    expected = f"{sha256_file(artifact)}  {artifact.name}\n"
    if not path.is_file() or path.read_text(encoding="utf-8") != expected:
        raise ValueError(f"checksum is invalid: {path.name}")


def validate_manifest(manifest: dict[str, object], directory: Path) -> None:
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be an object")
    expected_keys = {"schemaVersion", "version", "versionCode", "minimumMacOS", "minimumAndroidSdk", "macos", "android"}
    if set(manifest) != expected_keys or manifest["schemaVersion"] != 1:
        raise ValueError("manifest schema is invalid")
    version_value = manifest["version"]
    if not isinstance(version_value, str):
        raise ValueError("manifest version is invalid")
    version = parse_version(version_value)
    if manifest["versionCode"] != version.code or manifest["minimumMacOS"] != "13.0" or manifest["minimumAndroidSdk"] != 33:
        raise ValueError("manifest version or platform minimum is invalid")
    # The channel is inferred only from exact expected artifact names.
    macos_name = manifest["macos"].get("name") if isinstance(manifest["macos"], dict) else None
    channel = "rolling" if macos_name == artifact_names(version, "rolling")["macos"] else "stable"
    names = artifact_names(version, channel)
    _validate_descriptor(manifest["macos"], names["macos"], directory, False)
    _validate_descriptor(manifest["android"], names["android"], directory, True)
    _validate_checksum(directory / names["macosChecksum"], directory / names["macos"])
    _validate_checksum(directory / names["androidChecksum"], directory / names["android"])
    for key in ("macosSbom", "androidSbom"):
        sbom = directory / names[key]
        if not sbom.is_file():
            raise ValueError(f"required SBOM is missing: {sbom.name}")
        try:
            parsed = json.loads(sbom.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError(f"SBOM is not valid JSON: {sbom.name}") from error
        if not isinstance(parsed, dict):
            raise ValueError(f"SBOM is not a JSON object: {sbom.name}")
        if parsed.get("bomFormat") != "CycloneDX" or not isinstance(parsed.get("specVersion"), str) or not parsed["specVersion"]:
            raise ValueError(f"SBOM is not a CycloneDX document: {sbom.name}")
    if channel == "stable":
        for artifact_key, alias_key, checksum_key in (
            ("macos", "macosAlias", "macosAliasChecksum"),
            ("android", "androidAlias", "androidAliasChecksum"),
        ):
            artifact = directory / names[artifact_key]
            alias = directory / names[alias_key]
            if not alias.is_file() or alias.stat().st_size != artifact.stat().st_size or sha256_file(alias) != sha256_file(artifact):
                raise ValueError(f"stable alias is not byte-identical: {alias.name}")
            _validate_checksum(directory / names[checksum_key], alias)


def write_checksum(path: Path) -> Path:
    output = path.with_name(f"{path.name}.sha256")
    output.write_text(f"{sha256_file(path)}  {path.name}\n", encoding="utf-8")
    return output


def render_notes(template: Path, output: Path, version: SemanticVersion, commit: str, repository: str, channel: str, names: dict[str, str]) -> None:
    if channel not in {"stable", "rolling"} or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) or not re.fullmatch(r"[0-9a-fA-F]{7,64}", commit):
        raise ValueError("notes inputs are invalid")
    base = (
        f"https://github.com/{repository}/releases/latest/download/"
        if channel == "stable"
        else f"https://github.com/{repository}/releases/download/latest-build/"
    )
    macos = names.get("macosAlias", names["macos"])
    android = names.get("androidAlias", names["android"])
    replacements = {
        "VERSION": version.text,
        "COMMIT": commit,
        "CHANNEL": channel,
        "MACOS_URL": f"{base}{macos}",
        "ANDROID_URL": f"{base}{android}",
        "MACOS_CHECKSUM": names.get("macosAliasChecksum", names["macosChecksum"]),
        "ANDROID_CHECKSUM": names.get("androidAliasChecksum", names["androidChecksum"]),
        "MACOS_SBOM": names["macosSbom"],
        "ANDROID_SBOM": names["androidSbom"],
    }
    content = template.read_text(encoding="utf-8")
    unknown = set(TOKEN_PATTERN.findall(content)) - set(replacements)
    if unknown:
        raise ValueError(f"unknown notes token: {sorted(unknown)[0]}")
    content = TOKEN_PATTERN.sub(lambda match: replacements[match.group(1)], content)
    if TOKEN_PATTERN.search(content):
        raise ValueError("release notes contain an unreplaced token")
    output.write_text(content, encoding="utf-8")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="release.py")
    subcommands = parser.add_subparsers(dest="command", required=True)
    version_parser = subcommands.add_parser("version")
    version_parser.add_argument("--root", type=Path, required=True)
    version_parser.add_argument("--check-tag")
    version_parser.add_argument("--field", choices=("version", "code"), default="version")
    for command in ("manifest", "validate"):
        command_parser = subcommands.add_parser(command)
        command_parser.add_argument("--root", type=Path, required=True)
        command_parser.add_argument("--channel", choices=("stable", "rolling"), required=True)
        command_parser.add_argument("--directory", type=Path, required=True)
        command_parser.add_argument("--output" if command == "manifest" else "--manifest", type=Path, required=True)
        if command == "manifest":
            command_parser.add_argument("--android-signer", required=True)
    notes_parser = subcommands.add_parser("notes")
    notes_parser.add_argument("--root", type=Path, required=True)
    notes_parser.add_argument("--channel", choices=("stable", "rolling"), required=True)
    notes_parser.add_argument("--commit", required=True)
    notes_parser.add_argument("--repository", required=True)
    notes_parser.add_argument("--template", type=Path, required=True)
    notes_parser.add_argument("--output", type=Path, required=True)
    checksum_parser = subcommands.add_parser("checksum")
    checksum_parser.add_argument("--path", type=Path, required=True)
    return parser


def _run(arguments: argparse.Namespace) -> None:
    if arguments.command == "checksum":
        print(write_checksum(arguments.path))
        return
    version = read_version(arguments.root / "VERSION")
    if arguments.command == "version":
        if arguments.check_tag is not None and arguments.check_tag != f"v{version.text}":
            raise ValueError("tag must exactly match vVERSION")
        print(version.text if arguments.field == "version" else version.code)
        return
    names = artifact_names(version, arguments.channel)
    if arguments.command == "manifest":
        manifest = build_manifest(version, names, arguments.directory, arguments.android_signer)
        arguments.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    elif arguments.command == "notes":
        render_notes(arguments.template, arguments.output, version, arguments.commit, arguments.repository, arguments.channel, names)
    else:
        manifest = json.loads(arguments.manifest.read_text(encoding="utf-8"))
        if not isinstance(manifest, dict) or manifest.get("version") != version.text:
            raise ValueError("manifest version does not match VERSION")
        macos, android = manifest.get("macos"), manifest.get("android")
        if not isinstance(macos, dict) or not isinstance(android, dict):
            raise ValueError("manifest platform descriptors must be objects")
        if macos.get("name") != names["macos"] or android.get("name") != names["android"]:
            raise ValueError("manifest names do not match channel")
        validate_manifest(manifest, arguments.directory)


def main() -> int:
    try:
        _run(_parser().parse_args())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"release.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
