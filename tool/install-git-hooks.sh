#!/bin/bash
# Point this repo's git at the committed hooks in tool/hooks (shared by every worktree).
# Usage: tool/install-git-hooks.sh            install
#        tool/install-git-hooks.sh --uninstall  remove
set -e
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
if [ "$1" = "--uninstall" ]; then
    git config --unset core.hooksPath || true
    echo "pre-commit hook removed"
    exit 0
fi
chmod +x tool/hooks/pre-commit tool/pre_commit_gate.py
git config core.hooksPath tool/hooks
echo "pre-commit hook installed: core.hooksPath = tool/hooks"
echo "swept directories the hook analyzes:"
python3 tool/pre_commit_gate.py --list | sed 's/^/  /'
