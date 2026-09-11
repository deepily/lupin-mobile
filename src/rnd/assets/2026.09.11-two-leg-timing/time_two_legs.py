"""
Time the two legs of today's phone flow against the one-leg audio-to-ask door, on the TEST server.

Leg A  "get the transcription back": POST audio -> transcript in hand (wav door, what the phone uses)
Leg B  "simple submission":          POST that transcript as text to /api/v2/ask, speak=False
One-leg:                             POST the same audio to /api/upload-and-transcribe-mp3 with
                                     prefix="multimodal agent", which transcribes AND runs ask in one request
Floor:                               GET /health, server work ~0 — what an HTTP round trip costs on its own

Every duration is one clock (perf_counter on this host). Server-side ask time comes from the
response's own timings_ms (server clock), never subtracted from a client timestamp.
"""
import base64, json, os, statistics as st, sys, time
import requests

BASE    = os.environ.get( "LUPIN_TEST_BASE_URL", "http://localhost:8000" )
HERE    = os.path.dirname( os.path.abspath( __file__ ) )
ASSETS  = "/mnt/DATA01/include/www.deepily.ai/projects/lupin/src/rnd/assets/2026.09.10-voice-real-speech-measurement"
N       = int( os.environ.get( "N", "10" ) )

def ms( t0 ): return ( time.perf_counter() - t0 ) * 1000.0

def summ( xs ):
    xs = sorted( xs )
    p90 = xs[ min( len( xs ) - 1, int( round( 0.9 * ( len( xs ) - 1 ) ) ) ) ]
    return { "n": len( xs ), "median": round( st.median( xs ), 1 ), "p90": round( p90, 1 ), "min": round( xs[ 0 ], 1 ), "max": round( xs[ -1 ], 1 ) }

def main():
    http = requests.Session()   # keep-alive, like the phone's Dio and the browser
    r = http.post( f"{BASE}/auth/login", json={ "email": os.environ[ "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_EMAIL" ],
                                               "password": os.environ[ "LUPIN_TEST_INTERACTIVE_MOCK_JOBS_PASSWORD" ] }, timeout=10 )
    r.raise_for_status()
    auth = { "Authorization": f"Bearer {r.json()[ 'tokens' ][ 'access_token' ]}" }

    clips = {
        "rick-2.8s-44k.wav" : os.path.join( HERE, "rick-question-44k.wav" ),
        "speech-30s-44k.wav": os.path.join( HERE, "speech-30s-44k.wav" ),
    }
    out = { "base": BASE, "n": N, "started": time.strftime( "%Y-%m-%d %H:%M:%S %Z" ), "raw": {} }
    raw = out[ "raw" ]

    # Floor
    raw[ "floor_health" ] = []
    for _ in range( N * 2 ):
        t0 = time.perf_counter(); http.get( f"{BASE}/health", timeout=5 ).raise_for_status(); raw[ "floor_health" ].append( ms( t0 ) )

    transcripts = {}
    for name, path in clips.items():
        data = open( path, "rb" ).read()
        kA = f"legA_total[{name}]"; kAh = f"legA_headers[{name}]"
        raw[ kA ] = []; raw[ kAh ] = []
        for i in range( N ):
            t0  = time.perf_counter()
            res = http.post( f"{BASE}/api/upload-and-transcribe-wav", files={ "file": ( name, data, "audio/wav" ) }, headers=auth, timeout=60 )
            tot = ms( t0 )
            res.raise_for_status()
            raw[ kA ].append( tot ); raw[ kAh ].append( res.elapsed.total_seconds() * 1000.0 )
            transcripts[ name ] = res.json() if res.headers.get( "content-type", "" ).startswith( "application/json" ) else res.text
        out[ f"upload_bytes[{name}]" ] = len( data )

    question = str( transcripts[ "rick-2.8s-44k.wav" ] ).strip().strip( '"' )
    out[ "question" ] = question

    # Interleaved per iteration (B, one-leg, dictation) so cache warm-up cannot land on one design
    mp3_b64 = base64.b64encode( open( os.path.join( HERE, "rick-question.mp3" ), "rb" ).read() )
    raw[ "legB_total" ] = []; raw[ "legB_server_t_complete" ] = []; out[ "legB_paths" ] = []
    raw[ "oneleg_mp3_total" ] = []; raw[ "oneleg_ask_t_complete" ] = []; out[ "oneleg_paths" ] = []
    raw[ "mp3_dictation_total" ] = []
    for i in range( N ):
        # Leg B — the text submission, same question the audio carries
        t0  = time.perf_counter()
        res = http.post( f"{BASE}/api/v2/ask", json={ "question": question, "speak": False }, headers=auth, timeout=60 )
        tot = ms( t0 )
        res.raise_for_status()
        body = res.json()
        raw[ "legB_total" ].append( tot )
        tc = body.get( "timings_ms", {} ).get( "t_complete" )
        if tc is not None: raw[ "legB_server_t_complete" ].append( tc )
        out[ "legB_paths" ].append( f"{body[ 'path' ]}/{body[ 'status' ]}" )
        out[ "legB_last_body_timings" ] = body.get( "timings_ms" )

        # One leg — the mp3 door, agent prefix, same recording (base64 body, as the browser sends it)
        t0  = time.perf_counter()
        res = http.post( f"{BASE}/api/upload-and-transcribe-mp3", params={ "prefix": "multimodal agent" }, data=mp3_b64, headers=auth, timeout=60 )
        tot = ms( t0 )
        res.raise_for_status()
        body = res.json()
        raw[ "oneleg_mp3_total" ].append( tot )
        results = body.get( "results" )
        if isinstance( results, dict ):
            tc = ( results.get( "timings_ms" ) or {} ).get( "t_complete" )
            if tc is not None: raw[ "oneleg_ask_t_complete" ].append( tc )
            out[ "oneleg_paths" ].append( f"{results.get( 'path' )}/{results.get( 'status' )}" )
        else:
            out[ "oneleg_paths" ].append( f"mode={body.get( 'mode' )}" )
        out[ "oneleg_last_body" ] = { k: body.get( k ) for k in ( "mode", "prefix", "transcription" ) }

        # Dictation-only mp3 door on the same recording — the mp3 door's own "transcript back" cost
        t0 = time.perf_counter()
        res = http.post( f"{BASE}/api/upload-and-transcribe-mp3", data=mp3_b64, headers=auth, timeout=60 )
        raw[ "mp3_dictation_total" ].append( ms( t0 ) ); res.raise_for_status()

    out[ "transcripts" ] = transcripts
    out[ "summary_ms" ] = { k: summ( v ) for k, v in raw.items() if v }
    out[ "finished" ] = time.strftime( "%Y-%m-%d %H:%M:%S %Z" )
    json.dump( out, open( os.path.join( HERE, "two-legs-results.json" ), "w" ), indent=2 )
    for k, v in out[ "summary_ms" ].items(): print( f"{k:42s} {v}" )
    print( "question:", question ); print( "legB paths:", out[ "legB_paths" ] ); print( "oneleg paths:", out[ "oneleg_paths" ] )
    print( "oneleg last body:", out[ "oneleg_last_body" ] ); print( "legB timings:", out[ "legB_last_body_timings" ] )

if __name__ == "__main__":
    main()
