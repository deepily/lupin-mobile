#!/usr/bin/env python3
"""
Entry point for the vendored markdown linter: python3 tool/lint_markdown.py [--json] [--strict] [--staged] [paths]

Needs no lupin checkout and no LUPIN_ROOT; the word list lives in tool/data/.
"""

import os
import sys

sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )

from doc_lint.md_lint import main

if __name__ == "__main__":
    sys.exit( main() )
