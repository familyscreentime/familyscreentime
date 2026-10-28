#include "platform_channel.h"

// clang-format off
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
// clang-format on

#include <flutter/standard_method_codec.h>

#include "app_info.h"
#include "encodable.h"
#include "ipc.h"

namespace {

std::wstring MonitorCommand() {
  return L"\"" + SelfPath() + L"\" " + kMonitorArgument;
}

bool RunValueSet(HKEY root) {
  DWORD size = 0;
  return ::RegGetValueW(root, kRunKey, kRunValueName, RRF_RT_REG_SZ, nullptr,
                        nullptr, &size) == ERROR_SUCCESS;
}

std::wstring ComputerName() {
  wchar_t name[MAX_COMPUTERNAME_LENGTH + 1];
  DWORD size = MAX_COMPUTERNAME_LENGTH + 1;
  if (!::GetComputerNameW(name, &size)) return L"PC";
  return std::wstring(name, size);
}

std::wstring UserName() {
  wchar_t name[257];
  DWORD size = 257;
  if (!::GetUserNameW(name, &size) || size == 0) return std::wstring();
  return std::wstring(name);
}

// Puts [path] in the Downloads folder and shows it there: Windows has no
// share sheet for any file.
bool ShowInDownloads(const std::wstring& path) {
  PWSTR downloads = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_Downloads, 0, nullptr,
                                    &downloads))) {
    ::CoTaskMemFree(downloads);
    return false;
  }
  std::wstring dir = downloads;
  ::CoTaskMemFree(downloads);
  size_t slash = path.find_last_of(L"\\/");
  std::wstring target =
      dir + L"\\" + (slash == std::wstring::npos ? path : path.substr(slash + 1));
  if (!::CopyFileW(path.c_str(), target.c_str(), FALSE)) return false;
  std::wstring args = L"/select,\"" + target + L"\"";
  ::ShellExecuteW(nullptr, L"open", L"explorer.exe", args.c_str(), nullptr,
                  SW_SHOWNORMAL);
  return true;
}

}  // namespace

bool MonitorRunning() {
  return ::FindWindowW(kMonitorWindowClass, nullptr) != nullptr;
}

bool StartMonitor() {
  if (MonitorRunning()) return true;
  std::wstring command = MonitorCommand();
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  std::wstring self = SelfPath();
  if (!::CreateProcessW(self.c_str(), command.data(), nullptr, nullptr, FALSE,
                        0, nullptr, nullptr, &startup, &process)) {
    return false;
  }
  ::CloseHandle(process.hThread);
  ::CloseHandle(process.hProcess);
  return true;
}

bool AutostartSet() {
  return RunValueSet(HKEY_LOCAL_MACHINE) || RunValueSet(HKEY_CURRENT_USER);
}

void SetAutostart() {
  if (RunValueSet(HKEY_LOCAL_MACHINE)) return;
  std::wstring command = MonitorCommand();
  ::RegSetKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunValueName, REG_SZ,
                    command.c_str(),
                    static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
}

bool IsAdminAccount() {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION_TYPE type = TokenElevationTypeDefault;
  DWORD size = 0;
  bool admin = false;
  if (::GetTokenInformation(token, TokenElevationType, &type, sizeof(type),
                            &size) &&
      type != TokenElevationTypeDefault) {
    // With the administrator prompt: an administrator, elevated or not.
    admin = true;
  } else {
    BYTE sid[SECURITY_MAX_SID_SIZE];
    DWORD sid_size = sizeof(sid);
    BOOL member = FALSE;
    if (::CreateWellKnownSid(WinBuiltinAdministratorsSid, nullptr, sid,
                             &sid_size) &&
        ::CheckTokenMembership(nullptr, sid, &member)) {
      admin = member != FALSE;
    }
  }
  ::CloseHandle(token);
  return admin;
}

void OpenInterface() {
  HWND ui = ::FindWindowW(kUiWindowClass, kUiWindowTitle);
  if (ui) {
    DWORD pid = 0;
    ::GetWindowThreadProcessId(ui, &pid);
    ::AllowSetForegroundWindow(pid);
    ::PostMessageW(ui, kMsgShowUi, 0, 0);
    return;
  }
  ::AllowSetForegroundWindow(ASFW_ANY);
  std::wstring self = SelfPath();
  std::wstring command = L"\"" + self + L"\"";
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  if (::CreateProcessW(self.c_str(), command.data(), nullptr, nullptr, FALSE,
                       0, nullptr, nullptr, &startup, &process)) {
    ::CloseHandle(process.hThread);
    ::CloseHandle(process.hProcess);
  }
}

PlatformChannel::PlatformChannel(flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "org.familyscreentime/platform",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    Handle(call, std::move(result));
  });
}

void PlatformChannel::Notify(const std::string& method) {
  channel_->InvokeMethod(method, nullptr);
}

void PlatformChannel::Handle(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableValue* args = call.arguments();

  if (method == "permissionStatus") {
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("autostartWindows"), EncodableValue(AutostartSet())},
        {EncodableValue("monitorRunning"), EncodableValue(MonitorRunning())},
        {EncodableValue("standardAccount"), EncodableValue(!IsAdminAccount())},
    }));
  } else if (method == "openPermissionSettings") {
    std::string kind = StringField(args, "kind");
    if (kind == "autostartWindows") {
      SetAutostart();
    } else if (kind == "monitorRunning") {
      StartMonitor();
    } else if (kind == "standardAccount") {
      ::ShellExecuteW(nullptr, L"open", L"ms-settings:otherusers", nullptr,
                      nullptr, SW_SHOWNORMAL);
    }
    result->Success();
  } else if (method == "launcherApps") {
    EncodableList list;
    for (const auto& [id, app] : InstalledApps()) {
      list.push_back(EncodableValue(EncodableMap{
          {EncodableValue("package"), EncodableValue(id)},
          {EncodableValue("label"), EncodableValue(Utf8(app.label))},
      }));
    }
    result->Success(EncodableValue(list));
  } else if (method == "appInfo") {
    int size = static_cast<int>(IntField(args, "size", 48));
    auto known = LoadKnownApps();
    EncodableMap out;
    for (const auto& id : StringsField(args, "packages")) {
      auto it = known.find(id);
      if (it == known.end()) continue;
      std::wstring label = it->second.label.empty()
                               ? ProgramLabel(it->second.path)
                               : it->second.label;
      EncodableMap info{{EncodableValue("label"), EncodableValue(Utf8(label))}};
      std::vector<uint8_t> icon = IconPng(it->second.path, size);
      if (!icon.empty()) {
        info[EncodableValue("icon")] = EncodableValue(icon);
      }
      out[EncodableValue(id)] = EncodableValue(info);
    }
    result->Success(EncodableValue(out));
  } else if (method == "usageHistory") {
    // Windows keeps no history of the apps' use: none to import.
    result->Success();
  } else if (method == "systemPackages") {
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("self"), EncodableValue(kSelfAppId)},
        {EncodableValue("launchers"),
         EncodableValue(EncodableList{EncodableValue("explorer.exe")})},
    }));
  } else if (method == "startMonitor") {
    SetAutostart();
    result->Success(EncodableValue(StartMonitor()));
  } else if (method == "deviceName") {
    std::wstring name = ComputerName();
    std::wstring user = UserName();
    if (!user.empty()) name += L" (" + user + L")";
    result->Success(EncodableValue(Utf8(name)));
  } else if (method == "reloadMonitor") {
    HWND monitor = ::FindWindowW(kMonitorWindowClass, nullptr);
    if (monitor) ::PostMessageW(monitor, kMsgReload, 0, 0);
    result->Success();
  } else if (method == "shareFile") {
    result->Success(EncodableValue(
        ShowInDownloads(Utf16FromUtf8(StringField(args, "path")))));
  } else if (method == "parentMode") {
    HWND monitor = ::FindWindowW(kMonitorWindowClass, nullptr);
    if (monitor) {
      bool on = BoolField(args, "on");
      ::PostMessageW(monitor, kMsgParentMode, on ? 1 : 0,
                     static_cast<LPARAM>(IntField(args, "forMs") / 1000));
    }
    result->Success();
  } else if (method == "disableDeviceAdmin") {
    result->Success();
  } else {
    result->NotImplemented();
  }
}
