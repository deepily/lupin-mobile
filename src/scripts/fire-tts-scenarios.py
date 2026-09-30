#!/usr/bin/env python3
"""
Fire the 10 on-device TTS + notification-audio test scenarios from TODO.md
against a running Lupin backend.

Designed to be invoked from either the laptop (during on-device verify on
emulator) or the dev server. Each scenario runs in isolation with a user-
configurable inter-scenario pause so the operator can observe the emulator
behavior between scenarios.

Usage:
    # All scenarios against local dev server:
    python fire-tts-scenarios.py \\
        --target-email you@example.com \\
        --base-url http://localhost:7999

    # Single scenario:
    python fire-tts-scenarios.py \\
        --target-email you@example.com \\
        --scenario s6_urgent_preempts_high

    # Dry run (print, don't fire):
    python fire-tts-scenarios.py \\
        --target-email you@example.com --dry-run

Scenarios map 1:1 to TODO.md lines 54-71.

Requires:
    - Python 3.8+
    - `requests` library (pip install requests)
    - API key at src/conf/keys/notification-api-claude-code-dev
      (relative to LUPIN_ROOT or the `--api-key-path` you supply)
    - Backend reachable at --base-url
    - Emulator (or physical device) logged in as --target-email
"""

import argparse
import os
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional

try:
    import requests
except ImportError:
    print( "ERROR: this script needs `requests`. Install it:", file=sys.stderr )
    print( "    pip install requests", file=sys.stderr )
    sys.exit( 2 )


# ---------- Scenario definitions ----------

class Scenario:
    """One on-device verify scenario. `params` are query params for /api/notify."""
    def __init__(
        self,
        key              : str,
        title            : str,
        expect           : str,
        params           : Dict[str, str],
        manual_precursor : Optional[str] = None,
        gotcha           : Optional[str] = None,
    ):
        self.key              = key
        self.title            = title
        self.expect           = expect
        self.params           = params
        self.manual_precursor = manual_precursor
        self.gotcha           = gotcha


def build_scenarios() -> List[Scenario]:
    """The 10 scenarios from TODO.md lines 54-71, indexed s1..s11 for stable CLI names."""
    return [
        Scenario(
            key    = "s1_medium_ding",
            title  = "Medium ding only",
            expect = "single medium ding, no speech",
            params = { "priority": "medium", "title": "S1", "message": "Medium priority test." },
        ),
        Scenario(
            key    = "s2_high_ding_plus_speech",
            title  = "High ding + ElevenLabs speech",
            expect = "high ding, then ~300ms, then ElevenLabs voice speaks 'S2. High priority test.'",
            params = { "priority": "high",   "title": "S2", "message": "High priority test." },
            gotcha = "With the 2026-04-24 overlap fix, TtsCompleteEvent only fires AFTER audio finishes.",
        ),
        Scenario(
            key    = "s3_urgent_alert_tone",
            title  = "Urgent alert tone + speech",
            expect = "urgent alert tone, then ElevenLabs voice speaks 'S3. Prod down, please check.'",
            params = { "priority": "urgent", "title": "S3", "message": "Prod down, please check." },
        ),
        Scenario(
            key    = "s4_suppress_ding",
            title  = "suppress_ding=true, medium priority",
            expect = "SILENCE — no ding, no speech (priority=medium has no speech path)",
            params = { "priority": "medium", "title": "S4", "message": "Suppressed ding test.", "suppress_ding": "true" },
            gotcha = "Web-client semantics: suppress_ding silences the DING only. At priority=medium there "
                     "is no speech anyway. At priority=high with speakOnHigh=true, speech would still play.",
        ),
        Scenario(
            key    = "s5_second_rapid_high_fifo",
            title  = "Two rapid highs (FIFO)",
            expect = "first 'S5a.' plays fully, then 'S5b.' plays fully. NO overlap, NO truncation. "
                     "This is the regression test for the 2026-04-24 overlap fix.",
            params = { "priority": "high", "title": "S5a", "message": "First of two rapid highs." },
            manual_precursor = "This scenario fires two notifications ~500ms apart. Second is fired "
                               "automatically by the next scenario `s5b_second_high`.",
        ),
        Scenario(
            key    = "s5b_second_high",
            title  = "Second of rapid-fire pair",
            expect = "(Fired after s5 with 500ms delay.) Second 'S5b.' plays AFTER first 'S5a.' finishes.",
            params = { "priority": "high", "title": "S5b", "message": "Second of two rapid highs." },
        ),
        Scenario(
            key    = "s6_urgent_preempts_high",
            title  = "Urgent preempts mid-high",
            expect = "high starts speaking. ~2s later urgent arrives and CUTS OFF the high, speaks 'S6.' instead.",
            params = { "priority": "high", "title": "Long message for preempt", "message":
                       "This is a deliberately long message to give the preempt time to fire. "
                       "Several clauses. More clauses. Testing the urgent preempt path." },
            manual_precursor = "After this fires and you hear speech start, re-run the script with "
                               "--scenario s6b_urgent_preempter to fire the urgent that preempts it.",
        ),
        Scenario(
            key    = "s6b_urgent_preempter",
            title  = "The urgent that preempts s6",
            expect = "Cuts off s6's ongoing high speech, speaks 'S6. Preempted.' Tests _preemptForUrgent path.",
            params = { "priority": "urgent", "title": "S6", "message": "Preempted." },
        ),
        Scenario(
            key    = "s8_quota_exceeded_fallback",
            title  = "Simulate ElevenLabs quota_exceeded mid-stream",
            expect = "Current utterance re-speaks via on-device flutter_tts, next 5 minutes of highs "
                     "also route through flutter_tts.",
            params = { "priority": "high", "title": "S8", "message": "Quota fallback test." },
            manual_precursor = "Requires either: (a) pointing backend at an exhausted ElevenLabs account "
                               "for the duration of this scenario, OR (b) backend stub injecting a "
                               "`tts_error` event. See `src/rnd/v0.1.7/2026.04.24-on-device-tts-verify-runbook.md` "
                               "section `Stub-injection strategy` before firing this one.",
        ),
        Scenario(
            key    = "s9_elevenlabs_retry_after_window",
            title  = "ElevenLabs retried after 5min window",
            expect = "ElevenLabs voice speaks 'S9.' (quota window has elapsed).",
            params = { "priority": "high", "title": "S9", "message": "ElevenLabs retry after 5 minute window." },
            manual_precursor = "Wait 5+ minutes after s8 before running this.",
        ),
        Scenario(
            key    = "s10_master_mute_silence",
            title  = "Master mute → silence at all priorities",
            expect = "Urgent fires but device is SILENT (no ding, no speech).",
            params = { "priority": "urgent", "title": "S10", "message": "Master mute test." },
            manual_precursor = "In Settings → Notification Audio, toggle Master Mute ON before firing.",
        ),
        Scenario(
            key    = "s11_speakon_high_false",
            title  = "speakOnHigh=false → ding without speech",
            expect = "High ding plays, but ElevenLabs voice does NOT speak.",
            params = { "priority": "high", "title": "S11", "message": "Ding-only high test." },
            manual_precursor = "In Settings → Notification Audio, ensure Master Mute is OFF and "
                               "toggle 'Speak on high priority' OFF before firing.",
        ),
    ]


# ---------- API interaction ----------

def load_api_key( key_path: Path ) -> str:
    if not key_path.exists():
        print( f"ERROR: API key file not found at {key_path}", file=sys.stderr )
        sys.exit( 2 )
    return key_path.read_text().strip()


def fire( scenario: Scenario, base_url: str, api_key: str, target_email: str, timeout: float, dry_run: bool ) -> bool:
    """POST to /api/notify with scenario params. Returns True on 200."""
    url     = f"{base_url}/api/notify"
    headers = { "X-API-Key": api_key }
    params  = dict( scenario.params )
    params[ "target_user" ] = target_email

    if dry_run:
        print( f"    DRY-RUN: POST {url}" )
        print( f"    DRY-RUN: params = {params}" )
        return True

    try:
        resp = requests.post( url, headers=headers, params=params, timeout=timeout )
        ok   = 200 <= resp.status_code < 300
        status_icon = "✅" if ok else "❌"
        print( f"    {status_icon} HTTP {resp.status_code}" )
        if not ok:
            print( f"    response: {resp.text[ :400 ]}" )
        return ok
    except requests.RequestException as e:
        print( f"    ❌ request failed: {e}" )
        return False


def print_scenario_header( s: Scenario ) -> None:
    print( f"\n  📣 {s.key}: {s.title}" )
    print( f"     Expect: {s.expect}" )
    if s.manual_precursor:
        print( f"     ⚠️  Manual precursor: {s.manual_precursor}" )
    if s.gotcha:
        print( f"     Gotcha: {s.gotcha}" )


def summarize( results: List[Dict[str, object]] ) -> None:
    """Tabular summary per CLAUDE.md directive."""
    print( "\n" + "=" * 72 )
    print( "  SUMMARY" )
    print( "=" * 72 )
    header = f"{'Scenario':<32} {'HTTP':<6} {'Result':<10}"
    print( header )
    print( "-" * 72 )
    for r in results:
        icon = "✅ sent" if r[ "ok" ] else "❌ fail"
        print( f"{str( r[ 'key' ] ):<32} {str( r[ 'http' ] ):<6} {icon:<10}" )
    print( "=" * 72 )
    passed = sum( 1 for r in results if r[ "ok" ] )
    print( f"  {passed}/{len( results )} scenarios fired successfully.\n" )
    print( "  NOTE: 'sent' only means the POST returned 200. You must observe the" )
    print( "        emulator to judge whether the behavior matched `expect`." )
    print()


# ---------- Main ----------

def main() -> int:
    p = argparse.ArgumentParser( description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter )
    p.add_argument( "--target-email",  required=True, help="Email of the logged-in emulator user" )
    p.add_argument( "--base-url",      default="http://localhost:7999",
                    help="Backend base URL (emulator: http://10.0.2.2:7999 from inside emulator, "
                         "but this script runs on the HOST so localhost is usually right)" )
    p.add_argument( "--api-key-path",  default=None,
                    help="Path to the Lupin notification API key file. Defaults to "
                         "$LUPIN_ROOT/src/conf/keys/notification-api-claude-code-dev" )
    p.add_argument( "--scenario",      default="all",
                    help="Scenario key (e.g. s2_high_ding_plus_speech) or 'all'" )
    p.add_argument( "--pause-seconds", type=float, default=6.0,
                    help="Seconds to wait between scenarios when running 'all' (default: 6)" )
    p.add_argument( "--rapid-gap-ms",  type=int, default=500,
                    help="Milliseconds between s5a and s5b for FIFO rapid-fire test (default: 500)" )
    p.add_argument( "--timeout",       type=float, default=10.0, help="Per-request timeout seconds" )
    p.add_argument( "--dry-run",       action="store_true", help="Print requests, do not fire them" )
    args = p.parse_args()

    # Resolve API key path
    if args.api_key_path:
        key_path = Path( args.api_key_path )
    else:
        lupin_root = os.environ.get( "LUPIN_ROOT", "/var/lupin" )
        key_path   = Path( lupin_root ) / "src" / "conf" / "keys" / "notification-api-claude-code-dev"
    api_key = "DRY-RUN" if args.dry_run else load_api_key( key_path )

    scenarios = build_scenarios()
    if args.scenario != "all":
        scenarios = [ s for s in scenarios if s.key == args.scenario ]
        if not scenarios:
            print( f"ERROR: unknown scenario '{args.scenario}'. Run with --scenario all, or pick one:", file=sys.stderr )
            for s in build_scenarios():
                print( f"    {s.key}", file=sys.stderr )
            return 2

    print( "=" * 72 )
    print( "  Lupin Mobile — On-device TTS + notification-audio scenarios" )
    print( "=" * 72 )
    print( f"  Base URL    : {args.base_url}" )
    print( f"  Target user : {args.target_email}" )
    print( f"  API key     : {key_path if not args.dry_run else '(dry-run, no key loaded)'}" )
    print( f"  Scenarios   : {args.scenario} ({len( scenarios )} total)" )
    print( f"  Pause       : {args.pause_seconds}s between scenarios" )
    print( "=" * 72 )

    results = []
    for i, s in enumerate( scenarios ):
        print_scenario_header( s )
        ok   = fire( s, args.base_url, api_key, args.target_email, args.timeout, args.dry_run )
        http = "SENT" if ok else "FAIL"
        results.append( { "key": s.key, "ok": ok, "http": http } )

        # Special-case: s5 triggers s5b automatically with tight timing.
        if s.key == "s5_second_rapid_high_fifo" and not args.dry_run:
            gap = args.rapid_gap_ms / 1000.0
            print( f"    ⏱  Rapid-fire: waiting {gap:.2f}s then firing s5b..." )
            time.sleep( gap )
            s5b  = next( x for x in build_scenarios() if x.key == "s5b_second_high" )
            print_scenario_header( s5b )
            ok_b = fire( s5b, args.base_url, api_key, args.target_email, args.timeout, args.dry_run )
            results.append( { "key": s5b.key, "ok": ok_b, "http": "SENT" if ok_b else "FAIL" } )

        if i < len( scenarios ) - 1:
            time.sleep( args.pause_seconds )

    summarize( results )
    return 0 if all( r[ "ok" ] for r in results ) else 1


if __name__ == "__main__":
    sys.exit( main() )
