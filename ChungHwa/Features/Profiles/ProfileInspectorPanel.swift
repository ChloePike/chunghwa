import SwiftUI
import AppKit

/// Read/edit YAML for one profile. Pushed save triggers a kernel reload when
/// the profile is the active one.
struct ProfileInspectorSheet: View {
    let profile: Profile
    let yaml: String?
    let yamlURL: URL
    let onClose: () -> Void

    @Environment(ProfileStore.self) private var store
    @Environment(KernelController.self) private var kernel

    @State private var copyHint: String?
    @State private var isEditing: Bool = false
    @State private var editedContent: String = ""
    @State private var displayContent: String?
    @State private var highlighted: AttributedString?
    /// Past ~100KB the per-line `out.append` path hits an O(N²) wall in
    /// AttributedString and freezes the main thread.
    private let highlightCap = 100_000
    @State private var saveStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            Divider().background(ChungHwa.Palette.lineSoft)
            sourceLine
            bodyArea
            footerLine
            Divider().background(ChungHwa.Palette.lineSoft)
            bottomButtons
        }
        .frame(minWidth: 720, idealWidth: 720, minHeight: 600, idealHeight: 600)
        .background(ChungHwa.Palette.card)
        .onAppear {
            displayContent = yaml
            editedContent = yaml ?? ""
        }
        .task(id: displayContent ?? "") {
            await rehighlight()
        }
    }

    private func rehighlight() async {
        guard let content = displayContent, !content.isEmpty else {
            highlighted = nil
            return
        }
        if content.utf8.count > highlightCap {
            highlighted = nil
            return
        }
        let attr = await Task.detached(priority: .userInitiated) {
            YAMLHighlighter.highlight(content)
        }.value
        // Only commit if displayContent didn't change underneath us.
        if displayContent == content {
            highlighted = attr
        }
    }

    private var titleBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(profile.name)
                .font(ChungHwa.Typography.serif(18, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)
                .tracking(-0.2)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(ChungHwa.Palette.pillBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sourceLine: some View {
        HStack(spacing: 6) {
            Text(sourceTag)
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.dim)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(
                    Capsule().fill(ChungHwa.Palette.fill)
                )
                .overlay(
                    Capsule().strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
                )
            Spacer(minLength: 0)
            if let saveStatus {
                Text(saveStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.brass)
                    .transition(.opacity)
            }
            if let copyHint {
                Text(copyHint)
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.patina)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var sourceTag: String {
        switch profile.source {
        case .file:
            return "本地文件"
        case .url(let url):
            return url.host ?? url.absoluteString
        }
    }

    @ViewBuilder
    private var bodyArea: some View {
        if isEditing {
            // TextEditor doesn't support AttributedString styling — edit mode
            // loses the highlight; we keep mono font + soft card to minimise
            // visual change.
            TextEditor(text: $editedContent)
                .font(ChungHwa.Typography.mono(11))
                .foregroundStyle(ChungHwa.Palette.text)
                .scrollContentBackground(.hidden)
                .background(ChungHwa.Palette.cardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
                )
                .padding(.horizontal, 18)
        } else if let displayContent {
            ScrollView([.vertical, .horizontal]) {
                Group {
                    if let highlighted {
                        Text(highlighted)
                    } else {
                        // Highlighter still running, or file is past the cap.
                        Text(displayContent)
                            .foregroundStyle(ChungHwa.Palette.text)
                    }
                }
                .textSelection(.enabled)
                .font(ChungHwa.Typography.mono(11))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .background(ChungHwa.Palette.cardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
            )
            .padding(.horizontal, 18)
        } else {
            ScrollView {
                Text("找不到 \(yamlURL.path)")
                    .font(ChungHwa.Typography.mono(11))
                    .foregroundStyle(ChungHwa.Palette.earth)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(ChungHwa.Palette.cardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ChungHwa.Palette.lineSoft, lineWidth: 0.5)
            )
            .padding(.horizontal, 18)
        }
    }

    private var footerSource: String? {
        isEditing ? editedContent : displayContent
    }

    private var footerLine: some View {
        HStack(spacing: 10) {
            if let s = footerSource {
                Text("\(s.utf8.count) 字节")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .monospacedDigit()
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.faint)
                Text("\(lineCount(s)) 行")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.dim)
                    .monospacedDigit()
            } else {
                Text("空文件")
                    .font(.system(size: 11))
                    .foregroundStyle(ChungHwa.Palette.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func lineCount(_ s: String) -> Int {
        if s.isEmpty { return 0 }
        var n = 1
        for c in s where c == "\n" { n += 1 }
        if s.hasSuffix("\n") { n -= 1 }
        return max(n, 1)
    }

    @ViewBuilder
    private var bottomButtons: some View {
        if isEditing {
            editModeButtons
        } else {
            readModeButtons
        }
    }

    private var readModeButtons: some View {
        HStack(spacing: 8) {
            sheetBrassButton(title: "编辑", systemImage: "pencil") {
                editedContent = displayContent ?? ""
                saveStatus = nil
                isEditing = true
            }
            Spacer(minLength: 0)
            if case .file = profile.source {
                sheetGhostButton(title: "在 Finder 显示", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([yamlURL])
                }
            }
            sheetGhostButton(title: "复制内容", systemImage: "doc.on.doc") {
                guard let s = displayContent else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(s, forType: .string)
                withAnimation { copyHint = "已复制" }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation { copyHint = nil }
                }
            }
            sheetGhostButton(title: "关闭", systemImage: "xmark", action: onClose)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var editModeButtons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            sheetGhostButton(title: "取消", systemImage: "arrow.uturn.backward") {
                editedContent = displayContent ?? ""
                isEditing = false
                saveStatus = nil
            }
            sheetBrassButton(title: "保存", systemImage: "checkmark") {
                performSave()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// Persist edits, refresh read-mode buffer, and reload mihomo if this is
    /// the active profile. The kernel surfaces parse errors via the global
    /// banner so we don't pre-validate here.
    private func performSave() {
        let toSave = editedContent
        do {
            try store.setYaml(toSave, for: profile.id)
        } catch {
            // Inline error; stay in edit mode so the user can copy out edits.
            saveStatus = "保存失败: \(error)"
            return
        }
        displayContent = toSave
        isEditing = false

        if profile.id == store.activeProfileID {
            withAnimation { saveStatus = "重载中…" }
            Task {
                await kernel.reload()
                withAnimation { saveStatus = "已保存" }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation { saveStatus = nil }
            }
        } else {
            withAnimation { saveStatus = "已保存" }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation { saveStatus = nil }
            }
        }
    }

    private func sheetBrassButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(ChungHwa.Palette.ink)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.brass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.brassDark.opacity(0.55), lineWidth: 0.5)
            )
            .shadow(color: ChungHwa.Palette.brassDark.opacity(0.20), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func sheetGhostButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(ChungHwa.Palette.text)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ChungHwa.Palette.pillBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ChungHwa.Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
