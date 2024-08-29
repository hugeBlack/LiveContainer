//
//  SwiftUIView.swift
//  nmsl
//
//  Created by s s on 2024/8/23.
//

import SwiftUI
import WebKit

struct LCWebView: View {
    @State private var webView : WebView
    @State private var didAppear = false
    
    @Binding var url : URL
    @Binding var isPresent: Bool
    @State private var loadStatus = 0.0
    @State private var uiLoadStatus = 0.0
    @State private var pageTitle = ""
    
    @Binding var apps : [LCAppInfo]
    
    @State private var runAppAlertShow = false
    @State private var runAppAlertMsg = ""
    @State private var doRunApp = false
    @State private var renameFolderContent = ""
    @State private var doRunAppContinuation : CheckedContinuation<Void, Never>? = nil
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    
    init(url: Binding<URL>, apps: Binding<[LCAppInfo]>, isPresent: Binding<Bool>) {
        self.webView = WebView()
        self._url = url
        self._apps = apps
        self._isPresent = isPresent
    }
    
    var body: some View {
        
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Button(action: {
                        webView.goBack()
                    }, label: {
                        Image(systemName: "chevron.backward")
                    })
                    
                    Button(action: {
                        webView.goForward()
                    }, label: {
                        Image(systemName: "chevron.forward")
                    }).padding(.horizontal)
                }
                
                Spacer()
                Text(pageTitle)
                    .lineLimit(1)
                Spacer()
                Button(action: {
                    webView.reload()
                }, label: {
                    Image(systemName: "arrow.clockwise")
                }).padding(.horizontal)
                Button(action: {
                    isPresent = false
                }, label: {
                    Text("Done")
                })
                
            }
            .padding([.bottom, .horizontal])
            .background(Color(.systemGray6))
            .overlay(alignment: .bottomTrailing) {
                ProgressView(value: uiLoadStatus)
                    .opacity(loadStatus == 1.0 ? 0 : 1)
                    .scaleEffect(y: 0.5)
                    .offset(y: 1)
                    .onChange(of: loadStatus) { newValue in
                        if newValue > uiLoadStatus {
                            withAnimation(.easeIn(duration: 0.3)) {
                                uiLoadStatus = newValue
                            }
                        } else {
                            uiLoadStatus = newValue
                        }
                    }
                
            }
            webView
        }
        .onAppear(){
            webView.loadURL(url: url)
            if !didAppear {
                onViewAppear()
                didAppear = true
            }

        }
        .alert("Run App", isPresented: $runAppAlertShow) {
            Button("Run", action: {
                self.doRunApp = true
                self.doRunAppContinuation?.resume()
            })
            Button("Cancel", role: .cancel, action: {
                self.doRunApp = false
                self.doRunAppContinuation?.resume()
            })
        } message: {
            Text(runAppAlertMsg)
        }
        .alert("Error", isPresented: $errorShow) {
            Button("OK", action: {
            })
        } message: {
            Text(errorInfo)
        }
        
    }
    
    func onViewAppear() {
        let observer = WebViewLoadObserver(loadStatus: $loadStatus, webView: self.webView.webView)
        let webViewDelegate = WebViewDelegate(pageTitle: $pageTitle, urlSchemeHandler:onURLSchemeDetected, universalLinkHandler: onUniversalLinkDetected)
        webView.setDelegate(delegete: webViewDelegate)
        webView.setObserver(observer: observer)
    }
    
    public func onURLSchemeDetected(url: URL) async {
        var appToLaunch : LCAppInfo? = nil
    appLoop: for app in apps {
        if let schemes = app.urlSchemes() {
            for scheme in schemes {
                if let scheme = scheme as? String, scheme == url.scheme {
                    appToLaunch = app
                    break appLoop
                }
            }
        }
    }
        
        guard let appToLaunch = appToLaunch else {
            errorInfo = "Scheme \"\(url.scheme!)\" cannot be opened by any app installed in LiveContainer."
            errorShow = true
            return
        }
        
        runAppAlertMsg = "This web page is trying to launch \"\(appToLaunch.displayName()!)\", continue?"
        
        await withCheckedContinuation { c in
            self.doRunAppContinuation = c
            runAppAlertShow = true
        }
        
        if !doRunApp {
            return
        }
        
        UserDefaults.standard.setValue(appToLaunch.relativeBundlePath!, forKey: "selected")
        UserDefaults.standard.setValue(url.absoluteString, forKey: "launchAppUrlScheme")
        LCUtils.launchToGuestApp()
        
    }
    
    public func onUniversalLinkDetected(url: URL, bundleIDs: [String]) async {
        var bundleIDToAppDict: [String: LCAppInfo] = [:]
        for app in apps {
            bundleIDToAppDict[app.bundleIdentifier()!] = app
        }
        
        var appToLaunch: LCAppInfo? = nil
        for bundleID in bundleIDs {
            if let app = bundleIDToAppDict[bundleID] {
                appToLaunch = app
                break
            }
        }
        guard let appToLaunch = appToLaunch else {
            return
        }
        
        runAppAlertMsg = "This web page can be opened in \"\(appToLaunch.displayName()!)\" according to its Associated Domains, continue?"
        runAppAlertShow = true
        await withCheckedContinuation { c in
            self.doRunAppContinuation = c
            runAppAlertShow = true
        }
        if !doRunApp {
            return
        }
        UserDefaults.standard.setValue(appToLaunch.relativeBundlePath!, forKey: "selected")
        UserDefaults.standard.setValue(url.absoluteString, forKey: "launchAppUrlScheme")
        LCUtils.launchToGuestApp()
    }
}

class WebViewLoadObserver : NSObject {
    private var loadStatus: Binding<Double>
    private var webView: WKWebView
    
    init(loadStatus: Binding<Double>, webView: WKWebView) {
        self.loadStatus = loadStatus
        self.webView = webView
        super.init()
        self.webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil);
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            loadStatus.wrappedValue = self.webView.estimatedProgress
        }
    }
    

}

class WebViewDelegate : NSObject,WKNavigationDelegate {
    private var pageTitle: Binding<String>
    private var urlSchemeHandler: (URL) async -> Void
    private var universalLinkHandler: (URL , [String]) async -> Void // url, [String] of all apps that can open this web page
    var domainBundleIdDict : [String:[String]] = [:]
    
    init(pageTitle: Binding<String>, urlSchemeHandler: @escaping (URL) async -> Void, universalLinkHandler: @escaping (URL , [String]) async -> Void) {
        self.pageTitle = pageTitle
        self.urlSchemeHandler = urlSchemeHandler
        self.universalLinkHandler = universalLinkHandler
        super.init()
    }
    
    func webView(_ webView: WKWebView,
                   decidePolicyFor navigationAction: WKNavigationAction,
                   decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler((WKNavigationActionPolicy)(rawValue: WKNavigationActionPolicy.allow.rawValue + 2)!)
        guard let url = navigationAction.request.url, let scheme = navigationAction.request.url?.scheme else {
            return
        }
        if(scheme == "https") {
            Task {
                await self.loadDomainAssociations(url: url)
                if let host = url.host, let appIDs = self.domainBundleIdDict[host] {
                    Task{ await self.universalLinkHandler(url, appIDs) }
                }
            }
            return
        }
        if(scheme == "http" || scheme == "about" || scheme == "itms-appss") {
            return;
        }
        Task{ await urlSchemeHandler(url) }

    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.pageTitle.wrappedValue = webView.title!
    }
    
    
    func loadDomainAssociations(url: URL) async {
        if url.scheme != "https" || url.host == nil {
            return
        }
        if self.domainBundleIdDict[url.host!] != nil {
            return
        }
        guard let host = url.host else {
            return
        }
        
        // download and read apple-app-site-association
        let appleAppSiteAssociationURLs = [
            URL(string: "https://\(host)/apple-app-site-association")!,
            URL(string: "https://\(host)/.well-known/apple-app-site-association")!
            ]

        await withTaskGroup(of: Void.self) { group in
            for siteAssociationURL in appleAppSiteAssociationURLs {
                group.addTask {
                    await withCheckedContinuation { c in
                        let task = URLSession.shared.dataTask(with: siteAssociationURL) { data, response, error in
                            do {
                                guard let data = data else {
                                    c.resume()
                                    return
                                }
                                let siteAssociationObj = try JSONDecoder().decode(SiteAssociation.self, from: data)
                                guard let detailItems = siteAssociationObj.applinks?.details else {
                                    c.resume()
                                    return
                                }
                                self.domainBundleIdDict[host] = []
                                for item in detailItems {
                                    self.domainBundleIdDict[host]!.append(contentsOf: item.getBundleIds())
                                }
                            } catch {
                                
                            }
                            c.resume()
                        }
                        
                        task.resume()
                    }
                }
            }
        }

    }
}

struct WebView: UIViewRepresentable {
    
    let webView: WKWebView
    var observer: WebViewLoadObserver?
    var delegate: WKNavigationDelegate?
    
    init() {
        self.webView = WKWebView()
    }
    
    mutating func setDelegate(delegete: WKNavigationDelegate) {
        self.delegate = delegete
        self.webView.navigationDelegate = delegete
    }
    
    mutating func setObserver(observer: WebViewLoadObserver) {
        self.observer = observer
    }
    
    func makeUIView(context: Context) -> WKWebView {
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
    
    func reload() {
        webView.reload()
    }
    
    func goBack(){
        webView.goBack()
    }
    
    func goForward(){
        webView.goForward()
    }
    
    
    func loadURL(url: URL) {
        webView.load(URLRequest(url: url))
    }
    

}
