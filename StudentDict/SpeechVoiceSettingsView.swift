import SwiftUI
import AVFoundation

struct SpeechVoiceSettingsView: View {
    @ObservedObject private var speechManager = SpeechManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var refreshToken = UUID()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("先選一個已安裝的語音試聽。想換更自然的聲音，可照下面步驟到 iPhone 設定下載 Apple 增強語音。\nPreview an installed voice. To download a more natural Apple voice, follow the steps below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("語音設定 · Voice Settings")
                }

                Section("已安裝的繁體中文語音 · Installed Traditional Chinese Voices") {
                    if speechManager.availableChineseVoices.isEmpty {
                        Text("目前找不到已安裝的繁體中文語音。請先依下方步驟下載，再回來重新整理。\nNo Traditional Chinese voices are installed yet. Follow the steps below, then return and refresh.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(speechManager.availableChineseVoices, id: \.identifier) { voice in
                            HStack(spacing: 12) {
                                Button {
                                    speechManager.selectVoice(identifier: voice.identifier)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(voice.name)
                                            .foregroundStyle(.primary)
                                        Text("\(qualityName(voice.quality)) · \(qualityNameEnglish(voice.quality))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if speechManager.effectiveVoiceIdentifier == voice.identifier {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }

                                Button {
                                    speechManager.selectVoice(identifier: voice.identifier)
                                    speechManager.speak("你好，歡迎使用國語辭典。")
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("試聽／Preview \(voice.name)")
                            }
                        }
                    }
                }

                Section("下載 Apple 增強語音 · Download Apple Enhanced Voices") {
                    BilingualVoiceStep(number: 1, chinese: "打開 iPhone 的「設定」App", english: "Open the Settings app on your iPhone.")
                    BilingualVoiceStep(number: 2, chinese: "點「輔助使用」→「閱讀與朗讀」", english: "Tap Accessibility → Read & Speak.")
                    BilingualVoiceStep(number: 3, chinese: "點「聲音」→「中文（繁體）」", english: "Tap Voices → Chinese (Traditional).")
                    Text("找不到時，請用「設定」上方搜尋「閱讀與朗讀」；較舊的 iOS 版本可能叫「朗讀內容」。選擇喜歡的語音並點下載圖示，建議連接 Wi‑Fi。下載完成後回到本頁重新整理。\nCan’t find it? Search Settings for “Read & Speak” or, on older iOS versions, “Spoken Content.” Choose a voice and tap its download icon. Wi‑Fi is recommended. Return here and refresh the voice list when the download is complete.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("重新整理已安裝語音 · Refresh Installed Voices") {
                        refreshToken = UUID()
                    }

                    Link("查看 Apple 官方說明 · View Apple Support Guide", destination: URL(string: "https://support.apple.com/zh-tw/guide/iphone/iph96b214f0/ios")!)
                }
            }
            .id(refreshToken)
            .navigationTitle("語音設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成 · Done") { dismiss() }
                }
            }
        }
    }

    private func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Apple 進階語音"
        case .enhanced: return "Apple 增強語音"
        default: return "標準語音"
        }
    }

    private func qualityNameEnglish(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Standard"
        }
    }
}

private struct BilingualVoiceStep: View {
    let number: Int
    let chinese: String
    let english: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(chinese)
                    .foregroundStyle(.primary)
                Text(english)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
