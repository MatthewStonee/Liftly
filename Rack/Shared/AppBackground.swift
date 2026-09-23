import SwiftUI

extension View {
    /// Draws the app's dark blue-to-black gradient behind this view, into the safe areas.
    func appBackground() -> some View {
        background {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}
