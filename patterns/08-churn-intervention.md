# Pattern 08: Churn Intervention

**Use when:** A user is canceling, has canceled, or is in a billing grace period. This is your last shot before they're gone.

**Conversion style:** Cancel intent → Win-back offer

**Examples:** Any subscription app. Churn intervention is highest-ROI paywall work because these users already know your product.

---

## The Subscription States That Matter

RC's `CustomerInfo` tracks subscription status with 8 possible states. Three are churn intervention windows:

```
active          — Subscribed and current. No action needed.
trial           — In trial. Nurture, don't interrupt.
intro_pricing   — In intro period. Same as trial.

grace_period    — ⚠️ Payment failed, store gave a grace period (1-16 days).
                   User thinks they're still subscribed. They're not paying.
                   Intervention: soft notification, not a hard gate.

billing_retry   — ⚠️ Grace period ended. RC is retrying payment.
                   User's access may be suspended.
                   Intervention: direct ask to update payment method.

expired         — ⚠️ Subscription lapsed. No renewal pending.
                   Intervention: win-back offer (price drop, extra credits, etc.)

paused          — Subscription paused (Play Store only).
revoked         — Family sharing revoked.
```

---

## Implementation

### Grace Period: Soft Touch

```swift
func handleSubscriptionStatus(_ info: CustomerInfo) {
    guard let subscription = info.entitlements["premium"]?.latestPurchaseDate,
          let status = info.entitlements["premium"] else { return }
    
    if status.periodType == .normal && !status.isActive {
        // Check if in grace period (billingIssueDetectedAt is set)
        if info.entitlements["premium"] != nil {
            showGracePeriodBanner()  // Soft: "There was an issue with your payment"
        }
    }
}

func showGracePeriodBanner() {
    // Non-blocking banner, not a full-screen paywall
    // Give the user a path to update payment method
    let banner = InAppBanner(
        message: "There was an issue with your payment. Your access is active while we retry.",
        action: "Update payment method",
        onTap: { openSubscriptionManagement() }
    )
    present(banner)
}
```

### Billing Retry: Direct Ask

```swift
func showBillingRetryPrompt() {
    // More urgent — access may be restricted
    let alert = UIAlertController(
        title: "Payment issue",
        message: "We couldn't process your payment. Update your payment method to keep access.",
        preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Update now", style: .default) { _ in
        openSubscriptionManagement()
    })
    alert.addAction(UIAlertAction(title: "Maybe later", style: .cancel))
    present(alert, animated: true)
}

// Open Apple's subscription management
func openSubscriptionManagement() {
    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
        UIApplication.shared.open(url)
    }
}
```

### Win-Back: Expired Users

```swift
func showWinBackPaywall(for userId: String) async {
    // RC Experiments or per-customer assignment for win-back pricing
    await assignWinBackOffering(userId: userId)
    
    // Fetch (now win-back) offering
    let offerings = try? await Purchases.shared.offerings()
    guard let offering = offerings?.current else { return }
    
    await MainActor.run {
        let controller = WinBackPaywallViewController(
            offering: offering,
            context: "We've missed you. Here's 30% off your first month back."
        )
        present(controller, animated: true)
    }
}

func assignWinBackOffering(userId: String) async {
    // Via your backend: POST /v2/projects/{id}/customers/{userId}/actions/assign_offering
    // with your win-back offering ID
}
```

---

## Webhook-Driven Churn Intervention

The best churn interventions are triggered by RC webhooks, not client-side checks. Why: the user may not open the app during a grace period.

```python
# Server-side webhook handler (Python example)
@app.post("/webhook/revenuecat")
async def handle_webhook(event: dict):
    event_type = event.get("event", {}).get("type")
    app_user_id = event.get("event", {}).get("app_user_id")
    
    match event_type:
        case "BILLING_ISSUE":
            # Grace period started — send a gentle email
            await send_email(app_user_id, template="billing_issue_soft")
        
        case "EXPIRATION":
            # Subscription expired — start win-back sequence
            await queue_winback_email(app_user_id, delay_hours=24)
        
        case "CANCELLATION":
            # User canceled (subscription still active until period end)
            # Don't panic yet — but log it
            await log_cancellation_intent(app_user_id)
        
        case "RENEWAL":
            # They came back — cancel any pending win-back
            await cancel_winback_sequence(app_user_id)
```

---

## What Makes It Work

- **Timing matters more than offer.** A win-back email sent 24 hours after expiration converts better than one sent 2 weeks later. Urgency is real.
- **Soft before hard.** Grace period → gentle notification. Billing retry → firm ask. Expired → win-back offer. Escalate in proportion to the situation.
- **Price isn't always the lever.** Some churned users didn't cancel because of price — they stopped using the product. A win-back offer that highlights new features or improvements can convert where a discount won't.
- **Don't gate during grace period.** If a user is in grace period, they think they're subscribed. Showing a paywall creates confusion and destroys trust. Show a banner or notification instead.

---

## Failure Modes

- **Treating `expired` and `grace_period` the same.** They're not. One is "payment failed, we're retrying." The other is "they're gone." Different urgency, different tone.
- **Sending win-back emails too frequently.** Three emails in 24 hours is spam. One email at 24h, a follow-up at 7 days, and a final at 30 days is a sequence.
- **Canceling the win-back sequence too late.** If a user re-subscribes, cancel all pending win-back communications immediately. RC's `RENEWAL` webhook is your trigger.

---

## RC Notes

- `billingIssueDetectedAt` on the entitlement indicates when RC first detected a billing problem.
- Subscription state is best checked via webhooks for server-side triggers. Client-side `customerInfo` works for in-app UI.
- `CANCELLATION` event fires when the user cancels but while the subscription is still active. `EXPIRATION` fires when the period actually ends. Don't confuse them.
- RC webhooks should be event-driven, not polled. Rate limit on Charts API (5/min) makes polling expensive.
