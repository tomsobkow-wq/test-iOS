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

    /// A second opening message, for Lolek only: the invitation to try airplane mode.
    var introExtra: LocalizedStringKey? {
        switch self {
        case .lolek: "Try it: switch on airplane mode and ask me anything. I'm still here."
        case .bolek: nil
        }
    }

    var intro: LocalizedStringKey {
        switch self {
        case .lolek: "Hi, I'm Lolek. I run on this iPhone, and your chats and documents never leave it. Ask me about the weather, set an alarm, or text a friend."
        case .bolek: "Hi, I'm Bolek, the full agent. Ask me anything, or tell me what to do on your phone."
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            ModeHeader(selection: $model.mode, isOnline: model.network.isOnline, mail: model.mode == .lolek && model.mail.canConnect ? model.mail : nil, onMail: { model.showMail = true })
            Divider()
            ChatView(viewModel: model.current, setup: model.mode == .lolek ? model.lolekSetup : nil, handoff: model.handoff, mail: model.mode == .lolek ? model.mail : nil, onAskBolek: { model.askBolek($0) })
                .id(model.mode)
        }
        .tint(model.mode.accent)
        .animation(.easeInOut(duration: 0.25), value: model.mode)
        .sheet(isPresented: $model.showMail) {
            MailScreen(
                model: model.mailModel,
                onClose: { model.showMail = false },
                onSummarise: { model.discussEmail($0, prompt: String(localized: "Summarise this email.")) },
                onAsk: { model.askAboutEmail($0) }
            )
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.connectBackend(); Task { await model.mail.refreshUnread() } }
        }
    }
}

/// Lolek | Bolek switch, with a line saying who you are talking to.
struct ModeHeader: View {
    @Binding var selection: AgentMode
    var isOnline = true
    /// Lolek only: the envelope button that opens the Mail screen.
    var mail: MailConnection?
    var onMail: () -> Void = {}
    @Namespace private var thumb

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
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
            if let mail {
                Button(action: onMail) {
                    Image(systemName: "envelope")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selection.accent)
                        .frame(width: 46, height: 46)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topTrailing) {
                            if let unread = mail.unread, unread > 0 {
                                Text(verbatim: unread > 99 ? "99+" : String(unread))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(selection.accent, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color(.systemBackground), lineWidth: 2))
                                    .offset(x: 6, y: -6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Mail"))
                .accessibilityIdentifier("mail-button")
                .transition(.scale.combined(with: .opacity))
            }
            }

            HStack(spacing: 6) {
                if !isOnline, selection == .lolek {
                    // The moment that proves the promise: no connection, and Lolek is still here.
                    Image(systemName: "airplane").font(.system(size: 12, weight: .semibold)).foregroundStyle(selection.accent)
                    Text("Offline · still working").font(.footnote.weight(.medium)).foregroundStyle(selection.accent)
                } else if !isOnline {
                    Image(systemName: "wifi.slash").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Text("No internet · Bolek needs a connection").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Circle().fill(selection.accent).frame(width: 7, height: 7)
                    Text(selection.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isOnline)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
