import SwiftUI
import NookCore

struct OrganiseView: View {
    @ObservedObject var model: NookModel
    @FocusState private var searchFocused: Bool
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        PaneTitle(title: "Organise")
                        VisibilityStatus(model: model)
                    }
                    Spacer()
                    if model.permissionGranted {
                        HStack(spacing: 12) {
                            PauseMenu(model: model)
                            Button("Show all") { model.showEverything() }.controlSize(.large)
                            Button(model.toggleTitle) { model.toggle() }.buttonStyle(NookPrimaryButtonStyle())
                                .disabled(model.applying || (!model.available && !model.isPaused))
                                .help(model.available ? "Show or hide apps using your saved rules" : model.compatibility)
                        }
                    }
                }
                if !model.permissionGranted {
                    PermissionView(model: model)
                    Spacer()
                } else {
                    HStack(spacing: 12) {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").foregroundStyle(NookStyle.muted).accessibilityHidden(true)
                            TextField("Search apps", text: $model.search).textFieldStyle(.plain).focused($searchFocused)
                                .accessibilityLabel("Search menu bar apps")
                            if !model.search.isEmpty {
                                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(NookStyle.muted).accessibilityLabel("Clear search")
                            }
                        }.font(.system(size: 13)).padding(.horizontal, 10).frame(height: 32)
                            .background(NookStyle.surface, in: RoundedRectangle(cornerRadius: 6))
                        Picker("Show apps", selection: $model.appFilter) {
                            ForEach(AppFilter.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 165)
                        Text("\(model.visibleEntries.count) of \(model.entries.count) apps")
                            .font(.system(size: 11)).foregroundStyle(NookStyle.muted).monospacedDigit().fixedSize()
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 28) }
                            .buttonStyle(.plain).accessibilityLabel("Refresh menu bar apps").help("Refresh menu bar apps")
                    }
                    if geometry.size.width >= 850 {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(Place.allCases) { place in
                                ScrollView { PlaceGroup(model: model, place: place) }.frame(maxWidth: .infinity)
                            }
                        }.frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(Place.allCases) { PlaceGroup(model: model, place: $0) }
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text("Groups are saved rules. Show all temporarily reveals every app.")
                        Spacer()
                        Text("⌘-drag icons in macOS to change native order.")
                    }.font(.system(size: 11)).foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(24)
        }.background {
            Button("Find apps") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden()
        }
    }
}

struct PlaceGroup: View {
    @ObservedObject var model: NookModel
    let place: Place
    @State private var isTargeted = false
    private var items: [AppEntry] { model.filtered(place) }
    private var detail: String {
        switch place {
        case .visible: return "Stay in the menu bar"
        case .tucked: return "Reveal with Nook"
        case .quiet: return "Reveal with Show all or search"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(place.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(items.count)").font(.system(size: 12)).monospacedDigit().foregroundStyle(NookStyle.muted)
            }
            Text(detail).font(.system(size: 11)).foregroundStyle(NookStyle.muted)
            VStack(spacing: 2) {
                ForEach(items) { entry in
                    AppRow(model: model, entry: entry)
                        .dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first, model.entries.contains(where: { $0.id == id }) else { return false }
                            model.assign(id, to: place, before: entry.id); return true
                        }
                }
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.search.isEmpty ? (model.appFilter == .running ? "No running apps here" : "No apps here") : "No matches")
                            .font(.system(size: 12))
                        Text(model.search.isEmpty ? "Drop an app here, or use its options menu." : "Try another name or clear the search.")
                            .font(.system(size: 11)).foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(NookStyle.surface, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(isTargeted ? NookStyle.teal.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isTargeted ? NookStyle.teal : .clear, lineWidth: 2))
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, model.entries.contains(where: { $0.id == id }) else { return false }
                model.assign(id, to: place); return true
            } isTargeted: { isTargeted = $0 }
    }
}

struct AppRow: View {
    @ObservedObject var model: NookModel
    let entry: AppEntry
    @State private var hovered = false
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.icon(entry.id)).resizable().frame(width: 26, height: 26)
                .opacity(entry.isRunning ? 1 : 0.6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(!entry.isRunning ? "Not running" : model.visibleIDs.contains(entry.id) ? "On menu bar" : "Hidden")
                    .font(.system(size: 11)).foregroundStyle(NookStyle.muted)
            }
            Spacer(minLength: 4)
            Menu { AppActions(model: model, entry: entry, runningOnly: model.appFilter == .running) } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 28)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Options for \(entry.displayName)").help("Options for \(entry.displayName)")
        }.padding(.horizontal, 8).padding(.vertical, 10).contentShape(Rectangle())
            .background(hovered ? NookStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovered = $0 }.help(entry.displayName)
            .draggable(entry.id)
            .contextMenu { AppActions(model: model, entry: entry, runningOnly: model.appFilter == .running) }
            .accessibilityElement(children: .contain).accessibilityLabel(entry.displayName)
    }
}

struct AppActions: View {
    @ObservedObject var model: NookModel
    let entry: AppEntry
    var runningOnly = false
    private var peers: [AppEntry] { model.sortedEntries.filter { model.preferences.place(for: $0.id) == model.preferences.place(for: entry.id) && (!runningOnly || $0.isRunning) } }
    var body: some View {
        ForEach(Place.allCases) { destination in
            Button { model.assign(entry.id, to: destination) } label: {
                Label(destination.title, systemImage: model.preferences.place(for: entry.id) == destination ? "checkmark" : destination.symbol)
            }
        }
        Divider()
        Button("Move up") { model.move(entry.id, by: -1, runningOnly: runningOnly) }.disabled(peers.first?.id == entry.id)
        Button("Move down") { model.move(entry.id, by: 1, runningOnly: runningOnly) }.disabled(peers.last?.id == entry.id)
        Divider()
        Button("Open menu") { model.revealApp(entry.id) }.disabled(!entry.isRunning)
        Button("Forget app") { model.forget(entry.id) }.disabled(entry.isRunning).help("Quit the app before removing its saved rule")
    }
}
