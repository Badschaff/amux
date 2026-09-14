---
description: When editing dashboard CSS — mobile and PWA considerations
globs: ["crates/amux-dashboard/static/**"]
---

When editing CSS:
- Check that any new UI fits within the existing `@media (max-width: 600px)` breakpoints
- Touch targets must be at least 44x44 on mobile
- Use `env(safe-area-inset-*)` for anything positioned at screen edges (iOS PWA notch)
- The viewport uses `viewport-fit=cover` — fixed overlays must extend to physical edges
- Test that flex containers don't overflow on 375px-wide screens


Use the production component contract in `docs/ui-style-guide.md` and **Settings →
Style guide** before creating or changing a control. Reuse `.btn`, `.input`, the
shared dialog helpers and theme/spacing tokens; fix a recurring pattern in the
shared class instead of adding another independent variant. Preserve the owner's
original toolbar icons. Primary fills pair `--accent` with `--on-accent`; verify
focus, disabled, loading and invalid states in both themes. The gallery must render
production classes, not copied demonstration styles.
