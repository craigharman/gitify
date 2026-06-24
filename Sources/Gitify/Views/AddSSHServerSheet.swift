import SwiftUI

/// Sheet to add an SSH server connection by entering host, user, port, and base path.
/// Layout follows the same hand-laid-out pattern as `AddAccountSheet`.
struct AddSSHServerSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var host = ""
    @State private var user = "git"
    @State private var portString = "22"
    @State private var basePath = "~"
    @State private var testing = false
    @State private var testResult: String?
    @State private var testPassed = false

    private var port: Int { Int(portString) ?? 22 }
    private var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !user.trimmingCharacters(in: .whitespaces).isEmpty &&
        port > 0 && port <= 65535
    }

    private let labelWidth: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add SSH Server").font(.title2.bold())

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("Label").frame(width: labelWidth, alignment: .trailing)
                    TextField("My Server", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Host").frame(width: labelWidth, alignment: .trailing)
                    TextField("example.com", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("User").frame(width: labelWidth, alignment: .trailing)
                    TextField("git", text: $user)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Port").frame(width: labelWidth, alignment: .trailing)
                    TextField("22", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                GridRow {
                    Text("Base Path").frame(width: labelWidth, alignment: .trailing)
                    TextField("~", text: $basePath)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("Gitify uses your SSH config and keys. No credentials are stored.")
                .font(.caption).foregroundStyle(.secondary)

            if let testResult {
                HStack(spacing: 6) {
                    Image(systemName: testPassed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testPassed ? .green : .red)
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testPassed ? Color.primary : Color.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack {
                Button(testing ? "Testing\u{2026}" : "Test Connection") {
                    Task { await testConnection() }
                }
                .disabled(!isValid || testing)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { addServer() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 460, height: 380)
    }

    private func testConnection() async {
        let server = buildServer()
        testing = true
        testResult = nil
        defer { testing = false }
        if let error = await SSHScanner.testConnection(server) {
            testResult = error
            testPassed = false
        } else {
            testResult = "Connection successful."
            testPassed = true
        }
    }

    private func addServer() {
        let server = buildServer()
        model.addSSHServer(server)
        dismiss()
    }

    private func buildServer() -> SSHServer {
        let effectiveLabel = label.trimmingCharacters(in: .whitespaces)
        let effectiveHost = host.trimmingCharacters(in: .whitespaces)
        return SSHServer(
            label: effectiveLabel.isEmpty ? effectiveHost : effectiveLabel,
            host: effectiveHost,
            user: user.trimmingCharacters(in: .whitespaces),
            port: port,
            basePath: basePath.trimmingCharacters(in: .whitespaces)
        )
    }
}
