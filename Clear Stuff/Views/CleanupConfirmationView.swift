import SwiftUI

struct CleanupConfirmationView: View {
    let model: CleanupModel
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Move these files to Trash?", systemImage: "trash")
                .font(.title2.weight(.semibold))
            Text("\(model.selectedItems.count) selected · \(model.selectedBytes.formatted(.byteCount(style: .file)))")
                .font(.headline).monospacedDigit()
            Text("You can restore them from Finder’s Trash until it’s emptied.")
                .font(.callout).foregroundStyle(AppTheme.secondaryText)
            List(model.selectedItems) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayName).font(.headline)
                        Text(item.url.path).font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1).truncationMode(.middle)
                            .help(item.url.path).textSelection(.enabled)
                    }
                    Spacer()
                    Text(item.bytes, format: .byteCount(style: .file))
                        .font(.callout).monospacedDigit()
                }.padding(.vertical, 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("Close the apps using these files. Saved offline data may be lost; apps may need to download or rebuild files.")
                .font(.callout).foregroundStyle(AppTheme.secondaryText)
            DisclosureGroup("What happens to these files?") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(CleanupCategory.allCases.filter { category in model.selectedItems.contains { $0.category == category } }) { category in
                        Text(category.consequence)
                    }
                    Text("Files that changed or can’t be accessed will be skipped. Empty Trash in Finder to free storage.")
                }
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                .padding(.top, 8)
            }
            Toggle("I’ve closed affected apps and stopped builds, downloads, and installers.", isOn: $acknowledged)
                .toggleStyle(.checkbox)
            HStack(spacing: 16) {
                Button("Go back") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Move to Trash", role: .destructive) {
                    dismiss()
                    model.clean()
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(!acknowledged || model.selectedItems.isEmpty || model.busy || model.grantingAccess)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 620, minHeight: 540, idealHeight: 620)
        .background(AppTheme.canvas)
    }
}

struct ActivityView: View {
    let records: [CleanupRecord]
    let reveal: (URL) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History").font(.largeTitle).fontWeight(.semibold)
            Text("See what moved to Trash and what was skipped.")
                .foregroundStyle(AppTheme.secondaryText)
            if records.isEmpty {
                ContentUnavailableView("No cleanup yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Your completed and skipped actions will appear here."))
            } else {
                List(records) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: record.path).lastPathComponent).font(.headline)
                            Text(record.path).font(.caption).foregroundStyle(AppTheme.secondaryText).textSelection(.enabled)
                            Text(record.outcome).font(.callout)
                            Text(record.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        if let trashPath = record.trashPath {
                            Button("Show in Trash") { reveal(URL(fileURLWithPath: trashPath)) }
                        }
                    }.padding(.vertical, 6)
                }
            }
            Spacer(minLength: 0)
        }.padding(24).navigationTitle("History")
    }
}

struct CleanupSettingsView: View {
    let model: CleanupModel
    var body: some View {
        Form {
            Section("Folder access") {
                FolderAccessActions(model: model)
                ForEach(CleanupCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 8) {
                        FolderAccessRow(category: category, root: model.roots[category], busy: model.busy || model.grantingAccess) { model.grant(category) }
                        if model.roots[category] != nil {
                            Button("Remove Access") { model.revoke(category) }.disabled(model.busy || model.grantingAccess)
                        }
                    }
                }
            }
            Section("Excluded locations") {
                Text("\(model.exclusions.count) items excluded")
                ForEach(model.exclusions.sorted(), id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                Button("Reset Exclusions", action: model.resetExclusions).disabled(model.busy || model.exclusions.isEmpty)
            }
            Section("Need help with folder access?") {
                Text("If a folder can’t be read, allow Clear Stuff in System Settings, then quit and reopen the app.")
                    .foregroundStyle(AppTheme.secondaryText)
                Button("Open Full Disk Access…", action: model.openSystemSettings)
                    .disabled(model.grantingAccess)
            }
            Section("About cleanup") {
                DisclosureGroup("Which files are included?") {
                    Text("App and browser caches, Xcode build files, logs, unfinished downloads, and saved installers. Review each file before removing it.")
                    Text("Browser passwords, bookmarks, and history are preserved. Download results may include incomplete ZIPs; keep files you still need.")
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            Section("Privacy") {
                Text("Everything stays on your Mac. Cleanup history stores the last 100 file paths locally until you clear it. Nothing is removed automatically.")
                Button("Clear Cleanup History", role: .destructive, action: model.clearHistory)
                    .disabled(model.busy || model.history.isEmpty)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvas)
        .navigationTitle("Settings")
    }
}
