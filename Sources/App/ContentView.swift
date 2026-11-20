import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ViewState private var model = AppModel()
    @ViewState private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            SettingsPanel(model: model)
                .frame(width: 340)
            Divider()
            VStack(spacing: 0) {
                PreviewBar(model: model)
                Divider()
                WebPreview(html: model.html)
                    .overlay {
                        if dropTargeted {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                                .padding(10)
                        }
                    }
            }
            .frame(minWidth: 520)
        }
        .frame(minHeight: 600)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { model.open(url) }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkExtension()
        }
    }
}

private struct PreviewBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
            if let file = model.previewFile {
                Text(file.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)
            } else {
                Text("Sample document")
                Text("— or drop a Markdown file here")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if model.previewFile != nil {
                Button("Sample") { model.showSample() }
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
            }
            Button("Open File…") { model.chooseFile() }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.bar)
    }
}

private struct SettingsPanel: View {
    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                header
                status
            }

            Section {
                HStack(spacing: 10) {
                    ForEach(LookdownSettings.Theme.allCases) { theme in
                        ThemeCard(theme: theme, selected: model.settings.theme == theme, dark: showsDark)
                            .onTapGesture { model.update { $0.theme = theme } }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(theme.title)
                    }
                }
                .padding(.vertical, 4)
                Text(model.settings.theme.blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Theme")
            }

            Section("Display") {
                Picker("Appearance", selection: binding(\.appearance)) {
                    ForEach(LookdownSettings.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Text size") {
                    HStack(spacing: 10) {
                        Slider(value: binding(\.fontSize), in: 12...24, step: 1)
                        Text("\(Int(model.settings.fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Picker("Width", selection: binding(\.width)) {
                    ForEach(LookdownSettings.Width.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle(isOn: binding(\.softBreaks)) {
                    Text("Single line breaks start a new line")
                    Text("How Obsidian shows notes. Off follows GitHub and CommonMark, which join the lines.")
                }
                Picker("Front matter", selection: binding(\.properties)) {
                    ForEach(LookdownSettings.Properties.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: binding(\.remoteImages)) {
                    Text("Load images from the web")
                    Text("Off shows a placeholder instead of contacting the image's server.")
                }
            } header: {
                Text("Markdown")
            } footer: {
                if let error = model.saveError {
                    Text("Couldn't save settings: \(error)").foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var showsDark: Bool {
        switch model.settings.appearance {
        case .system: colorScheme == .dark
        case .light: false
        case .dark: true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lookdown")
                    .font(.title3.weight(.semibold))
                Text("Readable Markdown when you press Space")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var status: some View {
        switch model.extensionState {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking Quick Look…").foregroundStyle(.secondary)
            }
        case .enabled:
            VStack(alignment: .leading, spacing: 4) {
                Label("Quick Look extension is on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(TintedIconLabelStyle())
                Text("Select a .md file in Finder and press Space. Changes here apply to the next preview.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .disabled:
            VStack(alignment: .leading, spacing: 6) {
                Label("Quick Look extension is turned off", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .labelStyle(TintedIconLabelStyle())
                Text("Turn on Lookdown under Quick Look in Login Items & Extensions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Extension Settings…") { openExtensionSettings() }
            }
        case .missing:
            VStack(alignment: .leading, spacing: 4) {
                Label("macOS hasn't registered the extension yet", systemImage: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                    .labelStyle(TintedIconLabelStyle())
                Text("Keep Lookdown in your Applications folder and open it once more.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openExtensionSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<LookdownSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// Colors only the icon, keeping the label text in the primary color.
private struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title.foregroundStyle(Color.primary)
        }
    }
}

private struct ThemeCard: View {
    let theme: LookdownSettings.Theme
    let selected: Bool
    let dark: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.bg)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Aa")
                        .font(.system(size: 19, weight: theme == .warm ? .semibold : .bold,
                                      design: theme == .warm ? .serif : .default))
                        .foregroundStyle(colors.fg)
                    Capsule().fill(colors.fg.opacity(0.28)).frame(width: 52, height: 4)
                    Capsule().fill(colors.fg.opacity(0.28)).frame(width: 38, height: 4)
                    Capsule().fill(colors.accent).frame(width: 24, height: 4)
                }
                .padding(9)
            }
            .frame(height: 78)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.14),
                                  lineWidth: selected ? 2.5 : 1)
            }
            Text(theme.title)
                .font(.callout.weight(selected ? .semibold : .regular))
        }
        .contentShape(Rectangle())
    }

    private var colors: (bg: Color, fg: Color, accent: Color) {
        switch (theme, dark) {
        case (.warm, false): (Color(hex: 0xFAF9F5), Color(hex: 0x2C2A25), Color(hex: 0xC4633F))
        case (.warm, true): (Color(hex: 0x262624), Color(hex: 0xE7E4DB), Color(hex: 0xD97757))
        case (.clean, false): (Color(hex: 0xFFFFFF), Color(hex: 0x2E2E2E), Color(hex: 0x7B5CF0))
        case (.clean, true): (Color(hex: 0x1E1E1E), Color(hex: 0xDCDDDE), Color(hex: 0x8B6CF7))
        case (.github, false): (Color(hex: 0xFFFFFF), Color(hex: 0x1F2328), Color(hex: 0x0969DA))
        case (.github, true): (Color(hex: 0x0D1117), Color(hex: 0xF0F6FC), Color(hex: 0x4493F8))
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
