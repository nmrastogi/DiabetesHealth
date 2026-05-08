import SwiftUI

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @EnvironmentObject var auth: AuthService
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            if auth.isGuest {
                SignInPromptView()
                    .navigationTitle("Chat")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
            VStack(spacing: 0) {
                // Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if vm.messages.isEmpty {
                                emptyChatPlaceholder
                            }
                            ForEach(vm.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                            if vm.isThinking {
                                ThinkingBubble()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.messages.count) { _ in
                        if let last = vm.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: vm.isThinking) { thinking in
                        if thinking {
                            withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                        }
                    }
                }

                Divider()

                // Input bar
                HStack(spacing: 12) {
                    TextField("Ask about your health data…", text: $vm.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .focused($fieldFocused)
                        .onSubmit { sendIfPossible() }

                    Button(action: sendIfPossible) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(vm.canSend ? .blue : .secondary)
                    }
                    .disabled(!vm.canSend)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { vm.messages.removeAll() }
                        .disabled(vm.messages.isEmpty)
                }
            }
            } // end guest else
        }
    }

    private var emptyChatPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.opacity(0.6))
            Text("Ask me anything about your diabetes health data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                SuggestionChip("What was my average glucose last week?") { vm.send($0) }
                SuggestionChip("How is my sleep affecting my glucose?") { vm.send($0) }
                SuggestionChip("Summarize my health trends this month.") { vm.send($0) }
            }
        }
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    private func sendIfPossible() {
        guard vm.canSend else { return }
        vm.send(vm.inputText)
    }
}

// MARK: - Subviews

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: message.role == .assistant ? .leading : .trailing, spacing: 6) {
                Group {
                    if message.role == .assistant {
                        MarkdownText(content: message.content)
                    } else {
                        Text(message.content)
                            .font(.subheadline)
                    }
                }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? Color.blue : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                if message.role == .assistant, let tools = message.toolsUsed, !tools.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tools, id: \.self) { ToolChip(toolName: $0) }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }
}

struct ToolChip: View {
    let toolName: String

    private var label: String {
        switch toolName {
        case "get_glucose_data":  return "Glucose Data"
        case "get_sleep_data":    return "Sleep Data"
        case "get_exercise_data": return "Exercise Data"
        case "detect_patterns":   return "Patterns"
        case "find_correlations": return "Correlations"
        default: return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var icon: String {
        switch toolName {
        case "get_glucose_data":  return "drop.fill"
        case "get_sleep_data":    return "moon.zzz.fill"
        case "get_exercise_data": return "figure.run"
        case "detect_patterns":   return "waveform.path.ecg"
        case "find_correlations": return "arrow.triangle.branch"
        default: return "wrench.and.screwdriver"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(Color.purple)
    }
}

struct ThinkingBubble: View {
    @State private var phase = 0.0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .frame(width: 7, height: 7)
                        .foregroundStyle(.secondary)
                        .offset(y: phase == Double(i) ? -4 : 0)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .id("thinking")
            .onAppear { phase = 2 }
            Spacer(minLength: 48)
        }
    }
}

struct SuggestionChip: View {
    let text: String
    let action: (String) -> Void

    init(_ text: String, action: @escaping (String) -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button { action(text) } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                .foregroundStyle(.tint)
        }
    }
}

// MARK: - ViewModel

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isThinking = false

    var canSend: Bool { !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isThinking }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        messages.append(ChatMessage(role: .user, content: trimmed))
        isThinking = true

        let history = messages.dropLast().map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.content]
        }

        Task {
            do {
                let response = try await APIService.shared.sendChat(question: trimmed, history: history)
                messages.append(ChatMessage(role: .assistant, content: response.answer,
                                            toolsUsed: response.toolsUsed))
            } catch {
                messages.append(ChatMessage(role: .assistant,
                                            content: "Sorry, I couldn't reach the server. Please try again."))
            }
            isThinking = false
        }
    }
}
