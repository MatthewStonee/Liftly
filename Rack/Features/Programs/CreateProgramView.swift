import SwiftUI
import SwiftData

struct CreateProgramView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Program Name")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    TextField("e.g. 5-Day PPL Split", text: $name)
                        .font(.body)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    TextField("Optional notes about this program", text: $description, axis: .vertical)
                        .font(.body)
                        .lineLimit(3...5)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                }

                Spacer()

                PrimaryButton("Create Program", icon: "plus") {
                    createProgram()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("New Program")
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func createProgram() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let program = Program(name: trimmed, description: description.trimmingCharacters(in: .whitespaces))
        context.insert(program)
        try? context.save()
        dismiss()
    }
}
