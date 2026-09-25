import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Task 3.9.5: the Bonjour browse behind `BonjourModelNameSource`.
  private let bonjourModelNames = BonjourModelNameStreamHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "BonjourModelNames")?.messenger() {
      FlutterEventChannel(
        name: "com.ekmanch.devialet_expert_remote_app/bonjour_model_names",
        binaryMessenger: messenger
      ).setStreamHandler(bonjourModelNames)
    }
  }
}
