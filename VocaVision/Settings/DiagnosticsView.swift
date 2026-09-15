import SwiftUI
import UIKit

/// Live in-app log viewer + share sheet.
///
/// Use this from the device when something goes wrong: scroll through
/// recent events, copy the text, or AirDrop / email the full log file
/// straight from the share sheet.
@MainActor
struct DiagnosticsView: View {
    @State private var log = DiagnosticsLog.shared
    @State private var didCopy = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                actionsBar
                Divider()
                logScroll
            }
        }
        .navigationTitle(tr(ar: "سجلّ التشخيص", en: "Diagnostics log"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    log.clear()
                    announce(tr(ar: "تمّ مسح السجلّ", en: "Log cleared"))
                } label: {
                    Label(tr(ar: "مسح السجلّ", en: "Clear log"), systemImage: "trash")
                }
            }
        }
    }

    // MARK: Header actions

    private var actionsBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button {
                UIPasteboard.general.string = log.snapshotText()
                didCopy = true
                announce(tr(ar: "تمّ نسخ السجلّ", en: "Log copied"))
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    didCopy = false
                }
            } label: {
                Label(
                    didCopy
                        ? tr(ar: "تمّ النسخ", en: "Copied")
                        : tr(ar: "نسخ", en: "Copy"),
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .accessibilityHint(tr(
                ar: "ينسخ كامل السجلّ إلى الحافظة",
                en: "Copies the full log to the clipboard"
            ))

            ShareLink(item: log.fileURL) {
                Label(tr(ar: "مشاركة الملفّ", en: "Share file"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .accessibilityHint(tr(
                ar: "يفتح ورقة المشاركة لإرسال ملفّ السجلّ",
                en: "Opens the share sheet to send the log file"
            ))
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var background: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
    }

    // MARK: Log feed

    private var logScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if log.entries.isEmpty {
                    emptyState
                } else {
                    ForEach(log.entries) { entry in
                        LogRow(entry: entry)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .environment(\.layoutDirection, .leftToRight) // keep timestamps readable
        }
        .defaultScrollAnchor(.bottom)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(tr(
                ar: "لا توجد سجلّات بعد. ابدأ مكالمة وستظهر هنا الأحداث.",
                en: "No log entries yet. Start a call and events will appear here."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

private struct LogRow: View {
    let entry: DiagnosticsLog.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.rawValue)
                .font(.system(size: 14))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.timeString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("[\(entry.category)]")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(categoryColor)
                }
                Text(entry.message)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(rowBackground, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.formatted)
    }

    private var categoryColor: Color {
        switch entry.category {
        case "live":      return .blue
        case "audio":     return .purple
        case "camera":    return .orange
        case "perm":      return .yellow
        case "session":   return .teal
        case "call":      return .green
        case "socket":    return .indigo
        default:          return .secondary
        }
    }

    private var rowBackground: Color {
        switch entry.level {
        case .error:   return Color.red.opacity(0.10)
        case .warning: return Color.yellow.opacity(0.10)
        default:       return Color(.secondarySystemBackground)
        }
    }
}

