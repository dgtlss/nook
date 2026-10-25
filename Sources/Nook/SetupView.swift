import SwiftUI
import NookCore

struct SetupView: View {
    @ObservedObject var model: NookModel
    @State private var step = 0
    @State private var selectedID = ""
    private var apps: [AppEntry] { model.sortedEntries.filter(\.isRunning) }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                PaneTitle(title: "A little room in your menu bar", subtitle: "Set up Nook in three small steps.")
                Spacer()
                Text("\(step + 1) of 3").font(.system(size: 12)).monospacedDigit().foregroundStyle(NookStyle.muted)
            }
            ProgressView(value: Double(step), total: 3).tint(NookStyle.teal).accessibilityLabel("\(step) of 3 setup steps completed")
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case 0:
                    Text("Connect your menu bar").font(.system(size: 18, weight: .semibold))
                    Text("Accessibility lets Nook find your menu bar apps and open their menus. Your preferences stay on your Mac; Screen Recording is not needed.")
                        .font(.system(size: 13)).foregroundStyle(NookStyle.muted)
                    if model.permissionGranted {
                        Label("Accessibility is ready", systemImage: "checkmark.circle").font(.system(size: 13)).foregroundStyle(NookStyle.teal)
                    } else {
                        HStack {
                            Button("Open Accessibility Settings") { model.openAccessibilitySettings() }.buttonStyle(NookPrimaryButtonStyle())
                            Button("Check again") { model.refresh() }
                        }
                    }
                case 1:
                    Text("Choose an app to tuck away").font(.system(size: 18, weight: .semibold))
                    Text("The app keeps running. Only its menu bar icon hides. You can change its group later in Organise.")
                        .font(.system(size: 13)).foregroundStyle(NookStyle.muted)
                    if apps.isEmpty {
                        Text("No menu bar apps were found yet. Open a menu bar app, then refresh.").font(.system(size: 13))
                        Button("Refresh apps") { model.refresh() }
                    } else {
                        Picker("Menu bar app", selection: $selectedID) {
                            Text("Choose an app").tag("")
                            ForEach(apps) { Text($0.displayName).tag($0.id) }
                        }.frame(maxWidth: 360)
                    }
                    if !model.available { Text(model.compatibility).font(.system(size: 12)).foregroundStyle(NookStyle.orange) }
                    if model.isPaused {
                        HStack {
                            Text("Hiding is paused. Resume to try this step.").font(.system(size: 12)).foregroundStyle(NookStyle.muted)
                            Button("Resume hiding") { model.resumeHiding() }
                        }
                    }
                default:
                    Text("Bring it back whenever you need it").font(.system(size: 18, weight: .semibold))
                    Text("Click Nook to reveal hidden apps. Option-click shows everything, including Always hidden apps. Right-click opens search and quick controls.")
                        .font(.system(size: 13)).foregroundStyle(NookStyle.muted)
                    HStack {
                        Button("Show hidden apps") { model.peek(automaticallyRehide: false) }.disabled(!model.available)
                        Button("Show all apps") { model.showEverything() }
                    }
                    Text("If you ever lose Nook’s icon, reopen Nook from Applications. Every icon returns.")
                        .font(.system(size: 12)).foregroundStyle(NookStyle.muted)
                    VisibilityStatus(model: model)
                }
            }.padding(22).frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                .background(NookStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Set up later") { model.completeSetup() }.buttonStyle(.plain).foregroundStyle(NookStyle.muted)
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                Button(step == 0 ? "Continue" : step == 1 ? "Hide chosen app" : "Finish setup") {
                    if step == 1 { model.assign(selectedID, to: .tucked); model.tuck() }
                    if step == 2 { model.completeSetup() } else { step += 1 }
                }.buttonStyle(NookPrimaryButtonStyle())
                    .disabled(step == 0 ? !model.permissionGranted : step == 1 ? selectedID.isEmpty || !model.available || model.applying || model.isPaused : false)
            }
        }.frame(maxWidth: 620).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
