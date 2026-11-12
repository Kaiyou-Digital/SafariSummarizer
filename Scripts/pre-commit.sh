#!/bin/bash
# Pre-commit: auto-format staged Swift files under Sources/ and block on SwiftLint errors (not warnings; the
# pre-push gate runs lint with --strict for those).
#
# No test step: this package has no tests. The compile and smoke checks live in Scripts/pre-push.sh.
#
# A file with unstaged changes on top of its staged ones is refused: formatting re-adds whole files, so
# those changes would be committed too.
#
# Written for macOS's stock /bin/bash 3.2: no mapfile, NUL-delimited reads instead.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

swift_files=()
while IFS= read -r -d '' file; do
  case "$file" in
    Sources/*.swift) [ -f "$file" ] && swift_files+=("$file") ;;
  esac
done < <(git diff --cached --name-only --diff-filter=ACMR -z)

if [ "${#swift_files[@]}" -eq 0 ]; then
  exit 0
fi

for tool in swiftformat swiftlint; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "pre-commit: $tool not found. Install it with 'brew install $tool'" >&2
    exit 1
  fi
done

# Formatting re-adds whole files, so a partly staged file would have its unstaged hunks committed too.
# Refuse rather than quietly commit work the author left out on purpose.
partly_staged=()
for file in "${swift_files[@]}"; do
    git diff --quiet -- "$file" || partly_staged+=("$file")
done
if [ "${#partly_staged[@]}" -gt 0 ]; then
    echo "pre-commit: these files have unstaged changes on top of the staged ones, and formatting would add them to the commit:" >&2
    printf '  %s\n' "${partly_staged[@]}" >&2
    echo "pre-commit: stage the whole file (git add <file>), or put the unstaged part aside first, then commit again." >&2
    exit 1
fi

echo "pre-commit: formatting ${#swift_files[@]} staged Swift file(s)..."
swiftformat --quiet "${swift_files[@]}"
git add "${swift_files[@]}"

# Non-strict SwiftLint exits non-zero only for errors, so its exit status is the whole check. --force-exclude applies the
# config's `excluded` list to files named explicitly; if every file is excluded SwiftLint says so and exits 1, which is
# a pass here.
echo "pre-commit: linting staged Swift file(s)..."
lint_log="$(mktemp)"
if ! swiftlint lint --quiet --force-exclude "${swift_files[@]}" > "$lint_log" 2>&1; then
  if grep -q "No lintable files found" "$lint_log"; then
    :
  else
    cat "$lint_log" >&2
    rm -f "$lint_log"
    echo "pre-commit: blocked, SwiftLint errors above. Fix them, or if one is a false positive, adjust" \
      ".swiftlint.yml with a comment explaining why rather than committing around it." >&2
    exit 1
  fi
fi
rm -f "$lint_log"

echo "pre-commit: all checks passed."
