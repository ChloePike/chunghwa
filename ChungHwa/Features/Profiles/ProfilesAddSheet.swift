import SwiftUI

struct ImportURLSheet: View {
    @Binding var urlText: String
    @Binding var urlName: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从 URL 导入")
                .font(ChungHwa.Typography.serif(17, weight: .semibold))
                .foregroundStyle(ChungHwa.Palette.text)

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.dim)
                TextField("https://example.com/subscription", text: $urlText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("名称（可留空）")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChungHwa.Palette.dim)
                TextField("起个名字", text: $urlName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("导入", action: onSubmit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValidURL)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(ChungHwa.Palette.card)
    }

    private var isValidURL: Bool {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }
        return true
    }
}
