# Pattern 06: Entitlement Check

**Use when:** You have multiple tiers or a set of features that map to different subscription levels. The entitlement check is the foundation every other pattern builds on — do it right and the rest follows.

**Conversion style:** Gate features by entitlement (not by price, not by product)

**Examples:** Any app with Free / Pro / Team tiers; feature-based gating ("export is Pro only"); agent apps with tool access tiers.

---

## The Mental Model

RC's entitlement system decouples *what a user can do* (entitlement) from *how they're paying* (product). This matters because:

- A user might subscribe monthly or annually — same entitlement, different product
- A user might be grandfathered — same entitlement, discontinued product
- You might A/B test different price points — same entitlement, different offering

**Check entitlements, never products.** If you gate on product IDs, you'll break every time you change pricing.

---

## Setup (Single Tier)

```
Entitlement: pro
  └── Products: pro_monthly, pro_annual, pro_lifetime

Gate features by: info.entitlements["pro"]?.isActive
```

## Setup (Multiple Tiers)

```
Entitlements:
  - basic    → products: basic_monthly, basic_annual
  - pro      → products: pro_monthly, pro_annual, pro_lifetime
  - team     → products: team_monthly, team_annual

Feature matrix:
  Feature               Free    Basic   Pro     Team
  Core functionality     ✓       ✓       ✓       ✓
  Export                         ✓       ✓       ✓
  Advanced tools                         ✓       ✓
  Team collaboration                             ✓
  API access                             ✓       ✓
```

---

## Implementation (Swift/iOS)

### Basic Entitlement Check

```swift
// The fundamental check — use this everywhere
func hasEntitlement(_ key: String) async -> Bool {
    let info = try? await Purchases.shared.customerInfo()
    return info?.entitlements[key]?.isActive == true
}

// Feature gate
func canExport() async -> Bool {
    return await hasEntitlement("basic") || await hasEntitlement("pro") || await hasEntitlement("team")
}

// Or, if your tiers are strictly hierarchical:
func highestTier() async -> Tier {
    let info = try? await Purchases.shared.customerInfo()
    let entitlements = info?.entitlements
    
    if entitlements?["team"]?.isActive == true { return .team }
    if entitlements?["pro"]?.isActive == true { return .pro }
    if entitlements?["basic"]?.isActive == true { return .basic }
    return .free
}

enum Tier: Comparable {
    case free, basic, pro, team
}
```

### Single Check, Cached

Making an async call every time you gate a feature is slow. Cache `customerInfo` and invalidate on purchase:

```swift
actor EntitlementCache {
    private var info: CustomerInfo?
    private var lastFetched: Date?
    private let ttl: TimeInterval = 60 * 5  // 5 minutes
    
    func customerInfo() async -> CustomerInfo? {
        if let info, let fetched = lastFetched, Date().timeIntervalSince(fetched) < ttl {
            return info
        }
        let fresh = try? await Purchases.shared.customerInfo()
        self.info = fresh
        self.lastFetched = Date()
        return fresh
    }
    
    func invalidate() {
        info = nil
        lastFetched = nil
    }
}

let entitlementCache = EntitlementCache()

// On purchase completion:
func onPurchaseComplete() async {
    await entitlementCache.invalidate()
    Purchases.shared.invalidateCustomerInfoCache()
}
```

### Listener Pattern (React to Changes)

```swift
// PurchasesDelegate — called when entitlements change
class AppDelegate: NSObject, PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        // Update UI everywhere that depends on entitlements
        NotificationCenter.default.post(
            name: .entitlementsUpdated,
            object: nil,
            userInfo: ["customerInfo": customerInfo]
        )
    }
}

// In your views:
.onReceive(NotificationCenter.default.publisher(for: .entitlementsUpdated)) { notification in
    if let info = notification.userInfo?["customerInfo"] as? CustomerInfo {
        isPro = info.entitlements["pro"]?.isActive == true
    }
}
```

---

## Server-Side Entitlement Check

For features that live on your backend (API access, data processing), check entitlements server-side via RC REST API. Don't trust the client.

```python
import httpx

RC_SECRET_KEY = os.getenv("RC_SECRET_KEY")
RC_PROJECT_ID = os.getenv("RC_PROJECT_ID")

async def has_entitlement(app_user_id: str, entitlement_key: str) -> bool:
    """Check entitlement via RC REST API. Use this for server-enforced gates."""
    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"https://api.revenuecat.com/v2/projects/{RC_PROJECT_ID}/customers/{app_user_id}",
            headers={"Authorization": f"Bearer {RC_SECRET_KEY}"},
            params={"expand": "subscriber"}
        )
        
        if response.status_code != 200:
            # RC unreachable — fail safe (deny) or fail open based on your risk model
            return False
        
        data = response.json()
        entitlements = data.get("subscriber", {}).get("entitlements", {})
        entitlement = entitlements.get(entitlement_key, {})
        
        # Check isActive equivalent: expires_date in the future (or null for lifetime)
        expires_date = entitlement.get("expires_date")
        if expires_date is None and entitlement:
            return True  # Lifetime / non-expiring
        
        from datetime import datetime, timezone
        if expires_date:
            expiry = datetime.fromisoformat(expires_date.replace("Z", "+00:00"))
            return expiry > datetime.now(timezone.utc)
        
        return False


# Usage in FastAPI
@app.get("/api/export")
async def export_data(user_id: str = Depends(get_current_user)):
    if not await has_entitlement(user_id, "pro"):
        raise HTTPException(status_code=403, detail="Pro subscription required")
    return await perform_export(user_id)
```

---

## Entitlement Expiry Edge Cases

```swift
// isActive already handles these — but know what it's doing:
let entitlement = info.entitlements["pro"]

entitlement?.isActive          // true if: not expired AND store-validated
entitlement?.expirationDate    // nil for lifetime purchases
entitlement?.periodType        // .normal, .trial, .intro
entitlement?.willRenew         // false if user has canceled (but still active until expiry)
entitlement?.unsubscribeDetectedAt  // when cancellation was detected

// Pattern: show "renewal warning" if willRenew == false but still active
if entitlement?.isActive == true && entitlement?.willRenew == false {
    showRenewalWarning(expiresAt: entitlement?.expirationDate)
}
```

---

## What Makes It Work

- **One source of truth.** Always check RC, never maintain your own "is_premium" flag in your database that could drift from RC's state.
- **Gate on entitlements, not products.** The product ID is an implementation detail. The entitlement is the contract.
- **Handle the RC-unreachable case.** Network calls fail. Decide per-feature: fail open (grant access) or fail closed (deny access). Safety-critical features should fail closed. UX features can fail open.
- **Sync check with UI state.** Use the delegate pattern or `customerInfoStream` to keep UI in sync when purchases happen (including restoration, renewals, and cross-device sync).

## Failure Modes

- **Gating on product ID.** When you rename a product or add a new one, gates break for existing subscribers. Don't do it.
- **Not handling `willRenew == false`.** A user who canceled is still `isActive == true` until expiry. If you only check `isActive`, you'll miss the window to re-engage them before they lapse.
- **Server not checking, trusting client.** The client can lie. If a feature has real value (API access, data export, team features), verify server-side.
- **Caching too aggressively.** A 5-minute TTL is usually fine. A 24-hour TTL means users who let their subscription lapse still get access all day. Tune TTL based on your risk tolerance.

---

## RC Notes

- `customerInfo.entitlements` is a dictionary keyed by entitlement `lookup_key` (not display name).
- `isActive` is the safe check — it accounts for expiry, store validation, and grace periods.
- Multiple products can map to the same entitlement. Adding a new pricing tier? Just add the product to the entitlement, no code changes needed.
- `Purchases.shared.invalidateCustomerInfoCache()` forces a fresh fetch on next access. Call after restoring purchases.
- For agents: check entitlements via REST API using the customer's `app_user_id`. Don't build separate access control systems — let RC be the authority.
