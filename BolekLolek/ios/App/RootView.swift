import AgentCore
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ModeSwitcher(selection: $model.mode)
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            ChatView(viewModel: model.current)
                .id(model.mode)
        }
    }
}

/// The two big buttons. Names are defined once here so they are easy to change.
struct ModeSwitcher: View {
    @Binding var selection: AgentMode

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AgentMode.allCases) { mode in
                let isSelected = selection == mode
                Button {
                    selection = mode
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.title)
                            .font(.headline)
                        Text(mode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

extension AgentMode {
    var title: LocalizedStringKey {
        switch self {
        case .lolek: "Lolek"
        case .bolek: "Bolek"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .lolek: "Private · on this iPhone"
        case .bolek: "Full agent · EU cloud"
        }
    }

    var intro: LocalizedStringKey {
        switch self {
        case .lolek: "Hi, I'm Lolek. I run only on this iPhone and never talk to any server. Try: “note: buy milk”."
        case .bolek: "Hi, I'm Bolek. I can act for you on the web and in your apps. This is a demo model for now. Try: “send: hello to Anna”."
        }
    }
}
