import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(EditorialTheme.displayFont(size: 31))
                        .foregroundStyle(EditorialTheme.ink)

                    Text("Configure your OpenAI and ElevenLabs connections and voice preferences.")
                        .font(EditorialTheme.detailFont(size: 16))
                        .foregroundStyle(EditorialTheme.mutedInk)
                }

                settingsSection(title: "OpenAI") {
                    settingsField(label: "API Key", isSecure: true, text: $settings.apiKey)
                }

                settingsSection(title: "ElevenLabs") {
                    settingsField(label: "API Key", isSecure: true, text: $settings.elevenLabsAPIKey)
                    EditorialDivider()
                    voicePicker
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                EditorialTheme.paperHighlight,
                EditorialTheme.paper,
                EditorialTheme.paperShadow.opacity(0.75)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func settingsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialEyebrow(text: title)

            VStack(spacing: 0) {
                content()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.34))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(EditorialTheme.separator.opacity(0.66), lineWidth: 1)
            }
        }
    }

    private func settingsField(label: String, isSecure: Bool = false, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(EditorialTheme.uiFont(size: 13, weight: .medium))
                .foregroundStyle(EditorialTheme.mutedInk)

            if isSecure {
                SecureField("", text: text)
                    .font(EditorialTheme.detailFont(size: 17))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField("", text: text)
                    .font(EditorialTheme.detailFont(size: 17))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.vertical, 4)
    }

    private var voicePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice")
                .font(EditorialTheme.uiFont(size: 13, weight: .medium))
                .foregroundStyle(EditorialTheme.mutedInk)
                .padding(.top, 4)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(Self.voices, id: \.id) { voice in
                    Button {
                        settings.speechVoice = voice.id
                    } label: {
                        Text(voice.name)
                            .font(EditorialTheme.uiFont(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(settings.speechVoice == voice.id
                                          ? EditorialTheme.forest
                                          : Color.white.opacity(0.5))
                            )
                            .foregroundStyle(settings.speechVoice == voice.id
                                             ? EditorialTheme.paperHighlight
                                             : EditorialTheme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private struct ElevenLabsVoice {
        let name: String
        let id: String
    }

    private static let voices: [ElevenLabsVoice] = [
        .init(name: "James", id: "lUTamkMw7gOzZbFIwmq4"),
        .init(name: "Jodi", id: "FF59babHL8N8gfTgtBMT")
    ]
}
