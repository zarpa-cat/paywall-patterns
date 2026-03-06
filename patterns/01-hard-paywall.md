# Pattern 01: Hard Paywall

**Use when:** The core functionality *is* the product. There's no meaningful "lite" version. Users who arrive know what they're getting.

**Conversion style:** Block → Subscribe

**Examples:** Pro tools, niche utilities, productivity apps where the first launch IS the value proposition.

---

## The Setup

One entitlement. One (or two) offerings. No free tier.

```
Entitlement: pro
  └── Products: monthly ($4.99), annual ($39.99)

Offering: default [is_current: true]
  └── Packages: $rc_monthly, $rc_annual
```

Via RC REST API:
```bash
# Create entitlement
POST /v2/projects/{project_id}/entitlements
{ "lookup_key": "pro", "display_name": "Pro" }

# Attach products
POST /v2/projects/{project_id}/entitlements/{entitlement_id}/actions/attach_products
{ "product_ids": ["prod_monthly_id", "prod_annual_id"] }
```

---

## Implementation (Swift/iOS)

```swift
// On app launch, check entitlement
func checkAccess() async {
    let customerInfo = try? await Purchases.shared.customerInfo()
    let hasAccess = customerInfo?.entitlements["pro"]?.isActive == true
    
    if !hasAccess {
        showPaywall()
    }
}

// Show RevenueCat paywall
func showPaywall() {
    Task {
        guard let offering = try? await Purchases.shared.offerings().current else { return }
        await MainActor.run {
            let controller = PaywallViewController(offering: offering)
            present(controller, animated: true)
        }
    }
}
```

---

## What Makes It Work

- **Speed.** User opens app, hits paywall immediately. Every second of friction is a lost conversion. Pre-fetch `customerInfo` on launch, not on paywall trigger.
- **Annual anchor.** Show monthly and annual. Annual should be visibly discounted. Users often pick annual when you surface the per-month math.
- **No free trial on hard paywalls** (usually). If you're using a hard paywall, the product is the value — users should see that *before* they sign up. Consider a "try free for 7 days" only if your activation takes >1 session.

## Failure Modes

- **Too early in the flow.** If you gate before the user understands what they're paying for, you lose them to confusion, not indecision. Even on a hard paywall, a 15-second onboarding that shows what the product does converts better than cold-gating.
- **Not handling `customerInfo` errors.** If RC is unreachable, don't lock the user out. Cache the last known state and fail open (or show a graceful error, not a blank screen).

```swift
// Fail-open pattern
func hasProAccess() async -> Bool {
    do {
        let info = try await Purchases.shared.customerInfo()
        return info.entitlements["pro"]?.isActive == true
    } catch {
        // RC unreachable — use cached value or fail open
        return cachedAccessState ?? false
    }
}
```

---

## RC Notes

- `is_current: true` on the offering means RC's `current` offering returns this one. Keep it simple: one current offering unless you're running experiments.
- Entitlement `isActive` checks both expiry AND store validation. It's the right check — don't roll your own.
- If you support multiple platforms: use the same entitlement key across platforms. RC handles the product ID mapping per-platform.
