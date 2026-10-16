#!/bin/bash
# Checks that build-release.sh runs BEFORE it changes anything: before the version bump, the release commit and the
# tag. Sourced, never run directly. Each check stops with a message that says what to do.
#
# Why: the release publishes (git push of main and the tag, a GitHub release, the Homebrew formula), and it used to
# commit and tag before building, so a failed build left a stranded release commit and tag.
#
# Tested by Scripts/test-release-preflight.sh (the git checks, in throwaway repos). The gate is exercised by
# running: PREFLIGHT_ONLY=1 ./build-release.sh

pf_die() {
    echo "Preflight failed: $*" >&2
    exit 1
}

pf_step() {
    echo "==> Preflight: $*"
}

# preflight_tools TOOL...: every tool the release uses is on PATH.
preflight_tools() {
    local t
    for t in "$@"; do
        command -v "$t" > /dev/null 2>&1 || pf_die "$t is not installed or not on PATH"
    done
}

# gh is signed in (the release is created with it).
preflight_credentials() {
    pf_step "GitHub login"
    gh auth status > /dev/null 2>&1 || pf_die "gh is not signed in (run: gh auth login)"
}

# Is this exactly the code that is published? Run from the repo root.
# The release always pushes `main`, so it must be run from main: from another branch the version bump would be
# committed there and never published. A clean tree counts untracked files too.
preflight_repo_state() {
    pf_step "repository state"
    [[ -z "$(git status --porcelain)" ]] \
        || pf_die "the working tree is not clean (uncommitted or untracked files); commit, stash or remove them first"
    [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] \
        || pf_die "release from main (the script pushes main, so a version bump on another branch would never be published)"
    git fetch --quiet --tags origin || pf_die "couldn't reach origin to compare"
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse --verify --quiet refs/remotes/origin/main)" ]] \
        || pf_die "main is not the same as origin/main; push or pull first so the release doesn't publish stray commits"
}

# preflight_tag vX.Y.Z: the tag the release is about to create doesn't exist yet, here or on origin.
preflight_tag() {
    local tag="$1"
    pf_step "tag ${tag}"
    git rev-parse -q --verify "refs/tags/${tag}" > /dev/null && pf_die "the tag ${tag} already exists locally"
    [[ -z "$(git ls-remote --tags origin "refs/tags/${tag}")" ]] || pf_die "the tag ${tag} already exists on origin"
    return 0
}

# preflight_tap DIR FORMULA_FILE: the Homebrew tap checkout can be updated. Tracked changes would break the push that
# runs after the release is already published; untracked files (.DS_Store) are fine.
preflight_tap() {
    local dir="$1" formula="$2"
    [[ -f "$formula" ]] || return 0 # the script itself warns and skips when the formula is missing
    pf_step "Homebrew tap checkout"
    [[ -z "$(git -C "$dir" status --porcelain --untracked-files=no)" ]] \
        || pf_die "the tap repo at ${dir} has uncommitted changes to tracked files; the release would stop after publishing"
}

# The same checks as Scripts/pre-push.sh, before anything changes. SKIP_CHECKS=1 skips them (not recommended).
preflight_gate() {
    if [[ "${SKIP_CHECKS:-}" == "1" ]]; then
        echo "!!  SKIP_CHECKS=1: not running the format, lint and build gate"
        return 0
    fi
    pf_step "format, lint, release build and --help (SKIP_CHECKS=1 skips)"
    swiftformat Sources --lint > /dev/null 2>&1 || pf_die "swiftformat --lint found problems; run: swiftformat Sources"
    swiftlint lint --strict --quiet > /dev/null 2>&1 || pf_die "swiftlint --strict found problems; run: swiftlint lint --strict"
    swift build -c release > /dev/null 2>&1 || pf_die "swift build -c release failed; run it to see the errors"
    .build/release/SafariSummary --help > /dev/null 2>&1 || pf_die "the built binary fails on --help"
}
