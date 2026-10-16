# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS command-line tool that reads all open Safari tabs via AppleScript, sends each tab's URL to a local LLM server (OpenAI-compatible chat completions API) for a short summary, and writes the results out as a Netscape-format bookmarks HTML file to the Desktop.

It's a single-file Swift package (`Sources/SafariSummary.swift`) — no test target, no other source files.

## Build & run

```bash
swift build              # debug build
swift build -c release   # release build
swift run                # build and run (debug)
.build/debug/SafariSummary    # run debug binary directly
.build/release/SafariSummary  # run release binary directly
```

There is no test suite. VS Code launch configs (`.vscode/launch.json`) exist for debug/release launches via the Swift extension.

The tool requires:
- macOS (uses `Cocoa`/`NSAppleScript` and AppleScript automation of Safari — this will not build or run on other platforms).
- Safari running with automation permission granted (System Settings → Privacy & Security → Automation) for whatever runs the binary (Terminal, VS Code, etc.).
- A local OpenAI-compatible chat completions server, by default reachable at `http://127.0.0.1:1234/v1/chat/completions` (the code targets an LM Studio-style server with model `gpt-oss-20b` by default). Without it running, every tab's summarization step fails and is skipped (the tool still produces a bookmarks file with just the summary comment omitted). Both the server URL and model name are configurable via `--server-url` and `--model`.

## Gates

Install the hooks once per clone with `Scripts/install-git-hooks.sh` (a shim, so every worktree runs its own scripts). Needs `swiftformat` and `swiftlint` (brew).

- **pre-commit** (`Scripts/pre-commit.sh`): `swiftformat` on the staged `Sources/*.swift` (re-added), then `swiftlint` (errors block, warnings don't). No test step, because there are no tests.
- **pre-push** (`Scripts/pre-push.sh`) is the real gate, about 10s: `swiftformat Sources --lint`, `swiftlint lint --strict`, `swift build` in Debug and Release, then a smoke test of the release binary (`--version` must print the version in `Sources/Version.swift`; `--help` must exit 0; neither needs Safari or an LLM server). It skips a push with no code changes, runs everything if it cannot tell what changed, and `SKIP_PREPUSH=1 git push` bypasses it once.
- **CI** (`.github/workflows/ci.yml`) is manual-only (`workflow_dispatch`): the same lint, builds and smoke test. The Claude PR review (`claude-review.yml`) runs on pull requests and needs the `CLAUDE_CODE_OAUTH_TOKEN` repo secret.
- `.swiftformat` is a rule allowlist that leaves `indent` off on purpose: it wants to re-indent the multi-line HTML template, which is the tool's output format. `.swiftlint.yml` scopes to `Sources/` (`.build/checkouts` holds a dependency), disables `trailing_comma`, allows the loop names `id`, `i`, `k`, `v`, and `run()` carries an inline `function_body_length` note.

## Release

`build-release.sh` **publishes**; there is no confirmation prompt (`PREFLIGHT_ONLY=1` is the dry run). SafariSummary is already released (v0.1.0), so unlike a pre-release app the script does everything:

1. Runs the **preflight** (`release-preflight.sh`) before anything changes: tools installed; clean tree (untracked files count), on `main`, and `main` equal to `origin/main` after a fetch (the script pushes `main`, so a release from another branch would never publish its version bump); `gh` signed in; the new version's tag doesn't exist locally or on `origin`; the tap checkout has no tracked changes; and format, strict lint, a release build and `--help`.
2. Works out the next version from conventional-commit prefixes since the last `v*` tag, edits `Sources/Version.swift`, then **commits `release: vX.Y.Z` and tags it, before building**. A failed build still leaves that commit and tag behind to undo, but the preflight's release build makes that unlikely.
3. Builds in release mode and checks `--version` against the new version.
4. **`git push origin main --tags`**, `gh release create`, then updates `Formula/safari-summary.rb` in the `homebrew-tap` repo (version, sha256 of the tag archive) and pushes it.

`PREFLIGHT_ONLY=1 ./build-release.sh` runs the preflight and stops before the version bump (nothing is changed, committed, tagged or published); `SKIP_CHECKS=1` skips only the format, lint and build gate. Tests for the git checks: `Scripts/test-release-preflight.sh`.

## Architecture

Everything lives in `Sources/SafariSummary.swift`, structured as a single linear pipeline inside `SafariSummary.main()`:

1. **Fetch tabs** — `getSafariTabs()` runs an inline AppleScript string via `NSAppleScript` to collect `{title, URL}` for every tab in every Safari window, returned as `[TabInfo]`.
2. **Summarize each tab** — for each tab, POSTs a `ChatCompletionRequest` (OpenAI chat-completions shape) to `lmServerURL` and decodes a `ChatCompletionResponse`; the summary is truncated to `summaryCharLimit` (200 chars). Failures on a single tab are logged and skipped rather than aborting the run.
3. **Build bookmarks HTML** — each tab becomes a `<DT><A>`/`<DD>` pair (Netscape bookmark format), with the summary embedded as an HTML comment under `<DD>`.
4. **Write output** — the full HTML is written to `~/Desktop/Safari_Bookmarks_<yyyyMMdd>.html`.

Configuration (server URL, model name, request timeout, summary character limit) is exposed as `@Option` properties on the `SafariSummary` struct (`--server-url`, `--model`, `--timeout`, `--summary-limit`), each with the same default it had as a hardcoded constant. Add new configuration the same way rather than reintroducing top-level constants.

Networking (`httpGet`, `httpPostJSON`) is done directly with `URLSession`, no HTTP client dependency. The only external dependency is `swift-argument-parser` (via `AsyncParsableCommand`).
