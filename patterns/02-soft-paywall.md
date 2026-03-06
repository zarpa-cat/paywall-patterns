# Pattern 02: Soft Paywall

**Use when:** The product has genuine value to show before asking for money. Users need to experience the core loop to understand what they're buying.

**Conversion style:** Try → Subscribe

**Examples:** Photo editors, habit trackers, journaling apps, anything where the first session creates attachment.

---

## The Setup

Same entitlement structure as hard paywall, but you don't check it on launch. You check it at the *moment of friction* — when the user tries to do something that requires premium.

```
Entitlement: premium
  └── Products: monthly ($5.99), annual ($49.99)

Offering: default [is_current: true]
  └── Packages: $rc_monthly, $rc_annual
```

The difference is in *when* you call `checkAccess()`, not *how*.

---

## Implementation (Swift/iOS)

```swift
// Don't gate on launch. Gate on the action.
func exportToCloud() async {
    let info = try? await Purchases.shared.customerInfo()
    guard info?.entitlements["premium"]?.isActive == true else {
        // User hit the premium feature. Show paywall with context.
        showPaywall(context: "export")
        return
    }
    // proceed with export
    performCloudExport()
}

// Context-aware paywall — tell the user WHY they're seeing this
func showPaywall(context: String) {
    Task {
        guard let offering = try? await Purchases.shared.offerings().current else { return }
        await MainActor.run {
            let controller = PaywallViewController(offering: offering)
            // If your paywall supports metadata, pass the context
            present(controller, animated: true)
        }
    }
}
```

---

## The Moment of Friction

The paywall works best when it appears at genuine value moments, not arbitrary gates. Ask yourself: "Is the user thinking *I want this* right now?" If yes, that's when to show the paywall.

Bad friction points:
- After 3 days of use regardless of what the user is doing (time-based, not behavior-based)
- On opening the app (that's a hard paywall; own that choice)
- Repeatedly, after the user has already seen and dismissed it

Good friction points:
- First use of an export/share feature
- When a user creates their 5th item (if the limit is part of your model)
- At the end of a completed action ("You just did X. Want to unlock Y?")

---

## What Makes It Work

- **The user has already invested.** They've used the app. The paywall now has an anchor — the user has something to lose (their progress, their data, their habit).
- **Show the benefit, not the feature.** "Unlock unlimited exports" converts better than "Upgrade to Premium." The feature is a means; the benefit is the end.
- **Don't interrupt.** If the user is in a flow state, gate them *after* they complete the action, not mid-action.

---

## Failure Modes

- **Too many gates.** If a user hits a paywall every session, they churn. Decide on 1-2 friction points and stick to them.
- **Surprise gates.** The user shouldn't discover limits accidentally. Surface them gracefully: "You've used 4 of 5 free projects. 1 remaining." Give them warning.
- **Not remembering dismissals.** If a user dismisses the paywall, don't show it again in the same session. Track this in `UserDefaults` or `@AppStorage`.

```swift
// Track dismissal to avoid repeated interruption
func showPaywallIfAppropriate(context: String) {
    let dismissedKey = "paywall_dismissed_\(Date().formatted(.dateTime.month().day()))"
    guard !UserDefaults.standard.bool(forKey: dismissedKey) else { return }
    
    showPaywall(context: context) {
        // on dismiss
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }
}
```

---

## RC Notes

- For soft paywalls, prefetch `customerInfo` early (on login or first app open) so it's cached when you need it at the friction point. RC caches aggressively — you're reading from local cache most of the time, which is fast.
- Consider using RC's `Offering` metadata to store the copy for each friction context. That way you can A/B test paywall messaging without an app update.
