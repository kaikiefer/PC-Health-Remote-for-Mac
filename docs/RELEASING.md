# GitHub release

The current release path is a full-featured direct macOS app. No App Store target
or reduced-sensor edition is included.

## Upload the source

Upload the source archive's contents to your GitHub repository, or push this
folder with Git. Do not upload `build/`, developer caches, or machine-specific
`VALIDATION.md`; `.gitignore` excludes them. Keep the project license and
third-party notices. The source archive deliberately includes only the source,
assets, tests, scripts, public docs, and GitHub workflow files.

```sh
git init -b main
git add .
git commit -m "Initial Mac companion release"
git remote add origin https://github.com/YOUR-ACCOUNT/YOUR-REPO.git
git push -u origin main
```

Replace the example repository URL with your own. These commands are for the
maintainer to run; preparing this folder does not publish anything.

## Build and package

On a Mac with Xcode or matching Command Line Tools:

```sh
./scripts/test.sh
./scripts/release.sh
```

`release.sh` builds both arm64 and x86_64 into one universal app, verifies the
local code signature, then writes the app ZIP, an adjacent SHA-256 checksum,
and draft release notes into `build/releases/`. Hardware behavior on Intel is
not established by cross-compiling. To package only one architecture, set
`ARCH=arm64` or `ARCH=x86_64`.

To verify a downloaded archive, run `shasum -a 256 -c` against its adjacent
`.sha256` file from the directory holding both files.

The default signature is ad-hoc: it verifies local bundle integrity but does
not identify a trusted developer or establish notarization. Gatekeeper may
block downloads. Do not advertise the default artifact as notarized or
Apple-approved. A Developer ID signature can be selected explicitly through
`CODESIGN_IDENTITY`; that alone does not notarize the app. Notarization and
stapling remain separate future release work if a developer account is added.

## Review and publish

1. Confirm the version in `Info.plist` and update `CHANGELOG.md`.
2. Run tests and the release build; verify the checksums.
3. Test on a fresh Mac, physical USB, Bluetooth pairing/reconnects, and each
   supported chip/firmware before claiming broad hardware compatibility.
4. In GitHub Releases, create a draft tag matching the version (for example
   `v1.3.0`). Attach the app ZIP and checksum. Paste `build/releases/RELEASE_NOTES.md`.
5. Review installation/signing limitations and publish when ready.

Alternatively, pushing a `v*.*.*` tag runs `.github/workflows/release.yml`.
The workflow validates that the tag matches `Info.plist`, runs tests, builds a
universal app, and creates a **draft** GitHub release for maintainer review.
It requires the repository's Actions workflow permissions to allow the job's
`contents: write` token. Branch pushes/PRs only build/test and upload an Actions
artifact; they do not create public releases. Hosted workflows have been
prepared locally and still need their first run in the actual repository.

## Brand files

`Assets/Brand/` contains the mark, dark wordmark, desktop icon master, and brand
notes. `scripts/prepare-assets.sh` regenerates the raster exports and Xcode
asset catalog from native drawing code. The SVG files are editable vector
companions. The normal build embeds `LogoMark.png` and an `.icns` icon.

## Later App Store feasibility

The full sensor build reads undocumented SMC/IOReport interfaces and driver
statistics, and is not sandboxed. Do not submit it unchanged to the Mac App
Store. A separate design would need public-API sensor limits, sandboxed USB/BLE
validation, privacy-manifest review (including restrictions on disk/boot-time
data transmission), developer enrollment, and App Review hardware instructions.
See [Apple's review guidelines](https://developer.apple.com/app-store/review/guidelines/)
and [required-reason API documentation](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
