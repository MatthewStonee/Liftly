import SwiftUI

/// Inline feedback shown below a weight field when its text can't be saved.
struct WeightValidationMessage: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
