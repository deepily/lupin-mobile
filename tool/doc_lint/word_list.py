"""
The English word list behind the ALL-CAPS predicate (rule 4).

An ALL-CAPS token is emphasis when its lowercase form is a word. This vendored copy reads the
list from tool/data/ in this repository, never from the tree being linted and never from a
lupin checkout. Lupin's original calls configure_root with the linted tree; that call is gone.
"""

import os

WORD_LIST_PATH = os.path.join( os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) ), "data", "dm-tutor-lowercase-words.txt" )

_state = { "words": None }


def load_words( path ):
    """
    Read a word list, one lowercase word per line.

    Requires:
        - path names a UTF-8 text file

    Ensures:
        - returns a frozenset of the non-blank stripped lines

    Raises:
        - OSError when the file cannot be read; an unreadable list must not silently turn rule 4 off
    """
    with open( path, encoding="utf-8" ) as handle:
        return frozenset( line.strip() for line in handle if line.strip() )


def default_words():
    """
    Return the word list, read once per process.

    Requires:
        - WORD_LIST_PATH exists (tool/data/dm-tutor-lowercase-words.txt)

    Ensures:
        - returns a frozenset of lowercase words
        - later calls return the same object

    Raises:
        - OSError when the list is missing
    """
    if _state[ "words" ] is None: _state[ "words" ] = load_words( WORD_LIST_PATH )
    return _state[ "words" ]
