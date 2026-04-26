import SwiftUI

/// Shows a single Managed Agents investigation. While the investigation is
/// still running the view polls every 1.5s and renders the partial report
/// — useful because reports stream in chunks and we persist them
/// incrementally on the backend.
struct InvestigationDetailView: View {
    let investigationId: String
    let widgetTitle: String
    let theme: Theme

    @State private var investigation: Investigation?
    @State private var errorText: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let inv = investigation {
                    statusPill(inv: inv)
                    if let report = inv.report, !report.isEmpty {
                        reportBody(report)
                    } else if inv.status == "pending" || inv.status == "running" {
                        emptyRunning
                    } else if inv.status == "failed" {
                        failure(inv: inv)
                    }
                } else if let errorText {
                    Text(errorText)
                        .foregroundStyle(Color(hex: theme.colors.negative))
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading investigation…")
                            .foregroundStyle(Color(hex: theme.colors.secondary))
                    }
                }
            }
            .padding(20)
        }
        .background(Color(hex: theme.colors.background))
        .navigationTitle("Investigation")
        .navigationBarTitleDisplayMode(.inline)
        .task { startPolling() }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INCIDENT REPORT")
                .font(theme.secondaryFont(size: 11))
                .foregroundStyle(Color(hex: theme.colors.secondary))
            Text(widgetTitle)
                .font(theme.primaryFont(size: 24))
                .foregroundStyle(Color(hex: theme.colors.primary))
        }
    }

    @ViewBuilder
    private func statusPill(inv: Investigation) -> some View {
        let (label, color, icon) = pillInfo(for: inv.status)
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(label).font(theme.secondaryFont(size: 11))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(hex: theme.colors.surface))
                .overlay(Capsule().stroke(color, lineWidth: 1))
        )
    }

    private func pillInfo(for status: String) -> (String, Color, String) {
        switch status {
        case "pending":
            return ("Queued", Color(hex: theme.colors.secondary), "clock")
        case "running":
            return ("Claude is investigating…", Color(hex: theme.colors.accent), "sparkles")
        case "done":
            return ("Investigation complete", Color(hex: theme.colors.positive), "checkmark.seal.fill")
        case "failed":
            return ("Investigation failed", Color(hex: theme.colors.negative), "exclamationmark.triangle.fill")
        default:
            return (status, Color(hex: theme.colors.secondary), "circle")
        }
    }

    private func reportBody(_ report: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parseSections(report).enumerated()), id: \.offset) { _, section in
                sectionView(section)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: ReportSection) -> some View {
        switch section {
        case let .heading(text):
            Text(text)
                .font(theme.primaryFont(size: 18))
                .foregroundStyle(Color(hex: theme.colors.primary))
                .padding(.top, 4)
        case let .bullets(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(Color(hex: theme.colors.accent))
                        markdownText(item)
                            .foregroundStyle(Color(hex: theme.colors.primary))
                    }
                }
            }
        case let .paragraph(text):
            markdownText(text)
                .foregroundStyle(Color(hex: theme.colors.primary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func markdownText(_ s: String) -> some View {
        if let attributed = try? AttributedString(markdown: s) {
            Text(attributed)
                .font(theme.primaryFont(size: 15))
        } else {
            Text(s)
                .font(theme.primaryFont(size: 15))
        }
    }

    private var emptyRunning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Investigating in real time")
                .font(theme.primaryFont(size: 15))
                .foregroundStyle(Color(hex: theme.colors.primary))
            Text("Claude is gathering context, looking up related signals, and writing a runbook. This usually takes 30–60 seconds. The report will appear here as it's written.")
                .font(theme.secondaryFont(size: 13))
                .foregroundStyle(Color(hex: theme.colors.secondary))
        }
    }

    private func failure(inv: Investigation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Investigation could not complete.")
                .font(theme.primaryFont(size: 14))
                .foregroundStyle(Color(hex: theme.colors.negative))
            if let err = inv.error {
                Text(err)
                    .font(theme.secondaryFont(size: 12))
                    .foregroundStyle(Color(hex: theme.colors.secondary))
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            let api = APIClient()
            while !Task.isCancelled {
                do {
                    let inv = try await api.fetchInvestigation(id: investigationId)
                    investigation = inv
                    errorText = nil
                    if inv.isTerminal { return }
                } catch {
                    errorText = error.localizedDescription
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }
}

// MARK: - Tiny markdown sectioniser

private enum ReportSection {
    case heading(String)
    case bullets([String])
    case paragraph(String)
}

private func parseSections(_ markdown: String) -> [ReportSection] {
    var sections: [ReportSection] = []
    var paragraph: [String] = []
    var bullets: [String] = []

    func flushParagraph() {
        if !paragraph.isEmpty {
            sections.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }
    }
    func flushBullets() {
        if !bullets.isEmpty {
            sections.append(.bullets(bullets))
            bullets.removeAll()
        }
    }

    for rawLine in markdown.components(separatedBy: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            flushParagraph()
            flushBullets()
            continue
        }
        if line.hasPrefix("##") {
            flushParagraph(); flushBullets()
            sections.append(.heading(line.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)))
            continue
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            flushParagraph()
            bullets.append(String(line.dropFirst(2)))
            continue
        }
        flushBullets()
        paragraph.append(line)
    }
    flushParagraph()
    flushBullets()
    return sections
}
