import Cocoa
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  private var databaseChannel: FlutterMethodChannel?
  private let settingsService = "vn.cuahang.xemayApp.database-settings"

  private func keychainQuery() -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: settingsService,
     kSecAttrAccount as String: "connections"]
  }

  private func databaseCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "load":
      var query = keychainQuery()
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      if status == errSecItemNotFound { result(nil) }
      else if status == errSecSuccess, let data = item as? Data { result(String(data: data, encoding: .utf8)) }
      else { result(FlutterError(code: "keychain_read", message: "Chưa đọc được cấu hình kết nối đã lưu.", details: nil)) }
    case "save":
      guard let args = call.arguments as? [String: Any], let value = args["value"] as? String,
            let data = value.data(using: .utf8), data.count < 65536 else {
        result(FlutterError(code: "invalid_settings", message: "Cấu hình kết nối không hợp lệ.", details: nil)); return
      }
      let query = keychainQuery()
      var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      if status == errSecItemNotFound {
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        status = SecItemAdd(entry as CFDictionary, nil)
      }
      if status == errSecSuccess { result(nil) }
      else { result(FlutterError(code: "keychain_write", message: "Chưa lưu được cấu hình vào Keychain của máy.", details: nil)) }
    case "supportDirectory":
      do {
        let parent = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
          appropriateFor: nil, create: true)
        let folder = parent.appendingPathComponent("vn.cuahang.xemayApp", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        result(folder.path)
      } catch { result(FlutterError(code: "storage", message: "Chưa mở được thư mục dữ liệu ứng dụng.", details: nil)) }
    case "openMongoInstallation":
      let opened = NSWorkspace.shared.open(URL(string: "https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-os-x/")!)
      if opened { result(nil) }
      else { result(FlutterError(code: "open_url", message: "Chưa mở được hướng dẫn cài MongoDB.", details: nil)) }
    default: result(FlutterMethodNotImplemented)
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 1360, height: 860), display: true)
    self.minSize = NSSize(width: 720, height: 580)

    RegisterGeneratedPlugins(registry: flutterViewController)
    databaseChannel = FlutterMethodChannel(name: "xemay/database_settings", binaryMessenger: flutterViewController.engine.binaryMessenger)
    databaseChannel?.setMethodCallHandler { [weak self] call, result in
      self?.databaseCall(call, result: result)
    }

    super.awakeFromNib()
  }
}
