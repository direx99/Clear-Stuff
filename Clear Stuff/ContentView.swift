import SwiftUI

private enum AppSection: Hashable {
    case overview, category(CleanupCategory), activity, settings
}

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = CleanupModel()
    @State private var section: AppSection? = .overview

    @State private var sidebarVisible = true
    @State private var compactWindow = false
    @State private var navigationHistory: [AppSection?] = [.overview]
    @State private var historyIndex = 0

    var body: some View {
        GeometryReader { geometry in
            let showsSidebar = sidebarVisible && geometry.size.width >= 980
            HStack(spacing: 0) {
                if showsSidebar {
                    AppSidebar(model: model, selection: $section)
                        .frame(width: 220)
                    Divider()
                }
                VStack(spacing: 0) {
                    if !showsSidebar {
                        CompactNavigation(selection: $section)
                        Divider()
                    }
                    Group {
                        switch section {
                        case .activity:
                            ActivityView(records: model.history, reveal: model.reveal)
                        case .settings:
                            CleanupSettingsView(model: model)
                        default:
                            ScanDashboard(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 980 } action: { compactWindow = $0 }
        .background(AppTheme.canvas)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Back", systemImage: "arrow.left") {
                    historyIndex -= 1
                    section = navigationHistory[historyIndex]
                }
                .disabled(historyIndex == 0)
                .help("Go back")
                Button("Forward", systemImage: "arrow.right") {
                    historyIndex += 1
                    section = navigationHistory[historyIndex]
                }
                .disabled(historyIndex == navigationHistory.count - 1)
                .help("Go forward")
                if !compactWindow {
                    Button("Toggle Sidebar", systemImage: "sidebar.left") {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0)) {
                            sidebarVisible.toggle()
                        }
                    }
                    .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
                    .keyboardShortcut("s", modifiers: [.command, .control])
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.busy { model.cancel() } else { model.scan() }
                } label: {
                    Label(model.busy ? "Cancel" : "Scan Folders",
                          systemImage: model.busy ? "stop.circle" : "magnifyingglass")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.grantingAccess || (!model.busy && model.roots.isEmpty))
            }
        }
        .toolbarBackground(AppTheme.canvas, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .onChange(of: section) {
            if navigationHistory[historyIndex] != section {
                navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
                navigationHistory.append(section)
                historyIndex = navigationHistory.count - 1
            }
            if case .category(let category) = section { model.category = category }
            else { model.category = nil }
        }
        .sheet(isPresented: $model.showConfirmation) { CleanupConfirmationView(model: model) }
        .alert("Clear Stuff", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .frame(minWidth: 580, minHeight: 520)
        .tint(AppTheme.action)
    }
}

private struct CompactNavigation: View {
    @Binding var selection: AppSection?

    var body: some View {
        HStack {
            Menu {
                Button("Overview", systemImage: "square.grid.2x2") { selection = .overview }
                Section("Cleanup categories") {
                    ForEach(CleanupCategory.allCases) { category in
                        Button(category.title, systemImage: category.icon) { selection = .category(category) }
                    }
                }
                Divider()
                Button("History", systemImage: "clock.arrow.circlepath") { selection = .activity }
                Button("Settings", systemImage: "gearshape") { selection = .settings }
            } label: {
                Label("Browse", systemImage: "sidebar.left")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Navigate to a category, activity, or settings")
            Spacer()
            Label("Clear Stuff", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

private struct AppSidebar: View {
    let model: CleanupModel
    @Binding var selection: AppSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarHeader(model: model)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    SidebarRow(title: "Overview", icon: "square.grid.2x2", selected: selection == .overview) {
                        selection = .overview
                    }
                    Text("Folders")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 6)
                    ForEach(CleanupCategory.allCases) { category in
                        SidebarRow(title: LocalizedStringKey(String(localized: category.title)),
                                   icon: category.icon, selected: selection == .category(category)) {
                            selection = .category(category)
                        }
                    }
                }.padding(.horizontal, 12)
            }
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                SidebarRow(title: "History", icon: "clock.arrow.circlepath", selected: selection == .activity) {
                    selection = .activity
                }
                SidebarRow(title: "Settings", icon: "gearshape", selected: selection == .settings) {
                    selection = .settings
                }
                Label("Private. On your Mac.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }.padding(20)
        }
        .background(AppTheme.sidebar, ignoresSafeAreaEdges: [])
    }
}

private struct SidebarRow: View {
    let title: LocalizedStringKey
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title).fontWeight(.medium)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12).padding(.vertical, 11)
            .foregroundStyle(selected ? AppTheme.accent : AppTheme.secondaryText)
            .background(selected ? AppTheme.selection : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SidebarHeader: View {
    let model: CleanupModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Clear Stuff").font(.system(size: 17, weight: .semibold))
            Spacer()
            if model.busy { ProgressView().controlSize(.mini) }
        }
        .padding(20)
    }
}

#Preview {
    ContentView()
}
