#!/bin/bash
# Tests for release-preflight.sh (the git-state, tag and tap checks) in throwaway repos with a bare origin.
# The gate needs Swift, SwiftFormat and SwiftLint; run it with: PREFLIGHT_ONLY=1 ./build-release.sh
# Run: Scripts/test-release-preflight.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="${HERE}/../release-preflight.sh"
TOP="$(mktemp -d)"
trap 'rm -rf "${TOP}"' EXIT
FAILS=0
N=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; FAILS=$((FAILS + 1)); fi; }

# A fresh repo with one commit on main, pushed to a bare origin.
fresh() {
    N=$((N + 1))
    R="${TOP}/r${N}"
    O="${TOP}/o${N}.git"
    git init -q --bare "${O}"
    git init -q -b main "${R}"
    git -C "${R}" config user.email t@t
    git -C "${R}" config user.name t
    git -C "${R}" config commit.gpgsign false
    git -C "${R}" config tag.gpgsign false
    echo one > "${R}/a.txt"
    git -C "${R}" add -A
    git -C "${R}" commit -qm init
    git -C "${R}" remote add origin "${O}"
    git -C "${R}" push -q origin main
}
# run FUNCTION [ARGS]: runs a preflight function inside the repo R; sets OUT and CODE.
run() {
    OUT="$(cd "${R}" && source "${PREFLIGHT}" && "$@" 2>&1)"
    CODE=$?
}

fresh; run preflight_repo_state
check "a clean main in sync with origin passes" '[ "${CODE}" = 0 ]'

fresh; echo x > "${R}/untracked.txt"; run preflight_repo_state
check "an untracked file refuses" '[ "${CODE}" != 0 ] && [[ "${OUT}" == *"not clean"* ]]'

fresh; echo two >> "${R}/a.txt"; run preflight_repo_state
check "a modified tracked file refuses" '[ "${CODE}" != 0 ] && [[ "${OUT}" == *"not clean"* ]]'

fresh; git -C "${R}" commit -q --allow-empty -m "local only"; run preflight_repo_state
check "main ahead of origin/main refuses" '[ "${CODE}" != 0 ] && [[ "${OUT}" == *"origin/main"* ]]'

fresh
git clone -q "${O}" "${TOP}/other${N}"
git -C "${TOP}/other${N}" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m elsewhere
git -C "${TOP}/other${N}" push -q origin main
run preflight_repo_state
check "main behind origin/main refuses" '[ "${CODE}" != 0 ] && [[ "${OUT}" == *"origin/main"* ]]'

# Unlike remarka, this script pushes main whatever branch you are on, so a feature-branch release is refused.
fresh; git -C "${R}" switch -q -c feature; run preflight_repo_state
check "releasing from a feature branch refuses" '[ "${CODE}" != 0 ] && [[ "${OUT}" == *"release from main"* ]]'

fresh; git -C "${R}" remote set-url origin "${TOP}/nowhere.git"; run preflight_repo_state
check "an unreachable origin refuses" '[ "${CODE}" != 0 ] && [[ "${OUT}" == *"reach origin"* ]]'

fresh; run preflight_tag v1.0.0
check "an unused tag passes" '[ "${CODE}" = 0 ]'

fresh; git -C "${R}" tag v1.0.0; run preflight_tag v1.0.0
check "a tag that exists locally refuses" '[ "${CODE}" != 0 ] && [[ "${OUT}" == *"locally"* ]]'

fresh; git -C "${R}" tag v1.0.0; git -C "${R}" push -q origin v1.0.0; git -C "${R}" tag -d v1.0.0 > /dev/null; run preflight_tag v1.0.0
check "a tag that exists only on origin refuses" '[ "${CODE}" != 0 ] && [[ "${OUT}" == *"origin"* ]]'

# Tap checkout: tracked changes refuse; untracked files (.DS_Store) do not; a missing formula skips the check.
fresh; mkdir -p "${R}/Formula"; echo formula > "${R}/Formula/safari-summary.rb"; git -C "${R}" add -A; git -C "${R}" commit -qm formula
run preflight_tap "${R}" "${R}/Formula/safari-summary.rb"
check "a clean tap passes" '[ "${CODE}" = 0 ]'

echo more >> "${R}/Formula/safari-summary.rb"; run preflight_tap "${R}" "${R}/Formula/safari-summary.rb"
check "a tap with a tracked change refuses" '[ "${CODE}" != 0 ] && [[ "${OUT}" == *"tracked files"* ]]'

fresh; mkdir -p "${R}/Formula"; echo formula > "${R}/Formula/safari-summary.rb"; git -C "${R}" add -A; git -C "${R}" commit -qm formula
touch "${R}/.DS_Store"; run preflight_tap "${R}" "${R}/Formula/safari-summary.rb"
check "an untracked .DS_Store in the tap is ignored" '[ "${CODE}" = 0 ]'

fresh; run preflight_tap "${R}" "${R}/Formula/missing.rb"
check "a missing formula skips the tap check" '[ "${CODE}" = 0 ]'

[ "${FAILS}" = 0 ] && echo "all passed" || {
    echo "${FAILS} failed"
    exit 1
}
