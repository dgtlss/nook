import SwiftUI
import NookCore

enum NookStyle {
    static func adaptive(_ name: String, light: Double, dark: Double) -> Color {
        Color(nsColor: NSColor(name: name) { appearance in
            NSColor(white: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light, alpha: 1)
        })
    }
    static let ground = adaptive("NookGround", light: 0.97, dark: 0.06)
    static let surface = adaptive("NookSurface", light: 1, dark: 0.105)
    static let raised = adaptive("NookRaised", light: 0.92, dark: 0.17)
    static let primaryFill = adaptive("NookPrimary", light: 0.10, dark: 0.94)
    static let primaryInk = adaptive("NookPrimaryInk", light: 1, dark: 0.06)
    static let muted = adaptive("NookMuted", light: 0.38, dark: 0.70)
    static let teal = Color(nsColor: NSColor(name: "NookTeal") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.40, green: 0.80, blue: 0.70, alpha: 1)
            : NSColor(red: 0.05, green: 0.36, blue: 0.32, alpha: 1)
    })
    static let orange = Color(nsColor: NSColor(name: "NookWarning") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .systemOrange : NSColor(red: 0.62, green: 0.28, blue: 0.02, alpha: 1)
    })
}

struct NookPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).frame(height: 32)
            .foregroundStyle(enabled ? NookStyle.primaryInk : Color.secondary)
            .background(enabled ? NookStyle.primaryFill : NookStyle.raised, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? NookStyle.teal : .clear, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct SettingsView: View {
    @ObservedObject var model: NookModel
    @ObservedObject var updates: UpdateController
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                HStack(spacing: 9) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30).accessibilityHidden(true)
                    Text("Nook").font(.system(size: 19, weight: .semibold, design: .rounded))
                }
                Spacer(minLength: 16)
                HStack(spacing: 4) {
                    ForEach(SettingsPane.allCases) { pane in
                        Button {
                            model.recordingShortcut = nil
                            model.selectedPane = pane
                        } label: {
                            Text(pane.rawValue).font(.system(size: 13, weight: model.selectedPane == pane ? .semibold : .regular))
                                .padding(.horizontal, 13).frame(height: 32)
                                .contentShape(Rectangle())
                                .background(model.selectedPane == pane ? NookStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(model.selectedPane == pane ? .isSelected : [])
                    }
                }.disabled(model.showingSetup)
            }.padding(.horizontal, 24).padding(.vertical, 12)
            Divider().opacity(0.45)
            Group {
                if model.showingSetup { SetupView(model: model) }
                else {
                    switch model.selectedPane {
                    case .organise: OrganiseView(model: model)
                    case .behaviour: BehaviourView(model: model)
                    case .appearance: AppearanceView(model: model)
                    case .about: AboutView(model: model, updates: updates)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let feedback = model.feedback {
                HStack(spacing: 12) {
                    Text(feedback).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if model.feedbackCanUndo, model.undoManager.canUndo {
                        Button("Undo") { model.undoManager.undo() }.controlSize(.small)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 10).background(NookStyle.raised)
            }
        }.frame(minWidth: 760, minHeight: 550).background(NookStyle.ground)
            .tint(NookStyle.primaryFill)
            .onChange(of: model.preferences) { _, _ in model.updatePreferences() }
            .onChange(of: model.selectedPane) { _, _ in model.recordingShortcut = nil }
    }
}

struct PaneTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .semibold))
            if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true) }
        }.accessibilityElement(children: .combine)
    }
}

struct VisibilityStatus: View {
    @ObservedObject var model: NookModel
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            if model.applying { ProgressView().controlSize(.small) }
            else {
                Image(systemName: model.message != nil || !model.permissionGranted || !model.available
                      ? "exclamationmark.circle" : model.isPaused ? "pause.circle" : "circle.fill")
                    .font(.system(size: model.message != nil || model.isPaused ? 12 : 7))
                    .foregroundStyle(model.message != nil || !model.permissionGranted || !model.available ? NookStyle.orange : NookStyle.teal)
                    .frame(width: 13, height: 16).accessibilityHidden(true)
            }
            Text(model.status).font(.system(size: 12)).foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}

struct PauseMenu: View {
    @ObservedObject var model: NookModel
    var body: some View {
        Menu {
            if model.isPaused { Button("Resume hiding") { model.resumeHiding() }; Divider() }
            Button("Pause for 5 minutes") { model.pauseHiding(minutes: 5) }
            Button("Pause for 15 minutes") { model.pauseHiding(minutes: 15) }
            Button("Pause until I resume") { model.pauseHiding() }
        } label: { Label("Pause", systemImage: "pause") }
            .menuStyle(.borderlessButton).tint(NookStyle.primaryFill).fixedSize().help("Keep every app visible and suspend automatic hiding")
    }
}

struct PermissionView: View {
    @ObservedObject var model: NookModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your menu bar").font(.system(size: 17, weight: .semibold))
            Text("Enable Nook in System Settings → Privacy & Security → Accessibility to find menu bar apps and open their menus. Screen Recording is not required.")
                .font(.system(size: 13)).foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Accessibility Settings") { model.openAccessibilitySettings() }.buttonStyle(NookPrimaryButtonStyle())
                Button("Check again") { model.refresh() }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(NookStyle.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NookStyle.surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control
        }.padding(.vertical, 10)
    }
}

struct SettingsToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var enabled = true
    var body: some View {
        SettingRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!enabled)
        }
    }
}

struct BehaviourView: View {
    @ObservedObject var model: NookModel
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PaneTitle(title: "Behaviour", subtitle: "Choose how apps reveal, then settle back into place.")
                    if geometry.size.width >= 900 {
                        HStack(alignment: .top, spacing: 20) {
                            interactionSettings.frame(maxWidth: .infinity)
                            shortcutSettings.frame(maxWidth: .infinity)
                        }
                    } else { interactionSettings; shortcutSettings }
                }.padding(24)
            }
        }.onDisappear { model.recordingShortcut = nil }
    }
    private var interactionSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "General") {
                SettingsToggle(title: "Launch Nook at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLogin($0) }))
                Divider()
                SettingsToggle(title: "Reveal in the shelf", detail: "Use a searchable shelf instead of revealing icons across the menu bar.", isOn: $model.preferences.useShelf)
            }
            SettingsSection(title: "Reveal gestures") {
                SettingsToggle(title: "Hover over Nook", isOn: $model.preferences.showOnHover)
                Divider()
                SettingsToggle(title: "Scroll in the menu bar", isOn: $model.preferences.showOnScroll)
                Divider()
                SettingsToggle(title: "Click empty menu bar space", isOn: $model.preferences.showOnEmptyClick)
            }.font(.system(size: 13)).toggleStyle(.switch).controlSize(.small)
            SettingsSection(title: "Temporary reveals") {
                SettingsToggle(title: "Hide again automatically", isOn: $model.preferences.rehide)
                HStack(spacing: 12) {
                    Text("After").font(.system(size: 13))
                    Slider(value: $model.preferences.rehideDelay, in: 2...60, step: 1).accessibilityLabel("Auto-hide delay").disabled(!model.preferences.rehide)
                    Text("\(Int(model.preferences.rehideDelay)) s").font(.system(size: 12)).monospacedDigit().frame(width: 36, alignment: .trailing)
                }.padding(.bottom, 10)
                Text("Applies to gestures. Clicking Nook keeps apps shown until your next click. Hiding waits while a menu is open or the pointer is over the menu bar.")
                    .font(.system(size: 11)).foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
            }
        }
    }
    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Keyboard shortcuts") {
                SettingsToggle(title: "Enable shortcuts", isOn: $model.preferences.hotkeyEnabled)
                Divider()
                ForEach(ShortcutAction.allCases) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(action.title).font(.system(size: 13))
                            Spacer(minLength: 8)
                            ShortcutRecorder(model: model, action: action).frame(width: 145, height: 30)
                        }
                        if let issue = model.shortcutValidationIssues[action] ?? model.shortcutIssues[action] {
                            Text(issue).font(.system(size: 11)).foregroundStyle(NookStyle.orange).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.vertical, 9)
                }
                HStack {
                    Text(model.preferences.hotkeyEnabled ? "Click a shortcut to record. Escape cancels." : "Enable shortcuts to edit them.")
                        .font(.system(size: 11)).foregroundStyle(NookStyle.muted)
                    Spacer()
                    Button("Reset") { model.resetShortcuts() }.controlSize(.small).help("Restore the three default shortcuts")
                }.padding(.vertical, 10)
            }
            SettingsSection(title: "Take a pause") {
                Text("Keep every icon visible while you work. Reveal gestures and the auto-hide timer stay paused until you resume.")
                    .font(.system(size: 12)).foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                HStack { VisibilityStatus(model: model); Spacer(); PauseMenu(model: model) }.padding(.vertical, 12)
            }
        }
    }
}

struct AppearanceView: View {
    @ObservedObject var model: NookModel
    @State private var previewShown = false
    @State private var theme = PreviewTheme.system
    @State private var notched = (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PaneTitle(title: "Appearance", subtitle: "Preview the same icon, tint and shape used in your menu bar.")
                    VStack(spacing: 14) {
                        HStack {
                            Text("Preview").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("Preview appearance", selection: $theme) {
                                ForEach(PreviewTheme.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                        }
                        MenuBarPreview(preferences: model.preferences, shown: previewShown, theme: theme, notched: notched).frame(height: 42)
                        HStack {
                            Picker("Icon state", selection: $previewShown) {
                                Text("Icons hidden").tag(false); Text("Icons shown").tag(true)
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                            Spacer()
                            Toggle("Notched display", isOn: $notched).toggleStyle(.checkbox).font(.system(size: 12))
                        }
                    }.padding(16).background(NookStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                    if geometry.size.width >= 900 {
                        HStack(alignment: .top, spacing: 20) { iconSettings.frame(maxWidth: .infinity); barSettings.frame(maxWidth: .infinity) }
                    } else { iconSettings; barSettings }
                }.padding(24)
            }
        }
    }
    private var iconSettings: some View {
        SettingsSection(title: "Nook’s menu bar icon") {
            HStack(spacing: 8) {
                ForEach(MenuBarIcon.allCases) { choice in
                    Button { model.preferences.menuBarIcon = choice } label: {
                        VStack(spacing: 7) {
                            Image(nsImage: MenuBarArtwork.image(choice, peeking: previewShown)).frame(width: 24, height: 24)
                            Text(choice.title).font(.system(size: 11))
                        }.frame(width: 62, height: 62)
                            .contentShape(Rectangle())
                            .background(model.preferences.menuBarIcon == choice ? NookStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .topTrailing) {
                                if model.preferences.menuBarIcon == choice { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).padding(5) }
                            }
                    }.buttonStyle(.plain).accessibilityLabel("\(choice.title) menu bar icon")
                        .accessibilityAddTraits(model.preferences.menuBarIcon == choice ? .isSelected : [])
                }
            }.padding(.vertical, 10)
            Text("Changes apply immediately. Preview both visibility states above.")
                .font(.system(size: 11)).foregroundStyle(NookStyle.muted).padding(.bottom, 10)
        }
    }
    private var barSettings: some View {
        SettingsSection(title: "Menu bar finish") {
            SettingsToggle(title: "Colour tint", isOn: $model.preferences.tintEnabled)
            Divider()
            SettingRow(title: "Tint colour") {
                ColorPicker("Tint colour", selection: Binding(get: { Color(hex: model.preferences.tintHex) }, set: { model.preferences.tintHex = $0.hex }), supportsOpacity: false)
                    .labelsHidden().disabled(!model.preferences.tintEnabled)
            }
            HStack {
                Text("Strength").font(.system(size: 13))
                Slider(value: $model.preferences.tintOpacity, in: 0.03...0.6).accessibilityLabel("Tint strength").disabled(!model.preferences.tintEnabled)
                Text("\(Int(model.preferences.tintOpacity * 100))%").font(.system(size: 12)).monospacedDigit().frame(width: 36, alignment: .trailing)
            }.padding(.bottom, 10)
            if !model.preferences.tintEnabled {
                Text("Enable Colour tint to edit its colour and strength.").font(.system(size: 11)).foregroundStyle(NookStyle.muted).padding(.bottom, 10)
            }
            Divider()
            SettingRow(title: "Shape") {
                Picker("Shape", selection: $model.preferences.shape) {
                    ForEach(BarShape.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize()
            }
            SettingsToggle(title: "Border", isOn: $model.preferences.borderEnabled)
            SettingsToggle(title: "Shadow", isOn: $model.preferences.shadowEnabled)
        }.font(.system(size: 13)).toggleStyle(.switch).controlSize(.small)
    }
}

enum PreviewTheme: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

struct MenuBarPreview: View {
    let preferences: Preferences
    let shown: Bool
    let theme: PreviewTheme
    let notched: Bool
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { theme == .dark || (theme == .system && scheme == .dark) }
    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = notched ? min(100, geometry.size.width * 0.15) : 0
            let notch = notched ? CGRect(x: geometry.size.width / 2 - gap / 2, y: 0, width: gap, height: geometry.size.height) : nil
            ZStack(alignment: .top) {
                Color(white: dark ? 0.13 : 0.92)
                MenuBarTint(preferences: preferences, notch: notch, barHeight: 32)
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                    Text("Finder").fontWeight(.semibold)
                    Text("File   Edit   View")
                    Spacer()
                    Image(nsImage: MenuBarArtwork.image(preferences.menuBarIcon, peeking: shown)).renderingMode(.template).frame(width: 20)
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75percent")
                    Text("9:41").monospacedDigit()
                }.font(.system(size: 12)).foregroundStyle(dark ? .white : .black).padding(.horizontal, 15).frame(height: 32)
                if notched { RoundedRectangle(cornerRadius: 7).fill(.black).frame(width: gap, height: 24).offset(y: -5).accessibilityHidden(true) }
            }.clipShape(RoundedRectangle(cornerRadius: 6))
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Menu bar preview: \(preferences.menuBarIcon.title), icons \(shown ? "shown" : "hidden"), \(preferences.shape.title) shape\(notched ? ", notched display" : "")")
    }
}

struct AboutView: View {
    @ObservedObject var model: NookModel
    @ObservedObject var updates: UpdateController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48).accessibilityHidden(true)
                    PaneTitle(title: "About Nook", subtitle: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · Open-source menu bar manager")
                    Spacer()
                }
                SettingsSection(title: "Updates") {
                    if let error = updates.configurationError {
                        Text(error).font(.system(size: 13)).foregroundStyle(NookStyle.muted).padding(.vertical, 12)
                    } else {
                        SettingsToggle(title: "Automatically check for updates", isOn: Binding(get: { updates.automaticallyChecks }, set: updates.setAutomaticallyChecks))
                        SettingsToggle(title: "Download and install automatically", isOn: Binding(get: { updates.automaticallyInstalls }, set: updates.setAutomaticallyInstalls), enabled: updates.automaticallyChecks)
                        HStack {
                            Button("Check for Updates…") { updates.checkForUpdates() }.disabled(!updates.canCheckForUpdates)
                            Spacer()
                            Text(updates.lastCheck.map { "Last checked \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not checked yet")
                                .font(.system(size: 11)).foregroundStyle(NookStyle.muted)
                        }.padding(.bottom, 10)
                        Text(updates.automaticallyChecks ? "Checks daily. Automatic installation happens when Nook quits." : "Enable automatic checks to allow automatic installation.")
                            .font(.system(size: 11)).foregroundStyle(NookStyle.muted).padding(.bottom, 10)
                    }
                }.font(.system(size: 13)).toggleStyle(.switch).controlSize(.small)
                SettingsSection(title: "Compatibility and recovery") {
                    SettingRow(title: model.compatibility, detail: model.testedBuild
                               ? "This is the validated macOS 27.2 build, 26B5091g."
                               : "\(ProcessInfo.processInfo.operatingSystemVersionString). This build has not been validated. Nook verifies visibility and restores icons if a check fails.") {
                        Image(systemName: model.available ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(model.available ? NookStyle.teal : NookStyle.orange)
                    }
                    Text("If you lose Nook’s control, reopen Nook from Applications to restore every icon. Quitting Nook also restores the menu bar.")
                        .font(.system(size: 12)).foregroundStyle(NookStyle.muted).padding(.bottom, 12)
                    HStack {
                        Button("Show all apps") { model.showEverything() }
                        Button("Copy diagnostics") { model.copyDiagnostics() }
                        Spacer()
                        Link("Report an issue", destination: URL(string: "https://github.com/dgtlss/nook/issues")!)
                    }.font(.system(size: 12)).padding(.bottom, 10)
                    DisclosureGroup("Diagnostics") {
                        VStack(spacing: 8) {
                            LabeledContent("Nook control", value: model.controlReachable ? "Available" : "Unavailable")
                            LabeledContent("Discovered apps", value: "\(model.entries.count)")
                            LabeledContent("Last verification", value: model.lastVerified?.formatted(date: .omitted, time: .standard) ?? "Not yet")
                            Text("Copied diagnostics contain OS and display counts, permissions and Nook’s state. App names, menu contents and account details are excluded.")
                                .foregroundStyle(NookStyle.muted).fixedSize(horizontal: false, vertical: true)
                        }.font(.system(size: 11)).padding(.vertical, 10)
                    }.font(.system(size: 12)).padding(.bottom, 10)
                }
                SettingsSection(title: "Your settings") {
                    HStack {
                        Button("Export…") { model.exportSettings() }
                        Button("Import…") { model.importSettings() }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.storeURL]) }
                        Spacer()
                        Button("Run setup again") { model.showingSetup = true }
                    }.font(.system(size: 12)).padding(.vertical, 12)
                    Text("Settings save automatically on your Mac. Nook has no analytics. Sparkle checks the update server when checks are enabled.")
                        .font(.system(size: 11)).foregroundStyle(NookStyle.muted).padding(.bottom, 10)
                }
                HStack {
                    Text("© 2026 Nathan Langer · MIT License")
                    Spacer()
                    Link("Source code", destination: URL(string: "https://github.com/dgtlss/nook")!)
                    Button("Third-party licences") {
                        if let url = Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: "txt") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(.link)
                }.font(.system(size: 11)).foregroundStyle(NookStyle.muted)
            }.padding(24)
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
