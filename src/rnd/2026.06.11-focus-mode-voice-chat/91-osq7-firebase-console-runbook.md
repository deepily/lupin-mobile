# OSQ-7 Firebase Console Provisioning — Click-Path Runbook

**EXECUTOR: HUMAN (Rick)** — the one genuinely-human step of the focus-mode plan (OSQ-7,
RATIFIED 2026-06-12; working-contract gate #4). AI prepared this click-path and **validates the
resulting config after** you finish (validation checklist at the bottom — DM/say "Firebase done"
and the AI runs it).

**Authored**: 2026-06-12, Mr. Radio 🦉 (post-handoff implementation phase)
**Consumed by**: S5 (mobile FCM handler — needs `google-services.json` on the laptop) and
S6 (parent sender — needs a service-account key for the Admin SDK on the dev server).

---

## Part A — Create the Firebase project (~3 min)

1. Open https://console.firebase.google.com → **Add project**.
2. Project name: `lupin-mobile` (or any name — the name is cosmetic; the project ID it generates
   is what matters, note it down).
3. Google Analytics: **Disable** (not needed for FCM silent-relay; one less consent surface).
4. **Create project** → wait for provisioning → **Continue**.

## Part B — Register the Android app (~3 min)

1. On the project overview page, click the **Android icon** (Add app → Android).
2. **Android package name**: `ai.deepily.lupin_mobile`
   ← MUST match exactly (`android/app/build.gradle.kts:29` `applicationId`). A typo here is the
   #1 silent-failure mode: FCM tokens will mint but pushes never arrive.
3. App nickname: `Lupin Mobile` (cosmetic). SHA-1: **leave blank** (not needed for FCM
   data-only messages; only for Google Sign-In/Dynamic Links).
4. **Register app** → **Download `google-services.json`**.
5. **Placement (laptop)**: drop the file at
   `<lupin-mobile repo root>/android/app/google-services.json`
   (sibling of `build.gradle.kts`). Do NOT commit it yet — the AI validation step checks
   whether `.gitignore` policy wants it tracked or local-only (decision recorded at validation).
6. SKIP the console's "Add Firebase SDK" gradle instructions — the S5 implementer applies the
   gradle plugin changes as part of the section work (ENABLE_FCM default-OFF). Click through
   **Next → Next → Continue to console**.

## Part C — Service-account key for the parent sender (S6) (~2 min)

1. Console → ⚙️ **Project settings** → **Service accounts** tab.
2. Confirm "Firebase Admin SDK" shows a service account (auto-created).
3. **Generate new private key** → confirm → a JSON key file downloads.
4. **Placement (dev server)**: copy it to the parent Lupin box. Recommended landing spot:
   `/mnt/DATA01/include/www.deepily.ai/projects/lupin/src/conf/keys/firebase-admin-key.json`
   (the `src/conf/` tree is where credentials/config live; Tiberius's S6 task names the final
   INI key that points at it). **NEVER commit this file.** Treat it like an API key.
5. Tell Tiberius 👑 (or the AI relays) the final path so S6's admin-SDK init can reference it.

## Part D — Enable the FCM v1 API (~1 min, usually already on)

1. Console → ⚙️ **Project settings** → **Cloud Messaging** tab.
2. Confirm **Firebase Cloud Messaging API (V1)** shows "Enabled". If it shows disabled, click
   the ⋮ menu → Manage API in Google Cloud Console → **Enable**.
3. (The legacy "Cloud Messaging API (Legacy)" stays disabled — S6 uses the v1 Admin SDK.)

---

## AI validation checklist (EXECUTOR: AI — runs after you say "Firebase done")

- [ ] `android/app/google-services.json` exists on the laptop; `package_name` inside ==
      `ai.deepily.lupin_mobile`; `project_id` noted into S5 §8 Execution Log.
- [ ] Parent service-account key file exists at the agreed path; `client_email` +
      `project_id` fields parse; path handed to Tiberius for the S6 INI key.
- [ ] Git hygiene: `google-services.json` tracking decision recorded (FCM sender IDs are not
      secret, but default = ignore until ruled); service-account key confirmed git-ignored.
- [ ] S5 §8 + S6 §8 Execution Logs updated with provisioning evidence (project ID, UTC).

**Total human time: ~10 minutes.** Everything else in Stage 2 is AI-side or AI-scripted.
