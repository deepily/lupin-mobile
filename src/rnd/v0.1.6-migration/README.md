# Lupin Mobile → Lupin v0.1.6 Migration

**Started**: 2026-04-15
**Owner**: [LUPIN-MOBILE]
**Driver**: After ~9 months idle (last touched 2025-07-10), the parent Lupin backend has advanced to **v0.1.6** with a FastAPI surface of **113 endpoints across 24 router groups** and a dual-WebSocket / dual-session architecture. The mobile prototype currently calls only **4 endpoints** (~5% coverage). This subdirectory tracks the staged migration of the mobile app onto the v0.1.6 backend.

---

## Documents

### Master Reference
- 📌 **[Resync Audit — Mobile vs Lupin API v0.1.6](2026.04.15-resync-mobile-with-lupin-api-v0.1.6.md)** — single source of truth. Return here whenever you need the full 28-row category table or the coverage matrix.

### Per-Tier Planning Docs

| Tier | Scope | Plan Doc | Status |
|------|-------|----------|--------|
| **1** | Auth (`/auth/*`) + WebSocket session persistence | [tier-1-auth-and-ws-persistence-plan](2026.04.15-tier-1-auth-and-ws-persistence-plan.md) | 🎯 active — drafting |
| **2** | Notifications (`/api/notifications/*`) + Decision Proxy (`/api/proxy/*`) + multi-sender inbox UI | [tier-2-notifications-and-decision-proxy-plan](2026.04.15-tier-2-notifications-and-decision-proxy-plan.md) | ⏸️ stubbed |
| **3** | Queue / CJ Flow REST + interactive Claude Code sessions | [tier-3-queue-and-claude-code-plan](2026.04.15-tier-3-queue-and-claude-code-plan.md) | ⏸️ stubbed |
| **4** | Agentic UIs (deep research, podcast, presentation, SWE team) + IO file artifacts | [tier-4-agentic-uis-plan](2026.04.15-tier-4-agentic-uis-plan.md) | ⏸️ stubbed |

---

## Conventions

- All migration docs live in this directory with `yyyy.mm.dd-` prefix.
- One doc per tier (planning) plus per-tier completion summaries.
- Reference the parent backend's authoritative API surface via:
  - Live OpenAPI: `http://localhost:7999/openapi.json`
  - Swagger UI: `http://localhost:7999/docs`
- Backend doc index: `lupin/src/docs/README.md`
