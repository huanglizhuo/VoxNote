import SwiftUI
import Combine

struct DictationSettingsView: View {
    @ObservedObject var dictationService: DictationService

    @AppStorage("dictationEnabled") private var dictationEnabled = false
    @AppStorage("dictationHotkey") private var hotkeyRaw = HotkeyTrigger.rightOption.rawValue
    @AppStorage("dictationInputMethod") private var inputMethodRaw = InputMethod.typing.rawValue
    @State private var testText = ""

    var body: some View {
        Form {
            Section {
                Toggle("启用按键听写", isOn: $dictationEnabled)
                    .onChange(of: dictationEnabled) { _, enabled in
                        if enabled {
                            dictationService.enableDictation()
                        } else {
                            dictationService.disableDictation()
                        }
                    }

                Picker("快捷键", selection: $hotkeyRaw) {
                    ForEach(HotkeyTrigger.allCases) { trigger in
                        Text(trigger.displayName).tag(trigger.rawValue)
                    }
                }
                .onChange(of: hotkeyRaw) { _, raw in
                    if let trigger = HotkeyTrigger(rawValue: raw) {
                        dictationService.hotkeyMonitor.selectedTrigger = trigger
                    }
                }

                Picker("输入方式", selection: $inputMethodRaw) {
                    ForEach(InputMethod.allCases) { method in
                        Text(method.displayName).tag(method.rawValue)
                    }
                }

                if let method = InputMethod(rawValue: inputMethodRaw) {
                    Text(method.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("按住快捷键说话，松开后自动将识别结果输出到当前输入框")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("快捷键听写")
            }

            Section {
                permissionRow(
                    name: "辅助功能",
                    granted: dictationService.permissionManager.isAccessibilityGranted,
                    action: { dictationService.permissionManager.checkAccessibility(prompt: true) }
                )
                permissionRow(
                    name: "麦克风",
                    granted: dictationService.permissionManager.isMicrophoneGranted,
                    action: {
                        Task {
                            await dictationService.permissionManager.requestMicrophonePermission()
                        }
                    }
                )
            } header: {
                Text("权限状态")
            }

            if let error = dictationService.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                TextField("在此测试听写输入...", text: $testText, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)

                if !testText.isEmpty {
                    Button("清空") {
                        testText = ""
                    }
                    .font(.caption)
                }
            } header: {
                Text("测试区域")
            } footer: {
                Text("将光标点击到上方输入框，然后按住快捷键说话测试")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 480)
        .onAppear {
            dictationService.permissionManager.refreshStatus()
            if let trigger = HotkeyTrigger(rawValue: hotkeyRaw) {
                dictationService.hotkeyMonitor.selectedTrigger = trigger
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            dictationService.permissionManager.refreshStatus()
        }
    }

    private func permissionRow(name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(name)
            Spacer()
            if granted {
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Label("未授权", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                Button("去授权") { action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}
