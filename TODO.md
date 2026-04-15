# TODO

Last updated: 2026-04-15 (Session: re-sync with Lupin v0.1.6)

## Pending

### Tier 1 — Auth + WebSocket session persistence (active)
- [ ] [LUPIN-MOBILE] Add `flutter_secure_storage` and `local_auth` deps
- [ ] [LUPIN-MOBILE] Build `ServerContextService` (Dev :7999 ↔ Test :8000 toggle)
- [ ] [LUPIN-MOBILE] Build `SecureCredentialStore` (per-context refresh token + last-used email)
- [ ] [LUPIN-MOBILE] Build `AuthRepository` against `/auth/login`, `/auth/refresh`, `/auth/logout`, `/auth/me`
- [ ] [LUPIN-MOBILE] Build `BiometricGate` (unlock on launch; password fallback when no enrollment)
- [ ] [LUPIN-MOBILE] Wire `AuthBloc` (replace TODOs in `lib/features/auth/.../auth_bloc.dart`)
- [ ] [LUPIN-MOBILE] Add HTTP interceptor for token refresh + 401 handling
- [ ] [LUPIN-MOBILE] Update login screen with email pre-fill from secure storage
- [ ] [LUPIN-MOBILE] Update `WebSocketService` to use real JWT (replace `Bearer mock_token_email_*`)
- [ ] [LUPIN-MOBILE] Add `SessionPersistence` for "wise penguin" caching (per-context, per-user)
- [ ] [LUPIN-MOBILE] Build Settings entry for server-context toggle with confirmation dialog
- [ ] [LUPIN-MOBILE] Smoke-test full flow against running Dev backend on :7999

### Tier 2 — Notifications + Decision Proxy (blocked on Tier 1)
- [ ] [LUPIN-MOBILE] Expand stub plan: `src/rnd/v0.1.6-migration/2026.04.15-tier-2-notifications-and-decision-proxy-plan.md`

### Tier 3 — Queue/CJ Flow + Claude Code sessions (blocked on Tiers 1+2)
- [ ] [LUPIN-MOBILE] Expand stub plan: `src/rnd/v0.1.6-migration/2026.04.15-tier-3-queue-and-claude-code-plan.md`

### Tier 4 — Agentic UIs (blocked on Tiers 1-3)
- [ ] [LUPIN-MOBILE] Expand stub plan: `src/rnd/v0.1.6-migration/2026.04.15-tier-4-agentic-uis-plan.md`

### Cross-cutting
- [ ] [LUPIN-MOBILE] Decide whether/when to PR `2025.07.07-wip-mobile-phased-implementation` → `main` (currently 6 commits ahead of main, never merged)

## Completed (Recent)
- [x] [LUPIN-MOBILE] Audit Lupin v0.1.6 backend (113 endpoints, 24 router groups) — 2026-04-15
- [x] [LUPIN-MOBILE] Map mobile REST + WebSocket coverage (~5%) — 2026-04-15
- [x] [LUPIN-MOBILE] Create `src/rnd/v0.1.6-migration/` with master audit + 4 tier plans — 2026-04-15
- [x] [LUPIN-MOBILE] Create date branch `2026.04.15-resync-with-lupin-v0.1.6` off WIP — 2026-04-15
- [x] [LUPIN-MOBILE] Delete `src/scripts/notify.sh`, untrack auto-gen Flutter env — 2026-04-15
- [x] [LUPIN-MOBILE] Install planning-is-prompting (all 13 groups, 30 slash commands) — 2026-04-15
