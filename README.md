# Clear Stuff

Clear Stuff is an open-source macOS app for reviewing cleanup candidates and moving selected items to Trash. It scans only folders you authorize through the macOS folder picker. Scanning never removes files, and cleanup requires an explicit selection and confirmation.

> **Initial build:** This repository contains source code, not a signed or notarized app download. Review the candidates before moving anything; cached or offline data may need to be downloaded again.

## Requirements

- macOS 26.4 or later (the app target's current deployment setting).
- Xcode with an SDK that supports that macOS target.
- Folder access granted in the app for each location you want to scan.

## Build and run

1. Clone the repository:

   ```sh
   git clone https://github.com/direx99/Clear-Stuff.git
   cd Clear-Stuff
   ```

2. Open `Clear Stuff.xcodeproj` in Xcode.
3. Select the **Clear Stuff** scheme and run it on your Mac.

The app uses the sandbox and user-selected, read/write folder access. It saves security-scoped bookmarks locally so approved folders can be scanned again. If a grant becomes unavailable, reconnect that folder in **Settings**.

## Use

1. Choose **Connect All Folders…** or connect individual folders under **Settings**. Approve each location shown in the macOS picker. A custom Xcode build folder must be named `DerivedData`.
2. Choose **Scan Folders**. Review sizes, paths, reasons, and any skipped locations. A zero estimate can mean a folder was inaccessible or had no eligible candidates.
3. Select only items you recognize. You can search, filter, reveal an item in Finder, or exclude it from future scans.
4. Close apps using the files and stop builds, downloads, or installers. Choose **Review selected files**, acknowledge the warning, then **Move to Trash**.
5. Check **History** for completed or skipped moves. Restore an item through Finder's Trash if needed. Clear Stuff never empties Trash, so moving items there does not immediately free disk space.

## What it scans

| Category | Authorized location | Candidates |
| --- | --- | --- |
| App Caches | `~/Library/Caches` | Top-level app cache entries. Safari and Firefox disk caches appear here. |
| Browser Caches | `~/Library/Application Support` | Cache folders in supported Chrome, Edge, Brave, Chromium, Vivaldi, Opera, and Firefox profiles. Profile data such as passwords, bookmarks, history, cookies, and extensions is excluded. |
| Developer Data | `~/Library/Developer/Xcode/DerivedData` or a selected custom `DerivedData` folder | Xcode generated data, including build and module caches. |
| Logs & Reports | `~/Library/Logs` | Logs and reports, regardless of age or filename. |
| System Caches | `/Library/Caches` | Shared cache entries owned by your account; system-owned items are skipped. |
| Download Cleanup | `~/Downloads` | Direct children with partial-download extensions, downloaded `.dmg`/`.pkg`/`.mpkg` installers, and ZIP files missing a complete standard directory footer. These are review candidates, not confirmed corruption. |
| macOS Installers | `/Applications` | Saved `Install macOS … .app` or `Install OS X … .app` bundles. Active update staging is excluded. |

The browser scan visits only known cache paths inside Application Support. It does not scan other app support data. Complete personal downloads and nested Downloads folders are not scanned. The [cleanup plan](docs/macos-cleanup-plan.md) describes possible future scope; it is not a list of implemented features.

## Safety and privacy

- Cleanup is manual. The app does not delete files permanently, schedule cleanup, or clean in the background.
- Candidates are rechecked before moving. Items that change, cannot be accessed, or fail safety checks are skipped. A concurrent process can still change a path; close affected apps first.
- Symlink targets are not followed. Top-level links, special files, unexpected mounts, other owners, and overlapping scan roots are skipped.
- Size figures are logical estimates. APFS clones and snapshots can make actual reclaimed space differ.
- Folder bookmarks, exclusions, and the last 100 cleanup results stay on your Mac. History includes full file paths. Use **Settings → Clear Cleanup History** to erase it; removing a folder grant does not erase history.
- If a move's result cannot be verified, History says so and includes a Trash location when available. Check Trash before retrying. If an item cannot be restored after staging, History names its staged path for manual recovery.

macOS may deny access to some locations even after a folder is selected. Reconnect the folder or review **Privacy & Security → Files & Folders** in System Settings. Full Disk Access is optional and does not override sandbox or ownership restrictions. Quit and reopen the app after changing system permissions.

## Development

Run the focused core tests:

```sh
swift test
```

Build the app from the command line:

```sh
xcodebuild -project 'Clear Stuff.xcodeproj' -scheme 'Clear Stuff' -configuration Debug build
```

The tests use disposable fixtures for scanning, exclusions, links, changed files, download and browser filtering, and Trash moves. The core Swift package has no third-party dependencies.

## Public distribution

This initial build has **no notarized release**. To distribute an app outside the Mac App Store, archive it, sign it with a Developer ID Application identity, notarize it, and staple the ticket. Run the release gate against the exact exported app:

```sh
scripts/verify-public-release.sh '/path/to/Clear Stuff.app'
```

The script checks the Developer ID signature, hardened runtime, stapled notarization, and Gatekeeper assessment. Test the final artifact on a clean Mac before publishing it.

## Contributing and support

Everyone is welcome to contribute. Use [GitHub Issues](https://github.com/direx99/Clear-Stuff/issues) for bugs, feature ideas, and questions. For a bug, include the macOS version, steps to reproduce, expected result, and actual result. Do not post personal paths, private files, or sensitive logs in a public issue. Pull requests should describe the change and include relevant verification.

Created by **Dinith Hasaranga** · [GitHub profile](https://github.com/direx99) · [dinith.dash@gmail.com](mailto:dinith.dash@gmail.com)

## License

Clear Stuff is available under the [MIT License](LICENSE).
