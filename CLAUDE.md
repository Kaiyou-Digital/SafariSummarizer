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

## Architecture

Everything lives in `Sources/SafariSummary.swift`, structured as a single linear pipeline inside `SafariSummary.main()`:

1. **Fetch tabs** — `getSafariTabs()` runs an inline AppleScript string via `NSAppleScript` to collect `{title, URL}` for every tab in every Safari window, returned as `[TabInfo]`.
2. **Summarize each tab** — for each tab, POSTs a `ChatCompletionRequest` (OpenAI chat-completions shape) to `lmServerURL` and decodes a `ChatCompletionResponse`; the summary is truncated to `summaryCharLimit` (200 chars). Failures on a single tab are logged and skipped rather than aborting the run.
3. **Build bookmarks HTML** — each tab becomes a `<DT><A>`/`<DD>` pair (Netscape bookmark format), with the summary embedded as an HTML comment under `<DD>`.
4. **Write output** — the full HTML is written to `~/Desktop/Safari_Bookmarks_<yyyyMMdd>.html`.

Configuration (server URL, model name, request timeout, summary character limit) is exposed as `@Option` properties on the `SafariSummary` struct (`--server-url`, `--model`, `--timeout`, `--summary-limit`), each with the same default it had as a hardcoded constant. Add new configuration the same way rather than reintroducing top-level constants.

Networking (`httpGet`, `httpPostJSON`) is done directly with `URLSession`, no HTTP client dependency. The only external dependency is `swift-argument-parser` (via `AsyncParsableCommand`).
