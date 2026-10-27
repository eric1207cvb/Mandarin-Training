import AVFoundation
import UIKit
import Combine

// [Fix] 加入 @MainActor，確保 UI 更新都在主執行緒
@MainActor
class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    // 用來標記正在說話，可讓 UI 顯示對應圖示
    @Published var isSpeaking = false
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    /// 依教育部注音朗讀。對得上音節才使用國際音標，否則退回系統猜音。
    func speak(word: String, phonetic: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        let plain = MOEText.plain(word)
        guard !plain.isEmpty else { return }
        if let attributed = BopomofoPronunciation.attributedString(word: plain, phonetic: phonetic) {
            speak(attributed, rate: rate)
        } else {
            speak(plain, rate: rate)
        }
    }

    /// 朗讀文字
    /// - Parameter text: 要朗讀的文字
    /// - Parameter rate: 語速 (0.0 ~ 1.0)，預設 0.45
    func speak(_ text: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        speak(NSAttributedString(string: text), rate: rate)
    }

    private func speak(_ text: NSAttributedString, rate: Float) {
        // 1. 如果正在講話，先停止
        stop()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // [關鍵修正]
            // 步驟 A: 先解除目前的 Session (這會釋放麥克風鎖定)
            try? audioSession.setActive(false)
            
            // 步驟 B: 設定為 "純播放模式" (.playback)
            // 這裡不需要 overrideOutputAudioPort(.speaker)，因為 .playback 預設就是喇叭
            // 如果加了 override... 會導致 Error -50 錯誤
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            
            // 步驟 C: 啟用 Session
            try audioSession.setActive(true)
        } catch {
            print("⚠️ 發音前置設定失敗: \(error.localizedDescription)")
        }
        
        guard text.length > 0 else { return }

        // 2. 建立發聲物件。有注音時，每個字都帶教育部讀音的音標。
        let utterance = AVSpeechUtterance(attributedString: text)
        
        // 3. 尋找最佳台灣語音
        if let voice = findBestChineseVoice() {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        }
        
        // 4. 設定參數
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0 // 確保最大音量
        
        // 5. 開始朗讀
        synthesizer.speak(utterance)
    }
    
    /// 停止朗讀
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    /// 已安裝高品質或增強語音時，聽起來會接近真人。基本語音是內建的機械音。
    var hasNaturalVoice: Bool {
        guard let voice = findBestChineseVoice() else { return false }
        return voice.quality == .premium || voice.quality == .enhanced
    }

    // MARK: - 尋找最佳的台灣語音
    private func findBestChineseVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh-TW") }
        return voices.max { rank($0) < rank($1) }
    }

    private func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        let identifier = voice.identifier.lowercased()
        var score = 0
        switch voice.quality {
        case .premium: score += 300
        case .enhanced: score += 200
        default: score += 40
        }
        if identifier.contains("eloquence") || identifier.contains("novelty") { score -= 80 }
        if identifier.contains("meijia") || voice.name.localizedCaseInsensitiveContains("美佳") { score += 30 }
        return score
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

/// 把教育部注音一式轉成國際音標，讓台灣語音唸出這個詞條的讀音，而不是自行猜測多音字。
enum BopomofoPronunciation {
    private static let ipaKey = NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute)
    private static let toneMarks: [Character] = ["ˉ", "ˊ", "ˇ", "ˋ", "˙"]
    private static let punctuation = CharacterSet(charactersIn: "，；、！？。,.!?;:：「」『』（）()[]【】—…· ")
    private static let initials: [Character: String] = [
        "ㄅ": "p", "ㄆ": "pʰ", "ㄇ": "m", "ㄈ": "f",
        "ㄉ": "t", "ㄊ": "tʰ", "ㄋ": "n", "ㄌ": "l",
        "ㄍ": "k", "ㄎ": "kʰ", "ㄏ": "x",
        "ㄐ": "tɕ", "ㄑ": "tɕʰ", "ㄒ": "ɕ",
        "ㄓ": "ʈʂ", "ㄔ": "ʈʂʰ", "ㄕ": "ʂ", "ㄖ": "ʐ",
        "ㄗ": "ts", "ㄘ": "tsʰ", "ㄙ": "s"
    ]
    private static let emptyRhyme: [Character: String] = [
        "ㄓ": "ʈʂɨ", "ㄔ": "ʈʂʰɨ", "ㄕ": "ʂɨ", "ㄖ": "ʐɨ",
        "ㄗ": "tsɯ", "ㄘ": "tsʰɯ", "ㄙ": "sɯ"
    ]
    private static let finals: [String: String] = [
        "ㄚ": "a", "ㄛ": "o", "ㄜ": "ɤ", "ㄝ": "ɛ",
        "ㄞ": "aɪ", "ㄟ": "eɪ", "ㄠ": "aʊ", "ㄡ": "oʊ",
        "ㄢ": "an", "ㄣ": "ən", "ㄤ": "ɑŋ", "ㄥ": "əŋ", "ㄦ": "ɚ",
        "ㄧ": "i", "ㄧㄚ": "ia", "ㄧㄛ": "io", "ㄧㄝ": "iɛ", "ㄧㄞ": "iaɪ",
        "ㄧㄠ": "iaʊ", "ㄧㄡ": "ioʊ", "ㄧㄢ": "iɛn", "ㄧㄣ": "in", "ㄧㄤ": "iɑŋ", "ㄧㄥ": "iŋ",
        "ㄨ": "u", "ㄨㄚ": "ua", "ㄨㄛ": "uo", "ㄨㄞ": "uaɪ", "ㄨㄟ": "ueɪ",
        "ㄨㄢ": "uan", "ㄨㄣ": "uən", "ㄨㄤ": "uɑŋ", "ㄨㄥ": "ʊŋ",
        "ㄩ": "y", "ㄩㄝ": "yɛ", "ㄩㄢ": "yɛn", "ㄩㄣ": "yn", "ㄩㄥ": "yʊŋ"
    ]
    private static let toneIPA = [1: "˥", 2: "˧˥", 3: "˨˩˦", 4: "˥˩", 5: "˨"]

    static func attributedString(word: String, phonetic: String) -> NSAttributedString? {
        let syllables = phonetic
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !isPunctuation($0) }
        guard !syllables.isEmpty else { return nil }

        let result = NSMutableAttributedString(string: word)
        let characters = Array(word)
        var charIndex = 0
        var utf16Index = 0
        var syllableIndex = 0
        var phrase: [String] = []
        var sawPunctuation = false

        while charIndex < characters.count {
            let character = characters[charIndex]
            let characterLength = utf16Length(of: character)
            if isPunctuation(String(character)) {
                sawPunctuation = true
                charIndex += 1
                utf16Index += characterLength
                continue
            }
            guard syllableIndex < syllables.count,
                  let pronunciation = ipa(for: syllables[syllableIndex]) else { return nil }

            var rangeLength = characterLength
            charIndex += 1
            if pronunciation.erhua, charIndex < characters.count, characters[charIndex] == "兒" {
                rangeLength += utf16Length(of: characters[charIndex])
                charIndex += 1
            }
            phrase.append(pronunciation.ipa)
            result.addAttribute(ipaKey, value: pronunciation.ipa, range: NSRange(location: utf16Index, length: rangeLength))
            utf16Index += rangeLength
            syllableIndex += 1
        }
        guard syllableIndex == syllables.count else { return nil }
        // 整詞共用一條音標，語音才能連成詞，而不是一個字一個字分開唸。
        if !sawPunctuation {
            let phraseIPA = phrase.joined(separator: ".")
            let connected = NSMutableAttributedString(string: word)
            connected.addAttribute(ipaKey, value: phraseIPA, range: NSRange(location: 0, length: connected.length))
            return connected
        }
        return result
    }

    private static func ipa(for syllable: String) -> (ipa: String, erhua: Bool)? {
        var body = syllable
        var tone = 1
        if body.first == "˙" {
            tone = 5
            body.removeFirst()
        }
        let erhua = body.contains("ㄦ") && body.contains { isLetter($0) && $0 != "ㄦ" }
        if erhua, body.last == "ㄦ" {
            body.removeLast()
        }
        if let last = body.last, toneMarks.contains(last), last != "˙" {
            tone = toneNumber(last)
            body.removeLast()
        }
        guard let segmental = segmentalIPA(body) else { return nil }
        let rhyme = erhua ? segmental + "ɚ" : segmental
        return (rhyme + (toneIPA[tone] ?? ""), erhua)
    }

    private static func segmentalIPA(_ body: String) -> String? {
        guard let first = body.first else { return nil }
        if let initial = initials[first] {
            let final = String(body.dropFirst())
            if final.isEmpty { return emptyRhyme[first] }
            guard let vowel = finals[final] else { return nil }
            return initial + vowel
        }
        return finals[body]
    }

    private static func toneNumber(_ mark: Character) -> Int {
        switch mark {
        case "ˊ": return 2
        case "ˇ": return 3
        case "ˋ": return 4
        default: return 1
        }
    }

    private static func isLetter(_ character: Character) -> Bool {
        BopomofoData.isBopomofo(character) && !toneMarks.contains(character)
    }

    private static func isPunctuation(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { punctuation.contains($0) }
    }

    private static func utf16Length(of character: Character) -> Int {
        (String(character) as NSString).length
    }
}
