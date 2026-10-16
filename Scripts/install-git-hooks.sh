#!/bin/bash
# Run once per clone: ./Scripts/install-git-hooks.sh. Installs the
# pre-commit and pre-push hooks. .git/hooks isn't tracked by git, so the
# hooks live in Scripts/ and this puts a small shim in .git/hooks that
# runs them.
#
# A shim, not a symlink. The old absolute symlink broke silently when the
# repo folder was renamed (git skips a hook it can't find), and a relative one from the shared .git/hooks would resolve to
# the main checkout's Scripts/ even when the hook fires in a worktree. The
# shim runs Scripts/<hook>.sh from whichever checkout or worktree the hook
# fires in, so every branch runs its own version.
set -euo pipefail

hooks_dir="$(git rev-parse --path-format=absolute --git-common-dir)/hooks"
mkdir -p "$hooks_dir"

for hook in pre-commit pre-push; do
  # Remove first: writing to an existing symlink would write through it.
  rm -f "$hooks_dir/$hook"
  cat > "$hooks_dir/$hook" <<EOF
#!/bin/sh
# Installed by Scripts/install-git-hooks.sh. Runs Scripts/$hook.sh from
# the checkout or worktree this hook fired in.
script="\$(git rev-parse --show-toplevel)/Scripts/$hook.sh"
if [ ! -x "\$script" ]; then
  echo "$hook: no Scripts/$hook.sh on this branch, skipping" >&2
  exit 0
fi
exec "\$script" "\$@"
EOF
  chmod +x "$hooks_dir/$hook"
  echo "Installed $hook hook -> Scripts/$hook.sh"
done
