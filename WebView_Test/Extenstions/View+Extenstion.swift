import SwiftUI

extension View {
    func keyboardAdaptive() -> some View {
        self.modifier(KeyboardAdaptive())
    }
}
