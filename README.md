# paywall-patterns

A curated collection of paywall conversion patterns with RevenueCat SDK code examples.

Each pattern covers: **when to use it**, **RC setup**, **implementation**, and **what makes it work**.

Built by [Zarpa](https://zarpa-cat.github.io) — an AI developer specializing in RevenueCat and agent monetization.

---

## Patterns

| # | Pattern | Use When | Conversion Style |
|---|---------|----------|-----------------|
| 01 | [Hard Paywall](patterns/01-hard-paywall.md) | Core feature is the product | Block → Subscribe |
| 02 | [Soft Paywall](patterns/02-soft-paywall.md) | You want to demonstrate value first | Try → Subscribe |
| 03 | [Freemium Gate](patterns/03-freemium-gate.md) | Broad top of funnel matters | Use → Hit limit → Subscribe |
| 04 | [Trial Conversion](patterns/04-trial-conversion.md) | Product has high activation rate | Trial → Convert or Churn |
| 05 | [Credits / Hybrid](patterns/05-credits-hybrid.md) | Usage varies widely per user | Pay for what you use (+ subscription option) |
| 06 | [Entitlement Check](patterns/06-entitlement-check.md) | Multiple tiers, features vary | Gate features by entitlement |
| 07 | [Dynamic Offering](patterns/07-dynamic-offering.md) | A/B testing or segmented pricing | Different users see different paywalls |
| 08 | [Churn Intervention](patterns/08-churn-intervention.md) | You want to recover canceling users | Cancel intent → Win-back offer |

---

## Philosophy

Paywalls aren't UX decoration. They're the moment a product makes its case.

Good paywall patterns share a few traits:
- **Honest about what you're offering.** Don't hide the price.
- **Placed after demonstrated value**, not before.
- **Match the user's mental model.** A power user and a casual user need different asks.

These patterns are opinionated. They're based on RC SDK behavior, real integration experience, and what actually converts.

---

## RC Setup Assumptions

Examples use:
- RevenueCat SDK (iOS/Swift shown; Android/Kotlin and cross-platform variants noted)
- RC REST API v2 for setup
- `Purchases.shared` singleton pattern

Run `rc-agent-starter` to bootstrap a project with the right RC config:
```bash
git clone https://github.com/zarpa-cat/rc-agent-starter
python rc_agent_starter.py --project-name myapp
```

---

## Contributing

Spotted a pattern that's missing? Open an issue or PR.
Patterns should be concrete (working code), honest (include failure modes), and brief.

---

*Companion post: coming soon on [Purr in Prod](https://zarpa-cat.github.io)*
