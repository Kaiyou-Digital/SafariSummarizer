#!/bin/bash
# Pre-push gate: the work CI would do, run locally (the CI workflow is manual-only to save macOS runner minutes).
#
#   - swiftformat --lint and swiftlint --strict over the whole repo
#   - swift build in Debug AND Release. There are no tests, so a compile is the safety net, and Debug and Release are
#     genuinely different builds
#   - a smoke test of the built binary: `--version` must print the version in Sources/Version.swift and `--help` must
#     exit 0. Neither needs Safari or an LLM server.
#
# Skips itself when the push touches no code. Fails closed: if it cannot work out what changed, it runs everything.
# Bypass once with SKIP_PREPUSH=1 git push (cleaner than --no-verify, which would skip every hook).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ "${SKIP_PREPUSH:-}" = "1" ]; then
  echo "pre-push: skipped (SKIP_PREPUSH=1)"
  exit 0
fi

# The default branch, never hardcoded.
default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2> /dev/null || true)"
default_branch="${default_branch:-origin/main}"

zero=0000000000000000000000000000000000000000
pushed=0
code_changed=0
while read -r _ local_sha _ remote_sha; do
  [ "$local_sha" = "$zero" ] && continue # branch deletion
  pushed=1
  base="$remote_sha"
  if [ "$base" = "$zero" ]; then
    base="$(git merge-base "$default_branch" "$local_sha" 2> /dev/null || true)"
  fi
  # Fail closed: if we cannot work out what changed, run the checks rather than skip them.
  if [ -z "$base" ] || ! git cat-file -e "$base^{commit}" 2> /dev/null; then
    code_changed=1
    continue
  fi
  if ! changed="$(git diff --name-only "$base..$local_sha" 2> /dev/null)"; then
    code_changed=1
    continue
  fi
  # Here-string, not printf | grep -q: under pipefail, grep -q exiting early can SIGPIPE the printf.
  if grep -qE '^(Sources/|Package\.swift|Package\.resolved|\.swiftlint|\.swiftformat)' <<< "$changed"; then
    code_changed=1
  fi
done

if [ "$pushed" -eq 0 ]; then
  echo "pre-push: only deleting refs, nothing to check"
  exit 0
fi

if [ "$code_changed" -eq 0 ]; then
  echo "pre-push: no code changes in this push, skipping checks"
  exit 0
fi

for tool in swiftformat swiftlint; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "pre-push: $tool not found. Install it with 'brew install $tool'" >&2
    exit 1
  fi
done

run_logged() {
  local label="$1"
  shift
  local log_file
  log_file="$(mktemp)"
  echo "pre-push: $label"
  if ! "$@" > "$log_file" 2>&1; then
    echo "pre-push: $label FAILED:" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit 1
  fi
  rm -f "$log_file"
}

run_logged "swiftformat --lint" swiftformat Sources --lint
run_logged "swiftlint --strict" swiftlint lint --strict --quiet
run_logged "swift build (debug)" swift build
run_logged "swift build (release)" swift build -c release

binary=".build/release/SafariSummary"
expected="$(sed -n 's/^let safariSummaryVersion = "\(.*\)"/\1/p' Sources/Version.swift)"
actual="$("$binary" --version 2> /dev/null || true)"
if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
  echo "pre-push: smoke test FAILED: --version printed '${actual}', Sources/Version.swift says '${expected}'" >&2
  exit 1
fi
run_logged "smoke test: --help" "$binary" --help

echo "pre-push: all checks passed."
