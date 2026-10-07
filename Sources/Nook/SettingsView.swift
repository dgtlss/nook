import SwiftUI
import NookCore

enum NookStyle {
    static let teal = Color(nsColor: NSColor(name: "NookTeal") { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.40, green: 0.80, blue: 0.70, alpha: 1)
        }
        return NSColor(red: 0.05, green: 0.36, blue: 0.32, alpha: 1)
    })
    static let orange = Color(red: 0.94, green: 0.54, blue: 0.18)
}

struct SettingsView: View {
    @ObservedObject var model: NookModel
    @ObservedObject var updates: UpdateController
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nook").font(.system(size: 23, weight: .bold, design: .rounded))
                    }
                }.padding(.horizontal, 18).padding(.top, 27).padding(.bottom, 28)
                ForEach(SettingsPane.allCases) { pane in
                    Button { model.selectedPane = pane } label: {
                        Label(pane.rawValue, systemImage: pane.symbol)
                            .font(.system(size: 13, weight: model.selectedPane == pane ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                            .background(model.selectedPane == pane ? NookStyle.teal.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).foregroundStyle(model.selectedPane == pane ? NookStyle.teal : .primary)
                    .padding(.horizontal, 10).padding(.bottom, 3)
                }
                Spacer()
                if !model.permissionGranted {
                    Label("Accessibility required", systemImage: "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(NookStyle.orange).padding(20)
                }
            }.frame(width: 194).background(.ultraThinMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                switch model.selectedPane {
                case .organise: OrganiseView(model: model)
                case .behaviour: BehaviourView(model: model)
                case .appearance: AppearanceView(model: model)
                case .about: AboutView(model: model, updates: updates)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 920, minHeight: 610).tint(NookStyle.teal)
        .onChange(of: model.preferences) { _, _ in model.updatePreferences() }
    }
}

struct PaneTitle: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 29, weight: .bold, design: .rounded))
            if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(.bottom, 24)
    }
}

struct PermissionView: View {
    @ObservedObject var model: NookModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hand.wave").font(.system(size: 28)).foregroundStyle(NookStyle.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accessibility required").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("Enable Nook in System Settings → Privacy & Security → Accessibility to find menu bar apps and open their menus.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button("Open Accessibility Settings") { model.openAccessibilitySettings() }.buttonStyle(.borderedProminent)
                Button("Check again") { model.refresh() }.buttonStyle(.bordered)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(NookStyle.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(NookStyle.teal.opacity(0.14)))
    }
}

struct OrganiseView: View {
    @ObservedObject var model: NookModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                PaneTitle(title: "Organise", subtitle: "Drag apps between groups to choose when they appear.")
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Refresh menu bar apps")
            }
            if !model.permissionGranted {
                PermissionView(model: model)
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "cursorarrow.click").font(.title2).foregroundStyle(NookStyle.teal)
                    Text("Click Nook to toggle hidden apps. Option-click to show all. Right-click for controls.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.bottom, 30)
            } else {
                HStack(spacing: 12) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search apps", text: $model.search).textFieldStyle(.plain)
                        if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search") }
                    }.padding(9).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    Button("Show all") { model.showEverything() }.buttonStyle(.bordered)
                    Button("Toggle hidden apps") { model.toggle() }.buttonStyle(.borderedProminent).disabled(model.applying || !model.available)
                }.padding(.bottom, 20)
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Place.allCases) { place in PlaceColumn(model: model, place: place) }
                }.frame(maxHeight: .infinity)
                HStack(spacing: 8) {
                    if model.applying { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.message == nil ? "checkmark.circle" : "info.circle").foregroundStyle(model.message == nil ? NookStyle.teal : NookStyle.orange) }
                    Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.top, 16)
                Text("Apps with multiple icons move together. ⌘-drag menu bar icons to reorder them.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        }.padding(30)
    }
}

struct PlaceColumn: View {
    @ObservedObject var model: NookModel
    var place: Place
    @State private var isTargeted = false
    var items: [AppEntry] { model.filtered(place) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: place.symbol).foregroundStyle(place == .visible ? NookStyle.teal : NookStyle.orange)
                Text(place.title).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(items.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.top, 14)
            Text(place == .visible ? "Always shown" : place == .tucked ? "Shown on request" : "Only with Show all")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { entry in
                        AppCard(model: model, entry: entry, place: place)
                            .dropDestination(for: String.self) { ids, _ in
                                guard let id = ids.first, model.entries.contains(where: { $0.id == id }) else { return false }
                                model.assign(id, to: place, before: entry.id); return true
                            }
                    }
                    if items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: place == .visible ? "sun.max" : "tray").font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                            Text(model.search.isEmpty ? "Drop an app here" : "No matches").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).frame(height: 125)
                    }
                }.padding(9)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isTargeted ? NookStyle.teal.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isTargeted ? NookStyle.teal : Color.primary.opacity(0.06)))
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, model.entries.contains(where: { $0.id == id }) else { return false }
                model.assign(id, to: place); return true
            } isTargeted: { isTargeted = $0 }
    }
}

struct AppCard: View {
    @ObservedObject var model: NookModel
    var entry: AppEntry
    var place: Place
    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: model.icon(entry.id)).resizable().frame(width: 27, height: 27).opacity(entry.isRunning ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(!entry.isRunning ? "Not running" : model.visibleIDs.contains(entry.id) ? "On menu bar" : "Hidden")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(Place.allCases) { destination in
                    Button { model.assign(entry.id, to: destination) } label: { Label(destination.title, systemImage: destination == place ? "checkmark" : destination.symbol) }
                }
                Divider()
                Button("Open menu") { model.revealApp(entry.id) }.disabled(!entry.isRunning)
            } label: { Image(systemName: "ellipsis").frame(width: 14) }.menuStyle(.borderlessButton).fixedSize().help("Options for \(entry.name)")
        }.padding(10).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .draggable(entry.id)
            .accessibilityElement(children: .contain).accessibilityLabel(entry.name)
    }
}

struct BehaviourView: View {
    @ObservedObject var model: NookModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaneTitle(title: "Behaviour")
                Form {
                    Section("General") {
                        Toggle("Launch Nook at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLogin($0) }))
                        Toggle("Show hidden apps in the shelf", isOn: $model.preferences.useShelf)
                        Text("When off, hidden icons appear in the menu bar.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Show hidden apps") {
                        Toggle("Hover over Nook", isOn: $model.preferences.showOnHover)
                        Toggle("Scroll in the menu bar", isOn: $model.preferences.showOnScroll)
                        Toggle("Click empty menu bar space", isOn: $model.preferences.showOnEmptyClick)
                    }
                    Section("Auto-hide") {
                        Toggle("Hide after a temporary reveal", isOn: $model.preferences.rehide)
                        Text("Applies to hover, scroll and empty-space clicks. Clicking Nook keeps apps shown until the next click.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Delay")
                            Slider(value: $model.preferences.rehideDelay, in: 2...60, step: 1).frame(width: 175).accessibilityLabel("Auto-hide delay")
                            Text("\(Int(model.preferences.rehideDelay)) s").monospacedDigit().frame(width: 36)
                        }.disabled(!model.preferences.rehide)
                        Text("Waits while the pointer is in the menu bar or a menu is open.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Shortcuts") {
                        Toggle("Enable keyboard shortcuts", isOn: $model.preferences.hotkeyEnabled)
                        if let issue = model.shortcutIssue { Text(issue).font(.caption).foregroundStyle(NookStyle.orange) }
                        LabeledContent("Toggle hidden apps", value: "⌃⌥N")
                        LabeledContent("Search apps", value: "⌃⌥Space")
                        LabeledContent("Show all apps", value: "⌃⌥⇧N")
                    }
                }.formStyle(.grouped)
            }.padding(30)
        }
    }
}

struct AppearanceView: View {
    @ObservedObject var model: NookModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaneTitle(title: "Appearance")
                HStack {
                    Image(systemName: "apple.logo")
                    Text("Finder   File   Edit   View").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: "wifi"); Image(systemName: "battery.75percent"); Text("9:41").font(.system(size: 11))
                }.padding(13).background(Color(hex: model.preferences.tintHex).opacity(model.preferences.tintEnabled ? model.preferences.tintOpacity + 0.08 : 0.04), in: RoundedRectangle(cornerRadius: model.preferences.shape == .full ? 0 : 12))
                    .overlay(RoundedRectangle(cornerRadius: model.preferences.shape == .full ? 0 : 12).strokeBorder(model.preferences.borderEnabled ? Color(hex: model.preferences.tintHex).opacity(0.4) : .clear))
                    .padding(.bottom, 20).accessibilityLabel("Menu bar appearance preview")
                Form {
                    Section("Menu bar icon") {
                        HStack(spacing: 10) {
                            ForEach(MenuBarIcon.allCases) { choice in
                                Button { model.preferences.menuBarIcon = choice } label: {
                                    VStack(spacing: 8) {
                                        Image(nsImage: MenuBarArtwork.image(choice, peeking: true)).frame(width: 24, height: 24)
                                        Text(choice.title).font(.system(size: 11))
                                    }.frame(width: 68, height: 60)
                                        .contentShape(Rectangle())
                                        .background(model.preferences.menuBarIcon == choice ? NookStyle.teal.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.preferences.menuBarIcon == choice ? NookStyle.teal : Color.primary.opacity(0.12)))
                                }.buttonStyle(.plain)
                                .accessibilityLabel("\(choice.title) menu bar icon")
                                .accessibilityAddTraits(model.preferences.menuBarIcon == choice ? .isSelected : [])
                            }
                        }
                    }
                    Section("Menu bar") {
                        Toggle("Colour tint", isOn: $model.preferences.tintEnabled)
                        ColorPicker("Tint colour", selection: Binding(get: { Color(hex: model.preferences.tintHex) }, set: { model.preferences.tintHex = $0.hex }), supportsOpacity: false).disabled(!model.preferences.tintEnabled)
                        HStack { Text("Tint strength"); Slider(value: $model.preferences.tintOpacity, in: 0.03...0.6).accessibilityLabel("Tint strength"); Text("\(Int(model.preferences.tintOpacity * 100))%").monospacedDigit().frame(width: 40) }.disabled(!model.preferences.tintEnabled)
                        Picker("Tint shape", selection: $model.preferences.shape) { ForEach(BarShape.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Toggle("Border", isOn: $model.preferences.borderEnabled)
                        Toggle("Shadow", isOn: $model.preferences.shadowEnabled)
                    }
                }.formStyle(.grouped)
            }.padding(30)
        }
    }
}

struct AboutView: View {
    @ObservedObject var model: NookModel
    @ObservedObject var updates: UpdateController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nook").font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Open-source menu bar manager.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Updates").font(.headline)
                    if let error = updates.configurationError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Toggle("Automatically check for updates", isOn: Binding(
                            get: { updates.automaticallyChecks }, set: updates.setAutomaticallyChecks))
                        Toggle("Download and install updates automatically", isOn: Binding(
                            get: { updates.automaticallyInstalls }, set: updates.setAutomaticallyInstalls))
                            .disabled(!updates.automaticallyChecks)
                        Text("Checks daily. Automatic updates install when Nook quits.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Check for Updates…") { updates.checkForUpdates() }
                                .disabled(!updates.canCheckForUpdates)
                            if let checked = updates.lastCheck {
                                Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings").font(.headline)
                    HStack {
                        Button("Export settings…") { model.exportSettings() }
                        Button("Import settings…") { model.importSettings() }
                        Button("Show settings in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.storeURL]) }
                    }
                }
                DisclosureGroup("Diagnostics") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Visible menu bar apps", value: "\(model.visibleIDs.count)")
                        LabeledContent("Nook toggle", value: model.controlReachable ? "Available" : "Unavailable")
                        if let checked = model.lastVerified {
                            LabeledContent("Last visibility check", value: checked.formatted(date: .omitted, time: .standard))
                        }
                    }.font(.caption).padding(.top, 12)
                }
                Text("© 2026 Nathan Langer · MIT License").font(.caption).foregroundStyle(.secondary)
                Button("Third-party licences") {
                    if let url = Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: "txt") {
                        NSWorkspace.shared.open(url)
                    }
                }.font(.caption).buttonStyle(.link)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(36)
        }
    }
}

extension Color {
    init(hex: String) {
        let n = UInt64(hex, radix: 16) ?? 0x146B60
        self.init(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.deviceRGB) ?? .systemTeal
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
