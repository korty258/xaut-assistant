import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let platformChannelName = "io.github.korty258.jinhua_assistant/platform"
  private var platformChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: platformChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "clearWebViewData" {
        Self.clearWebViewData(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    platformChannel = channel
  }

  private static func clearWebViewData(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      URLCache.shared.removeAllCachedResponses()
      if let cookies = HTTPCookieStorage.shared.cookies {
        for cookie in cookies {
          HTTPCookieStorage.shared.deleteCookie(cookie)
        }
      }

      let dataStore = WKWebsiteDataStore.default()
      let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
      let epoch = Date(timeIntervalSince1970: 0)
      dataStore.removeData(ofTypes: allTypes, modifiedSince: epoch) {
        DispatchQueue.main.async {
          result(true)
        }
      }
    }
  }
}
