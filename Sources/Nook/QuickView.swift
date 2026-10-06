import SwiftUI
import NookCore

struct QuickView: View {
    @ObservedObject var model: NookModel
    var openSettings: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 35, height: 35)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nook").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button { openSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Nook settings")
            }
            if !model.permissionGranted {
                Button("Open settings") { openSettings() }.buttonStyle(.borderedProminent)
            } else {
                HStack {
                    Button("Toggle hidden apps") { model.toggle() }.buttonStyle(.borderedProminent)
                    Button("Show all") { model.showEverything() }.buttonStyle(.bordered)
                    Spacer()
                }
                TextField("Search apps", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.sortedEntries.filter { query.isEmpty ? model.preferences.place(for: $0.id) != .visible : $0.name.localizedCaseInsensitiveContains(query) }) { entry in
                            Button { model.revealApp(entry.id) } label: {
                                HStack(spacing: 10) {
                                    Image(nsImage: model.icon(entry.id)).resizable().frame(width: 22, height: 22)
                                    Text(entry.name).font(.system(size: 12))
                                    Spacer()
                                    Image(systemName: model.preferences.place(for: entry.id).symbol).font(.system(size: 10)).foregroundStyle(.secondary)
                                }.padding(.vertical, 7).padding(.horizontal, 5).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!entry.isRunning)
                        }
                    }
                }.frame(maxHeight: 245)
                if model.hiddenCount == 0 && query.isEmpty {
                    Text("Choose apps to hide in Settings.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                if model.preferences.hotkeyEnabled { Text("Toggle: ⌃⌥N").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                Button("Quit Nook") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(18).frame(width: 310).tint(NookStyle.teal)
        .onAppear { searchFocused = true }
    }
}

struct ShelfView: View {
    @ObservedObject var model: NookModel
    private var apps: [AppEntry] { model.sortedEntries.filter { model.preferences.place(for: $0.id) == .tucked } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hidden apps").font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Button("Show all") { model.showEverything() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(NookStyle.teal)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(apps) { entry in
                        Button { model.revealApp(entry.id) } label: {
                            VStack(spacing: 5) {
                                Image(nsImage: model.icon(entry.id)).resizable().frame(width: 28, height: 28)
                                Text(entry.name).font(.system(size: 9)).lineLimit(1).frame(width: 58)
                            }.padding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!entry.isRunning).help("Open \(entry.name)’s menu")
                    }
                }
            }.scrollIndicators(.hidden).frame(height: 72)
            if apps.isEmpty { Text("No hidden apps. Add apps in Settings.").font(.caption).foregroundStyle(.secondary) }
        }.padding(14).frame(width: min(560, max(260, CGFloat(apps.count) * 64 + 22)))
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
