import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Binding var isPresented: Bool
    @State private var offering: Offering?
    @State private var didLoad = false
    @State private var isPurchasing = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "book.closed.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .foregroundStyle(.blue)
                        .padding(.top, 24)

                    Text("開啟無干擾的學習模式")
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("移除底部廣告，專注查詢字詞。\n一次付費，永久有效。")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        FeatureRow(text: "移除底部橫幅廣告")
                        FeatureRow(text: "一次付費，不用每月訂閱")
                        FeatureRow(text: "換手機後可恢復購買")
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)

                    if let package = offering?.availablePackages.first {
                        Button(action: { purchase(package) }) {
                            VStack(spacing: 4) {
                                Text("永久移除廣告")
                                    .font(.headline)
                                    .bold()
                                Text(package.storeProduct.localizedPriceString + " / 永久買斷")
                                    .font(.caption)
                                    .opacity(0.9)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                        }
                        .disabled(isPurchasing)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    } else if didLoad {
                        Text("尚未讀到商品。請確認 RevenueCat 的 Current 方案包含 remove_ads_once，且 App Store Connect 商品資料已完成。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        ProgressView("正在載入商品...")
                            .font(.caption)
                    }

                    Button("恢復購買") { restorePurchases() }
                        .font(.footnote)
                        .disabled(isPurchasing)
                        .padding(.top, 4)

                    VStack(spacing: 6) {
                        Text("此為一次性購買。退款請聯繫 Apple 支援。")
                        HStack(spacing: 12) {
                            Link("隱私權政策", destination: URL(string: "https://eric1207cvb.github.io/Mandarin-Training/")!)
                            Text("|").foregroundStyle(.tertiary)
                            Link("使用條款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding()
                }
            }
            .navigationTitle("移除廣告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { isPresented = false }
                }
            }
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
            .alert("提示", isPresented: $showAlert) {
                Button("好", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onAppear(perform: loadOffering)
        }
    }

    private func FeatureRow(text: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
            Spacer()
        }
    }

    private func loadOffering() {
        Purchases.shared.getOfferings { offerings, _ in
            DispatchQueue.main.async {
                self.offering = offerings?.current
                self.didLoad = true
            }
        }
    }

    private func purchase(_ package: Package) {
        isPurchasing = true
        Purchases.shared.purchase(package: package) { _, customerInfo, error, userCancelled in
            DispatchQueue.main.async {
                self.isPurchasing = false
                if let error, !userCancelled {
                    self.alertMessage = "購買發生錯誤：\(error.localizedDescription)"
                    self.showAlert = true
                } else if customerInfo?.entitlements["premium"]?.isActive == true {
                    PurchaseManager.shared.isPremium = true
                    self.isPresented = false
                }
            }
        }
    }

    private func restorePurchases() {
        isPurchasing = true
        Purchases.shared.restorePurchases { customerInfo, _ in
            DispatchQueue.main.async {
                self.isPurchasing = false
                if customerInfo?.entitlements["premium"]?.isActive == true {
                    PurchaseManager.shared.isPremium = true
                    self.isPresented = false
                } else {
                    self.alertMessage = "查無此帳號的購買紀錄。"
                    self.showAlert = true
                }
            }
        }
    }
}
