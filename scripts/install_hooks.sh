#!/bin/sh
# Install this repository's git hooks. Safe to re-run.
#
#   sh scripts/install_hooks.sh
#
# Hooks are not version-controlled by git itself, so this has to be run once per clone.
# It copies rather than symlinks: Windows clones without developer mode cannot follow a
# symlink in .git/hooks, and the failure is silent - the hook simply never runs.

set -e
root=$(git rev-parse --show-toplevel)
for h in pre-commit; do
    src="$root/scripts/$h"
    dst="$root/.git/hooks/$h"
    [ -f "$src" ] || { echo "install_hooks: missing $src"; exit 1; }
    if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
        cp "$dst" "$dst.bak"
        echo "  existing $h backed up to $h.bak"
    fi
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "  installed $h"
done
echo "done. Verify with: python scripts/check_docs.py"
