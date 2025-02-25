import SwiftUI
import WebKit
import Combine
import UIKit

// Если WKOpenPanelParameters недоступен (например, в SDK для iOS 16),
// объявляем его заглушку, чтобы компилировалось.
#if !swift(>=5.9)
public class WKOpenPanelParameters: NSObject {}
#endif

// MARK: - Keyboard Adaptive Modifier
struct KeyboardAdaptive: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    @State private var animationDuration: TimeInterval = 0

    func body(content: Content) -> some View {
        content
            .offset(y: -keyboardHeight)
            .animation(.easeOut(duration: animationDuration), value: keyboardHeight)
            .onAppear(perform: subscribeToKeyboardNotifications)
    }
    
    private func subscribeToKeyboardNotifications() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification,
                                               object: nil,
                                               queue: .main) { notification in
            guard let userInfo = notification.userInfo,
                  let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
            else { return }
            animationDuration = duration
            withAnimation {
                keyboardHeight = keyboardFrame.height
            }
        }
        
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                               object: nil,
                                               queue: .main) { notification in
            guard let userInfo = notification.userInfo,
                  let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
            else { return }
            animationDuration = duration
            withAnimation {
                keyboardHeight = 0
            }
        }
    }
}

// MARK: - WebView (UIViewRepresentable)
struct WebView: UIViewRepresentable {
    let baseURL: URL
    let parameters: [String: String]
    
    private var url: URL {
        if var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
            var queryItems = components.queryItems ?? []
            for (key, value) in parameters {
                queryItems.append(URLQueryItem(name: key, value: value))
            }
            components.queryItems = queryItems
            return components.url ?? baseURL
        }
        return baseURL
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Поддержка JavaScript, Cookie и сессий
        configuration.preferences.javaScriptEnabled = true
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.allowsInlineMediaPlayback = true
        
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        } else {
            configuration.requiresUserActionForMediaPlayback = false
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // Меняем User-Agent, чтобы не выдавалось использование WKWebView
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
        
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Обновлений не требуется
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: WebView
        private var hasTriedReload = false
        
        var fileUploadCallback: ((URL?) -> Void)?
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        // MARK: Автоматическое разрешение Protected Media ID (iOS 15+)
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
        
        // MARK: Обработка множественных редиректов
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleRedirectErrorIfNeeded(webView: webView, error: error)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleRedirectErrorIfNeeded(webView: webView, error: error)
        }
        
        private func handleRedirectErrorIfNeeded(webView: WKWebView, error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorHTTPTooManyRedirects {
                if !hasTriedReload {
                    hasTriedReload = true
                    webView.load(URLRequest(url: parent.url))
                }
            }
        }
        
        // MARK: Обработка запроса загрузки файлов
        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            if message == "file_upload_request" {
                self.presentFilePicker()
                completionHandler(true)
            } else {
                completionHandler(false)
            }
        }
        
        private func presentFilePicker() {
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.delegate = self
            
            DispatchQueue.main.async {
                if let topVC = UIApplication.shared.windows.first?.rootViewController {
                    topVC.present(picker, animated: true, completion: nil)
                }
            }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            
            if let imageUrl = info[.imageURL] as? URL {
                self.fileUploadCallback?(imageUrl)
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Экран WebView с передачей параметров и keyboardAdaptive
struct WebViewScreen: View {
    let baseURLString: String
    
    // Пример дополнительных параметров
    let parameters: [String: String] = [
        "param1": "value1",
        "param2": "value2",
        "device": UIDevice.current.model,
        "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    ]
    
    var body: some View {
        VStack {
            if let baseURL = URL(string: baseURLString) {
                WebView(baseURL: baseURL, parameters: parameters)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Неверный URL")
                    .foregroundColor(.red)
            }
        }
        .navigationBarTitle("Web", displayMode: .inline)
        .background(.clear)
//        .keyboardAdaptive()
    }
}



// ДЛЯ Примера
struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Главное окно")
                    .font(.title)
                
                NavigationLink(destination: WebViewScreen(baseURLString: "https://habr.com")) {
                    Text("Open WebView")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
            .navigationBarTitle("Home", displayMode: .inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
