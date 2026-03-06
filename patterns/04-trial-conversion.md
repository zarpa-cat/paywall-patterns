# Pattern 04: Trial Conversion

**Use when:** Your product has high activation — users who complete a key action in the first session are likely to subscribe. The trial lets them reach that activation point before committing.

**Conversion style:** Trial → Convert or Churn

**Examples:** Fitness apps (finish first workout), creative tools (finish first project), productivity apps (complete first full workflow).

---

## The Setup

RC handles free trials natively via store-managed trial periods. You don't manage trial duration — the store does. RC tells you when someone is in a trial vs. paying.

```
Entitlement: premium
  └── Products:
        - monthly_with_trial: $7.99/mo (7-day free trial)
        - annual_with_trial:  $59.99/yr (14-day free trial)

Offering: default [is_current: true]
  └── Packages: $rc_monthly, $rc_annual
```

In RC, trial eligibility is tracked per user. A user who has had a trial before won't get another one — RC and the store enforce this.

---

## Implementation (Swift/iOS)

```swift
// Check trial status for contextual UI
func getSubscriptionContext() async -> SubscriptionContext {
    guard let info = try? await Purchases.shared.customerInfo() else {
        return .unknown
    }
    
    let entitlement = info.entitlements["premium"]
    
    if entitlement?.isActive == true {
        switch entitlement?.periodType {
        case .trial:
            let expiryDate = entitlement?.expirationDate
            return .inTrial(expiresAt: expiryDate)
        case .intro:
            return .inIntro
        default:
            return .subscribed
        }
    }
    
    // Check if eligible for trial (first-time offer)
    let offerings = try? await Purchases.shared.offerings()
    let package = offerings?.current?.monthly
    let isEligible = package?.storeProduct.introductoryDiscount != nil
    
    return isEligible ? .trialEligible : .notEligible
}

enum SubscriptionContext {
    case inTrial(expiresAt: Date?)
    case inIntro
    case subscribed
    case trialEligible
    case notEligible
    case unknown
}
```

### Contextual UI Based on Trial State

```swift
func updateSubscriptionBadge(context: SubscriptionContext) {
    switch context {
    case .inTrial(let expiresAt):
        let daysLeft = expiresAt.map { Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0 }
        badge.text = "Trial: \(daysLeft ?? 0) days left"
        badge.style = daysLeft.map { $0 <= 2 } == true ? .urgent : .neutral
        
    case .trialEligible:
        badge.text = "Try free for 7 days"
        badge.style = .promo
        
    case .notEligible:
        badge.text = nil  // Don't surface trial ineligibility — just show the price
        
    case .subscribed:
        badge.text = nil  // No badge needed
    }
}
```

---

## The Trial Nudge Sequence

Trials convert poorly when users forget they're in one. Build a lightweight nudge sequence:

**Day 1:** Nothing. Let them use the product. The trial shouldn't feel like a countdown.

**Day 3 (if engaged — 2+ sessions):** In-app nudge. "You've been using [feature]. Here's what you get when you subscribe."

**Day 6 (day before expiry):** Push notification + in-app banner. "Your trial ends tomorrow. Don't lose access."

**Day 7 (expiry):** If not converted, show paywall on next open.

```swift
func evaluateTrialNudge(context: SubscriptionContext, sessionCount: Int) async {
    guard case .inTrial(let expiresAt) = context else { return }
    
    let daysLeft = expiresAt.map { Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0 } ?? 7
    let hasBeenNudgedToday = UserDefaults.standard.bool(forKey: "trialNudge_\(Date().formatted(.dateTime.month().day()))")
    
    guard !hasBeenNudgedToday else { return }
    
    switch daysLeft {
    case 1...2:
        showTrialExpiryBanner(daysLeft: daysLeft)
        UserDefaults.standard.set(true, forKey: "trialNudge_\(Date().formatted(.dateTime.month().day()))")
    case 3...4 where sessionCount >= 2:
        showEngagementNudge()
        UserDefaults.standard.set(true, forKey: "trialNudge_\(Date().formatted(.dateTime.month().day()))")
    default:
        break
    }
}
```

---

## Server-Side: Trial Nudge via Webhooks

For push notifications and emails, drive from RC webhooks — not client-side:

```python
# RC sends TRIAL_STARTED, TRIAL_CONVERTED, TRIAL_CANCELLED, EXPIRATION

async def handle_rc_webhook(event: dict):
    event_type = event["event"]["type"]
    user_id = event["event"]["app_user_id"]
    
    match event_type:
        case "TRIAL_STARTED":
            # Day 3 nudge if engaged (check your engagement metrics)
            await schedule_nudge(user_id, delay_hours=72, template="trial_day3_engaged")
            # Day 6 expiry warning
            await schedule_nudge(user_id, delay_hours=144, template="trial_day6_expiry")
        
        case "TRIAL_CONVERTED":
            # Cancel pending nudges — they converted!
            await cancel_scheduled_nudges(user_id)
            await send_welcome_email(user_id, template="welcome_subscriber")
        
        case "TRIAL_CANCELLED":
            # They explicitly canceled during trial — immediate win-back attempt
            await send_email(user_id, template="trial_cancelled_winback")
        
        case "EXPIRATION":
            # Trial ended without conversion
            await send_email(user_id, template="trial_expired_offer")
```

---

## What Makes It Work

- **Activation before the paywall.** Don't ask them to start a trial on first launch. Let them see the product, hit the "I want more of this" moment, *then* offer the trial. The trial converts better when the user already wants to stay.
- **Make the trial feel full.** No "trial mode" badges that make the experience feel lesser. They're using the real product — that's the point.
- **Surface what they'll lose, not what they'll get.** "Your 3 saved workouts, your streak, your progress notes" converts better than "Unlimited everything." Loss aversion is real.
- **Day 6 is your most important nudge.** Converts at 2-3x the rate of any other touch point in the trial sequence.

---

## Failure Modes

- **Trial without activation.** If a user starts a trial but never completes a meaningful action, they'll churn at 100%. Fix activation first, then optimize trial conversion.
- **Hiding trial eligibility.** If a user is eligible for a trial but doesn't know it, you're leaving conversions on the table. Surface it in the upgrade flow: "Start your 7-day free trial" not just "Subscribe."
- **Not handling trial-ineligible users gracefully.** Users who've had a trial before shouldn't see trial messaging. `introductoryDiscount == nil` means the package's trial isn't available to this user. Show them the regular price, don't confuse them with trial language.
- **Expiry wall on re-open.** When a trial expires and the user opens the app, don't just block them. Show a warm paywall: "Your trial has ended. Here's what you've built — keep it with a subscription."

---

## RC Notes

- `periodType == .trial` tells you the user is currently in a trial period.
- `introductoryDiscount` on the `StoreProduct` indicates trial eligibility. `nil` means not eligible (previously used).
- RC's `TRIAL_STARTED` and `TRIAL_CONVERTED` webhooks are the reliable hooks for server-side nudge sequences.
- Trial duration is set in App Store Connect / Play Console, not in RC. RC mirrors what the store reports.
- Free trials are entitlements while active — `isActive == true` during the trial period.
