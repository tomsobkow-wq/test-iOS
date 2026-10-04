import AgentCore
import SwiftUI

extension AgentMode {
    /// Green is the private one, blue is the cloud one.
    var accent: Color {
        switch self {
        case .lolek: Color(red: 0.110, green: 0.502, blue: 0.282)
        case .bolek: Color(red: 0.157, green: 0.376, blue: 0.941)
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .lolek: "Lolek"
        case .bolek: "Bolek"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .lolek: "Private · runs on this iPhone"
        case .bolek: "Full agent · EU cloud"
        }
    }

    var intro: LocalizedStringKey {
        switch self {
        case .lolek: "Hi, I'm Lolek. I run only on this iPhone and never talk to any server. Ask me about the weather, set an alarm, or text a friend."
        case .bolek: "Hi, I'm Bolek, the full agent. Ask me anything, or tell me what to do on your phone."
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ModeHeader(selection: $model.mode)
            Divider()
            ChatView(viewModel: model.current, setup: model.mode == .lolek ? model.lolekSetup : nil)
                .id(model.mode)
        }
        .tint(model.mode.accent)
        .animation(.easeInOut(duration: 0.25), value: model.mode)
    }
}

/// Lolek | Bolek switch, with a line saying who you are talking to.
struct ModeHeader: View {
    @Binding var selection: AgentMode
    @Namespace private var thumb

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(AgentMode.allCases) { mode in
                    let isSelected = selection == mode
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = mode }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? mode.accent : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                                        .matchedGeometryEffect(id: "thumb", in: thumb)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 6) {
                Circle().fill(selection.accent).frame(width: 7, height: 7)
                Text(selection.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
