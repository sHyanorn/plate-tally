import Core
import SwiftUI

extension View {
    /// Shows a problem as an alert with its three parts, and clears it when the user closes the alert.
    func problemAlert(_ title: LocalizedStringKey, _ problem: Binding<Problem?>) -> some View {
        alert(
            title,
            isPresented: Binding(
                main: { problem.wrappedValue != nil }, set: { if !$0 { problem.wrappedValue = nil } }),
            presenting: problem.wrappedValue
        ) { _ in
            Button("OK") {}
        } message: { shown in
            Text(shown.message)
        }
    }
}
