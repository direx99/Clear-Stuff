# Clear Stuff

Native SwiftUI macOS cleanup app. The current MVP scans user application caches, browser caches, Xcode DerivedData, user logs, shared caches, download cleanup candidates, and saved macOS installers using folders explicitly authorized through the macOS folder picker. No scan deletes files.

## About and contributing

Clear Stuff is an initial open-source build by **Dinith Hasaranga**. Everyone is welcome to contribute. Report bugs, suggest features, or ask questions in [GitHub Issues](https://github.com/direx99/Clear-Stuff/issues); pull requests are welcome too. Please avoid posting personal file paths or sensitive logs in public issues.

- Email: [dinith.dash@gmail.com](mailto:dinith.dash@gmail.com)
- GitHub repository: [direx99/Clear-Stuff](https://github.com/direx99/Clear-Stuff)
- GitHub profile: [direx99](https://github.com/direx99)

Licensed under the [MIT License](LICENSE).

## Run

Open `Clear Stuff.xcodeproj` in Xcode and run the **Clear Stuff** scheme. The existing project targets macOS 26.4 and requires a compatible Xcode installation.

1. Choose **Connect All Folders…** to connect missing cleanup locations in one guided setup. Approve each displayed folder in the macOS picker; cancelling stops setup and keeps folders already connected. Use **Manage folders** to connect or reconnect a single category. A custom Xcode location must be named `DerivedData`.
2. Choose **Scan Folders** in the toolbar or **Scan folders** on the dashboard. Review estimated sizes, paths, modification dates, eligibility reasons, and skipped locations.
3. Filter or search the list, reveal items in Finder, or exclude them from future scans.
4. Select items or use **Select All**, then choose **Review selected files** at the bottom. Close the affected apps and stop builds, review the consequences, then choose **Move to Trash**.
5. Review **History**. Recover files through Finder's Trash. The app never empties Trash; moving files there does not immediately free disk space.

For additional browser profile caches, connect **Browser Caches** to `~/Library/Application Support`. The scanner visits only supported browser/cache paths in that folder; it does not scan other app support data. Default Chrome, Safari, and Firefox disk caches are also covered by connecting **App Caches** to `~/Library/Caches`.

The window adapts down to 580 × 520 points. Narrow windows replace the sidebar with a **Browse** menu; summary cards reflow, dashboard content scrolls, and selection controls remain at the bottom.

Folder access is saved with security-scoped bookmarks. Stale bookmarks are renewed when possible; unavailable grants can be reconnected. Use **Settings → Remove Access** to discard the saved access and related scan results. All history and exclusions are stored locally.

The last 100 cleanup results include full file paths. Use **Settings → Clear Cleanup History** to erase them; removing folder access does not erase history. Cleanup stages each selected item beside its original location and rechecks it before moving it to Trash. If that check fails and the item cannot be returned to its original path, the activity report identifies the staged path for manual recovery.

Permission failures appear with an access explanation above the skipped-location details. Use **Reconnect Folder…** to grant the affected scan folder again. If access is still denied, use **Full Disk Access…** to open the relevant Settings pane and review Clear Stuff under **Privacy & Security → Files & Folders** or **Full Disk Access**. Quit and reopen the app after changing permissions, then scan again. These settings do not override sandbox restrictions, file ownership, or all macOS protections. Unreadable locations remain skipped; accessible candidates are still available for review.

## Implemented scope

- Read-only, cancellable background scan with per-location errors and bounded traversal.
- Manual selection of app caches, with a reminder to close affected apps and review possible offline-data loss. Links inside selected folders move without following their targets.
- Manual selection of every scanned DerivedData item (including compilation and module caches) and every log/report, without age or recognition restrictions.
- Browser cache discovery for Chrome, Edge, Brave, Chromium, Vivaldi, Opera, and Firefox profile caches under Application Support; standard Safari and Firefox caches under Library/Caches appear in Browser Caches too. Profile roots, passwords, bookmarks, history, cookies, extensions, and website storage are not cleanup candidates.
- Explicit selection and confirmation; no default selections or background cleanup.
- Re-scan and identity checks before Trash operations, file coordination with cooperating writers, and resulting-location verification.
- Top-level links, special files, other owners, unexpected mounts, and overlapping roots are skipped. Links within a selected folder move with that folder without traversing the target.
- Search, category navigation, exclusions, Finder reveal, saved access, and the last 100 cleanup outcomes.

Download Cleanup reviews direct Downloads children: partial .crdownload/.part/.download files, downloaded .dmg/.pkg/.mpkg installers, and ZIPs missing a complete standard archive-directory footer. These are review candidates, not confirmed corruption findings. Stop downloads and installers before cleaning. Complete personal downloads and nested personal folders are not scanned.

macOS Installers reviews saved Install macOS / Install OS X apps directly inside /Applications, rather than active operating-system update staging. System Caches connects to /Library/Caches; only candidates owned by your account can be cleaned. System-owned files are reported as skipped and require administrator-managed cleanup.

The dashboard's **Available for cleanup** size counts only fully scanned, eligible candidates in the selected category. A zero estimate does not mean the connected folder is empty: skipped locations are excluded. Warnings are scoped to the selected category and distinguish permission failures, ownership restrictions, and scan limits. Reconnecting does not resolve ownership restrictions or scan limits. Reconnecting or removing a folder clears its old warnings; scan again to check its current state.

General file corruption detection, privileged system/update-staging cleanup, simulator runtimes, release archives, backups, Docker, package managers, browser profiles/website storage, and personal-file cleanup remain outside this MVP. The cleanup catalog describes those later integrations in `docs/macos-cleanup-plan.md`.

## Verification

Run the core tests:

```sh
swift test
```

Build the app:

```sh
xcodebuild -project 'Clear Stuff.xcodeproj' -scheme 'Clear Stuff' -configuration Debug build
```

Tests create disposable fixtures for manual selection, browser profile preservation, exclusions, symlinks, hard links, changed data, cancellation, scan limits, macOS path aliases, and a real Trash operation. The Trash test moves only its generated file and removes that fixture afterward.

Storage totals are logical size estimates and cannot predict APFS clone or snapshot reclamation. File coordination only controls cooperating writers: stop all command-line builds before cleaning DerivedData. Checks cannot guarantee safety against another process deliberately replacing paths during a move. This is an MVP, not a notarized release; broader cleanup rules require separate validation.

## Public distribution

Archive and distribute through Xcode Organizer using a **Developer ID Application** identity, then notarize and staple the exported app. Run `scripts/verify-public-release.sh '/path/to/Clear Stuff.app'` against the exact app you plan to publish. It rejects development signatures, a missing hardened runtime, missing stapled notarization, or a failed Gatekeeper assessment. Test that artifact on a clean Mac before publishing. The local development build is not a notarized release.
