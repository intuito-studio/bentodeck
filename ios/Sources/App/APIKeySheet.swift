import SwiftUI

/// Sheet presented when the user taps a "Connect" widget card.
///
/// Lets the user paste an API key into a SecureField and POST it to the
/// backend's `/data-sources/:id/key` endpoint. The token never appears as
/// plaintext on screen and never travels through the Claude Desktop chat
/// — that's the whole point of this flow.
struct APIKeySheet: View {
    let sourceId: String
    let sourceName: String
    let theme: Theme
    /// Called when the key has been successfully saved + verified.
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Paste your API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.go)
                        .onSubmit { Task { await save() } }
                } header: {
                    Text("Connect \(sourceName)")
                } footer: {
                    Text(footerText)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private var footerText: String {
        "Stored only on this device's BentoDeck server. Never sent to Anthropic and never visible in your Claude Desktop chat history."
    }

    private func save() async {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let result = try await APIClient().setDataSourceKey(
                sourceId: sourceId,
                apiKey: trimmed
            )
            switch result {
            case .ok:
                onSaved()
                dismiss()
            case let .failed(status, bodyPreview):
                let preview = bodyPreview?.trimmingCharacters(in: .whitespacesAndNewlines)
                if status == 401 || status == 403 {
                    errorMessage = "The API rejected this key (HTTP \(status)). Double-check it and try again."
                } else if status == 0 {
                    errorMessage = "Couldn't reach the API to verify the key. Check your network and try again."
                } else if let preview, !preview.isEmpty {
                    errorMessage = "Verification failed (HTTP \(status)). \(preview.prefix(160))"
                } else {
                    errorMessage = "Verification failed (HTTP \(status))."
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
