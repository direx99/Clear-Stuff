# Clear Stuff macOS Cleanup Plan

Draft dated 6 October 2026.

Current manual-cleanup behavior: every listed item in connected App Caches, Browser Caches, DerivedData, and Logs & Reports can be selected without age or recognition locks. Browser profile scans only list known cache subfolders. Internal links move without following targets; top-level links and inaccessible or unsupported entries are skipped. The age thresholds below describe potential future suggestions, not current selection restrictions.

Clear Stuff will help Mac users reclaim storage from known caches, developer build data, old logs, and files they choose to remove. The first release should scan and explain each item before cleanup, preserve personal and project data, and show what actually happened afterward.

Start with known user caches, inactive Xcode DerivedData, and old user logs. Add package manager and Docker cleanup through dedicated integrations later. “Unwanted” is a user decision; size, age, and a folder name alone do not prove a file is disposable.

This is a product cleanup plan. Paths below are discovery candidates, not instructions to delete whole directories. Locations vary with tool versions, profiles, and configuration; each cleanup rule must be verified before it ships.

## Cleanup levels

| Level | Meaning | Default behavior |
| --- | --- | --- |
| Routine candidates | Recognized regenerable data with a validated rule | May be suggested after age and activity checks; user reviews before cleaning |
| Optional cleanup | Regenerable but expensive to rebuild or useful offline | Unselected; explain the rebuild or download cost |
| Individual review | May contain unique data or recovery material | Unselected; inspect and confirm individual items |
| Protected | System state, credentials, personal data, or unknown content | Exclude from generic cleanup |

No category is universally safe. The current app allows manual selection of user app caches after individual review and confirmation; links inside selected caches move without following their targets. This does not classify unfamiliar cache layouts as routine cleanup candidates.

## General caches and temporary data

| Target | Discovery candidate | Cleanup policy and consequence |
| --- | --- | --- |
| User application caches | Known subdirectories of `~/Library/Caches` | Routine only for validated apps; close the owner first. Expect slower first launch or downloads |
| Sandboxed application caches | Specific `Data/Library/Caches` inside an app container | Optional, per app and permission; never remove the container or its support data |
| Shared application caches | Known entries under `/Library/Caches` | Later release; scan only initially because ownership and permissions differ |
| Browser caches | Cache locations for installed browsers and profiles | Optional, later; preserve cookies, logins, history, bookmarks, extensions, and offline site data |
| App temporary files | App-specific temporary locations | Only recognized abandoned items after owner checks; never sweep `/tmp` or `/private/var/folders` |
| Thumbnails and media previews | Tool-specific thumbnail or preview caches | Later, validated rules; rebuilding can cost time and CPU |
| Old download remnants | Recognized incomplete download files | Individual review; they may be resumable or still downloading |
| Creative application caches | Adobe, video editor, audio tool cache settings | Later, app-specific integration; preserve originals, project files, and render deliverables |

Keep cache folders and permissions intact where the owner expects them. Do not promise a performance improvement from routine cache removal.

## Logs and diagnostic reports

| Target | Discovery candidate | Cleanup policy and consequence |
| --- | --- | --- |
| User application logs | Known subdirectories of `~/Library/Logs` | Routine candidates for inactive rotated logs older than 30 days |
| User crash and diagnostic reports | `~/Library/Logs/DiagnosticReports` | Optional after 30 days; loses historical troubleshooting evidence |
| Developer tool logs | Known npm, IDE, test, and build log locations | Optional after 30 days; preserve reports needed for current failures |
| Shared and system logs | `/Library/Logs`, `/private/var/log` | Scan only initially; never truncate active logs |
| macOS unified logging store | System-managed diagnostic storage | Protected from generic cleanup; no blanket erase action |

Age thresholds are proposed product defaults, not guarantees of safety. Last modification is evidence of a write, not reliable evidence of last use. Do not read log contents for routine sizing or upload them.

## Xcode and Apple developer data

| Target | Discovery candidate | Cleanup policy and consequence |
| --- | --- | --- |
| DerivedData | Default `~/Library/Developer/Xcode/DerivedData` and discovered custom locations | Routine candidates after 14 days and with Xcode/builds inactive; next use rebuilds and reindexes |
| Xcode caches | Known entries under `~/Library/Caches/com.apple.dt.Xcode` | Optional; validate each layout and exclude active tool activity |
| Swift package build artifacts | Known build/cache data inside DerivedData or selected projects | Optional; keep source and `Package.resolved`; package downloads may require network access |
| Simulator devices | Inventory from the selected Xcode installation | Individual review, including unavailable devices; deleting a device loses its apps and test data |
| Simulator runtimes | Xcode component inventory | Individual review through supported management; reinstall requires downloads |
| Device support and symbols | Version-specific Xcode device support locations | Later, individual review; may still be needed for debugging older devices |
| Xcode archives and dSYMs | `~/Library/Developer/Xcode/Archives` | High risk; scan only initially. Preserve release archives and symbols needed for distribution and crash analysis |
| Downloaded Xcode components | Xcode-managed package locations | Later; distinguish installers from installed components through supported tooling |
| Preview artifacts | Version-specific Xcode preview storage | Optional, later; preserve simulator data unless explicitly selected |

Do not remove the whole `~/Library/Developer` directory. Xcode offers management of optional components; prefer those supported mechanisms for runtimes. [Apple Xcode component guidance](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components).

## Other developer tools

All rows in this section are later integrations and start unselected. Discover configuration and installed versions instead of assuming one fixed path.

| Tool or target | Discovery candidate | Cleanup policy and consequence |
| --- | --- | --- |
| Homebrew | `brew --cache` and `brew cleanup --dry-run` | Preview the tool's actual plan; explain removal of older installed versions and rollback impact |
| npm and npx | Configured cache and supported cache inventory | Prefer verification first; explicit cache removal requires renewed downloads |
| Yarn and pnpm | Configured cache or package store | Version-specific adapter; distinguish shared stores from project dependencies |
| Python pip and uv | `python -m pip cache dir` or tool-reported location | Cache-only cleanup; retain environments and installed tools |
| Ruby Bundler and gems | Tool-configured downloaded package cache | Cache-only cleanup; installed gems and vendored dependencies need separate review |
| Gradle and Maven | Configured user cache/repository locations | Optional; downloads and offline artifacts may be needed. Preserve credentials and settings |
| Android Studio | IDE cache inventory | Optional cache cleanup; SDKs, system images, and emulators require individual review |
| Go | Tool-reported build and module cache | Separate build cache from downloaded modules; explain offline and rebuild cost |
| Rust Cargo | Project `target` and configured registry/git cache | Selected-project artifacts only; never remove `.cargo` wholesale |
| Flutter and Dart | Configured package cache and selected build outputs | Keep SDKs and source; downloads/builds will recur |
| IDEs such as VS Code and JetBrains | Verified cache and log subdirectories | Preserve extensions, settings, local history, workspace state, and unsaved recovery data |
| Project generated files | Selected project `.build`, `build`, `target`, `dist`, `.next`, or dependencies | Individual review with project-aware rules; names alone do not prove regeneration is possible |
| Virtual environments and `node_modules` | User-selected project roots | Individual review; reinstall may fail if dependencies, private registries, or network access are unavailable |

Homebrew provides a dry run, npm provides cache verification, and pip provides cache discovery and management. These capabilities should shape their integrations. [Homebrew manual](https://docs.brew.sh/Manpage), [npm cache documentation](https://docs.npmjs.com/cli/v11/commands/npm-cache/), [pip cache documentation](https://pip.pypa.io/en/stable/cli/pip_cache/).

## Docker and virtual machines

| Target | Discovery method | Cleanup policy and consequence |
| --- | --- | --- |
| Docker build cache | Supported Docker inventory and builder-specific tooling | Optional targeted prune; builds become slower |
| Docker images | Docker inventory | Individual review; images can be needed offline |
| Stopped containers | Docker inventory | Individual review; stopped containers may hold unique writable-layer data |
| Docker volumes | Docker inventory | High risk; exclude from default cleanup because they may hold databases |
| Docker disk image | Docker Desktop storage management | Never delete `Docker.raw` or similar disk files as a cache |
| Other VM disks and snapshots | Application-managed inventory | Individual review; never infer unused state from age |

Avoid a generic “clean all Docker” action. Docker system pruning can remove stopped containers, images, networks, and build cache; volume pruning has separate data-loss implications. Use targeted operations and display their full scope. MVP discovery should use only the local engine; do not act on a remote Docker context. [Docker prune documentation](https://docs.docker.com/reference/cli/docker/system/prune/).

## Unwanted files and storage review

| Target | Discovery candidate | Cleanup policy |
| --- | --- | --- |
| Trash | Current user's accessible Trash | Individual review; emptying is permanent and separate from ordinary cleaning |
| Installers and disk images | Selected Downloads folders; `.dmg`, `.pkg`, archives | Review only; age and extension do not prove they are unwanted |
| Large and old files | User-selected folders | Review only; show path, size, and modification date |
| Duplicate files | User-selected folders | Later; hash local contents before claiming duplicates and retain a chosen original |
| App leftovers | Specific files associated with a removed app | Later; app absence does not prove support data is unwanted or unshared |
| iPhone and iPad backups | Finder backup management | Individual review through supported management; backups provide recovery |
| Mail attachments and offline media | Mail or media application management | Later; use owner controls and explain local versus synced deletion |
| Cloud files | Provider-managed storage | Prefer provider eviction controls; deleting a synced file may delete the cloud copy |
| Time Machine local snapshots | System backup inventory | Informational only in MVP; macOS manages their retention |

Apple describes System Data as a broad storage category, not a disposable folder. Moving files to Trash does not free their storage until Trash is emptied. [Apple storage guidance](https://support.apple.com/en-us/102624). macOS automatically manages Time Machine local snapshots as they age or space is needed. [Apple snapshot guidance](https://support.apple.com/en-us/102154).

## Protected exclusions

Always exclude these from generic cleanup:

- macOS system files, update assets, recovery data, swap, sleep files, Spotlight indexes, and system-managed databases.
- Keychains, SSH keys, signing certificates, provisioning credentials, browser passwords, and package-manager authentication.
- Source code, Git history, lockfiles, configuration, databases, and persistent Docker volumes.
- Documents, Photos libraries, Messages, Mail stores, music libraries, cloud originals, and backups.
- App containers, group containers, Application Support, and Preferences as whole directories.
- Unsaved documents, editor recovery files, and local history.
- Other users' homes and external/network volumes unless explicitly added to scope.

Do not disable System Integrity Protection or bypass macOS access controls. Unknown content remains excluded.

## The first release

**Include:** a read-only scanner; validated user-cache rules; inactive Xcode DerivedData; old user logs and optional crash reports; category and item review; exclusions; Finder reveal; Trash-based cleanup where supported; and an outcome report.

**Defer:** system-wide deletion, automatic schedules, privileged helpers, browser cleaning, package-manager execution, simulator deletion, Docker pruning, app uninstalling, duplicates, and backup removal. These need separate rules and verification.

Suggested interface sections: Overview, App Caches, Developer Data, Logs, Review Files, Cleanup History, and Settings. Overview should distinguish discovered data, eligible candidates, selected items, inaccessible locations, and protected items.

All cleanup remains user initiated. “Select recommended” includes only validated routine candidates that pass inactivity and age checks.

## Scan and clean workflow

1. Scan authorized locations without changing contents. Missing tools are “not installed”; access failures are “not scanned,” never zero bytes.
2. Identify the owner and rule for every candidate. Show path, category, size estimate, date, risk, and expected rebuild or data-loss consequence.
3. Let the user review selections, deselect items, reveal them in Finder, and add exclusions.
4. Build a fixed action plan containing only selected items. Show whether each action moves to Trash or permanently deletes through a tool.
5. Revalidate item identity, ownership, permitted root, and activity immediately before mutation. Skip changed or newly active items.
6. Execute serially for each owner, with progress and cancellation between operations. Record each success, skip, and failure.
7. Verify resulting state. Report bytes moved to Trash separately from actual observed free-space change.

Trash provides recovery only where the move succeeds. It is not immediate space reclamation. Tool-driven pruning is usually permanent; never promise Undo for it. Trash emptying must be a separate explicit action.

## Implementation boundaries

Use a native macOS app with a small set of explicit cleanup rules. Keep scanning, selection, and mutation separate so a scan cannot delete anything. Each rule defines supported versions, discovery, exclusions, inactivity checks, consequences, execution method, and result verification.

Operate as the current user for MVP. Show permission gaps honestly. Full Disk Access, administrator privileges, and App Sandbox are distinct constraints; one does not automatically grant the others. Validate access on the chosen distribution model before promising broad cleanup. A signed, notarized direct distribution is a candidate for wider coverage; a sandboxed App Store version needs a feasibility check. [Apple App Sandbox documentation](https://developer.apple.com/documentation/security/app-sandbox).

Use canonical roots and identity checks; never follow links outside scope or traverse unexpected mounts. Prevent path replacement races during deletion rather than relying only on an earlier path check. Avoid shell interpolation and broad recursive delete commands. Run supported tools with fixed arguments, bounded output, cancellation, and timeouts.

Deduplicate overlapping scan rules. Account for hard links, sparse files, and APFS clones; summed file sizes are estimates, not guaranteed reclaimable bytes. Keep processing bounded and off the UI thread. Store cleanup history locally without file contents or credentials.

## Delivery plan and acceptance checks

| Stage | Deliverable | Completion check |
| --- | --- | --- |
| 1 Identify | Cleanup catalog and protected exclusions | Every proposed category has a policy and consequence |
| 2 Validate access | Test selected macOS/Xcode versions and distribution model | Permissions and unsupported layouts are shown accurately |
| 3 Build scanner | Read-only inventory and item review | No changes to scanned data; no duplicate totals |
| 4 Add cleanup | Validated MVP rules and explicit action plan | Only selected, revalidated items can change |
| 5 Verify recovery | History, Trash recovery, failure reporting | Interrupted and partial operations remain understandable |
| 6 Expand | One tool-specific integration at a time | Version-specific inventory and cleanup behavior verified |

Before release, test with disposable fixtures and a dedicated test account: denied access, custom paths, symlinks, active builds, changed files between scan and cleanup, cancellation, low disk space, and interrupted operations. Confirm source files, credentials, personal data, archives, and backups remain untouched. Verify relevant apps reopen and an Xcode sample project rebuilds after supported cache cleanup.

The next implementation step is a read-only scanner for the three MVP categories. Decide the minimum macOS version and distribution channel during access validation before adding deletion behavior.
