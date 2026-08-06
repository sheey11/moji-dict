import SwiftUI

@main
struct MojiQuickLookApp: App {
    var body: some Scene {
        WindowGroup("Moji 辞書") {
            AppWindowContent()
        }
        .defaultSize(width: 1_050, height: 700)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }
}

private struct AppWindowContent: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            ContentView()
                .containerBackground(
                    Color(nsColor: .textBackgroundColor),
                    for: .window
                )
        } else {
            ContentView()
                .background(LegacyWindowBackgroundSetter())
        }
    }
}

private struct LegacyWindowBackgroundSetter: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowBackgroundView {
        WindowBackgroundView()
    }

    func updateNSView(_ nsView: WindowBackgroundView, context: Context) {
        nsView.applyWindowBackground()
    }
}

private final class WindowBackgroundView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowBackground()
    }

    func applyWindowBackground() {
        window?.backgroundColor = .textBackgroundColor
    }
}

private struct SettingsView: View {
    var body: some View {
        Form {
            Section("连接") {
                LabeledContent("接口模式", value: "公开只读查询")
                LabeledContent("本地缓存", value: "仅内存，退出即清除")
                LabeledContent("账号会话", value: "macOS 钥匙串")
                LabeledContent("浏览器会话", value: "不读取、不共享")
            }

            Section("说明") {
                Text("此应用是个人研究原型，不是 MOJi 官方客户端。它不包含 WebView，也不读取浏览器 Cookie；密码不会保存，会话令牌仅加密保存在 macOS 钥匙串中。")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .font(.callout)
        .padding()
        .frame(width: 520, height: 300)
    }
}
