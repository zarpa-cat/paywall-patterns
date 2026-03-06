# Pattern 05: Credits / Hybrid Monetization

**Use when:** Usage varies widely across your user base. Power users would pay for unlimited; casual users want occasional access without a recurring commitment.

**Conversion style:** Pay-per-use (credits) with subscription option for power users.

**Examples:** AI tools, image generators, API-heavy apps, anything with variable consumption.

---

## The Setup

Two monetization layers:
1. **Virtual currency** (credits) — consumable, purchased in packs or granted via subscription
2. **Subscription** — grants a monthly credit allowance automatically

```
Virtual Currency: CRED (Credits)
  Products:
    - credits_100  → 100 credits (one-time, $1.99)
    - credits_500  → 500 credits (one-time, $7.99)
    - premium_monthly → subscription ($5.99/mo) + 100 credits/cycle
    - premium_annual  → subscription ($48/yr)  + 1200 credits/year
```

Via RC REST API (virtual currency setup):
```bash
# Create virtual currency
POST /v2/projects/{project_id}/virtual_currencies
{
  "name": "Credits",
  "code": "CRED",
  "description": "1 credit = 1 AI generation"
}

# Grant credits via subscription product
POST /v2/projects/{project_id}/virtual_currencies/{vc_id}/product_grants
{
  "product_ids": ["prod_premium_monthly_id"],
  "amount": 100,
  "expire_at_cycle_end": true
}
```

> **Note:** `expire_at_cycle_end` and `trial_amount` are not documented in the main reference but are accepted and functional. `expire_at_cycle_end: true` means credits reset each billing cycle rather than accumulating indefinitely.

---

## Implementation (Swift/iOS)

```swift
// Check credits before performing an action
func generateImage(prompt: String) async {
    let info = try? await Purchases.shared.customerInfo()
    
    // Check subscription entitlement first (might grant credits automatically)
    if info?.entitlements["premium"]?.isActive == true {
        // Subscriber — credits managed server-side via RC
        await performGeneration(prompt: prompt)
        return
    }
    
    // Non-subscriber: check credit balance via your backend
    let credits = await fetchCreditBalance(userId: info?.originalAppUserId)
    guard credits > 0 else {
        showUpsell(reason: .outOfCredits)
        return
    }
    
    await performGeneration(prompt: prompt)
    await deductCredit(userId: info?.originalAppUserId)
}

// Show context-appropriate upsell
func showUpsell(reason: UpsellReason) {
    switch reason {
    case .outOfCredits:
        // Show both credit packs AND subscription — let user decide
        showPaywall(highlight: .creditsAndSubscription)
    case .firstTime:
        // Show subscription prominently, credits as fallback
        showPaywall(highlight: .subscriptionFirst)
    }
}
```

---

## Credit Balance: Client vs. Server

RC's virtual currency tracks the balance server-side. You can't read credit balance directly from `customerInfo` in the SDK (as of March 2026) — you need to query your backend or RC's REST API.

```swift
// Fetch balance via RC REST API (from your backend, not client-side — token stays server-side)
// GET /v2/projects/{project_id}/customers/{app_user_id}/virtual_currencies
// Response: { "balances": [{ "code": "CRED", "balance": 47 }] }
```

Design implication: **your backend needs to mediate credit checks**. Don't put your RC secret key in the client.

---

## What Makes It Work

- **Low barrier to first use.** Give new users some free credits on signup. Let them experience the value loop before asking for money. The subscription pitch lands better after they've used 10 credits.
- **Show the math.** "500 credits ($7.99) or subscribe for 100/month ($5.99)." Power users will do this math and subscribe. Casual users will buy credits. Both are right for their use case.
- **Subscription = power user signal.** If a user subscribes, they're your highest-value cohort. Treat them accordingly — give them more credits than the strict subscription math, early access, etc.

## The Pricing Trap

Don't price credits so that subscribing is always obviously better. If 100 credits ($1.99) is clearly worse than $5.99/mo subscription at any volume, casual users feel cheated and power users feel insulted. Leave room for the casual user to be right.

---

## Failure Modes

- **Credit balance out of sync.** If your backend and RC disagree on balance, users hit confusing states. Use RC as the source of truth and treat your local cache as optimistic.
- **Ignoring `expire_at_cycle_end`** on subscription grants. If credits accumulate indefinitely, heavy subscribers build a balance that makes them churn-resistant in a bad way — they leave but still have credits, so they don't feel the loss. Reset monthly.
- **Missing the zero-credit moment.** When a user runs out of credits, they're at peak motivation to buy. Don't show a generic "purchase" screen — show exactly what they're missing and what they'll get. This is your best conversion moment.

---

## RC Notes

- RC virtual currencies are separate from consumable products. A consumable product in the App Store (one-time purchase) can *grant* credits, but the credit balance lives in RC's system, not in `SKPaymentTransaction`.
- `update` on virtual currencies is POST not PATCH — this tripped me up.
- The `product_grants` endpoint accepts `product_ids` (array), not `product_id` (singular). Another gotcha.
- Charts/metrics for virtual currencies are rate-limited at 5 req/min. Cache aggressively if you're building dashboards.
