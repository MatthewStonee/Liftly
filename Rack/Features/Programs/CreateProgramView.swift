import SwiftUI
import SwiftData

struct CreateProgramView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let existingProgram: Program?

    @State private var viewModel = ProgramsViewModel()
    @State private var name: String
    @State private var description: String
    @State private var saveAlert: PersistenceAlert?
    @State private var showingSaveAlert = false

    init(existingProgram: Program? = nil) {
        self.existingProgram = existingProgram
        _name = State(initialValue: existingProgram?.name ?? "")
        _description = State(initialValue: existingProgram?.programDescription ?? "")
    }

    private var isEditing: Bool { existingProgram != nil }

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

                PrimaryButton(isEditing ? "Save Changes" : "Create Program", icon: isEditing ? "checkmark" : "plus") {
                    if isEditing {
                        saveChanges()
                    } else {
                        createProgram()
                    }
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
            .navigationTitle(isEditing ? "Edit Program" : "New Program")
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .persistenceAlert(isPresented: $showingSaveAlert, alert: saveAlert)
    }

    private func createProgram() {
        switch viewModel.createProgram(name: name, description: description, context: context) {
        case .success:
            dismiss()
        case .failure(let error):
            saveAlert = PersistenceAlert(title: "Couldn't Create Program", error: error)
            showingSaveAlert = true
        }
    }

    private func saveChanges() {
        guard let existingProgram else { return }

        switch viewModel.updateProgram(existingProgram, name: name, description: description, context: context) {
        case .success:
            dismiss()
        case .failure(let error):
            saveAlert = PersistenceAlert(title: "Couldn't Save Program", error: error)
            showingSaveAlert = true
        }
    }
}
