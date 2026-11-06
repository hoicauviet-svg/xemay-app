#include "database_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wincrypt.h>

#include <memory>
#include <string>
#include <vector>

namespace {

constexpr DWORD kMaxSettingsBytes = 65536;
constexpr wchar_t kSettingsFile[] = L"database-settings.bin";
const wchar_t* kMongoInstallUrl =
    L"https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-windows/";

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;

std::string Utf8FromWide(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  const int size = ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                          wide.data(),
                                          static_cast<int>(wide.size()),
                                          nullptr, 0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string utf8(size, '\0');
  if (::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide.data(),
                            static_cast<int>(wide.size()), utf8.data(), size,
                            nullptr, nullptr) <= 0) {
    return std::string();
  }
  return utf8;
}

std::wstring SupportDirectory() {
  PWSTR roaming = nullptr;
  const HRESULT result = ::SHGetKnownFolderPath(FOLDERID_RoamingAppData,
                                                 KF_FLAG_CREATE, nullptr,
                                                 &roaming);
  if (FAILED(result) || roaming == nullptr) return std::wstring();
  std::wstring path = std::wstring(roaming) + L"\\vn.cuahang.xemayApp";
  ::CoTaskMemFree(roaming);
  if (!::CreateDirectoryW(path.c_str(), nullptr) &&
      ::GetLastError() != ERROR_ALREADY_EXISTS) {
    return std::wstring();
  }
  return path;
}

std::wstring SettingsPath() {
  const std::wstring directory = SupportDirectory();
  if (directory.empty()) return std::wstring();
  return directory + L"\\" + kSettingsFile;
}

bool ReadFileBytes(const std::wstring& path, std::vector<BYTE>* bytes) {
  const HANDLE file = ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                                    nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                                    nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const DWORD size = ::GetFileSize(file, nullptr);
  if (size == INVALID_FILE_SIZE || size > kMaxSettingsBytes * 2) {
    ::CloseHandle(file);
    return false;
  }
  bytes->resize(size);
  DWORD read = 0;
  const BOOL ok = size == 0 || ::ReadFile(file, bytes->data(), size, &read, nullptr);
  ::CloseHandle(file);
  return ok && read == size;
}

bool WriteFileBytes(const std::wstring& path, const BYTE* data, DWORD size) {
  const std::wstring temporary = path + L".tmp";
  const HANDLE file = ::CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
                                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                                    nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const BOOL ok = ::WriteFile(file, data, size, &written, nullptr);
  ::CloseHandle(file);
  if (!ok || written != size) {
    ::DeleteFileW(temporary.c_str());
    return false;
  }
  if (!::MoveFileExW(temporary.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    ::DeleteFileW(temporary.c_str());
    return false;
  }
  return true;
}

void Fail(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
          const std::string& code, const std::string& message) {
  result->Error(code, message);
}

void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "load") {
    const std::wstring path = SettingsPath();
    if (path.empty()) {
      Fail(std::move(result), "storage",
           "Chưa mở được thư mục dữ liệu ứng dụng.");
      return;
    }
    std::vector<BYTE> protected_bytes;
    if (!ReadFileBytes(path, &protected_bytes)) {
      if (::GetLastError() == ERROR_FILE_NOT_FOUND) {
        result->Success();
        return;
      }
      Fail(std::move(result), "settings_read",
           "Chưa đọc được cấu hình kết nối đã lưu.");
      return;
    }
    DATA_BLOB input;
    input.pbData = protected_bytes.data();
    input.cbData = static_cast<DWORD>(protected_bytes.size());
    DATA_BLOB output;
    if (!::CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, 0,
                              &output)) {
      Fail(std::move(result), "settings_read",
           "Chưa đọc được cấu hình kết nối đã lưu.");
      return;
    }
    const std::string text(reinterpret_cast<char*>(output.pbData), output.cbData);
    ::LocalFree(output.pbData);
    result->Success(flutter::EncodableValue(text));
    return;
  }

  if (call.method_name() == "save") {
    const auto* arguments = call.arguments();
    const auto* map = arguments == nullptr
                          ? nullptr
                          : std::get_if<flutter::EncodableMap>(arguments);
    std::string value;
    if (map != nullptr) {
      const auto found = map->find(flutter::EncodableValue("value"));
      if (found != map->end()) {
        if (const auto* text = std::get_if<std::string>(&found->second)) {
          value = *text;
        }
      }
    }
    if (value.empty() || value.size() >= kMaxSettingsBytes) {
      Fail(std::move(result), "invalid_settings",
           "Cấu hình kết nối không hợp lệ.");
      return;
    }
    const std::wstring path = SettingsPath();
    if (path.empty()) {
      Fail(std::move(result), "storage",
           "Chưa mở được thư mục dữ liệu ứng dụng.");
      return;
    }
    std::vector<BYTE> plain(value.begin(), value.end());
    DATA_BLOB input;
    input.pbData = plain.data();
    input.cbData = static_cast<DWORD>(plain.size());
    DATA_BLOB output;
    if (!::CryptProtectData(&input, L"xemay-database-settings", nullptr, nullptr,
                            nullptr, 0, &output)) {
      Fail(std::move(result), "settings_write",
           "Chưa lưu được cấu hình kết nối trên máy này.");
      return;
    }
    const bool stored = WriteFileBytes(path, output.pbData, output.cbData);
    ::LocalFree(output.pbData);
    if (!stored) {
      Fail(std::move(result), "settings_write",
           "Chưa lưu được cấu hình kết nối trên máy này.");
      return;
    }
    result->Success();
    return;
  }

  if (call.method_name() == "supportDirectory") {
    const std::wstring path = SupportDirectory();
    const std::string utf8 = Utf8FromWide(path);
    if (utf8.empty()) {
      Fail(std::move(result), "storage",
           "Chưa mở được thư mục dữ liệu ứng dụng.");
      return;
    }
    result->Success(flutter::EncodableValue(utf8));
    return;
  }

  if (call.method_name() == "openMongoInstallation") {
    const HINSTANCE opened = ::ShellExecuteW(nullptr, L"open", kMongoInstallUrl,
                                              nullptr, nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(opened) <= 32) {
      Fail(std::move(result), "open_url",
           "Chưa mở được hướng dẫn cài MongoDB.");
      return;
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

}  // namespace

void RegisterDatabaseChannel(flutter::BinaryMessenger* messenger) {
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "xemay/database_settings",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(Handle);
}

void ResetDatabaseChannel() { channel.reset(); }
