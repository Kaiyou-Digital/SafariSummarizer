# SafariSummary

A macOS command-line tool that reads every open Safari tab, summarizes each one using a local LLM, and writes the results out as a bookmarks file you can import back into Safari (or any browser).

## What it does

1. Asks Safari (via AppleScript) for the title and URL of every tab in every window.
2. Sends each URL to a local OpenAI-compatible chat completions server for a short summary.
3. Builds a Netscape-format bookmarks HTML file, with each tab's summary embedded as a comment.
4. Writes the file to your Desktop as `Safari_Bookmarks_<yyyyMMdd>.html`.

Tabs that fail to summarize (e.g. the LLM server is down) are skipped rather than aborting the whole run.

## Requirements

- macOS, with Safari running.
- Automation permission granted to whatever runs the binary (Terminal, VS Code, etc.) under **System Settings → Privacy & Security → Automation**, so it can script Safari.
- A local OpenAI-compatible chat completions server (e.g. [LM Studio](https://lmstudio.ai)), by default expected at `http://127.0.0.1:1234/v1/chat/completions` serving a model named `gpt-oss-20b`. Without it, tabs will fail to summarize and be skipped.

## Build & run

```bash
swift build              # debug build
swift run                # build and run (debug)
swift build -c release   # release build
.build/release/SafariSummary   # run the release binary directly
```

## Options

```
--server-url <url>        URL of the OpenAI-compatible chat completions endpoint
                          (default: http://127.0.0.1:1234/v1/chat/completions)
--model <name>            Model name to request from the summarization server
                          (default: gpt-oss-20b)
--timeout <seconds>       Request timeout in seconds (default: 30.0)
--summary-limit <chars>   Maximum length of each summary, in characters (default: 200)
```

## License

MIT — see [LICENSE](LICENSE).
