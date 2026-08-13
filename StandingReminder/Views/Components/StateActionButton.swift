import SwiftUI

struct StateActionButton: View {
    let state: WorkState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: state.symbolName)
                    .font(.title2)
                    .frame(width: 30)

                Text(state.title)
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
                    .opacity(0.65)
            }
            .foregroundStyle(state.color)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(state.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(state.color.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel("切换到\(state.title)")
    }
}
