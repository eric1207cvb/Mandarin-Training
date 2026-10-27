import Foundation
import RevenueCat
import Combine // [新增] 必須加入這行，否則 @Published 會報錯

class PurchaseManager: NSObject, ObservableObject {
    static let shared = PurchaseManager()
    
    // 這就是控制「是否顯示廣告」的開關
    @Published var isPremium = false
    @Published private(set) var removeAdsPrice: String?
    
    override init() {
        super.init()
        // 付費狀態有變動時（含其他裝置恢復購買）同步是否顯示廣告。
        Purchases.shared.delegate = self
        checkSubscriptionStatus()
        loadRemoveAdsPrice()
    }
    
    // 檢查使用者是否已經付費
    func checkSubscriptionStatus() {
        Purchases.shared.getCustomerInfo { customerInfo, _ in
            self.applyPremiumStatus(customerInfo)
        }
    }
    
    // 購買功能
    func purchase(package: Package) {
        Purchases.shared.purchase(package: package) { _, customerInfo, _, _ in
            self.applyPremiumStatus(customerInfo)
        }
    }
    
    // 恢復購買 (Restore) - Apple 規定一定要有這個按鈕
    func restorePurchases() {
        Purchases.shared.restorePurchases { customerInfo, _ in
            self.applyPremiumStatus(customerInfo)
        }
    }

    private func loadRemoveAdsPrice() {
        Purchases.shared.getOfferings { offerings, _ in
            let price = offerings?.current?.availablePackages.first?.storeProduct.localizedPriceString
            DispatchQueue.main.async {
                self.removeAdsPrice = price
            }
        }
    }

    /// 有拿到顧客資料才更新。網路失敗時維持原狀態，避免誤把已購買使用者當成未購買。
    private func applyPremiumStatus(_ customerInfo: CustomerInfo?) {
        guard let customerInfo else { return }
        let active = customerInfo.entitlements["premium"]?.isActive == true
        DispatchQueue.main.async {
            self.isPremium = active
        }
    }
}

extension PurchaseManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        applyPremiumStatus(customerInfo)
    }
}
