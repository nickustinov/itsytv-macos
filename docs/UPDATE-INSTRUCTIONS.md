**Overview**: This project supports automatic updates via Sparkle. The repository includes a script and workflow to generate a Sparkle-compatible appcast.xml from GitHub Releases and publish it to `gh-pages`.

- **Add Sparkle to the app (SPM)**: In Xcode, select the project, choose the app target, then `Package Dependencies` → `+` and add `https://github.com/sparkle-project/Sparkle` (pick a stable Sparkle 2.x release). If you manage your project with XcodeGen, add Sparkle to the `packages` section of `project.yml` instead (see this repo's `project.yml`).

- **Configure feed URL**: Set your app's appcast URL to the GitHub Pages location where the workflow will publish the appcast. Example: `https://<owner>.github.io/<repo>/appcast.xml`.
  - You can either set `SUFeedURL` in `Info.plist` or update the `appcastURL` constant in `itsytv/Utilities/UpdateChecker.swift`.

- **Release workflow**: When you create a GitHub release (publish the release), the workflow `.github/workflows/generate-appcast.yml` runs, generating `docs/appcast.xml` and publishing `docs/` to the `gh-pages` branch. GitHub Pages will serve the appcast at `https://<owner>.github.io/<repo>/appcast.xml`.

- **Signing / EdDSA**: For secure updates you must sign update archives using Sparkle's EdDSA (Ed25519) signing keys. Legacy DSA-based signing is deprecated. This script does not sign artifacts; do NOT deploy unsigned updates to production. Before releasing, sign your archives and include the corresponding `sparkle:edSignature` attributes in the appcast enclosure elements.

- **Local testing**: After adding Sparkle via SPM, run the app and call `UpdateChecker.check()`; Sparkle will read the feed URL and check for updates. Use a draft or test release with a downloadable asset (`.zip`, `.dmg`, or `.pkg`) to validate.
