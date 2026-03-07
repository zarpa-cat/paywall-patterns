# Pattern 07: Dynamic Offering

**Use when:** You want to A/B test pricing, show different paywalls to different user segments, or personalize the paywall based on user behavior.

**Conversion style:** Different users see different paywalls — same entitlement, different ask.

**Examples:** Price testing ($4.99 vs $7.99), geographic pricing, new-user vs returning-user paywall, high-engagement users get annual push.

---

## The Setup

Multiple offerings, RC Experiments (A/B) or per-customer assignment:

```
Offerings:
  - default        [is_current: true] → $4.99/mo, $39.99/yr
  - high_intent    [not current]      → $7.99/mo, $59.99/yr
  - annual_push    [not current]      → Monthly hidden, Annual prominent ($49.99)
```

### Option A: RC Experiments (A/B test at scale)

Set up via dashboard (required — variant config not available via REST API as of March 2026). The SDK auto-receives the assigned offering.

```swift
// SDK automatically handles experiment assignment
let offerings = try? await Purchases.shared.offerings()
let offering = offerings?.current  // SDK returns the assigned variant
showPaywall(offering: offering)
```

### Option B: Per-customer offering assignment (via API)

No dashboard required. You decide which offering to assign based on your own signals.

```bash
# Assign a specific offering to a customer
POST /v2/projects/{project_id}/customers/{app_user_id}/actions/assign_offering
{
  "offering_id": "ofrng_high_intent_id"
}
```

```swift
// After server-side assignment, SDK sees the assigned offering
let offerings = try? await Purchases.shared.offerings()
let offering = offerings?.current  // Returns the assigned offering, not the default
showPaywall(offering: offering)
```

---

## When to Use Each

**Experiments (A/B):** When you want random assignment, statistical validity, and RC's built-in metrics. Requires dashboard for variant setup — can't automate this fully yet.

**Per-customer assignment:** When you want deterministic, behavior-based assignment. You control the logic. No statistical dashboard, but full control.

```swift
// Example: assign annual-push offering to high-engagement users
func assignOfferingForUser(userId: String, sessionsCount: Int, daysActive: Int) async {
    let offeringId: String
    
    switch (sessionsCount, daysActive) {
    case (_, let days) where days > 14:
        // Sticky user: push annual
        offeringId = "ofrng_annual_push"
    case (let sessions, _) where sessions > 20:
        // Power user: try higher price point
        offeringId = "ofrng_high_intent"
    default:
        offeringId = "ofrng_default"
    }
    
    await assignOffering(userId: userId, offeringId: offeringId)
}
```

---

## Customer Attributes: Signals for Targeting

Set arbitrary key-value attributes on customers. RC's dashboard targeting rules use these under the hood — or your own code can read them to drive assignment logic.

```bash
# Set attributes on a customer
POST /v2/projects/{project_id}/customers/{app_user_id}/attributes
{
  "attributes": [
    {"name": "segment", "value": "high_intent"},
    {"name": "sessions_count", "value": "42"},
    {"name": "ltv_tier", "value": "high"}
  ]
}
```

**Gotchas:**
- `attributes` must be an **array** (not an object) — `{"attributes": {...}}` returns 400
- Values are always **strings** — even numbers: `"42"` not `42`
- POST **merges** — safe to update individual attributes without touching others
- Delete an attribute by setting `"value": null`

**Two ways to use attributes:**
1. Set them and let RC dashboard targeting rules route the offering automatically
2. Read your own signals and call `assign_offering` directly — skip the rule engine entirely

---

## Offering Metadata: The Hidden Tool

RC offerings can carry arbitrary JSON metadata. Use this to drive paywall copy and layout without app updates.

```bash
# Set metadata on an offering via REST API
# Note: POST only — PATCH and PUT both return 405
# POST replaces the entire metadata object; include all keys you want to keep
POST /v2/projects/{project_id}/offerings/{offering_id}
{
  "metadata": {
    "headline": "Used 20+ times this month. You might love Pro.",
    "cta": "Start your 7-day free trial",
    "highlight_package": "annual",
    "show_comparison": true
  }
}
```

```swift
// Read metadata in your paywall view
if let metadata = offering.metadata {
    headlineLabel.text = metadata["headline"] as? String
    let highlightPackage = metadata["highlight_package"] as? String
    // render accordingly
}
```

This pattern lets you change paywall messaging, layout hints, and CTAs via the RC dashboard — no app review needed.

---

## What Makes It Work

- **Segment on behavior, not demographics.** "User has 15+ sessions" is better than "User is in the US." Behavior signals intent.
- **Match the ask to the signal.** High-engagement users get the annual push. New users get the trial. Returning lapsed users get the win-back offer.
- **Keep the default clean.** The `current` offering should be your best-performing baseline. Experiments branch from there.

---

## Failure Modes

- **Over-segmenting.** If you have 12 offerings and no clear logic for assignment, you'll lose track of what's converting and why. Start with 2 offerings: control and variant.
- **Stale assignment.** If you assign an offering when a user is "high intent" but don't update it when behavior changes, you'll show the wrong paywall months later. Re-evaluate assignment at meaningful lifecycle points (re-engagement, upgrade prompt).
- **Forgetting the SDK caches offerings.** RC caches offering data locally. If you assign a new offering server-side, the client may not see it immediately. Call `Purchases.shared.invalidateCustomerInfoCache()` after assignment if you need the change reflected in the current session.

---

## Agent Targeting Playbook

When your agent is the targeting logic — no dashboard rules needed:

```python
# Step 1: Compute user signals
signals = await compute_user_signals(user_id)

# Step 2: Pick the right offering
if signals.days_active > 14:
    offering_id = "ofrng_annual_push"   # sticky user → push annual
elif signals.sessions_30d > 20:
    offering_id = "ofrng_high_intent"   # power user → higher price point
else:
    offering_id = "ofrng_default"

# Step 3: (Optional) Write attributes for dashboard visibility / analytics
await post_customer_attributes(user_id, {
    "segment": signals.segment,
    "sessions_count": str(signals.sessions_30d),
    "ltv_tier": signals.ltv_tier,
})

# Step 4: Assign offering directly — overrides project default and dashboard rules
await assign_offering(user_id, offering_id)
# → Purchases.shared.offerings().current now returns the assigned offering
```

Use attributes + direct assignment when you want both programmatic control and RC dashboard visibility into your segments.

---

## RC Notes

- Experiments require dashboard for variant config — REST API supports create/delete but not variant/placement configuration (as of March 2026). An "Invalid experiment" error on `start` usually means placements aren't configured.
- `assign_offering` is `/actions/assign_offering` — the `/actions/VERB` pattern strikes again.
- Per-customer assignment survives across devices for the same App User ID. If you're using anonymous IDs, assignment is per-device until you call `logIn()`.
