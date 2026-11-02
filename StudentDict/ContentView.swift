import SwiftUI
import Speech
import AVFoundation
import GoogleMobileAds // AdMob
import RevenueCat       // RevenueCat

// ==========================================
// MARK: - 1. 工具與設定 (Utils & Models)
// ==========================================

struct AppTheme {
    static let background = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let primary = Color.blue
    static let secondary = Color.orange
    
    static func shadowColor(colorScheme: ColorScheme) -> Color {
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
    
    /// 系統字體：英文為 SF，繁體中文為蘋方（PingFang TC）。
    static func textFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }

    /// 注音與聲調。SF 沒有注音符號，改用 iOS 內建的蘋方繁體。
    static func zhuyinFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium:
            name = "PingFangTC-Medium"
        case .semibold, .bold, .heavy, .black:
            name = "PingFangTC-Semibold"
        default:
            name = "PingFangTC-Regular"
        }
        return Font.custom(name, size: size)
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct BopomofoData {
    static let initials = ["ㄅ", "ㄆ", "ㄇ", "ㄈ", "ㄉ", "ㄊ", "ㄋ", "ㄌ", "ㄍ", "ㄎ", "ㄏ", "ㄐ", "ㄑ", "ㄒ", "ㄓ", "ㄔ", "ㄕ", "ㄖ", "ㄗ", "ㄘ", "ㄙ"]
    static let medials = ["ㄧ", "ㄨ", "ㄩ"]
    static let finals = ["ㄚ", "ㄛ", "ㄜ", "ㄝ", "ㄞ", "ㄟ", "ㄠ", "ㄡ", "ㄢ", "ㄣ", "ㄤ", "ㄥ", "ㄦ"]
    static let tones = ["ˉ", "ˊ", "ˇ", "ˋ", "˙"]
    static var all: Set<String> { return Set(initials + medials + finals + tones) }
    static func isBopomofo(_ char: Character) -> Bool { return all.contains(String(char)) }
}

struct DefinitionItem: Identifiable {
    let id = UUID()
    let number: String?
    let text: String
    let example: String?
}

class DefinitionParser {
    static func parse(_ rawText: String) -> [DefinitionItem] {
        var items: [DefinitionItem] = []
        let pattern = "\\d+\\."
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsString = rawText as NSString
        let results = regex?.matches(in: rawText, range: NSRange(location: 0, length: nsString.length)) ?? []
        
        if !results.isEmpty {
            var lastLocation = 0
            for (index, match) in results.enumerated() {
                let start = match.range.location
                let end = match.range.location + match.range.length
                if index > 0 {
                    let content = nsString.substring(with: NSRange(location: lastLocation, length: start - lastLocation))
                    items.append(createItem(number: "\(index)", fullText: content))
                }
                lastLocation = end
            }
            if lastLocation < nsString.length {
                let content = nsString.substring(from: lastLocation)
                items.append(createItem(number: "\(results.count)", fullText: content))
            }
        } else {
            items.append(createItem(number: nil, fullText: rawText))
        }
        return items
    }
    
    private static func createItem(number: String?, fullText: String) -> DefinitionItem {
        let cleanText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let exampleKeys = ["如：", "例如：", "譬如：", "造句："]
        for key in exampleKeys {
            if let range = cleanText.range(of: key) {
                let definitionPart = String(cleanText[..<range.lowerBound])
                let examplePart = String(cleanText[range.lowerBound...])
                return DefinitionItem(number: number, text: definitionPart, example: examplePart)
            }
        }
        return DefinitionItem(number: number, text: cleanText, example: nil)
    }
}

class BopomofoSplitter {
    static func split(phonetic: String, count: Int) -> [String] {
        let normalized = phonetic.replacingOccurrences(of: "\u{3000}", with: " ")
        let parts = normalized.components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count == count { return parts }
        if parts.count > count { return Array(parts.prefix(count)) }
        var safeParts = parts
        while safeParts.count < count { safeParts.append("") }
        return safeParts
    }
}

struct ZhuyinIME {
    static let shared = ZhuyinIME()
    func getCandidates(for input: String) -> [String] {
        let currentBopomofo = extractLastBopomofo(from: input)
        if currentBopomofo.isEmpty { return [] }
        return DatabaseManager.shared.searchByPhonetic(currentBopomofo)
    }
    private func extractLastBopomofo(from text: String) -> String {
        var result = ""
        for char in text.reversed() {
            if BopomofoData.isBopomofo(char) { result.insert(char, at: result.startIndex) }
            else { break }
        }
        return result
    }
}

// ==========================================
// MARK: - 2. 主視圖 (Main View)
// ==========================================

struct ContentView: View {
    @State private var searchText = ""
    @State private var searchedKeyword = ""
    @State private var results: [DictItem] = []
    
    @State private var historyItems: [DictItem] = []
    @State private var favoriteItems: [DictItem] = []
    
    @State private var selectedTab = 0
    
    @State private var showLicense = false
    @State private var showPaywall = false
    @State private var showSpeechVoiceSettings = false
    @State private var showCustomKeyboard = true
    @State private var isLoading = true
    @StateObject private var speechInput = SpeechInputManager()
    
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var isPurchasing = false
    @State private var adLoaded = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    // [工具] 判斷是否為 iPad
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    @State private var hingePhase: DuoHingePhase = .unavailable
    @State private var bookFrost: Double = 0
    @State private var canvasSize: CGSize = .zero
    @State private var browseHeight: CGFloat = 0
    @State private var historyListHeight: CGFloat = 0
    @State private var trailingOcclusion: CGFloat = 0
    @State private var sawDuoHinge = false
    @State private var spreadPath: [DictItem] = []
    
    private var usesSpread: Bool {
        switch hingePhase {
        case .partiallyOpen, .fullyOpen:
            return true
        case .closed, .unavailable:
            return horizontalSizeClass == .regular && canvasSize.width > canvasSize.height + 40
        }
    }

    private var keyboardHeight: CGFloat {
        if verticalSizeClass == .compact { return 232 }
        return isPad ? 420 : 360
    }

    /// 展開後左頁要同時放下標題、至少一張詞卡、廣告和鍵盤，鍵盤改依剩餘高度縮短。
    private var spreadKeyboardHeight: CGFloat {
        fittedKeyboardHeight(reserveForCard: 148, limit: 300)
    }

    /// 折疊後的單頁沿用同一套鍵盤，並留出廣告高度。
    private var singlePageKeyboardHeight: CGFloat {
        fittedKeyboardHeight(reserveForCard: 176, limit: 340)
    }

    private func fittedKeyboardHeight(reserveForCard: CGFloat, limit: CGFloat) -> CGFloat {
        let adHeight: CGFloat = purchaseManager.isPremium ? 0 : 56
        let natural = 248 + adHeight
        guard browseHeight > 0 else { return min(limit, natural) }
        let room = browseHeight - reserveForCard
        return min(limit, max(240, min(natural, room)))
    }

    /// 封面的直向相機欄，或鉸鏈已經闔上。單頁仍把廣告放在鍵盤和授權連結中間，跟展開的左頁同一處。
    private var duoSinglePage: Bool {
        guard !usesSpread else { return false }
        let coverWidth = horizontalSizeClass == .compact && sawDuoHinge
        return hingePhase == .closed || trailingOcclusion >= 64 || coverWidth
    }

    private func noteBrowseLayout(_ proxy: GeometryProxy) {
        browseHeight = proxy.size.height
        guard #available(iOS 27.1, *) else { return }
        let span = proxy.reservedRegions(kind: .occlusion)
            .filter { $0.isActive }
            .map { min($0.frame.width, $0.frame.height) }
            .max() ?? 0
        if abs(span - trailingOcclusion) > 1 {
            trailingOcclusion = span
        }
    }
    
    var body: some View {
        readingRoot
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { canvasSize = proxy.size }
                        .onChange(of: proxy.size) { _, newValue in
                            canvasSize = newValue
                        }
                }
            }
            .observingDuoHinge { snapshot in
                applyHinge(snapshot)
            }
            .bookOpenFrost(bookFrost, horizontalFold: canvasSize.height > canvasSize.width)
    }

    private var readingRoot: some View {
        ZStack {
            if isLoading {
                LaunchScreenView().transition(.opacity).zIndex(2)
            } else if usesSpread {
                spreadReading
            } else {
                NavigationView {
                    browseColumn(onSelect: nil)
                        .navigationTitle("")
                        .navigationBarHidden(true)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .sheet(isPresented: $showLicense) { LicenseView() }
        .sheet(isPresented: $showPaywall) { PaywallView(isPresented: $showPaywall) }
        .sheet(isPresented: $showSpeechVoiceSettings) { SpeechVoiceSettingsView() }
        .onChange(of: selectedTab) { _ in loadData() }
        .onChange(of: speechInput.transcribedText) { _, val in if !val.isEmpty { searchText = val } }
        .onChange(of: searchText) { _, val in performSearch(keyword: val) }
        .onAppear { loadData() }
        .alert(isPresented: $showAlert) { Alert(title: Text("提示"), message: Text(alertMessage), dismissButton: .default(Text("好"))) }
        .overlay {
            if isPurchasing {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("正在連線 App Store…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation { isLoading = false } } }
    }

    @ViewBuilder
    private var spreadReading: some View {
        if #available(iOS 27.1, *) {
            ArrangementView {
                browseColumn(onSelect: selectEntry)
            } secondary: {
                spreadDetail
            }
            .arrangementViewStyle(.split)
            .splitArrangementLayoutRatio(idealHorizontal: 0.44, idealVertical: 0.46)
        } else if canvasSize.width >= canvasSize.height {
            HStack(spacing: 0) {
                browseColumn(onSelect: selectEntry)
                Divider()
                spreadDetail
            }
        } else {
            VStack(spacing: 0) {
                browseColumn(onSelect: selectEntry)
                Divider()
                spreadDetail
            }
        }
    }

    private var spreadDetail: some View {
        Group {
            if let item = spreadPath.last {
                DetailView(
                    item: item,
                    fillsPage: true,
                    onOpenItem: { spreadPath.append($0) },
                    onFavoriteChange: loadData
                )
                .id(item.id)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if spreadPath.count > 1 || !historyItems.isEmpty {
                        HStack {
                            Button {
                                if spreadPath.count > 1 {
                                    spreadPath.removeLast()
                                } else {
                                    spreadPath.removeAll()
                                }
                            } label: {
                                Label(spreadPath.count > 1 ? "返回" : "查詢紀錄", systemImage: "chevron.left")
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            } else if historyFlowsAcrossSpread {
                if !rightHistoryItems.isEmpty {
                    HistoryListView(
                        items: rightHistoryItems,
                        showsHeader: false,
                        singleColumn: true,
                        onClear: {},
                        onSelect: selectEntry
                    )
                }
            } else if !historyItems.isEmpty {
                HistoryListView(
                    items: historyItems,
                    onClear: {
                        DatabaseManager.shared.clearHistory()
                        spreadPath.removeAll()
                        loadData()
                    },
                    onSelect: selectEntry
                )
            } else {
                OpenDictionaryPage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .modifier(DisplayOcclusionPadding(fallbackTop: 88))
    }

    private func selectEntry(_ item: DictItem) {
        spreadPath = [item]
    }

    /// 鍵盤收起、尚未打開詞條時，最近查詢從左頁接到右頁，同一筆不重複。
    private var historyFlowsAcrossSpread: Bool {
        usesSpread && !showCustomKeyboard && searchText.isEmpty && selectedTab == 0 && spreadPath.isEmpty && !historyItems.isEmpty
    }

    private var historyColumnCapacity: Int {
        let rowHeight: CGFloat = 136
        let available = historyListHeight - 48
        guard available >= rowHeight * 0.7 else { return max(historyItems.count, 1) }
        return max(1, Int(floor(available / rowHeight)))
    }

    private var leftHistoryItems: [DictItem] {
        guard historyFlowsAcrossSpread else { return historyItems }
        return Array(historyItems.prefix(historyColumnCapacity))
    }

    private var rightHistoryItems: [DictItem] {
        guard historyFlowsAcrossSpread else { return historyItems }
        return Array(historyItems.dropFirst(historyColumnCapacity))
    }

    private func applyHinge(_ snapshot: DuoHingeSnapshot) {
        if snapshot.phase != .unavailable {
            sawDuoHinge = true
        }
        hingePhase = snapshot.phase
        let unfolded = snapshot.phase == .partiallyOpen || snapshot.phase == .fullyOpen
        DuoOrientation.setUnfolded(unfolded)
        guard !reduceMotion else {
            bookFrost = 0
            return
        }
        switch snapshot.phase {
        case .partiallyOpen:
            let flat = min(1, max(0, snapshot.radians / .pi))
            bookFrost = 1 - flat
        case .fullyOpen:
            withAnimation(.easeOut(duration: 0.45)) { bookFrost = 0 }
        case .closed, .unavailable:
            bookFrost = 0
        }
    }

    private func browseColumn(onSelect: ((DictItem) -> Void)?) -> some View {
        let fillsPage = onSelect != nil
        let compactColumn = fillsPage || duoSinglePage
        return VStack(spacing: 0) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("重編國語辭典修訂本")
                                        .font(compactColumn ? .system(size: 22, weight: .bold) : (isPad ? .system(size: 26, weight: .bold) : .headline))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Spacer()
                                    Menu {
                                        if !purchaseManager.isPremium {
                                            Button(action: { showPaywall = true }) {
                                                Label(removeAdsTitle, systemImage: "heart.fill")
                                            }
                                        }
                                        Button(action: { restorePurchases() }) { Label("恢復購買", systemImage: "arrow.clockwise") }
                                        Button(action: { showSpeechVoiceSettings = true }) { Label("語音設定", systemImage: "waveform") }
                                        Button(action: { showLicense = true }) { Label("關於本程式", systemImage: "info.circle") }
                                    } label: {
                                        Image(systemName: "ellipsis.circle").font(.system(size: 24)).foregroundColor(.primary).padding(8)
                                    }
                                }
                                .padding(.horizontal).padding(.top, compactColumn ? 12 : (isPad ? 16 : 8)).padding(.bottom, 8)

                                VStack(spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass").foregroundColor(.gray).font(isPad ? .title2 : .body)
                                        SimulatedTextField(text: searchText, placeholder: "輸入單字或按麥克風")
                                            .onTapGesture { withAnimation(.spring()) { showCustomKeyboard = true } }
                                            .frame(height: isPad ? 50 : 36)
                                        if !searchText.isEmpty {
                                            Button(action: { searchText = ""; results = [] }) { Image(systemName: "xmark.circle.fill").foregroundColor(.gray).font(isPad ? .title2 : .title3) }
                                            Button(action: {
                                                searchText.removeLast()
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            }) { Image(systemName: "delete.left.fill").foregroundColor(.gray).font(isPad ? .title2 : .title3).padding(.leading, 4) }
                                        }
                                        Button(action: {
                                            speechInput.toggleRecording()
                                            if speechInput.isRecording { showCustomKeyboard = false }
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }) {
                                            Image(systemName: speechInput.isRecording ? "mic.fill" : "mic")
                                                .font(isPad ? .title : .title2)
                                                .foregroundColor(speechInput.isRecording ? .red : .blue)
                                                .scaleEffect(speechInput.isRecording ? 1.2 : 1.0)
                                        }
                                        Button(action: { withAnimation(.spring()) { showCustomKeyboard.toggle() } }) {
                                            Image(systemName: showCustomKeyboard ? "keyboard.chevron.compact.down.fill" : "keyboard.fill")
                                                .font(isPad ? .title : .title2).foregroundColor(showCustomKeyboard ? .orange : .gray)
                                        }
                                    }
                                    .padding(isPad ? 14 : 12).background(AppTheme.cardBackground).cornerRadius(12)
                                    .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 5)
                                    if searchText.isEmpty {
                                        Picker("Tab", selection: $selectedTab) {
                                            Text("最近查詢").tag(0)
                                            Text("我的收藏").tag(1)
                                        }
                                        .pickerStyle(SegmentedPickerStyle()).padding(.horizontal, 4)
                                    }
                                }
                                .padding(.horizontal).padding(.bottom, 10)
                                if speechInput.isRecording {
                                    Text("正在聆聽...").font(.caption).foregroundColor(.red).padding(.bottom, 8)
                                } else if let speechError = speechInput.errorMessage {
                                    Text(speechError).font(.caption).foregroundColor(.red).padding(.bottom, 8)
                                }
                            }
                            .frame(maxWidth: fillsPage ? .infinity : (isPad ? 680 : .infinity))
                            .layoutPriority(2)

                            ZStack {
                                if !searchText.isEmpty {
                                    if results.isEmpty {
                                        VStack { Spacer(); Text("搜尋中 / 查無結果").foregroundColor(.gray); Spacer() }
                                    } else { ResultListView(items: results, onSelect: onSelect) }
                                } else if selectedTab == 0 {
                                    if historyItems.isEmpty { EmptyStateView(title: "尚無查詢紀錄") }
                                    else {
                                        HistoryListView(
                                            items: historyFlowsAcrossSpread ? leftHistoryItems : historyItems,
                                            singleColumn: historyFlowsAcrossSpread,
                                            onClear: { DatabaseManager.shared.clearHistory(); loadData() },
                                            onSelect: onSelect
                                        )
                                    }
                                } else {
                                    if favoriteItems.isEmpty { EmptyStateView(title: "尚無收藏單字", icon: "heart.slash") }
                                    else { FavoritesListView(items: favoriteItems, onSelect: onSelect) { loadData() } }
                                }
                            }
                            .frame(maxWidth: fillsPage ? .infinity : (isPad ? 800 : .infinity)).frame(maxHeight: .infinity)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear
                                        .onAppear { historyListHeight = proxy.size.height }
                                        .onChange(of: proxy.size.height) { _, newValue in
                                            historyListHeight = newValue
                                        }
                                }
                            }

                            VStack(spacing: 0) {
                                if !purchaseManager.isPremium && !compactColumn {
                                    AdBannerView(isLoaded: $adLoaded)
                                        .frame(height: isPad ? 90 : 50)
                                        .frame(maxWidth: .infinity)
                                        .clipped()
                                        .background(Color(UIColor.systemGray6))
                                }
                                if showCustomKeyboard {
                                    let keyboardHeightForPage = fillsPage ? spreadKeyboardHeight : singlePageKeyboardHeight
                                    let keyboard = ZhuyinKeyboardView(
                                        text: $searchText,
                                        compact: compactColumn,
                                        expandsFooter: true,
                                        showsBanner: compactColumn && !purchaseManager.isPremium,
                                        adLoaded: $adLoaded
                                    )
                                    if compactColumn {
                                        keyboard
                                            .frame(minHeight: keyboardHeightForPage, idealHeight: keyboardHeightForPage, maxHeight: keyboardHeightForPage)
                                            .clipped()
                                    } else {
                                        keyboard
                                            .frame(minHeight: keyboardHeight, idealHeight: keyboardHeight, maxHeight: keyboardHeight)
                                            .frame(maxWidth: isPad ? 640 : .infinity)
                                            .clipped()
                                            .cornerRadius(isPad ? 16 : 0, corners: [.topLeft, .topRight])
                                            .shadow(color: isPad ? .black.opacity(0.1) : .clear, radius: 10, x: 0, y: -5)
                                            .padding(.bottom, isPad ? 10 : 0)
                                    }
                                }
                            }
                            .layoutPriority(2)
                            .frame(maxWidth: .infinity).background(Color(UIColor.systemGray6).ignoresSafeArea(edges: .bottom))
                        }
                    .background(AppTheme.background.ignoresSafeArea())
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { noteBrowseLayout(proxy) }
                                .onChange(of: proxy.size) { _, _ in
                                    noteBrowseLayout(proxy)
                                }
                        }
                    }
    }
    
    // MARK: - Logic
    var removeAdsTitle: String {
        if let price = purchaseManager.removeAdsPrice {
            return "移除廣告 (\(price))"
        }
        return "移除廣告"
    }

    func restorePurchases() {
        isPurchasing = true
        Purchases.shared.restorePurchases { customerInfo, _ in
            DispatchQueue.main.async {
                self.isPurchasing = false
                if let info = customerInfo, info.entitlements["premium"]?.isActive == true {
                    self.purchaseManager.isPremium = true
                    self.alertMessage = "已成功恢復您的購買權益！"
                } else {
                    self.alertMessage = "查無此帳號的購買紀錄。"
                }
                self.showAlert = true
            }
        }
    }
    
    func performSearch(keyword: String) {
        guard keyword != searchedKeyword else { return }
        searchedKeyword = keyword
        if keyword.isEmpty {
            results = []
        } else {
            results = DatabaseManager.shared.search(keyword: keyword)
        }
    }
    
    func loadData() {
        historyItems = DatabaseManager.shared.getHistory()
        favoriteItems = DatabaseManager.shared.getFavorites()
    }
}

// ==========================================
// MARK: - 3. 詳情視圖 (Detail View)
// ==========================================

struct DetailView: View {
    let item: DictItem
    var fillsPage = false
    var onOpenItem: ((DictItem) -> Void)? = nil
    var onFavoriteChange: (() -> Void)? = nil
    @State private var isFav: Bool = false
    @State private var showSpeechVoiceSettings = false
    @State private var linkedWords: Set<String> = []
    @State private var crossReferences: [DictItem] = []
    @State private var openedWord: String?
    @ObservedObject private var speechManager = SpeechManager.shared
    @Environment(\.colorScheme) var colorScheme
    var isSingleChar: Bool { item.word.count == 1 }
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 0) {
                        if item.word.contains("&") {
                            VStack(spacing: 12) {
                                MOESourceTextView(sourceText: item.word)
                                if !item.phonetic.isEmpty {
                                    Text(item.phonetic).font(AppTheme.zhuyinFont(size: 24, weight: .heavy)).foregroundColor(.white)
                                        .padding(.vertical, 6).padding(.horizontal, 16).background(Capsule().fill(Color.orange))
                                }
                                if !item.pinyin.isEmpty { Text(item.pinyin).foregroundColor(.secondary) }
                            }
                        } else if isSingleChar {
                            HStack(alignment: .top, spacing: 20) {
                                MiZiGeView(char: item.word, font: AppTheme.textFont(size: 90))
                                    .frame(width: 140, height: 140).shadow(radius: 2)
                                VStack(alignment: .leading, spacing: 14) {
                                    if !item.phonetic.isEmpty {
                                        Text(item.phonetic).font(AppTheme.zhuyinFont(size: 24, weight: .heavy)).foregroundColor(.white)
                                            .padding(.vertical, 6).padding(.horizontal, 16).background(Capsule().fill(Color.orange))
                                            .shadow(color: .orange.opacity(0.3), radius: 3, x: 0, y: 2)
                                    } else if !item.variantCharacters.isEmpty {
                                        Text("異體字").font(.headline).foregroundColor(.orange)
                                    }
                                    if !item.pinyin.isEmpty { Text(item.pinyin).font(AppTheme.textFont(size: 18, weight: .medium)).foregroundColor(.secondary) }
                                    Divider()
                                    VStack(alignment: .leading, spacing: 8) {
                                        InfoLabel(title: "部首", value: item.radical.isEmpty ? "-" : item.radical, icon: "book.closed")
                                        InfoLabel(title: "筆畫", value: "\(item.strokeCount) 畫", icon: "pencil")
                                        if item.outsideRadicalStrokes > 0 {
                                            InfoLabel(title: "部首外", value: "\(item.outsideRadicalStrokes) 畫", icon: "number")
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            VStack(spacing: 10) {
                                IdiomBreakdownView(word: item.word, phonetic: item.phonetic)
                                if !item.pinyin.isEmpty { Text(item.pinyin).font(AppTheme.textFont(size: 18, weight: .medium)).foregroundColor(.secondary) }
                            }
                            .padding(.vertical, 10)
                        }
                        EntryLearningNotes(item: item, crossReferences: crossReferences, onOpenItem: onOpenItem)
                    }
                    .padding(24).background(AppTheme.cardBackground).cornerRadius(24)
                    .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 8, x: 0, y: 4)

                    VStack(spacing: 8) {
                        HStack(spacing: 14) {
                            ActionButton(icon: "speaker.wave.3.fill", text: "唸發音", color: .blue) { speechManager.speak(word: item.word, phonetic: item.phonetic) }
                            ActionButton(icon: "waveform", text: "選擇語音", color: .purple) { showSpeechVoiceSettings = true }
                            ActionButton(icon: isFav ? "heart.fill" : "heart", text: isFav ? "已收藏" : "收藏", color: isFav ? .red : .gray) {
                                isFav = DatabaseManager.shared.toggleFavorite(word: item.word)
                                onFavoriteChange?()
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        }
                        if !speechManager.hasNaturalVoice {
                            Text("目前使用標準語音。點「選擇語音」可切換或查看 Apple 增強語音下載方式。")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "text.book.closed.fill").foregroundColor(.green)
                            Text("教育部原文釋義").font(.headline).foregroundColor(.secondary)
                            Spacer()
                            Button {
                                let spoken = MOEText.plain(item.definition)
                                if !spoken.isEmpty { SpeechManager.shared.speak(spoken) }
                            } label: {
                                Image(systemName: "speaker.wave.2")
                            }
                            .accessibilityLabel("朗讀釋義")
                        }
                        .padding(.horizontal, 8)
                        VStack(alignment: .leading, spacing: 0) {
                            MOESourceTextView(sourceText: item.definition, linkedWords: linkedWords) { word in
                                openRelatedWord(word)
                            }
                        }
                            .padding().frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.cardBackground).cornerRadius(16)
                        if !item.synonyms.isEmpty || !item.antonyms.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                if !item.synonyms.isEmpty {
                                    RelatedWordsView(title: "相似詞", systemImage: "arrow.right.circle", words: MOEText.listWords(item.synonyms), linkedWords: linkedWords, onOpen: openRelatedWord)
                                }
                                if !item.antonyms.isEmpty {
                                    RelatedWordsView(title: "相反詞", systemImage: "arrow.left.circle", words: MOEText.listWords(item.antonyms), linkedWords: linkedWords, onOpen: openRelatedWord)
                                }
                            }
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground).cornerRadius(12)
                        }
                        MOEPronunciationView(item: item)
                        MOEEntryMetadataView(item: item)
                    }
                    .padding(.bottom, 40)
                }
                .padding().padding(.top, 12).frame(maxWidth: fillsPage ? .infinity : (isPad ? 720 : .infinity)).frame(maxWidth: .infinity)
            }
            .safeAreaPadding(.top, 8)
        }
        .sheet(isPresented: $showSpeechVoiceSettings) { SpeechVoiceSettingsView() }
        .background {
            if onOpenItem == nil {
                NavigationLink(isActive: Binding(get: { openedWord != nil }, set: { if !$0 { openedWord = nil } })) {
                    if let openedWord {
                        LinkedEntryView(word: openedWord)
                    } else {
                        EmptyView()
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            }
        }
        .onAppear {
            isFav = DatabaseManager.shared.isFavorite(word: item.word)
            DatabaseManager.shared.addToHistory(word: item.word)
            prepareRelatedLinks()
        }
        .onDisappear { SpeechManager.shared.stop() }
    }

    private func openRelatedWord(_ word: String) {
        if let onOpenItem, let found = DatabaseManager.shared.lookupExact(word: word) {
            onOpenItem(found)
        } else {
            openedWord = word
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func prepareRelatedLinks() {
        var candidates = MOEText.quotedWords(item.definition)
        candidates.append(contentsOf: MOEText.listWords(item.synonyms))
        candidates.append(contentsOf: MOEText.listWords(item.antonyms))
        candidates.removeAll { $0 == item.word }
        linkedWords = DatabaseManager.shared.wordsThatExist(candidates)
        crossReferences = DatabaseManager.shared.lookupEntryIDs(MOEText.crossReferenceIDs(item.pronunciationNote))
            .filter { $0.id != item.id }
    }
}

private struct EntryLearningNotes: View {
    let item: DictItem
    var crossReferences: [DictItem] = []
    var onOpenItem: ((DictItem) -> Void)? = nil

    private var showsVariantBadge: Bool {
        !item.variantCharacters.isEmpty && !item.phonetic.isEmpty
    }

    private var hasNotes: Bool {
        showsVariantBadge || !item.entryAlias.isEmpty || !item.pronunciationNote.isEmpty || !item.variantPhonetic.isEmpty || !item.variantPinyin.isEmpty || !crossReferences.isEmpty
    }

    var body: some View {
        if hasNotes {
            VStack(alignment: .leading, spacing: 6) {
                if showsVariantBadge {
                    Text(item.variantCharacters).font(.caption).foregroundColor(.orange)
                }
                if !item.entryAlias.isEmpty {
                    Text("別名：\(item.entryAlias)").font(.subheadline).foregroundColor(.secondary)
                }
                if !item.pronunciationNote.isEmpty {
                    Text("多音參見：\(item.pronunciationNote)")
                        .font(AppTheme.zhuyinFont(size: 15))
                        .foregroundColor(.primary)
                }
                ForEach(crossReferences) { target in
                    if let onOpenItem {
                        Button {
                            onOpenItem(target)
                        } label: {
                            crossReferenceLabel(target)
                        }
                    } else {
                        NavigationLink(destination: DetailView(item: target)) {
                            crossReferenceLabel(target)
                        }
                    }
                }
                if !item.variantPhonetic.isEmpty || !item.variantPinyin.isEmpty {
                    Text("變體讀音：\(item.variantPhonetic) \(item.variantPinyin)")
                        .font(AppTheme.zhuyinFont(size: 15))
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
        }
    }

    private func crossReferenceLabel(_ target: DictItem) -> some View {
        Label {
            Text("查看「\(target.word)」\(target.phonetic)")
                .font(AppTheme.zhuyinFont(size: 15))
        } icon: {
            Image(systemName: "link")
        }
    }
}

// ==========================================
// MARK: - 4. 列表元件 (Lists)
// ==========================================

struct ResultListView: View {
    let items: [DictItem]
    var onSelect: ((DictItem) -> Void)? = nil
    let columns = [GridItem(.adaptive(minimum: 280), spacing: 16)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    EntryDestination(item: item, onSelect: onSelect) { WordCardView(item: item, showsDisclosure: onSelect == nil) }
                }
            }
            .padding(.horizontal).padding(.bottom, 20)
        }
    }
}

struct FavoritesListView: View {
    let items: [DictItem]
    var onSelect: ((DictItem) -> Void)? = nil
    let onRefresh: () -> Void
    let columns = [GridItem(.adaptive(minimum: 280), spacing: 16)]
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label("我的收藏", systemImage: "heart.fill").font(.headline).foregroundColor(.red)
                Spacer()
                Text("\(items.count) 筆讀音").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal).padding(.top, 8)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        EntryDestination(item: item, onSelect: onSelect, onDisappear: onRefresh) {
                            WordCardView(item: item, showsDisclosure: onSelect == nil)
                                .overlay(Image(systemName: "heart.fill").foregroundColor(.red).padding(12), alignment: .topTrailing)
                        }
                    }
                }
                .padding(.horizontal).padding(.bottom, 20)
            }
        }
    }
}

struct HistoryListView: View {
    let items: [DictItem]
    var showsHeader = true
    var singleColumn = false
    let onClear: () -> Void
    var onSelect: ((DictItem) -> Void)? = nil

    private var columns: [GridItem] {
        singleColumn ? [GridItem(.flexible(), spacing: 16)] : [GridItem(.adaptive(minimum: 280), spacing: 16)]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HStack {
                    Label("最近查詢", systemImage: "clock.arrow.circlepath").font(.headline).foregroundColor(.secondary)
                    Spacer()
                    Button(action: onClear) { Text("清除").font(.caption).foregroundColor(.blue) }
                }
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 8)
            } else {
                Color.clear.frame(height: 40)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        EntryDestination(item: item, onSelect: onSelect) { WordCardView(item: item, showsDisclosure: onSelect == nil) }
                    }
                }
                .padding(.horizontal).padding(.bottom, 20)
            }
        }
    }
}

// ==========================================
// MARK: - 5. 通用元件 (Components)
// ==========================================

struct EmptyStateView: View {
    var title: String = "輸入單字開始查詢"
    var icon: String = "book.closed.circle.fill"
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 64)).foregroundColor(.gray.opacity(0.25))
            Text(title).font(.headline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MiZiGeView: View {
    let char: String
    let font: Font
    var body: some View {
        ZStack {
            Rectangle().stroke(Color.red, lineWidth: 3).background(Color.white)
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height/2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height/2))
                    path.move(to: CGPoint(x: geo.size.width/2, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width/2, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.move(to: CGPoint(x: geo.size.width, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                }
                .stroke(Color.red.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
            Text(char)
                .font(font)
                .foregroundColor(.black)
        }
    }
}

struct IdiomBreakdownView: View {
    let word: String; let phonetic: String
    var body: some View {
        let chars = Array(word); let phonetics = BopomofoSplitter.split(phonetic: phonetic, count: chars.count)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<chars.count, id: \.self) { index in
                    VStack(spacing: 8) {
                        Text(String(chars[index]))
                            .font(AppTheme.textFont(size: 48))
                            .foregroundColor(AppTheme.primary)
                            .frame(width: 50, height: 50)
                        Text(index < phonetics.count ? phonetics[index] : "")
                            .font(AppTheme.zhuyinFont(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.secondary)
                            .multilineTextAlignment(.center).fixedSize()
                    }
                    .padding(8).background(Color.gray.opacity(0.05)).cornerRadius(8)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct EntryDestination<Label: View>: View {
    let item: DictItem
    var onSelect: ((DictItem) -> Void)?
    var onDisappear: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        if let onSelect {
            Button {
                onSelect(item)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: DetailView(item: item).onDisappear { onDisappear?() }) {
                label()
            }
            .buttonStyle(.plain)
        }
    }
}

struct WordCardView: View {
    let item: DictItem
    var showsDisclosure = true
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            WordCardLeadingView(item: item, colorScheme: colorScheme)
                .frame(width: 132, height: 88)
            VStack(alignment: .leading, spacing: 4) {
                if !item.radical.isEmpty && item.word.count == 1 {
                    HStack(spacing: 8) {
                        Text("部首: \(item.radical)").font(.caption2).foregroundColor(.gray)
                        Text(item.outsideRadicalStrokes > 0 ? "筆畫: \(item.strokeCount)（部首外 \(item.outsideRadicalStrokes)）" : "筆畫: \(item.strokeCount)").font(.caption2).foregroundColor(.gray)
                    }
                    .padding(.bottom, 2)
                }
                Text(MOEText.plain(item.definition).isEmpty ? "（教育部字圖）" : MOEText.plain(item.definition))
                    .font(.system(size: 16)).foregroundColor(.primary).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer()
            if showsDisclosure {
                Image(systemName: "chevron.right").foregroundColor(.gray.opacity(0.5)).font(.system(size: 14, weight: .bold)).padding(.top, 12)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(minHeight: 120)
        .background(AppTheme.cardBackground).cornerRadius(20)
        .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 5, x: 0, y: 2)
    }
}

private struct WordCardLeadingView: View {
    let item: DictItem
    let colorScheme: ColorScheme

    var body: some View {
        Group {
            if item.word.count == 1 {
                VStack(spacing: 3) {
                    Text(item.word)
                        .font(AppTheme.textFont(size: 32))
                        .foregroundColor(AppTheme.primary)
                    Text(item.phonetic)
                        .font(AppTheme.zhuyinFont(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.secondary)
                    if !item.pinyin.isEmpty {
                        Text(item.pinyin)
                            .font(AppTheme.textFont(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            } else if item.word.contains("&") {
                MOESourceTextView(sourceText: item.word)
            } else {
                MiniIdiomView(word: item.word, phonetic: item.phonetic, maxWidth: 124, showsBackground: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.05))
        .cornerRadius(12)
        .clipped()
    }
}

struct MiniIdiomView: View {
    let word: String; let phonetic: String
    let maxWidth: CGFloat
    let showsBackground: Bool
    @Environment(\.colorScheme) var colorScheme

    init(word: String, phonetic: String, maxWidth: CGFloat = 220, showsBackground: Bool = true) {
        self.word = word
        self.phonetic = phonetic
        self.maxWidth = maxWidth
        self.showsBackground = showsBackground
    }

    var body: some View {
        let chars = Array(word)
        let phonetics = BopomofoSplitter.split(phonetic: phonetic, count: chars.count)
        
        let availableWidth: CGFloat = maxWidth
        let calculatedWidth = availableWidth / CGFloat(max(1, chars.count))
        let itemSize = min(34, max(20, calculatedWidth))
        let fontSize = itemSize * 0.7
        
        HStack(spacing: 2) {
            ForEach(0..<chars.count, id: \.self) { index in
                VStack(spacing: 0) {
                    Text(String(chars[index]))
                        .font(AppTheme.textFont(size: fontSize))
                        .foregroundColor(AppTheme.primary)
                        .frame(height: itemSize)
                    
                    Text(index < phonetics.count ? phonetics[index] : "")
                        .font(AppTheme.zhuyinFont(size: max(9, fontSize * 0.45), weight: .medium))
                        .foregroundColor(AppTheme.secondary)
                        .lineLimit(1).fixedSize()
                }
                .frame(width: itemSize)
            }
        }
        .padding(6)
        .background(showsBackground ? Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.05) : .clear)
        .cornerRadius(8)
    }
}

struct DefinitionCard: View {
    let def: DefinitionItem
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let num = def.number {
                Text(num).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                    .frame(width: 32, height: 32).background(Circle().fill(Color.blue.opacity(0.8))).shadow(radius: 2)
            } else {
                Circle().fill(Color.blue.opacity(0.5)).frame(width: 12, height: 12).padding(.top, 10).padding(.leading, 8)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(def.text).font(.system(size: 20, weight: .medium)).foregroundColor(.primary).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                if let example = def.example {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "quote.opening").foregroundColor(.green.opacity(0.7)).font(.caption).padding(.top, 2)
                        Text(example).font(.system(size: 18)).foregroundColor(colorScheme == .dark ? .green.opacity(0.8) : .green.opacity(0.9)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12).background(Color.green.opacity(0.05)).cornerRadius(12)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.cardBackground)
        .cornerRadius(20).shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 4, x: 0, y: 2)
        .overlay(Image(systemName: "speaker.wave.2.circle").foregroundColor(.gray.opacity(0.3)).padding(12), alignment: .topTrailing)
    }
}

struct ActionButton: View {
    let icon: String; let text: String; let color: Color; let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(colorScheme == .dark ? 0.2 : 0.1)).frame(width: 60, height: 60)
                    Image(systemName: icon).font(.title2).foregroundColor(color)
                }
                Text(text).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

struct InfoLabel: View {
    let title: String; let value: String; let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(.gray).font(.footnote).frame(width: 20)
            Text(title).font(.callout).foregroundColor(.secondary)
            Text(value).font(.title3).fontWeight(.semibold).foregroundColor(.primary)
        }
    }
}

struct SimulatedTextField: View {
    let text: String; let placeholder: String
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    
    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.gray.opacity(0.6))
                    .font(.system(size: isPad ? 22 : 17))
            }
            HStack(spacing: 0) {
                Text(text)
                    .foregroundColor(.primary)
                    .font(AppTheme.zhuyinFont(size: isPad ? 22 : 17))
                
                if !text.isEmpty { BlinkingCursor() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // [Version Update]: iPad 高度由 44 改為 50，iPhone 由 30 改為 36 (可微調)
        .frame(height: isPad ? 50 : 30)
        .contentShape(Rectangle())
    }
}

struct BlinkingCursor: View {
    @State private var isVisible = true
    var body: some View {
        Rectangle().fill(Color.blue).frame(width: 2, height: 20).opacity(isVisible ? 1 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { isVisible.toggle() } }
    }
}

struct LaunchScreenView: View {
    @State private var isBouncing = false
    var body: some View {
        ZStack {
            Color.blue.opacity(0.1).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "book.fill").font(.system(size: 80)).foregroundColor(.blue)
                    .offset(y: isBouncing ? -20 : 0)
                    .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBouncing)
                Text("字典準備中...").font(.headline).foregroundColor(.secondary)
            }
        }
        .onAppear { isBouncing = true }
    }
}

struct LicenseView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let privacyURL = URL(string: "https://eric1207cvb.github.io/Mandarin-Training/")!
    let eulaURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    let moeURL = URL(string: "https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/dict_reviseddict_download.html")!
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("App 設計與開發").font(.headline)
                        HStack(spacing: 16) {
                            Image("DeveloperAvatar")
                                .resizable().scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .shadow(radius: 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("HSUEH YI AN").font(.title3).bold().foregroundColor(.primary)
                                Text("Independent Developer").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground)).cornerRadius(12)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("法律與條款").font(.headline)
                        Link(destination: privacyURL) {
                            HStack {
                                Label("隱私權政策 (Privacy Policy)", systemImage: "hand.raised.fill").foregroundColor(.blue)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundColor(.gray)
                            }
                            .padding().background(Color.blue.opacity(0.05)).cornerRadius(10)
                        }
                        Link(destination: eulaURL) {
                            HStack {
                                Label("使用者授權合約 (EULA)", systemImage: "doc.text.fill").foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundColor(.gray)
                            }
                            .padding().background(Color.gray.opacity(0.1)).cornerRadius(10)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("資料來源授權").font(.headline)
                        Text("本應用程式使用之資料來源為中華民國教育部《重編國語辭典修訂本》。").font(.body)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("授權條款：").font(.subheadline).bold()
                            Text("創用 CC－姓名標示－禁止改作 3.0 臺灣（CC BY-ND 3.0 Taiwan）").font(.caption).foregroundColor(.secondary)
                            Text("教育部公告：可重製、散布、傳輸及商業性利用，但不得修改著作，並須遵照使用說明。使用時請標示教育部及資料名稱。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("原始資料出處 (Attribution)：").font(.subheadline).bold()
                            Text("中華民國教育部（Ministry of Education, R.O.C.）。").font(.caption)
                            Link(destination: moeURL) {
                                HStack {
                                    Text("開啟教育部《重編國語辭典修訂本》資料下載頁")
                                    Spacer()
                                    Image(systemName: "globe")
                                }
                                .font(.caption).bold().foregroundColor(.white)
                                .padding(10).background(Color.blue).cornerRadius(8)
                            }
                        }
                    }
                    Spacer(minLength: 20)
                    Text("本應用程式為第三方開發，非教育部官方 App。\n資料庫整理與格式轉換僅為提供離線查詢，未任意改作教育部辭典原始內容。")
                        .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("關於本程式")
            .navigationBarItems(trailing: Button("關閉") { presentationMode.wrappedValue.dismiss() })
        }
    }
}

// ==========================================
// MARK: - 8. 鍵盤與廣告元件
// ==========================================

struct ExpandedCandidatePanel: View {
    let candidates: [String]
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void
    // iPad 增加候選字大小
    let gridColumns = [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 100 : 50), spacing: 14)]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea().onTapGesture { withAnimation { isPresented = false } }
            VStack(spacing: 0) {
                HStack {
                    Text("請選擇國字").font(.headline).foregroundColor(.primary)
                    Spacer()
                    Button(action: { withAnimation { isPresented = false } }) {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray)
                    }
                }
                .padding().background(Color(.secondarySystemGroupedBackground))
                Divider()
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(candidates, id: \.self) { char in
                            Button(action: { onSelect(char) }) {
                                Text(char)
                                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 28, weight: .regular, design: .default))
                                    .foregroundColor(.primary)
                                    .frame(minWidth: UIDevice.current.userInterfaceIdiom == .pad ? 90 : 60, minHeight: UIDevice.current.userInterfaceIdiom == .pad ? 90 : 60)
                                    .background(Color.blue.opacity(0.05))
                                    .cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.1), lineWidth: 1))
                            }
                        }
                    }
                    .padding().padding(.bottom, 20)
                }
                .frame(maxHeight: UIDevice.current.userInterfaceIdiom == .pad ? 500 : 320)
            }
            .background(Color(.systemBackground)).cornerRadius(16, corners: [.topLeft, .topRight])
            .shadow(radius: 10).padding(.horizontal, 10).padding(.bottom, 10).frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct ZhuyinKeyboardView: View {
    @Binding var text: String
    var compact = false
    var expandsFooter = true
    var showsBanner = false
    @Binding var adLoaded: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var showExpandedCandidates = false
    @State private var candidates: [String] = []
    
    // 判斷裝置
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    
    var gridBopomofo: [String] { BopomofoData.initials + BopomofoData.medials + BopomofoData.finals }
    
    struct ToneItem { let symbol: String; let name: String }
    let toneItems = [
        ToneItem(symbol: "ˉ", name: "一聲"), ToneItem(symbol: "ˊ", name: "二聲"),
        ToneItem(symbol: "ˇ", name: "三聲"), ToneItem(symbol: "ˋ", name: "四聲"),
        ToneItem(symbol: "˙", name: "輕聲")
    ]
    
    // [iPad 優化]: 稍微放寬間距
    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: compact ? 30 : (isPad ? 64 : 36)), spacing: compact ? 4 : (isPad ? 8 : 5))]
    }

    private var keyHeight: CGFloat { compact ? 30 : (isPad ? 46 : 40) }
    private var candidateHeight: CGFloat { compact ? 34 : 44 }
    private var zhuyinSize: CGFloat { compact ? 16 : (isPad ? 26 : 20) }
    
    var body: some View {
        ZStack {
            VStack(spacing: compact ? 2 : (isPad ? 8 : 4)) { // [iPad 優化]: 調整垂直間距
                
                // 1. 候選字與拼音顯示列
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(AppTheme.cardBackground)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    
                    if candidates.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.and.outline").foregroundColor(.orange).font(.title3)
                            if text.isEmpty || !BopomofoData.isBopomofo(text.last ?? " ") {
                                Text("點擊下方按鍵拼音...").font(.system(size: 16, weight: .medium)).foregroundColor(.gray)
                            } else {
                                Text("找不到這個拼音喔！").font(.system(size: 16, weight: .medium)).foregroundColor(.red.opacity(0.6))
                            }
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(candidates.prefix(15), id: \.self) { char in
                                    Button(action: { selectChar(char) }) {
                                        Text(char)
                                            // 候選字使用系統中文字體，避免教育部楷體缺字造成 fallback 或字形不一致。
                                            .font(.system(size: compact ? 20 : (isPad ? 28 : 24), weight: .regular, design: .default))
                                            .foregroundColor(.primary)
                                            .frame(width: compact ? 40 : 50, height: candidateHeight)
                                            .background(Color.blue.opacity(0.1)).cornerRadius(10)
                                    }
                                }
                                if candidates.count > 15 {
                                    Button(action: {
                                        withAnimation(.spring()) { showExpandedCandidates = true }
                                        ZhuyinKeyHaptics.shared.more()
                                    }) {
                                        VStack(spacing: 2) {
                                            Image(systemName: "chevron.down.circle.fill").font(.title2)
                                            Text("更多").font(.caption2).fontWeight(.bold)
                                        }
                                        .foregroundColor(.white).frame(width: compact ? 40 : 50, height: candidateHeight).background(Color.orange).cornerRadius(10)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .frame(height: compact ? 42 : (isPad ? 56 : 50)) // [iPad 優化]: 候選字列增高
                .padding(.horizontal, 8)
                .padding(.top, compact ? 6 : 12)
                
                // 2. 聲調列
                HStack(spacing: 6) {
                    ForEach(toneItems, id: \.symbol) { item in
                        Button(action: {
                            if item.symbol != "ˉ" { text += item.symbol }
                            ZhuyinKeyHaptics.shared.tone()
                        }) {
                            VStack(spacing: -4) {
                                Text(item.symbol)
                                    .font(AppTheme.zhuyinFont(size: zhuyinSize, weight: .semibold))
                                    .baselineOffset(-zhuyinSize * 0.28)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .frame(height: zhuyinSize)
                                Text(item.name)
                                    .font(.system(size: compact ? 9 : (isPad ? 11 : 10), weight: .regular))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .foregroundColor(.purple)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .frame(height: keyHeight)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.purple.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: {
                        ZhuyinKeyHaptics.shared.delete(hasCharacter: !text.isEmpty)
                        if !text.isEmpty { text.removeLast() }
                    }) {
                        Image(systemName: "delete.left.fill").font(.system(size: compact ? 16 : (isPad ? 26 : 20))).foregroundColor(.white)
                            .frame(width: compact ? 44 : (isPad ? 60 : 54), height: keyHeight)
                            .background(Color.gray.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)

                // 3. 注音鍵盤區
                LazyVGrid(columns: columns, spacing: compact ? 3 : (isPad ? 8 : 6)) { // [iPad 優化]: 間距
                    ForEach(gridBopomofo, id: \.self) { char in
                        Button(action: {
                            ZhuyinKeyHaptics.shared.bopomofo(char)
                            text += char
                        }) {
                            Text(char).font(AppTheme.zhuyinFont(size: compact ? 16 : (isPad ? 26 : 20))).foregroundColor(getTextColor(for: char))
                                .frame(minWidth: compact ? 28 : (isPad ? 48 : 32), minHeight: keyHeight).frame(maxWidth: .infinity)
                                .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white).cornerRadius(6)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.1), radius: 1, x: 0, y: 1)
                        }
                    }
                }
                .padding(.horizontal, isPad ? 16 : 8)
                .padding(.bottom, 0)

                if expandsFooter {
                    Spacer(minLength: 0)
                }

                if showsBanner {
                    AdBannerView(isLoaded: $adLoaded)
                        .frame(minHeight: 50, idealHeight: 50, maxHeight: 50)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .padding(.bottom, 6)
                }
                
                // 4. 隱私權與 EULA (避免被 Home Indicator 遮擋)
                HStack(spacing: 16) {
                    Link("隱私權政策", destination: URL(string: "https://eric1207cvb.github.io/Mandarin-Training/")!)
                    Text("|").foregroundColor(.gray.opacity(0.5))
                    Link("使用者授權合約 (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.caption2)
                .foregroundColor(.gray)
                // [Version Update]: iPad 底部增加 Padding 至 40
                .padding(.bottom, compact ? 4 : (isPad ? 40 : 20))
                .layoutPriority(1)
            }
            
            if showExpandedCandidates {
                ExpandedCandidatePanel(candidates: candidates, isPresented: $showExpandedCandidates, onSelect: selectChar)
                    .transition(.move(edge: .bottom).combined(with: .opacity)).zIndex(100)
            }
        }
        .background(Color(UIColor.systemGray6).ignoresSafeArea(edges: .bottom))
        .onChange(of: text) { _, _ in updateCandidates() }
        .onAppear {
            updateCandidates()
            ZhuyinKeyHaptics.shared.prepare()
        }
    }
    
    // (Helper functions)
    private func updateCandidates() {
        let new = ZhuyinIME.shared.getCandidates(for: text)
        candidates = new
        if new.isEmpty { showExpandedCandidates = false }
    }
    private func selectChar(_ char: String) {
        while let last = text.last, BopomofoData.isBopomofo(last) { text.removeLast() }
        text += char
        showExpandedCandidates = false
        ZhuyinKeyHaptics.shared.confirm()
    }
    private func getTextColor(for char: String) -> Color {
        if BopomofoData.initials.contains(char) { return .primary }
        if BopomofoData.medials.contains(char) { return Color.green }
        if BopomofoData.finals.contains(char) { return Color.orange }
        return .primary
    }
}

/// 注音鍵盤的震動。產生器先 prepare，手指按下當下就回饋，避免每按一次才建立而漏震。
private final class ZhuyinKeyHaptics {
    static let shared = ZhuyinKeyHaptics()

    private let initial = UIImpactFeedbackGenerator(style: .light)
    private let medial = UIImpactFeedbackGenerator(style: .soft)
    private let final = UIImpactFeedbackGenerator(style: .rigid)
    private let toneMark = UIImpactFeedbackGenerator(style: .rigid)
    private let remove = UIImpactFeedbackGenerator(style: .medium)
    private let chosen = UIImpactFeedbackGenerator(style: .medium)

    func prepare() {
        initial.prepare()
        medial.prepare()
        final.prepare()
        toneMark.prepare()
        remove.prepare()
        chosen.prepare()
    }

    func bopomofo(_ char: String) {
        if BopomofoData.medials.contains(char) {
            medial.impactOccurred(intensity: 0.75)
            medial.prepare()
        } else if BopomofoData.finals.contains(char) {
            final.impactOccurred(intensity: 0.7)
            final.prepare()
        } else {
            initial.impactOccurred(intensity: 0.55)
            initial.prepare()
        }
    }

    func tone() {
        toneMark.impactOccurred(intensity: 1)
        toneMark.prepare()
    }

    func delete(hasCharacter: Bool) {
        remove.impactOccurred(intensity: hasCharacter ? 0.9 : 0.25)
        remove.prepare()
    }

    func confirm() {
        chosen.impactOccurred(intensity: 1)
        chosen.prepare()
    }

    func more() {
        initial.impactOccurred(intensity: 0.4)
        initial.prepare()
    }
}

struct AdBannerView: UIViewRepresentable {
    @Binding var isLoaded: Bool

    /// 開發階段用 Google 官方測試廣告，避免正式廣告單元被模擬器流量判定為無效點擊。
    private static var adUnitID: String {
        #if DEBUG
        "ca-app-pub-3940256099942544/6300978111"
        #else
        "ca-app-pub-8563333250584395/7537107959"
        #endif
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoaded: $isLoaded)
    }

    func makeUIView(context: Context) -> BannerContainer {
        let adSize = UIDevice.current.userInterfaceIdiom == .pad ? AdSizeLeaderboard : AdSizeBanner
        let container = BannerContainer(adSize: adSize, adUnitID: Self.adUnitID)
        container.banner.delegate = context.coordinator
        return container
    }

    func updateUIView(_ uiView: BannerContainer, context: Context) {
        uiView.banner.delegate = context.coordinator
        uiView.loadIfNeeded()
    }

    /// 不使用廣告識別碼，只請求非個人化廣告。
    fileprivate static func nonPersonalizedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var isLoaded: Bool

        init(isLoaded: Binding<Bool>) {
            _isLoaded = isLoaded
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            DispatchQueue.main.async { self.isLoaded = true }
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("⚠️ AdMob 橫幅載入失敗: \(error.localizedDescription)")
            DispatchQueue.main.async { self.isLoaded = false }
        }
    }
}

/// 廣告要等進到目前這面螢幕的視窗再載入。折疊換到封面時，不能沿用內頁那個視窗。
final class BannerContainer: UIView {
    let banner: BannerView
    private let adUnitID: String
    private var loadedWindow: UIWindow?

    init(adSize: AdSize, adUnitID: String) {
        self.adUnitID = adUnitID
        banner = BannerView(adSize: adSize)
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .clear
        banner.clipsToBounds = true
        banner.backgroundColor = .clear
        banner.adUnitID = adUnitID
        addSubview(banner)
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        loadIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = banner.adSize.size
        banner.frame = CGRect(
            x: max(0, (bounds.width - size.width) / 2),
            y: max(0, (bounds.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
        loadIfNeeded()
    }

    func loadIfNeeded() {
        guard let window, bounds.width > 1 else { return }
        guard let root = window.rootViewController else { return }
        let windowChanged = loadedWindow !== window
        if banner.rootViewController !== root {
            banner.rootViewController = root
        }
        guard windowChanged else { return }
        loadedWindow = window
        banner.load(AdBannerView.nonPersonalizedRequest())
    }
}
