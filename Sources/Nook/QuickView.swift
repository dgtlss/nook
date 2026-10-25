import SwiftUI
import NookCore

struct QuickView: View {
    @ObservedObject var model: NookModel
    let openSettings: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 23, height: 23).accessibilityHidden(true)
                Text("Nook").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Menu {
                    Button("Nook Settings…") { openSettings() }
                    Divider()
                    Button("Pause for 5 minutes") { model.pauseHiding(minutes: 5) }
                    Button("Pause for 15 minutes") { model.pauseHiding(minutes: 15) }
                    Button("Pause until I resume") { model.pauseHiding() }
                    if model.isPaused { Button("Resume hiding") { model.resumeHiding() } }
                    Divider()
                    Button("Quit Nook") { NSApp.terminate(nil) }
                } label: { Label("Nook controls", systemImage: "ellipsis").labelStyle(.iconOnly).frame(width: 24, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Nook controls").help("Nook controls")
            }
            if model.permissionGranted {
                AppPicker(model: model, onlyHidden: false, close: close)
                VisibilityStatus(model: model)
                HStack {
                    Button(model.toggleTitle) { model.toggle() }.buttonStyle(NookPrimaryButtonStyle())
                        .disabled(model.applying || (!model.available && !model.isPaused))
                    Spacer()
                    Button("Show all") { model.showEverything() }.controlSize(.small)
                }
            } else {
                Text("Enable Accessibility to find and open your menu bar apps.")
                    .font(.system(size: 13)).foregroundStyle(NookStyle.muted)
                Button("Open Nook Settings") { openSettings() }.buttonStyle(NookPrimaryButtonStyle())
            }
        }.padding(16).frame(width: 360).background(NookStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .tint(NookStyle.primaryFill)
    }
}

struct AppPicker: View {
    @ObservedObject var model: NookModel
    let onlyHidden: Bool
    let close: () -> Void
    @State private var query = ""
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool

    private var results: [AppEntry] {
        let empty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let matches = model.sortedEntries.filter {
            if onlyHidden {
                return $0.isRunning && model.preferences.place(for: $0.id) == .tucked && model.matches($0, query: query)
            }
            return model.matches($0, query: query) && (!empty || ($0.isRunning && model.preferences.place(for: $0.id) != .visible))
        }
        return matches.filter(\.isRunning) + matches.filter { !$0.isRunning }
    }
    private var selectable: [AppEntry] { results.filter(\.isRunning) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(NookStyle.muted).accessibilityHidden(true)
                TextField(onlyHidden ? "Search hidden apps" : "Search apps", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused).onSubmit { activateSelection() }
                    .accessibilityLabel(onlyHidden ? "Search hidden apps" : "Search menu bar apps")
                if !query.isEmpty {
                    Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(NookStyle.muted).accessibilityLabel("Clear search")
                }
            }.font(.system(size: 14)).padding(10)
                .background(NookStyle.ground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(searchFocused ? NookStyle.teal : .clear, lineWidth: 1.5))
            if results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(query.isEmpty ? "No hidden apps are running" : "No apps found").font(.system(size: 13, weight: .medium))
                    Text(query.isEmpty ? "Choose apps in Organise to keep them here." : "Try an app name or bundle identifier.")
                        .font(.system(size: 12)).foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true)
                    if !query.isEmpty { Button("Clear search") { query = ""; searchFocused = true }.controlSize(.small) }
                }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(results) { entry in
                                Button { activate(entry) } label: {
                                    HStack(spacing: 10) {
                                        Image(nsImage: model.icon(entry.id)).resizable().frame(width: 24, height: 24).accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(entry.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                            if !entry.isRunning { Text("Not running").font(.system(size: 11)).foregroundStyle(NookStyle.muted) }
                                        }
                                        Spacer(minLength: 4)
                                        Text(model.preferences.place(for: entry.id).title).font(.system(size: 11)).foregroundStyle(NookStyle.muted)
                                    }.padding(.horizontal, 8).frame(height: 46).contentShape(Rectangle())
                                        .background(selectedID == entry.id ? NookStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain).disabled(!entry.isRunning).id(entry.id)
                                    .help("Open \(entry.displayName)’s menu")
                                    .accessibilityLabel("\(entry.displayName), \(entry.isRunning ? model.preferences.place(for: entry.id).title : "not running")")
                                    .accessibilityAddTraits(selectedID == entry.id ? .isSelected : [])
                                    .onHover { if $0 && entry.isRunning { selectedID = entry.id } }
                                    .contextMenu { AppActions(model: model, entry: entry, runningOnly: true) }
                            }
                        }
                    }.frame(height: CGFloat(min(results.count, 6)) * 48)
                        .onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            Text("↑↓ Select   Return Open   Esc Close").font(.system(size: 11)).foregroundStyle(NookStyle.muted)
        }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onExitCommand { close() }
        .onChange(of: results.map(\.id), initial: true) { _, _ in
            if !selectable.contains(where: { $0.id == selectedID }) { selectedID = selectable.first?.id }
        }
        .onAppear { query = ""; selectedID = selectable.first?.id; searchFocused = true }
    }
    private func moveSelection(_ offset: Int) {
        guard !selectable.isEmpty else { return }
        let current = selectable.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : selectable.count)
        selectedID = selectable[min(max(current + offset, 0), selectable.count - 1)].id
    }
    private func activateSelection() {
        guard let entry = selectable.first(where: { $0.id == selectedID }) else { return }
        activate(entry)
    }
    private func activate(_ entry: AppEntry) {
        close(); model.revealApp(entry.id)
    }
}

struct ShelfView: View {
    @ObservedObject var model: NookModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hidden apps").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Show all") { model.showEverything() }.controlSize(.small)
            }
            AppPicker(model: model, onlyHidden: true, close: { model.closeShelf?() })
        }.padding(16).frame(width: 360).background(NookStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .tint(NookStyle.primaryFill)
    }
}
