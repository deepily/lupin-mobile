"""
Tests for tool/markdown_gate.py, the blocking markdown gate (lupin-mobile row 696b6744, plan steps 4 to 6).

Run: python3 -m pytest tool/test_markdown_gate.py -q -p no:structlog_config
Each test builds a real temporary git repo, so the staged content, the changed lines and the base ref are
what git reports. Each test says in a comment which result would refute it.
"""

import io
import os
import subprocess
import sys
import tempfile

import pytest

TOOL = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, TOOL )

import markdown_gate as mg

# One finding each, on line 3 of a page that begins "# Notes" and a blank line.
CAPS       = "# Notes\n\nThe value is NEVER cached.\n"      # rule caps: a language finding
DATED      = "# Notes\n\nChanged on 2026-10-13 here.\n"     # rules iso-date and dated-banner: a record keeps these
BARE_REF   = "# Notes\n\nSee row 696b6744 for it.\n"        # rule bare-ref: a record keeps this
CLEAN      = "# Notes\n\nThe value is read once.\n"
LONG_PAGE  = "# Notes\n\n" + "It is read once.\n" * 600      # about 2,400 words: rule reference-length under src/docs/


def sh( root, *args ):
    """
    Run git in a repo and return its stdout.

    Requires:
        - root is a git working tree

    Ensures:
        - raises when git exits non-zero
    """
    return subprocess.run( [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", root, *args ],
                           capture_output=True, text=True, check=True ).stdout


def write( root, rel, text ):
    """
    Write one file under root, making its folder.

    Requires:
        - rel is a repo-relative path
    """
    full = os.path.join( root, rel )
    os.makedirs( os.path.dirname( full ), exist_ok=True )
    with open( full, "w", encoding="utf-8" ) as f: f.write( text )


def make_repo( scope, committed=None ):
    """
    Create a temporary repo that holds the scope file and the committed pages.

    Requires:
        - scope is the text of tool/data/markdown_scope.txt, or None to leave the file out
        - committed maps a repo-relative path to its text, or is None

    Ensures:
        - returns the repo root; the scope file and the pages are in one commit
    """
    root = tempfile.mkdtemp()
    sh( root, "init", "-q", "-b", "main" )
    if scope is not None: write( root, mg.SCOPE_PATH, scope )
    for rel, text in ( committed or {} ).items(): write( root, rel, text )
    sh( root, "add", "-A" )
    sh( root, "commit", "-q", "--no-verify", "-m", "base", "--allow-empty" )
    return root


def stage( root, pages ):
    """
    Write pages and stage them.

    Requires:
        - pages maps a repo-relative path to its text
    """
    for rel, text in pages.items(): write( root, rel, text )
    sh( root, "add", *pages )


def run_gate( root, *flags ):
    """
    Run the gate's main over a repo.

    Requires:
        - root is a repo from make_repo

    Ensures:
        - returns ( exit code, stdout text, stderr text )
    """
    out, err = io.StringIO(), io.StringIO()
    real = sys.stderr
    sys.stderr = err
    try:
        code = mg.main( [ *flags, "--repo-root", root ], out=out )
    finally:
        sys.stderr = real
    return code, out.getvalue(), err.getvalue()


# ---------------------------------------------------------------- scope file

def test_a_scope_line_with_an_unknown_class_is_an_error():
    # Refuted if parse_scope returns entries instead of raising ScopeError for the class "sloppy".
    with pytest.raises( mg.ScopeError, match="sloppy" ): mg.parse_scope( "sloppy notes.md\n" )


def test_a_scope_line_with_no_path_or_two_paths_is_an_error():
    # Refuted if either malformed line is accepted.
    with pytest.raises( mg.ScopeError ): mg.parse_scope( "record\n" )
    with pytest.raises( mg.ScopeError ): mg.parse_scope( "record a.md b.md\n" )


def test_a_path_listed_twice_is_an_error():
    # Refuted if the second listing silently wins, so a later line could loosen an earlier one.
    with pytest.raises( mg.ScopeError, match="listed twice" ): mg.parse_scope( "record a.md\nexempt a.md\n" )


def test_comments_and_blank_lines_are_skipped():
    # Refuted if the comment line is read as an entry (it would raise) or the entries come back reordered or dropped.
    assert mg.parse_scope( "# note\n\nrecord a.md\n  \nexempt b/\n" ) == [ ( "a.md", "record" ), ( "b/", "exempt" ) ]


def test_a_missing_scope_file_exits_2_and_checks_nothing():
    # Refuted if the exit code is 0 or 1, or if a REFUSED line is printed for the staged page.
    root = make_repo( None )
    stage( root, { "notes.md": CAPS } )
    code, out, err = run_gate( root, "--staged" )
    assert code == 2
    assert "REFUSED" not in out
    assert "markdown_scope.txt" in err


def test_a_malformed_scope_file_exits_2():
    # Refuted if a bad class line lets the run go on to exit 0 or 1.
    root = make_repo( "sloppy notes.md\n" )
    stage( root, { "notes.md": CLEAN } )
    assert run_gate( root, "--staged" )[ 0 ] == 2


def test_the_checked_in_scope_file_parses():
    # Refuted if the real scope file has a bad line: every commit in the repo would exit 2.
    assert mg.load_scope( os.path.dirname( TOOL ) )


# ---------------------------------------------------------------- class lookup

def test_the_longest_entry_wins():
    # Refuted if the folder entry (listed first) wins over the longer file entry, or the order in the file decides.
    entries = [ ( "src/docs/", "exempt" ), ( "src/docs/post-games/", "record-lines" ), ( "src/docs/post-games/README.md", "record" ) ]
    assert mg.class_of( "src/docs/post-games/README.md", entries ) == "record"
    assert mg.class_of( "src/docs/post-games/v1/a.md", entries ) == "record-lines"
    assert mg.class_of( "src/docs/other.md", entries ) == "exempt"


def test_an_unlisted_page_is_a_reference_page():
    # Refuted if the default is anything but "reference".
    assert mg.class_of( "docs/new.md", [ ( "history/", "exempt" ) ] ) == "reference"


def test_a_folder_entry_needs_its_slash_and_a_file_entry_matches_one_file():
    # Refuted if "history.md" also matches "history.md.bak", or "history/" matches "history-old/a.md".
    entries = [ ( "history.md", "record-lines" ), ( "history/", "exempt" ) ]
    assert mg.class_of( "history.md.bak", entries ) == "reference"
    assert mg.class_of( "history-old/a.md", entries ) == "reference"
    assert mg.class_of( "history/a.md", entries ) == "exempt"


# ---------------------------------------------------------------- the commit check, by class

def test_a_reference_page_is_refused_for_a_finding_on_an_untouched_line():
    # Refuted if the commit passes: the bad line 3 is in the base, and only line 5 is added.
    root = make_repo( "", { "notes.md": CAPS } )
    stage( root, { "notes.md": CAPS + "\nAnother line that is fine.\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1
    assert "REFUSED notes.md:3: caps" in out


def test_a_clean_reference_page_passes():
    # Refuted if the clean page is refused, or the summary line is missing.
    root = make_repo( "", {} )
    stage( root, { "notes.md": CLEAN } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0
    assert "0 refused, 0 warned, 1 pages checked" in out


def test_a_record_keeps_its_dates_and_ids_and_its_length():
    # Refuted if any of iso-date, bare-ref, dated-banner or reference-length is refused on a record page.
    root = make_repo( "record src/docs/log.md\n", {} )
    stage( root, { "src/docs/log.md": DATED + "\nSee row 696b6744 for it.\n" + "It is read once.\n" * 600 } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0, out


def test_the_same_dates_are_refused_on_a_reference_page():
    # Refuted if the page passes: the control that shows the record test above is not vacuous.
    root = make_repo( "", {} )
    stage( root, { "notes.md": DATED + "\nSee row 696b6744 for it.\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1
    assert "iso-date" in out and "bare-ref" in out


def test_a_record_is_refused_for_a_language_finding():
    # Refuted if the record page passes with the ALL-CAPS word.
    root = make_repo( "record notes.md\n", {} )
    stage( root, { "notes.md": CAPS } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1
    assert "REFUSED notes.md:3: caps" in out and "[record]" in out


def test_a_record_page_that_is_long_under_src_docs_is_not_refused_for_length():
    # Refuted if reference-length appears: the control below proves the page is long enough to trip it as a reference.
    root = make_repo( "", {} )
    stage( root, { "src/docs/long.md": LONG_PAGE } )
    assert "reference-length" in run_gate( root, "--staged" )[ 1 ]


def test_a_record_lines_page_is_refused_only_for_a_staged_line():
    # Refuted if the old bad line 3 is refused, or the new bad line 5 is not.
    root = make_repo( "record-lines history.md\n", { "history.md": CAPS } )
    stage( root, { "history.md": CAPS + "\nA new line with ALWAYS in it.\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1
    assert "history.md:5: caps" in out
    assert "history.md:3:" not in out


def test_a_record_lines_page_passes_over_its_old_lines():
    # Refuted if the commit is refused: only a clean line is added below an old bad line.
    root = make_repo( "record-lines history.md\n", { "history.md": CAPS } )
    stage( root, { "history.md": CAPS + "\nA new line that is fine.\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0, out


def test_a_record_lines_page_keeps_dates_on_its_new_lines():
    # Refuted if a new dated line is refused: a log's entries carry dates.
    root = make_repo( "record-lines history.md\n", { "history.md": CLEAN } )
    stage( root, { "history.md": CLEAN + "\nDone on 2026-10-13 for row 696b6744.\n" } )
    assert run_gate( root, "--staged" )[ 0 ] == 0


def test_an_exempt_path_is_never_refused():
    # Refuted if history/old.md is refused or counted as checked.
    root = make_repo( "exempt history/\n", {} )
    stage( root, { "history/old.md": CAPS + DATED } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0
    assert "0 pages checked" in out


def test_a_warn_path_prints_warn_and_exits_0():
    # Refuted if the exit code is 1, or no WARN line is printed for the staged bad line.
    root = make_repo( "warn .claude/\n", {} )
    stage( root, { ".claude/notes.md": CAPS } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0
    assert "WARN    .claude/notes.md:3: caps" in out
    assert "1 warned" in out and "0 refused" in out


def test_a_warn_page_is_warned_only_for_a_staged_line():
    # Refuted if the old bad line 3 is warned about.
    root = make_repo( "warn .claude/\n", { ".claude/notes.md": CAPS } )
    stage( root, { ".claude/notes.md": CAPS + "\nA new line that is fine.\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0
    assert "WARN" not in out


# ---------------------------------------------------------------- what is read

def test_the_staged_content_is_what_is_linted():
    # Refuted if the commit passes: the working tree is fixed after staging, and the staged text is still bad.
    root = make_repo( "", {} )
    stage( root, { "notes.md": CAPS } )
    write( root, "notes.md", CLEAN )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1
    assert "notes.md:3: caps" in out


def test_an_unstaged_bad_edit_does_not_refuse_a_clean_staged_page():
    # Refuted if the commit is refused: the bad text exists only in the working tree.
    root = make_repo( "", {} )
    stage( root, { "notes.md": CLEAN } )
    write( root, "notes.md", CAPS )
    assert run_gate( root, "--staged" )[ 0 ] == 0


def test_a_page_that_is_not_staged_is_not_read():
    # Refuted if the committed bad page is refused when a different page is staged.
    root = make_repo( "", { "old.md": CAPS } )
    stage( root, { "new.md": CLEAN } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0
    assert "1 pages checked" in out


def test_a_deleted_file_is_not_read():
    # Refuted if the staged deletion of a bad page is refused or reported as unreadable.
    root = make_repo( "", { "old.md": CAPS } )
    sh( root, "rm", "-q", "old.md" )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0, out
    assert "unreadable" not in out


def test_a_file_deleted_from_the_working_tree_is_not_read_in_a_whole_tree_run():
    # Refuted if the run reports "unreadable" for a tracked file that was deleted in the working tree.
    root = make_repo( "", { "old.md": CLEAN, "keep.md": CLEAN } )
    os.remove( os.path.join( root, "old.md" ) )
    code, out, _ = run_gate( root )
    assert code == 0, out
    assert "1 pages checked" in out


def test_a_name_with_a_space_and_an_accent_is_read():
    # Refuted if git's quoted spelling of the name makes the page unreadable, so the gate refuses a clean commit
    # or, worse, skips a bad one.
    root = make_repo( "", {} )
    stage( root, { "año nuevo.md": CAPS } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1
    assert "caps" in out and "unreadable" not in out


def test_a_non_markdown_file_is_not_checked():
    # Refuted if notes.txt is linted.
    root = make_repo( "", {} )
    stage( root, { "notes.txt": CAPS } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0
    assert "0 pages checked" in out


# ---------------------------------------------------------------- the merge gate's modes

def test_base_checks_the_lines_changed_since_the_base():
    # Refuted if the line added after the base is not refused, or the old line 3 of the record-lines page is.
    root = make_repo( "record-lines history.md\n", { "history.md": CAPS } )
    base = sh( root, "rev-parse", "HEAD" ).strip()
    write( root, "history.md", CAPS + "\nA new line with ALWAYS in it.\n" )
    sh( root, "add", "history.md" )
    sh( root, "commit", "-q", "--no-verify", "-m", "next" )
    code, out, _ = run_gate( root, "--base", base )
    assert code == 1
    assert "history.md:5: caps" in out
    assert "history.md:3:" not in out


def test_base_passes_when_the_range_adds_only_clean_lines():
    # Refuted if the old bad line is refused when the range did not touch it.
    root = make_repo( "record-lines history.md\n", { "history.md": CAPS } )
    base = sh( root, "rev-parse", "HEAD" ).strip()
    write( root, "history.md", CAPS + "\nA new line that is fine.\n" )
    sh( root, "add", "history.md" )
    sh( root, "commit", "-q", "--no-verify", "-m", "next" )
    assert run_gate( root, "--base", base )[ 0 ] == 0


def test_base_still_refuses_a_reference_page_the_range_did_not_touch():
    # Refuted if the untouched bad reference page passes: whole-file classes are checked in full on the merge gate.
    root = make_repo( "", { "old.md": CAPS, "other.md": CLEAN } )
    base = sh( root, "rev-parse", "HEAD" ).strip()
    write( root, "other.md", CLEAN + "\nA second line.\n" )
    sh( root, "add", "other.md" )
    sh( root, "commit", "-q", "--no-verify", "-m", "next" )
    code, out, _ = run_gate( root, "--base", base )
    assert code == 1
    assert "old.md:3: caps" in out


def test_a_whole_tree_run_leaves_the_changed_lines_classes_alone():
    # Refuted if a record-lines page with an old bad line is refused when there is no base to say which lines changed.
    root = make_repo( "record-lines history.md\n", { "history.md": CAPS } )
    assert run_gate( root )[ 0 ] == 0


def test_staged_and_base_together_are_refused():
    # Refuted if argparse accepts both flags, so one would silently win.
    root = make_repo( "", {} )
    with pytest.raises( SystemExit ) as stop: run_gate( root, "--staged", "--base", "HEAD" )
    assert stop.value.code == 2


# ---------------------------------------------------------------- review findings B1 to B4 and n1 to n3

def test_b1_a_non_ascii_name_under_a_changed_lines_class_is_checked():
    # Refuted if "0 pages checked" or exit 0: git quotes such a name as "caf\303\251.md" unless names are read with -z.
    root = make_repo( "record-lines src/docs/post-games/\n", {} )
    stage( root, { "src/docs/post-games/café.md": CAPS } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1, out
    assert "caps" in out


def test_b2_a_name_with_a_space_under_a_changed_lines_class_is_checked():
    # Refuted if "0 pages checked": the diff header keeps a tab after a name with a space, so a header-keyed range misses.
    root = make_repo( "record-lines history.md\nrecord-lines src/docs/post-games/\n", {} )
    stage( root, { "src/docs/post-games/two words.md": CAPS } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1, out
    assert "caps" in out


def test_b3_a_pure_rename_into_a_changed_lines_class_is_checked_on_every_line():
    # Refuted if the rename of a bad page into a record-lines folder passes: it has no hunks, so only a whole-page check sees it.
    root = make_repo( "exempt src/rnd/\nrecord-lines src/docs/post-games/\n", { "src/rnd/old.md": CAPS } )
    os.makedirs( os.path.join( root, "src/docs/post-games" ) )
    sh( root, "mv", "src/rnd/old.md", "src/docs/post-games/old.md" )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1, out
    assert "src/docs/post-games/old.md:3: caps" in out


def test_b3_a_rename_inside_one_changed_lines_class_keeps_its_old_lines_unchecked():
    # Refuted if the old bad line is refused: the control that shows B3 does not turn every rename into a full check.
    root = make_repo( "record-lines src/docs/post-games/\n", { "src/docs/post-games/a.md": CAPS } )
    sh( root, "mv", "src/docs/post-games/a.md", "src/docs/post-games/b.md" )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0, out


def test_b4_a_commit_cannot_loosen_the_classes_it_is_judged_by():
    # Refuted if the commit passes: it stages "exempt src/docs/" and a bad page together; HEAD's scope has no such entry.
    root = make_repo( "", {} )
    stage( root, { mg.SCOPE_PATH: "exempt src/docs/\n", "src/docs/page.md": CAPS } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1, out
    assert "NOTICE" in out and "judged by the classes in HEAD" in out


def test_b4_an_unstaged_scope_edit_does_not_loosen_a_staged_page_either():
    # Refuted if the commit passes: the working tree's scope file exempts the page, HEAD's does not.
    root = make_repo( "", {} )
    write( root, mg.SCOPE_PATH, "exempt notes.md\n" )
    stage( root, { "notes.md": CAPS } )
    assert run_gate( root, "--staged" )[ 0 ] == 1


def test_n1_a_changed_lines_page_is_not_refused_for_the_shape_of_the_whole_page():
    # Refuted if the one-line append to a runbook-named record-lines page is refused for missing sections.
    root = make_repo( "record-lines src/docs/post-games/\n", { "src/docs/post-games/runbook.md": "# Run\n\nOne line.\n" } )
    stage( root, { "src/docs/post-games/runbook.md": "# Run\n\nOne line.\n\nAnother fine line.\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0, out


def test_n2_a_folder_entry_without_its_slash_is_an_error():
    # Refuted if "history" is accepted: it matches no page, so the class would silently never apply.
    with pytest.raises( mg.ScopeError, match="slash" ): mg.parse_scope( "exempt history\n" )


def test_n3_a_staged_page_that_is_not_utf8_is_refused():
    # Refuted if the commit passes: the old staged read replaced bad bytes, the whole-tree read refused them.
    root = make_repo( "", {} )
    with open( os.path.join( root, "bad.md" ), "wb" ) as f: f.write( b"# Notes\n\nCaf\xe9 is read once.\n" )
    sh( root, "add", "bad.md" )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1, out
    assert "unreadable" in out


# ---------------------------------------------------------------- n5: same-line waivers

WAIVE_CAPS = "<!-- doc-lint: waive caps -- verbatim quote of Rick -->"


def test_n5_a_waiver_drops_its_rule_on_its_line_and_is_printed_and_counted():
    # Refuted if the commit is refused, or no WAIVED line / "1 waived" is printed.
    root = make_repo( "", {} )
    stage( root, { "notes.md": f"# Notes\n\nThe value is NEVER cached. {WAIVE_CAPS}\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0, out
    assert "WAIVED  notes.md:3: caps -- verbatim quote of Rick" in out
    assert "1 waived" in out


def test_n5_a_waiver_cannot_cover_another_rule_on_the_same_line():
    # Refuted if the iso-date finding is dropped by a waiver that names caps.
    root = make_repo( "", {} )
    stage( root, { "notes.md": f"# Notes\n\nThe value is NEVER cached on 2026-10-13. {WAIVE_CAPS}\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1
    assert "iso-date" in out and "REFUSED notes.md:3: caps" not in out


def test_n5_a_waiver_cannot_cover_another_line():
    # Refuted if the waiver on line 3 drops the caps finding on line 5.
    root = make_repo( "", {} )
    stage( root, { "notes.md": f"# Notes\n\nA fine line. {WAIVE_CAPS}\n\nThe value is NEVER cached.\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 1
    assert "REFUSED notes.md:5: caps" in out
    assert "0 waived" in out


def test_n5_a_marker_without_a_reason_word_waives_nothing():
    # Refuted if either marker, with an empty reason or a two-letter reason, drops the finding.
    for reason in ( "", "ok" ):
        root = make_repo( "", {} )
        stage( root, { "notes.md": f"# Notes\n\nThe value is NEVER cached. <!-- doc-lint: waive caps -- {reason} -->\n" } )
        code, out, _ = run_gate( root, "--staged" )
        assert code == 1, reason
        assert "0 waived" in out


def test_n5_a_waiver_on_a_line_that_has_no_finding_is_not_counted():
    # Refuted if the summary says "1 waived" for a waiver that dropped nothing.
    root = make_repo( "", {} )
    stage( root, { "notes.md": f"# Notes\n\nThe value is read once. {WAIVE_CAPS}\n" } )
    code, out, _ = run_gate( root, "--staged" )
    assert code == 0
    assert "0 waived" in out
