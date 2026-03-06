# Pattern 03: Freemium Gate

**Use when:** You need broad top-of-funnel adoption. The free tier is real and useful; it's not a crippled demo. Users hit limits naturally as they get more value from the product.

**Conversion style:** Use → Hit limit → Subscribe

**Examples:** Note-taking apps (5 notes free), project tools (3 projects free), cloud storage (5GB free), any app where the core loop is repeatable.

---

## The Setup

Free tier is enforced by your app logic, not by RC entitlements. RC only manages the premium layer.

```
Entitlement: premium
  └── Products: monthly ($3.99), annual ($29.99)

Offering: default [is_current: true]
  └── Packages: $rc_monthly, $rc_annual

Free tier limits (enforced in-app, not by RC):
  - 5 items maximum
  - No export
  - No sync across devices
```

The free tier requires **no RC integration** — it's just your app's default behavior. RC enters the picture when a user hits a limit and you want to offer a way through.

---

## Implementation (Swift/iOS)

```swift
// App-level limit enforcement
struct FreemiumLimits {
    static let maxFreeItems = 5
    static let syncEnabled = false
    static let exportEnabled = false
}

// Check before creating a new item
func createItem(_ item: Item) async {
    let isPremium = await checkPremium()
    let currentCount = await fetchItemCount()
    
    if !isPremium && currentCount >= FreemiumLimits.maxFreeItems {
        showUpgradePrompt(reason: .itemLimit(current: currentCount, max: FreemiumLimits.maxFreeItems))
        return
    }
    
    await saveItem(item)
}

// RC entitlement check
func checkPremium() async -> Bool {
    let info = try? await Purchases.shared.customerInfo()
    return info?.entitlements["premium"]?.isActive == true
}

// Context-aware upgrade prompt
func showUpgradePrompt(reason: UpgradeReason) {
    Task {
        guard let offering = try? await Purchases.shared.offerings().current else { return }
        
        await MainActor.run {
            let message: String
            switch reason {
            case .itemLimit(let current, let max):
                message = "You've created \(current) of \(max) free items. Upgrade for unlimited."
            case .exportBlocked:
                message = "Export is a premium feature. Upgrade to unlock it."
            case .syncBlocked:
                message = "Sync across devices is a premium feature."
            }
            
            let vc = FreemiumUpgradeViewController(offering: offering, contextMessage: message)
            present(vc, animated: true)
        }
    }
}
```

---

## The Limit Design Problem

The free tier limits are your most important product decision. Too restrictive and users churn before they understand the product. Too generous and they never convert.

**Good limit signals:**

| Signal | What it means |
|--------|---------------|
| User hits 80% of limit | Show a warning ("1 item remaining") — don't wait for the wall |
| User hits the limit | This is your best conversion moment — show paywall immediately |
| User has used the product 5+ times | They understand it; limits are now frustration, not protection |
| User hasn't hit a limit after 30 days | They're a casual user; a different pitch might work better |

**Pre-warn before the wall:**

```swift
func checkAndWarnIfNearLimit() async {
    guard !(await checkPremium()) else { return }
    
    let count = await fetchItemCount()
    let limit = FreemiumLimits.maxFreeItems
    let remaining = limit - count
    
    if remaining == 1 {
        showBanner("1 \(itemName) remaining on your free plan.")
    } else if remaining == 0 {
        // They're at the wall — next create will trigger upgrade
        // Optionally show a proactive upgrade offer now
    }
}
```

---

## What Makes It Work

- **The limit must feel fair.** Five notes is enough to understand the product. Three notes is not. Test with real users.
- **Free tier should be genuinely useful**, not intentionally broken. Users who feel the free tier respects them convert at higher rates and have better LTV. Users who feel tricked churn and leave bad reviews.
- **Upgrade prompt must appear at the right moment.** The instant a user hits a limit is high motivation. Don't defer to "next time you open the app." Now is the moment.
- **Remember what they were trying to do.** After upgrade, complete the action automatically. Don't make them repeat the triggering action — that's friction right after a purchase.

```swift
// After successful purchase, complete the deferred action
func onPurchaseComplete(deferredAction: DeferredAction) async {
    switch deferredAction {
    case .createItem(let item):
        await saveItem(item)  // Complete what triggered the upgrade
        showSuccessToast("Item created! Welcome to premium.")
    case .export(let items):
        await exportItems(items)
    }
}
```

---

## Failure Modes

- **Inconsistent limit enforcement.** If limit is 5 but a sync bug lets users create 7, the paywall feels arbitrary when they finally hit it. Enforce limits server-side if items sync.
- **Losing the item they were trying to create.** If a user fills in a form, hits submit, gets paywalled, cancels the paywall, and their form is blank — that's a conversion killer. Save the in-progress item, complete it post-upgrade.
- **Not distinguishing old free users from new ones.** If you add a freemium tier after launch, grandfathered users who have 50 items shouldn't hit the 5-item limit retroactively. Give them a grace period or grandfather status.

---

## RC Notes

- The free tier doesn't need any RC configuration. RC only manages the premium entitlement.
- `customerInfo` is fast (cached locally). Check it in-line, not just at launch.
- For server-enforced limits (items synced to your backend): check entitlement server-side via the RC REST API — don't trust the client to self-report.
- Consider using RC's `Offering` metadata to store free tier limits: `{"max_items": 5}`. Change limits without an app update.
