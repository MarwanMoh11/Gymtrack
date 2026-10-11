import SwiftUI
import SwiftData
import WebKit

/// Form guidance within reach from the library and the workout logger.
struct FormVideoCard: View {
    let exercise: CatalogExercise
    @Query private var records: [FormVideoRecord]
    @State private var editing = false

    private var video: FormVideo? { FormVideos.video(for: exercise.id, records: records) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("Form video")
                Spacer()
                Button { editing = true } label: {
                    Image(systemName: "square.and.pencil")
                        .gtIcon(size: 15, relativeTo: .subheadline)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change form video")
                .accessibilityIdentifier("formVideo.edit")
            }
            if let video {
                YouTubePlayer(video: video)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                    .accessibilityIdentifier("formVideo.player")
                Link("Open in YouTube", destination: video.watchURL)
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                Button("Add a YouTube link") { editing = true }
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("formVideo.add")
            }
        }
        .gtCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("formVideo.card")
        .sheet(isPresented: $editing) { FormVideoSheet(exercise: exercise, records: records) }
    }
}

/// An inline player whose navigation cannot strand the lifter on a web page.
struct YouTubePlayer: UIViewRepresentable {
    let video: FormVideo

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // No YouTube cookies are kept in an app that otherwise never touches
        // the network.
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        // The detail screen redraws on every logged set. Reloading here would
        // restart a video the lifter was watching between sets.
        guard context.coordinator.loaded != video else { return }
        context.coordinator.loaded = video
        let html = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head><body><iframe src="\(video.embedURL.absoluteString)" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        // YouTube rejects embeds with no Referer (Error 153). An HTTPS base
        // URL built from the bundle ID supplies the origin it asks WebView
        // apps to send; an HTML string with no base URL sends none.
        let origin = URL(string: "https://\((Bundle.main.bundleIdentifier ?? "gymtrack").lowercased())/")
        view.loadHTMLString(html, baseURL: origin)
    }

    /// Remembers the loaded video and sends player links out of the card.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loaded: FormVideo?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { UIApplication.shared.open(url) }
            return nil
        }
    }
}
