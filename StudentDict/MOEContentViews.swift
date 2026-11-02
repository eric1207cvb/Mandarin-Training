import SwiftUI
import UIKit

/// Renders the Ministry of Education's image placeholders (for characters that
/// cannot be represented directly in UTF-8) from the supplied picture bundle.
struct MOESourceTextView: View {
    let sourceText: String
    var linkedWords: Set<String> = []
    var onOpenWord: (String) -> Void = { _ in }

    private var lines: [String] {
        sourceText.components(separatedBy: .newlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MOESourceLineView(text: line, linkedWords: linkedWords, onOpenWord: onOpenWord)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum MOEText {
    static func plain(_ source: String) -> String {
        let pattern = "&[^;\\n]{1,80};"
        let cleared = source.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return cleared
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func listWords(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "、，,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 「」與『』分開配對，避免引文裡的內層括號把外層截斷。
    static let quotePattern = try! NSRegularExpression(pattern: "「([^「」\\n]{1,18})」|『([^『』\\n]{1,18})』")
    static let crossReferencePattern = try! NSRegularExpression(pattern: "（(\\d{3,8})）")

    /// 釋義裡標出的字詞。整句不是詞條、但用頓號並列的短詞，會拆開來查。
    static func quotedWords(_ source: String) -> [String] {
        quoteSpans(in: source).flatMap(\.candidates)
    }

    /// 多音參見訊息裡的字詞號，例如（00584）。同一則訊息可以有多個。
    static func crossReferenceIDs(_ source: String) -> [String] {
        let nsSource = source as NSString
        return crossReferencePattern.matches(in: source, range: NSRange(location: 0, length: nsSource.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsSource.substring(with: match.range(at: 1))
        }
    }

    static func quoteSpans(in source: String) -> [(range: NSRange, inner: String, candidates: [String])] {
        let nsSource = source as NSString
        return quotePattern.matches(in: source, range: NSRange(location: 0, length: nsSource.length)).compactMap { match in
            let innerRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard innerRange.location != NSNotFound else { return nil }
            let inner = nsSource.substring(with: innerRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inner.isEmpty else { return nil }
            return (match.range, inner, candidates(inQuote: inner))
        }
    }

    private static func candidates(inQuote inner: String) -> [String] {
        guard inner.contains("、") else { return [inner] }
        let parts = inner
            .split(separator: "、", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let allShortWords = parts.count > 1 && parts.allSatisfy { part in
            (1...8).contains(part.count) && part.unicodeScalars.allSatisfy { scalar in
                (0x4E00...0x9FFF).contains(scalar.value)
            }
        }
        return allShortWords ? parts : [inner]
    }
}

struct MOEWordView: View {
    let word: String

    var body: some View {
        if word.contains("&") {
            MOESourceTextView(sourceText: word)
                .font(.system(size: 34, weight: .medium))
        } else {
            Text(word)
                .font(AppTheme.textFont(size: 34))
                .foregroundColor(AppTheme.primary)
        }
    }
}

private struct MOESourceLineView: View {
    let text: String
    var linkedWords: Set<String> = []
    var onOpenWord: (String) -> Void = { _ in }

    private var segments: [MOESourceSegment] {
        MOESourceSegment.split(text)
    }

    var body: some View {
        if segments.contains(where: { $0.image != nil }) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                ForEach(segments) { segment in
                    if let image = segment.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .accessibilityLabel("教育部字圖")
                    } else {
                        linkedText(segment.text)
                    }
                }
            }
        } else {
            linkedText(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func linkedText(_ source: String) -> some View {
        Text(attributed(source))
            .font(AppTheme.textFont(size: 17))
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "dictlink",
                      let word = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "word" })?
                        .value,
                      !word.isEmpty else {
                    return .discarded
                }
                onOpenWord(word)
                return .handled
            })
    }

    private func attributed(_ source: String) -> AttributedString {
        let nsSource = source as NSString
        let spans = MOEText.quoteSpans(in: source)
        var result = AttributedString()
        var cursor = 0
        for span in spans {
            if span.range.location > cursor {
                result += AttributedString(nsSource.substring(with: NSRange(location: cursor, length: span.range.location - cursor)))
            }
            let token = nsSource.substring(with: span.range)
            if let opening = token.first, let closing = token.last, linkedWords.contains(span.inner) {
                result += AttributedString(String(opening))
                result += link(span.inner)
                result += AttributedString(String(closing))
            } else if span.candidates.count > 1, span.candidates.contains(where: { linkedWords.contains($0) }) {
                result += AttributedString(String(token.first ?? "「"))
                for (index, part) in span.candidates.enumerated() {
                    if index > 0 { result += AttributedString("、") }
                    result += linkedWords.contains(part) ? link(part) : AttributedString(part)
                }
                result += AttributedString(String(token.last ?? "」"))
            } else {
                result += AttributedString(token)
            }
            cursor = span.range.location + span.range.length
        }
        if cursor < nsSource.length {
            result += AttributedString(nsSource.substring(from: cursor))
        }
        return result
    }

    private func link(_ word: String) -> AttributedString {
        var components = URLComponents()
        components.scheme = "dictlink"
        components.queryItems = [URLQueryItem(name: "word", value: word)]
        var linked = AttributedString(word)
        linked.link = components.url
        linked.foregroundColor = .blue
        linked.underlineStyle = .single
        return linked
    }
}

private struct MOESourceSegment: Identifiable {
    let id = UUID()
    let text: String
    let image: UIImage?

    static func split(_ source: String) -> [MOESourceSegment] {
        guard let regex = try? NSRegularExpression(pattern: "&[^;\\n]{1,80};") else {
            return [MOESourceSegment(text: source, image: nil)]
        }

        let nsSource = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
        guard !matches.isEmpty else {
            return [MOESourceSegment(text: source, image: nil)]
        }

        var result: [MOESourceSegment] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                result.append(MOESourceSegment(
                    text: nsSource.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                    image: nil
                ))
            }

            let token = nsSource.substring(with: match.range)
            let filename = String(token.dropFirst().dropLast())
            let image = Self.loadImage(named: filename)
            result.append(MOESourceSegment(text: image == nil ? token : "", image: image))
            cursor = match.range.location + match.range.length
        }

        if cursor < nsSource.length {
            result.append(MOESourceSegment(text: nsSource.substring(from: cursor), image: nil))
        }
        return result
    }

    private static func loadImage(named filename: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "MOEImages") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

struct MOEEntryMetadataView: View {
    let item: DictItem

    private var showsCharacterStrokeData: Bool {
        item.wordLength == 1 && (!item.radical.isEmpty || item.strokeCount > 0 || item.outsideRadicalStrokes > 0)
    }

    private var variantTypeName: String {
        item.variantType == "變" ? "變體" : item.variantType
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("教育部詞條資訊", systemImage: "list.bullet.rectangle")
                .font(.headline)
                .foregroundColor(.secondary)

            MOEInfoRow(label: "字詞名", value: item.word)
            MOEInfoRow(label: "字詞號", value: item.entryID)
            MOEInfoRow(label: "字數", value: "\(item.wordLength)")
            if !item.entryAlias.isEmpty { MOEInfoRow(label: "辭條別名", value: item.entryAlias) }
            if showsCharacterStrokeData {
                MOEInfoRow(label: "部首字", value: item.radical)
                MOEInfoRow(label: "總筆畫數", value: "\(item.strokeCount)")
                MOEInfoRow(label: "部首外筆畫數", value: "\(item.outsideRadicalStrokes)")
            }
            if item.pronunciationOrder > 0 {
                MOEInfoRow(label: "多音排序", value: "\(item.pronunciationOrder)")
            }
            if !item.variantType.isEmpty { MOEInfoRow(label: "變體類型", value: variantTypeName) }
            if !item.variantCharacters.isEmpty { MOEInfoRow(label: "異體字", value: item.variantCharacters) }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
}

struct MOEPronunciationView: View {
    let item: DictItem

    private var hasContent: Bool {
        !item.phonetic.isEmpty || !item.pinyin.isEmpty || !item.variantPhonetic.isEmpty || !item.variantPinyin.isEmpty || !item.pronunciationNote.isEmpty
    }

    var body: some View {
        if hasContent {
        VStack(alignment: .leading, spacing: 10) {
            Label("教育部讀音資料", systemImage: "speaker.wave.2")
                .font(.headline)
                .foregroundColor(.secondary)
            if !item.phonetic.isEmpty {
                MOEInfoRow(label: "注音一式", value: item.phonetic, valueFont: AppTheme.zhuyinFont(size: 17))
            }
            if !item.pinyin.isEmpty {
                MOEInfoRow(label: "漢語拼音", value: item.pinyin)
            }
            if !item.variantPhonetic.isEmpty { MOEInfoRow(label: "變體注音", value: item.variantPhonetic, valueFont: AppTheme.zhuyinFont(size: 17)) }
            if !item.variantPinyin.isEmpty { MOEInfoRow(label: "變體漢語拼音", value: item.variantPinyin) }
            if !item.pronunciationNote.isEmpty {
                MOEInfoRow(label: "多音參見訊息", value: item.pronunciationNote, valueFont: AppTheme.zhuyinFont(size: 17))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        }
    }
}

struct MOEInfoRow: View {
    let label: String
    let value: String
    var valueFont: Font = .body

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundColor(.secondary)
            if value.contains("&") {
                MOESourceTextView(sourceText: value)
            } else {
                Text(value).font(valueFont).foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RelatedWordsView: View {
    let title: String
    let systemImage: String
    let words: [String]
    var linkedWords: Set<String> = []
    var onOpen: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(words, id: \.self) { word in
                        if linkedWords.contains(word) {
                            if let onOpen {
                                Button {
                                    onOpen(word)
                                } label: {
                                    relatedWordLabel(word)
                                }
                            } else {
                                NavigationLink(destination: LinkedEntryView(word: word)) {
                                    relatedWordLabel(word)
                                }
                            }
                        } else {
                            Text(word)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }

    private func relatedWordLabel(_ word: String) -> some View {
        Text(word)
            .font(.subheadline)
            .foregroundColor(.blue)
            .underline()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(8)
    }
}

struct LinkedEntryView: View {
    let word: String

    var body: some View {
        if let item = DatabaseManager.shared.lookupExact(word: word) {
            DetailView(item: item)
        } else {
            ContentUnavailableView("辭典沒有獨立詞目", systemImage: "text.book.closed", description: Text("「\(word)」只出現在相關詞，沒有自己的條目。"))
        }
    }
}
