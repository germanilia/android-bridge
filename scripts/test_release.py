from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts import release

ROOT = Path(__file__).resolve().parents[1]


class ReleaseVersionTests(unittest.TestCase):
    def test_version_code_and_numeric_components(self) -> None:
        self.assertEqual(release.parse_version("0.1.0").code, 1000)
        self.assertLess(release.parse_version("1.2.3"), release.parse_version("1.10.0"))
        self.assertEqual(release.parse_version("2100.0.0").code, 2_100_000_000)

    def test_invalid_versions_and_file_shape(self) -> None:
        for value in ("0.0.0", "01.0.0", "1.1000.0", "1.0.1000", "1.0", "v1.0.0", "1.0.0 "):
            with self.assertRaises(ValueError, msg=value):
                release.parse_version(value)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "VERSION"
            path.write_text("0.1.0\nextra\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                release.read_version(path)


class ReleaseArtifactTests(unittest.TestCase):
    def _release_set(self, channel: str) -> tuple[Path, release.SemanticVersion, dict[str, str]]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        version = release.parse_version("0.1.0")
        names = release.artifact_names(version, channel)
        (directory / names["macos"]).write_bytes(b"dmg bytes")
        (directory / names["android"]).write_bytes(b"apk bytes")
        for key in ("macosSbom", "androidSbom"):
            (directory / names[key]).write_text('{"bomFormat":"CycloneDX","specVersion":"1.5"}', encoding="utf-8")
        release.write_checksum(directory / names["macos"])
        release.write_checksum(directory / names["android"])
        if channel == "stable":
            for source_key, alias_key in (("macos", "macosAlias"), ("android", "androidAlias")):
                (directory / names[alias_key]).write_bytes((directory / names[source_key]).read_bytes())
                release.write_checksum(directory / names[alias_key])
        return directory, version, names

    def test_names_and_checksum_format(self) -> None:
        version = release.parse_version("0.1.0")
        self.assertEqual(release.artifact_names(version, "rolling")["macos"], "AndroidBridge-latest-macOS-arm64.dmg")
        stable = release.artifact_names(version, "stable")
        self.assertEqual(stable["android"], "AndroidBridge-0.1.0-android.apk")
        self.assertEqual(stable["androidAlias"], "AndroidBridge-android.apk")
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "artifact"
            path.write_bytes(b"x")
            checksum = release.write_checksum(path)
            self.assertEqual(checksum.read_text(), f"{release.sha256_file(path)}  artifact\n")

    def test_manifest_success_and_rejections(self) -> None:
        directory, version, names = self._release_set("stable")
        manifest = release.build_manifest(version, names, directory, "A" * 64)
        release.validate_manifest(manifest, directory)
        for mutation in (
            lambda value: value.__setitem__("schemaVersion", 2),
            lambda value: value["android"].__setitem__("signerSha256", "bad"),
            lambda value: value["macos"].__setitem__("name", "wrong.dmg"),
            lambda value: value["android"].__setitem__("size", 1),
        ):
            broken = json.loads(json.dumps(manifest))
            mutation(broken)
            with self.assertRaises(ValueError):
                release.validate_manifest(broken, directory)
        (directory / names["macosAlias"]).write_bytes(b"different")
        with self.assertRaises(ValueError):
            release.validate_manifest(manifest, directory)

    def test_manifest_rejects_non_cyclonedx_sboms(self) -> None:
        directory, version, names = self._release_set("rolling")
        manifest = release.build_manifest(version, names, directory, "A" * 64)
        for content in ("{}", '{"bomFormat":"SPDX","specVersion":"2.3"}', '{"bomFormat":"CycloneDX","specVersion":""}'):
            (directory / names["macosSbom"]).write_text(content, encoding="utf-8")
            with self.assertRaises(ValueError, msg=content):
                release.validate_manifest(manifest, directory)
        (directory / names["macosSbom"]).write_text('{"bomFormat":"CycloneDX","specVersion":"1.5"}', encoding="utf-8")
        release.validate_manifest(manifest, directory)

    def test_notes_replaces_only_supported_tokens(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            template = directory / "template"
            output = directory / "notes"
            template.write_text("{{VERSION}} {{COMMIT}} {{MACOS_URL}} {{ANDROID_URL}}\n", encoding="utf-8")
            version = release.parse_version("0.1.0")
            release.render_notes(template, output, version, "abcdef0", "owner/repo", "stable", release.artifact_names(version, "stable"))
            stable_notes = output.read_text()
            self.assertIn("https://github.com/owner/repo/releases/latest/download/AndroidBridge-macOS-arm64.dmg", stable_notes)
            self.assertIn("https://github.com/owner/repo/releases/latest/download/AndroidBridge-android.apk", stable_notes)
            release.render_notes(template, output, version, "abcdef0", "owner/repo", "rolling", release.artifact_names(version, "rolling"))
            rolling_notes = output.read_text()
            self.assertIn("https://github.com/owner/repo/releases/download/latest-build/AndroidBridge-latest-macOS-arm64.dmg", rolling_notes)
            self.assertIn("https://github.com/owner/repo/releases/download/latest-build/AndroidBridge-latest-android.apk", rolling_notes)
            self.assertNotIn("{{", rolling_notes)
            template.write_text("{{UNSUPPORTED}}", encoding="utf-8")
            with self.assertRaises(ValueError):
                release.render_notes(template, output, version, "abcdef0", "owner/repo", "stable", release.artifact_names(version, "stable"))


class RepositoryPolicyTests(unittest.TestCase):
    def test_release_policy(self) -> None:
        workflow = (ROOT / ".github/workflows/release-macos.yml").read_text(encoding="utf-8")
        for action in (
            "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683",
            "actions/setup-java@c5195efecf7bdfc987ee8bae7a71cb8b11521c00",
            "anchore/sbom-action@e22c389904149dbc22b58101806040fa8d37a610",
            "anchore/scan-action@e1165082ffb1fe366ebaf02d8526e7c4989ea9d2",
        ):
            self.assertIn(action, workflow)
        self.assertIn(":app:assembleRelease", workflow)
        self.assertNotIn(":app:assembleDebug", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("contents: write", workflow)
        self.assertIn("swift test --package-path mac", workflow)
        self.assertIn("(cd android && ./gradlew :app:testDebugUnitTest --no-daemon)", workflow)
        self.assertNotIn("cd mac && swift test", workflow)
        self.assertIn("grep -Ec '^Signer #[0-9]+ certificate SHA-256 digest:'", workflow)
        self.assertIn("Android build-tools 34 apksigner is unavailable", workflow)
        self.assertIn('echo "LABEL=$VERSION" >> "$GITHUB_ENV"', workflow)
        self.assertIn('echo "LABEL=latest" >> "$GITHUB_ENV"', workflow)
        self.assertIn("${{ env.LABEL }}", workflow)
        self.assertIn('EXCLUDE_LOCAL_TOOL_ENV: "1"', workflow)
        self.assertNotIn("security add-trusted-cert", workflow)
        self.assertIn('security find-identity -p codesigning "$KEYCHAIN"', workflow)
        self.assertEqual(workflow.count("syft-version: v1.51.0"), 2)
        self.assertEqual(workflow.count("grype-version: v0.117.0"), 2)
        self.assertIn("--output release-dist/release-notes.md", workflow)
        self.assertIn("path: release-dist/", workflow)
        self.assertNotIn("env.CHANNEL ==", workflow)
        self.assertIn('gh api "repos/$GITHUB_REPOSITORY/commits/$tag" --jq .sha', workflow)
        self.assertIn('gh api --method DELETE "repos/$GITHUB_REPOSITORY/git/refs/tags/$tag"', workflow)
        self.assertIn("delete_tag_ref latest-build", workflow)
        self.assertIn('gh api "repos/$GITHUB_REPOSITORY/releases/$staging_id" > staged-release.json', workflow)
        self.assertIn('--method PATCH "repos/$GITHUB_REPOSITORY/releases/$staging_id"', workflow)
        installer = (ROOT / "install.sh").read_text(encoding="utf-8")
        requirement = 'identifier "com.androidbridge.mac" and certificate leaf = H"ef2fb966bb80189b6e12ef4a9111601f4d8466ec"'
        self.assertIn(requirement, installer)
        for app in ('"$MOUNT_POINT/$APP_NAME"', '"$TMP_DIR/$APP_NAME"', '"$INSTALL_PATH"'):
            self.assertIn(f"validate_app {app}", installer)
        self.assertIn("Existing Android Bridge uses a different signing identity. Refusing to replace it", installer)
        for secret in ("MACOS_SIGNING_P12", "MACOS_SIGNING_PASSWORD", "ANDROID_RELEASE_KEYSTORE_B64", "ANDROID_RELEASE_STORE_PASSWORD", "ANDROID_RELEASE_KEY_ALIAS", "ANDROID_RELEASE_KEY_PASSWORD"):
            self.assertIn(secret, workflow)
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("releases/latest/download/AndroidBridge-macOS-arm64.dmg", readme)
        self.assertIn("releases/latest/download/AndroidBridge-android.apk", readme)


if __name__ == "__main__":
    unittest.main()
