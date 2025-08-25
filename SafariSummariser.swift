//
//  SafariSummariser.swift
//  macOS 15.6 – Safari tab summariser to HTML bookmark file
//

import Foundation

// MARK: - Data Models

struct TabInfo: Codable {
    let id: Int
    let title: String
    let url: String
}

struct WindowTabs: Codable {
    let windows: [Window]
    struct Window: Codable {
        let id: Int
        let tabs: [TabInfo]
    }
}

struct SummariseRequest: Encodable {
    let model: String
    let prompt: String
}

struct SummariseResponse: Decodable {
    let summary: String
}

struct SafariSummariser {
    // MARK: - Configuration

    static let safariDriverURL = URL(string: "http://localhost:4444")!
    static let lmServerURL   = URL(string: "http://127.0.0.1:1234/summarise")!

    // Timeout values (seconds)
    static let driverTimeout  = 10.0
    static let apiTimeout     = 30.0

    // Summary length limit (characters)
    static let summaryCharLimit = 200

    // MARK: - Helper Functions

    static func httpGet(url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    static func httpPostJSON<T: Encodable>(url: URL, body: T, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    static func escapeHTML(_ string: String) -> String {
        var escaped = string
        let replaceMap: [String: String] = [
            "&": "&amp;",
            "<": "&lt;",
            ">": "&gt;",
            "\"": "&quot;"
        ]
        for (k, v) in replaceMap { escaped = escaped.replacingOccurrences(of: k, with: v) }
        return escaped
    }

    static func truncate(_ string: String, limit: Int) -> String {
        guard string.count > limit else { return string }
        let idx = string.index(string.startIndex, offsetBy: limit)
        return String(string[..<idx]) + "…"
    }

    // MARK: - Main Workflow

    static func main() async {
        print("🕵️  Starting Safari summariser…")

        // 1️⃣ Get all windows & tabs from SafariDriver
        guard let windowData = try? await httpGet(url: safariDriverURL.appendingPathComponent("/sessions"), timeout: driverTimeout) else {
            fputs("❌ Failed to contact SafariDriver. Ensure it is running.\n", stderr)
            exit(1)
        }

        let tmp = try? JSONSerialization.jsonObject(with: windowData)
        print(tmp)

        // SafariDriver returns a session list; we need the first active session
        guard let sessions = try? JSONSerialization.jsonObject(with: windowData) as? [[String: Any]],
              let sessionId = sessions.first?["id"] as? String else {
            fputs("❌ No active Safari session found.\n", stderr)
            exit(1)
        }

        // List windows
        guard let windowsData = try? await httpGet(url: safariDriverURL.appendingPathComponent("/session/\(sessionId)/window"), timeout: driverTimeout) else {
            fputs("❌ Failed to get window list from SafariDriver.\n", stderr)
            exit(1)
        }

        // Parse windows and tabs
        guard let windowsResp = try? JSONSerialization.jsonObject(with: windowsData) as? [String: Any],
              let value = windowsResp["value"] as? [Any] else {
            fputs("❌ Unexpected window response format.\n", stderr)
            exit(1)
        }

        var allTabs: [(windowId: Int, tab: TabInfo)] = []

        for (idx, win) in value.enumerated() {
            guard let tabsArray = win as? [[String: Any]] else { continue }
            for tabDict in tabsArray {
                if let id = tabDict["id"] as? Int,
                   let title = tabDict["title"] as? String,
                   let urlStr = tabDict["url"] as? String {
                    allTabs.append((windowId: idx + 1, tab: TabInfo(id: id, title: title, url: urlStr)))
                }
            }
        }

        print("📄 Found \(allTabs.count) tabs across \(value.count) windows.")

        // 2️⃣ Process each tab
        var bookmarkEntries: [String] = []

        let decoder = JSONDecoder()

        for (idx, entry) in allTabs.enumerated() {
            let tab = entry.tab
            print("\(idx + 1)/\(allTabs.count): Summarising '\(tab.title)'")

            // Fetch page source via SafariDriver
            guard let srcData = try? await httpGet(url: safariDriverURL.appendingPathComponent("/session/\(sessionId)/source"), timeout: driverTimeout),
                  let pageSource = String(data: srcData, encoding: .utf8) else {
                print("⚠️  Could not retrieve source for tab \(tab.id). Skipping.")
                continue
            }

            // Call LM Server API
            let reqBody = SummariseRequest(model: "gpt-oss-20b", prompt: pageSource)
            guard let apiData = try? await httpPostJSON(url: lmServerURL, body: reqBody, timeout: apiTimeout),
                  let summaryResp = try? decoder.decode(SummariseResponse.self, from: apiData) else {
                print("⚠️  Summarisation API failed for tab \(tab.id). Skipping.")
                continue
            }

            let summaryText = truncate(summaryResp.summary, limit: summaryCharLimit)

            // Build bookmark <dt>/<dd> pair
            let entryHTML =
"""
<DT><A HREF="\(escapeHTML(tab.url))" ADD_DATE="\(Int(Date().timeIntervalSince1970))" LAST_MODIFIED="\(Int(Date().timeIntervalSince1970))">\(escapeHTML(tab.title))</A>
<DD><!-- Summary: \(escapeHTML(summaryText)) -->
"""
            bookmarkEntries.append(entryHTML)
        }

        // 3️⃣ Build final HTML
        let header = """
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- This is an automatically generated file.
     It will be read and overwritten by the application that created it. -->
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Safari Bookmarks</TITLE>
<H1>Bookmarks – Auto‑generated by SafariSummariser</H1>

<DL><p>
"""
        let footer = """
</DL><p>
"""

        let fullHTML = header + bookmarkEntries.joined(separator: "\n") + "\n" + footer

        // 4️⃣ Write to Desktop
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let fileName = "Safari_Bookmarks_\(dateFormatter.string(from: Date())).html"
        let fileURL = desktopURL.appendingPathComponent(fileName)

        do {
            try fullHTML.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ Bookmark file written to \(fileURL.path)")
        } catch {
            fputs("❌ Failed to write bookmark file: \(error)\n", stderr)
            exit(1)
        }
    }
}

await SafariSummariser.main()
