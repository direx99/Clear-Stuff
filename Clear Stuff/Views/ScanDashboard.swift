import SwiftUI

struct ScanDashboard: View {
    @Bindable var model: CleanupModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashboardHeader(model: model)
                FolderAccessSection(model: model)
                if !model.scopedIssues.isEmpty {
                    ScanIssuesView(issues: model.scopedIssues, accessCategories: model.accessIssueCategories,
                                   busy: model.busy || model.grantingAccess,
                                   grant: model.grant, openSettings: model.openSystemSettings)
                }
                if model.scopedItems.isEmpty && (model.lastScan != nil || model.busy) {
                    ScanEmptyState(model: model)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if !model.scopedItems.isEmpty {
                    ItemBrowser(model: model)
                }
            }
            .padding(24)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { CleanupFooter(model: model) }
        .background(AppTheme.canvas)
        .navigationTitle("")
    }
}

private struct DashboardHeader: View {
    let model: CleanupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.category?.title ?? "Let’s clear some space.")
                    .font(.largeTitle.weight(.semibold))
                Text("Scan your folders, choose files, then move them to Trash.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        CleanupStep(number: "1", title: "Scan", active: model.lastScan == nil)
                        CleanupStep(number: "2", title: "Choose files", active: model.lastScan != nil && model.selectedItems.isEmpty)
                        CleanupStep(number: "3", title: "Move to Trash", active: !model.selectedItems.isEmpty)
                    }
                    Text("1. Scan   →   2. Choose files   →   3. Move to Trash")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                if !model.roots.isEmpty {
                    Button {
                        if model.busy { model.cancel() } else { model.scan() }
                    } label: {
                        Label(model.busy ? "Stop" : model.lastScan == nil ? "Scan folders" : "Scan again",
                              systemImage: model.busy ? "stop" : "magnifyingglass")
                            .frame(minHeight: 24)
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(model.grantingAccess)
                    .help("Scan folders (⌘R). No files are removed.")
                }
                if model.busy || model.grantingAccess || model.lastScan != nil {
                    HStack(spacing: 8) {
                        if model.busy || model.grantingAccess { ProgressView().controlSize(.small) }
                        Text(model.accessProgress ?? model.status)
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            .textSelection(.enabled)
                    }
                } else {
                    Label("Scanning never removes files.", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AppTheme.border))
            if model.lastScan != nil || model.busy {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    StorageMetric(title: "Found for review",
                                  value: model.totalBytes.formatted(.byteCount(style: .file)),
                                  detail: model.scopedIssues.isEmpty ? "\(model.scopedItems.count) files and folders" : "Unreadable folders aren’t counted",
                                  icon: "externaldrive")
                    StorageMetric(title: "Your selection",
                                  value: model.selectedBytes.formatted(.byteCount(style: .file)),
                                  detail: "\(model.selectedItems.count) selected", icon: "checkmark.circle")
                }
            }
        }
    }
}

private struct CleanupStep: View {
    let number: String
    let title: LocalizedStringKey
    let active: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(number).font(.caption.weight(.semibold))
                .frame(width: 26, height: 26)
                .background(active ? AppTheme.selection : AppTheme.subtle, in: Circle())
            Text(title).font(.callout.weight(.medium))
        }
        .foregroundStyle(active ? AppTheme.accent : AppTheme.secondaryText)
        .accessibilityElement(children: .combine)
    }
}

private struct StorageMetric: View {
    let title: LocalizedStringResource
    let value: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
                Spacer(minLength: 4)
                Image(systemName: icon).foregroundStyle(AppTheme.accent).accessibilityHidden(true)
            }
            Text(value).font(.title.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.border))
        .accessibilityElement(children: .combine)
    }
}

private struct ScanEmptyState: View {
    let model: CleanupModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: model.busy ? "magnifyingglass" : "checkmark.circle")
                .font(.largeTitle).foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text(model.busy ? "Looking for files…" : "No files to review here")
                .font(.title3.weight(.semibold))
            Text(model.busy ? "You can stop the scan at any time."
                 : model.scopedIssues.isEmpty ? "Try another folder or scan again."
                 : "Some folders were skipped. See the details above.")
                .font(.callout).foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }.padding(24)
    }
}

private struct FolderAccessSection: View {
    let model: CleanupModel
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.roots.count < CleanupCategory.allCases.count {
                FolderAccessActions(model: model)
            }
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 8) {
                    ForEach(CleanupCategory.allCases) { category in
                        FolderAccessRow(category: category, root: model.roots[category], busy: model.busy || model.grantingAccess) {
                            model.grant(category)
                        }
                    }
                }.padding(.top, 12)
            } label: {
                Label("\(model.roots.count) folders connected · Manage folders", systemImage: "folder.badge.checkmark")
                    .font(.callout.weight(.medium))
            }
        }
        .padding(20)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.border))
    }
}

struct FolderAccessActions: View {
    let model: CleanupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder.badge.plus").font(.title2).foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.roots.isEmpty ? "Start by connecting your folders" : "Add more folders").font(.headline)
                    Text("Choose Allow when macOS asks for folder access.")
                        .font(.callout).foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { FolderAccessButtons(model: model) }
                VStack(alignment: .leading, spacing: 10) { FolderAccessButtons(model: model) }
            }
            if model.grantingAccess, let progress = model.accessProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.callout).foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                Text("\(model.roots.count) of \(CleanupCategory.allCases.count) folders connected")
                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
            }
            Text("Only folders you allow will be scanned.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FolderAccessButtons: View {
    let model: CleanupModel

    var body: some View {
        Group {
            Button(action: model.grantAll) {
                Label(model.roots.count == CleanupCategory.allCases.count ? "All Connected" : "Connect All Folders…",
                      systemImage: model.roots.count == CleanupCategory.allCases.count ? "checkmark.circle" : "folder.badge.plus")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(model.busy || model.grantingAccess || model.roots.count == CleanupCategory.allCases.count)
        }
        .controlSize(.large)
    }
}

struct FolderAccessRow: View {
    let category: CleanupCategory
    let root: URL?
    let busy: Bool
    let grant: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: grant) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.title3).foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.selection, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                    Text(root?.path ?? category.relativePath)
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(root == nil ? "Connect…" : "Reconnect…")
                        .font(.callout.weight(.medium)).foregroundStyle(AppTheme.accent)
                    if root != nil {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(hovered && !busy ? AppTheme.selection : AppTheme.subtle,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(hovered && !busy ? AppTheme.accent : AppTheme.border))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
        .onHover { hovered = $0 }
        .help(root?.path ?? category.relativePath)
        .accessibilityLabel("\(root == nil ? "Connect" : "Reconnect") \(String(localized: category.title))")
        .accessibilityValue(root == nil ? "Not connected" : "Connected")
        .accessibilityHint("Opens the folder chooser")
    }
}

private struct ScanIssuesView: View {
    let issues: [ScanIssue]
    let accessCategories: [CleanupCategory]
    let busy: Bool
    let grant: (CleanupCategory) -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if issues.contains(where: \.requiresAccess) {
                Label("Some folders need permission", systemImage: "lock.shield")
                    .font(.headline)
                Text("Reconnect a folder and scan again. If it still won’t open, allow Clear Stuff in Full Disk Access and restart the app.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if !accessCategories.isEmpty {
                        Menu("Reconnect Folder…") {
                            ForEach(accessCategories) { category in
                                Button(category.title) { grant(category) }
                            }
                        }.disabled(busy)
                    }
                    Button("Full Disk Access…", action: openSettings)
                }
            }
            if issues.contains(where: { $0.kind == .ownership }) {
                Label("Protected files were skipped", systemImage: "person.badge.shield.checkmark")
                    .font(.headline)
                Text("Files owned by macOS or another user are left alone and aren’t included in the total.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if issues.contains(where: { $0.kind == .limit }) {
                Text("Some folders were too large to scan fully. They aren’t included in the total.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(issue.path).font(.caption).textSelection(.enabled)
                            Text(issue.message).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }.padding(.top, 8)
            } label: {
                Label("\(issues.count) folders skipped · Show details", systemImage: "exclamationmark.triangle")
                    .font(.callout)
            }
        }
        .padding(16)
        .background(AppTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.border))
    }
}

private struct ItemBrowser: View {
    @Bindable var model: CleanupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Choose what to remove").font(.title3.weight(.semibold))
                Spacer()
                Text("\(model.visibleItems.count) results").font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Text("Select only files you no longer need.")
                .font(.callout).foregroundStyle(AppTheme.secondaryText)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondaryText)
                TextField("Search names or paths", text: $model.search).textFieldStyle(.plain)
                if !model.search.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { model.search = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(10)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.border))
            if model.visibleItems.isEmpty {
                ContentUnavailableView("No matching items", systemImage: "line.3.horizontal.decrease",
                                       description: Text("Try another name or path."))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(model.visibleItems) { item in
                        CleanupItemRow(item: item, selected: $model[isSelected: item.id], busy: model.busy || model.grantingAccess,
                                       reveal: { model.reveal(item.url) }, exclude: { model.exclude(item) })
                    }
                }
            }
        }
    }
}

private struct CleanupItemRow: View {
    let item: CleanupItem
    @Binding var selected: Bool
    let busy: Bool
    let reveal: () -> Void
    let exclude: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $selected) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName).font(.headline).lineLimit(2)
                            Text(item.category.title).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Text(item.bytes, format: .byteCount(style: .file))
                            .font(.callout.weight(.semibold)).monospacedDigit().fixedSize()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .toggleStyle(.checkbox)
                .disabled(busy || !item.canClean)
                .accessibilityLabel("Select \(item.displayName)")
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.url.path).textSelection(.enabled)
                        Text(item.reason)
                        Text(item.modified, format: .dateTime.month().day().year())
                    }
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .padding(.top, 4)
                }
                .font(.caption)

            }
            Menu {
                Button("Reveal in Finder", systemImage: "folder", action: reveal)
                Button("Exclude from scans", systemImage: "minus.circle", action: exclude).disabled(busy)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).frame(width: 24)
            .accessibilityLabel("Actions for \(item.displayName)")
        }
        .padding(14)
        .background(selected ? AppTheme.selection : AppTheme.surface,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? AppTheme.accent : AppTheme.border))
    }
}

private struct CleanupFooter: View {
    @Bindable var model: CleanupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.visibleItems.contains(where: \.canClean) {
                HStack(spacing: 16) {
                    Button("Select all", action: model.selectEligible)
                        .disabled(model.busy || model.grantingAccess)
                    if !model.selected.isEmpty {
                        Button("Deselect all") { model.selected.removeAll() }
                            .disabled(model.busy || model.grantingAccess)
                    }
                }
                .buttonStyle(.borderless)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    SelectionSummary(count: model.selectedItems.count, bytes: model.selectedBytes)
                    Spacer(minLength: 0)
                    ReviewSelectionButton(model: model)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SelectionSummary(count: model.selectedItems.count, bytes: model.selectedBytes)
                    ReviewSelectionButton(model: model)
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(AppTheme.surface)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct SelectionSummary: View {
    let count: Int
    let bytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count == 0 ? "Choose files to continue" : "\(count) selected · \(bytes.formatted(.byteCount(style: .file)))")
                .font(.callout.weight(.semibold)).monospacedDigit()
            Text("You’ll review your selection before anything moves.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }
}

private struct ReviewSelectionButton: View {
    let model: CleanupModel

    var body: some View {
        Button { model.showConfirmation = true } label: {
            Label("Review selected files", systemImage: "arrow.right")
                .frame(minHeight: 28)
        }
        .buttonStyle(PrimaryActionStyle())
        .disabled(model.busy || model.grantingAccess || model.selectedItems.isEmpty)
        .help("Choose files above, then review them before moving to Trash.")
    }
}
