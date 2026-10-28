#include "app_info.h"

// clang-format off
#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <tlhelp32.h>
#include <wincodec.h>
// clang-format on

#include <algorithm>
#include <cwctype>
#include <fstream>
#include <iterator>
#include <sstream>

#include "ipc.h"

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        out.data(), length);
  return out;
}

std::string Utf8(const std::wstring& utf16) {
  if (utf16.empty()) return std::string();
  int length = ::WideCharToMultiByte(CP_UTF8, 0, utf16.data(),
                                     static_cast<int>(utf16.size()), nullptr, 0,
                                     nullptr, nullptr);
  if (length <= 0) return std::string();
  std::string out(static_cast<size_t>(length), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, utf16.data(),
                        static_cast<int>(utf16.size()), out.data(), length,
                        nullptr, nullptr);
  return out;
}

namespace {

std::wstring Lower(std::wstring s) {
  std::transform(s.begin(), s.end(), s.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return s;
}

bool EndsWith(const std::wstring& s, const std::wstring& end) {
  return s.size() >= end.size() &&
         s.compare(s.size() - end.size(), end.size(), end) == 0;
}

std::wstring FileName(const std::wstring& path) {
  size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

std::wstring Stem(const std::wstring& path) {
  std::wstring name = FileName(path);
  size_t dot = name.find_last_of(L'.');
  return dot == std::wstring::npos ? name : name.substr(0, dot);
}

std::wstring KnownFolder(REFKNOWNFOLDERID id) {
  PWSTR path = nullptr;
  std::wstring out;
  if (SUCCEEDED(::SHGetKnownFolderPath(id, 0, nullptr, &path))) out = path;
  ::CoTaskMemFree(path);
  return out;
}

// The file of the known apps: one per line, "id\tpath\tlabel", in UTF-8.
std::wstring KnownAppsFile() {
  std::wstring dir = KnownFolder(FOLDERID_LocalAppData);
  if (dir.empty()) return std::wstring();
  dir += L"\\FamilyScreenTime";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  return dir + L"\\apps.tsv";
}

void SaveKnownApps(const std::map<std::string, KnownApp>& apps) {
  std::wstring file = KnownAppsFile();
  if (file.empty()) return;
  std::wstring temp = file + L".new";
  {
    std::ofstream out(temp, std::ios::binary | std::ios::trunc);
    if (!out) return;
    for (const auto& [id, app] : apps) {
      out << id << '\t' << Utf8(app.path) << '\t' << Utf8(app.label) << '\n';
    }
  }
  ::MoveFileExW(temp.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING);
}

// Programs of processes, by process id, for a short while: a window's
// process is asked for often.
struct CachedPath {
  std::wstring path;
  ULONGLONG at;
};
std::map<DWORD, CachedPath>& PathCache() {
  static std::map<DWORD, CachedPath> cache;
  return cache;
}

std::wstring CachedProcessPath(DWORD pid) {
  auto& cache = PathCache();
  ULONGLONG now = ::GetTickCount64();
  auto it = cache.find(pid);
  if (it != cache.end() && now - it->second.at < 30000) return it->second.path;
  if (cache.size() > 512) cache.clear();
  std::wstring path = ProcessPath(pid);
  cache[pid] = {path, now};
  return path;
}

DWORD CurrentSession() {
  DWORD session = 0;
  ::ProcessIdToSessionId(::GetCurrentProcessId(), &session);
  return session;
}

// The target of shortcut [lnk], when a program.
std::wstring ShortcutTarget(const std::wstring& lnk) {
  IShellLinkW* link = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) {
    return std::wstring();
  }
  std::wstring target;
  IPersistFile* file = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&file)))) {
    if (SUCCEEDED(file->Load(lnk.c_str(), STGM_READ))) {
      wchar_t raw[MAX_PATH] = {};
      if (SUCCEEDED(link->GetPath(raw, MAX_PATH, nullptr, SLGP_RAWPATH)) &&
          raw[0]) {
        wchar_t expanded[MAX_PATH] = {};
        if (::ExpandEnvironmentStringsW(raw, expanded, MAX_PATH) > 0) {
          target = expanded;
        }
      }
    }
    file->Release();
  }
  link->Release();
  return target;
}

bool IsUninstaller(const std::wstring& name) {
  std::wstring n = Lower(name);
  for (const wchar_t* word : {L"unins", L"uninstall", L"d\u00e9sinstall",
                              L"desinstall", L"verwijder", L"remove"}) {
    if (n.find(word) != std::wstring::npos) return true;
  }
  return false;
}

void ScanShortcuts(const std::wstring& dir, int depth,
                   std::map<std::string, KnownApp>& apps) {
  if (dir.empty() || depth > 4) return;
  WIN32_FIND_DATAW data;
  HANDLE find = ::FindFirstFileW((dir + L"\\*").c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) return;
  do {
    std::wstring name = data.cFileName;
    if (name == L"." || name == L"..") continue;
    std::wstring path = dir + L"\\" + name;
    if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      ScanShortcuts(path, depth + 1, apps);
      continue;
    }
    if (!EndsWith(Lower(name), L".lnk") || IsUninstaller(name)) continue;
    std::wstring target = ShortcutTarget(path);
    std::wstring lower = Lower(target);
    if (!EndsWith(lower, L".exe") || IsUninstaller(FileName(target)) ||
        lower.find(L"\\installer\\") != std::wstring::npos ||
        ::GetFileAttributesW(target.c_str()) == INVALID_FILE_ATTRIBUTES) {
      continue;
    }
    std::string id = AppIdOfPath(target);
    if (id == kSelfAppId) continue;
    std::wstring label = Stem(name);
    auto it = apps.find(id);
    // Several shortcuts to one program: the shortest name.
    if (it == apps.end() || label.size() < it->second.label.size()) {
      apps[id] = {target, label};
    }
  } while (::FindNextFileW(find, &data));
  ::FindClose(find);
}

}  // namespace

std::string AppIdOfPath(const std::wstring& path) {
  if (path.empty()) return std::string();
  return Utf8(Lower(FileName(path)));
}

std::wstring ProcessPath(DWORD pid) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return std::wstring();
  wchar_t buffer[MAX_PATH * 2];
  DWORD size = static_cast<DWORD>(std::size(buffer));
  std::wstring path;
  if (::QueryFullProcessImageNameW(process, 0, buffer, &size)) {
    path.assign(buffer, size);
  }
  ::CloseHandle(process);
  return path;
}

WindowApp AppOfWindow(HWND hwnd) {
  WindowApp app;
  if (!hwnd) return app;
  ::GetWindowThreadProcessId(hwnd, &app.pid);
  app.path = CachedProcessPath(app.pid);
  app.id = AppIdOfPath(app.path);
  if (app.id == "applicationframehost.exe") {
    // A Store app: its own window is inside the frame, in its process.
    struct Search {
      DWORD frame;
      DWORD found;
    } search{app.pid, 0};
    ::EnumChildWindows(
        hwnd,
        [](HWND child, LPARAM param) -> BOOL {
          auto* s = reinterpret_cast<Search*>(param);
          DWORD pid = 0;
          ::GetWindowThreadProcessId(child, &pid);
          if (pid != 0 && pid != s->frame) {
            s->found = pid;
            return FALSE;
          }
          return TRUE;
        },
        reinterpret_cast<LPARAM>(&search));
    if (search.found) {
      app.pid = search.found;
      app.path = CachedProcessPath(app.pid);
      app.id = AppIdOfPath(app.path);
    }
  }
  return app;
}

std::map<std::string, KnownApp> LoadKnownApps() {
  std::map<std::string, KnownApp> apps;
  std::wstring file = KnownAppsFile();
  if (file.empty()) return apps;
  std::ifstream in(file, std::ios::binary);
  std::string line;
  while (std::getline(in, line)) {
    std::istringstream fields(line);
    std::string id, path, label;
    if (!std::getline(fields, id, '\t') || !std::getline(fields, path, '\t')) {
      continue;
    }
    std::getline(fields, label);
    if (!id.empty()) apps[id] = {Utf16FromUtf8(path), Utf16FromUtf8(label)};
  }
  return apps;
}

void RememberApp(const std::string& id, const std::wstring& path,
                 const std::wstring& label) {
  if (id.empty() || path.empty()) return;
  // What this process already wrote: the file is only written for news.
  static std::map<std::string, KnownApp> written;
  auto known = written.find(id);
  if (known != written.end() && known->second.path == path &&
      (label.empty() || known->second.label == label)) {
    return;
  }
  auto apps = LoadKnownApps();
  KnownApp& app = apps[id];
  bool changed = app.path != path || (!label.empty() && app.label != label);
  app.path = path;
  if (!label.empty()) app.label = label;
  written[id] = app;
  if (changed) SaveKnownApps(apps);
}

std::map<std::string, KnownApp> InstalledApps() {
  std::map<std::string, KnownApp> shortcuts;
  ScanShortcuts(KnownFolder(FOLDERID_CommonPrograms), 0, shortcuts);
  ScanShortcuts(KnownFolder(FOLDERID_Programs), 0, shortcuts);
  auto known = LoadKnownApps();
  bool changed = false;
  for (const auto& [id, app] : shortcuts) {
    KnownApp& k = known[id];
    if (k.path != app.path || k.label != app.label) {
      k = app;
      changed = true;
    }
  }
  if (changed) SaveKnownApps(known);
  // Those used here, without a shortcut (apps of the Store, say), too.
  std::map<std::string, KnownApp> apps = known;
  for (auto& [id, app] : apps) {
    if (app.label.empty()) app.label = ProgramLabel(app.path);
  }
  apps.erase(kSelfAppId);
  return apps;
}

std::wstring ProgramLabel(const std::wstring& path) {
  DWORD handle = 0;
  DWORD size = ::GetFileVersionInfoSizeW(path.c_str(), &handle);
  if (size > 0) {
    std::vector<BYTE> data(size);
    if (::GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
      struct Translation {
        WORD language;
        WORD codepage;
      }* translations = nullptr;
      UINT length = 0;
      if (::VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                           reinterpret_cast<LPVOID*>(&translations),
                           &length) &&
          length >= sizeof(Translation)) {
        for (const wchar_t* field : {L"FileDescription", L"ProductName"}) {
          wchar_t key[128];
          swprintf_s(key, L"\\StringFileInfo\\%04x%04x\\%s",
                     translations[0].language, translations[0].codepage,
                     field);
          wchar_t* value = nullptr;
          UINT value_length = 0;
          if (::VerQueryValueW(data.data(), key,
                               reinterpret_cast<LPVOID*>(&value),
                               &value_length) &&
              value && value_length > 1) {
            std::wstring label(value);
            while (!label.empty() && label.back() == L' ') label.pop_back();
            if (!label.empty()) return label;
          }
        }
      }
    }
  }
  return Stem(path);
}

std::wstring AppLabel(const std::string& id) {
  auto apps = LoadKnownApps();
  auto it = apps.find(id);
  if (it == apps.end()) return Utf16FromUtf8(id);
  if (!it->second.label.empty()) return it->second.label;
  return ProgramLabel(it->second.path);
}

std::vector<uint8_t> IconPng(const std::wstring& path, int size) {
  std::vector<uint8_t> png;
  HICON icon = nullptr;
  HRESULT found = ::SHDefExtractIconW(path.c_str(), 0, 0, &icon, nullptr,
                                      static_cast<UINT>(size));
  if (found != S_OK || !icon) {
    SHFILEINFOW info = {};
    if (::SHGetFileInfoW(path.c_str(), 0, &info, sizeof(info),
                         SHGFI_ICON | SHGFI_LARGEICON)) {
      icon = info.hIcon;
    }
  }
  if (!icon) return png;

  IWICImagingFactory* factory = nullptr;
  IWICBitmap* bitmap = nullptr;
  IStream* stream = nullptr;
  IWICBitmapEncoder* encoder = nullptr;
  IWICBitmapFrameEncode* frame = nullptr;
  bool ok =
      SUCCEEDED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&factory))) &&
      SUCCEEDED(factory->CreateBitmapFromHICON(icon, &bitmap)) &&
      (stream = ::SHCreateMemStream(nullptr, 0)) != nullptr &&
      SUCCEEDED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                       &encoder)) &&
      SUCCEEDED(encoder->Initialize(stream, WICBitmapEncoderNoCache)) &&
      SUCCEEDED(encoder->CreateNewFrame(&frame, nullptr)) &&
      SUCCEEDED(frame->Initialize(nullptr));
  if (ok) {
    UINT width = 0, height = 0;
    bitmap->GetSize(&width, &height);
    WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
    ok = SUCCEEDED(frame->SetSize(width, height)) &&
         SUCCEEDED(frame->SetPixelFormat(&format)) &&
         SUCCEEDED(frame->WriteSource(bitmap, nullptr)) &&
         SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit());
  }
  if (ok) {
    STATSTG stat = {};
    LARGE_INTEGER start = {};
    if (SUCCEEDED(stream->Stat(&stat, STATFLAG_NONAME)) &&
        SUCCEEDED(stream->Seek(start, STREAM_SEEK_SET, nullptr))) {
      png.resize(static_cast<size_t>(stat.cbSize.QuadPart));
      ULONG read = 0;
      stream->Read(png.data(), static_cast<ULONG>(png.size()), &read);
      png.resize(read);
    }
  }
  if (frame) frame->Release();
  if (encoder) encoder->Release();
  if (stream) stream->Release();
  if (bitmap) bitmap->Release();
  if (factory) factory->Release();
  ::DestroyIcon(icon);
  return png;
}

std::vector<DWORD> ProcessesOf(const std::string& id) {
  std::vector<DWORD> pids;
  HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return pids;
  DWORD session = CurrentSession();
  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);
  if (::Process32FirstW(snapshot, &entry)) {
    do {
      if (Utf8(Lower(entry.szExeFile)) != id) continue;
      DWORD their = 0;
      if (::ProcessIdToSessionId(entry.th32ProcessID, &their) &&
          their == session) {
        pids.push_back(entry.th32ProcessID);
      }
    } while (::Process32NextW(snapshot, &entry));
  }
  ::CloseHandle(snapshot);
  return pids;
}

std::vector<HWND> WindowsOf(const std::string& id) {
  struct Search {
    const std::string* id;
    std::vector<HWND> found;
  } search{&id, {}};
  ::EnumWindows(
      [](HWND hwnd, LPARAM param) -> BOOL {
        auto* s = reinterpret_cast<Search*>(param);
        if (::IsWindowVisible(hwnd) && AppOfWindow(hwnd).id == *s->id) {
          s->found.push_back(hwnd);
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&search));
  return search.found;
}

std::wstring SelfPath() {
  wchar_t buffer[MAX_PATH * 2];
  DWORD length = ::GetModuleFileNameW(nullptr, buffer,
                                      static_cast<DWORD>(std::size(buffer)));
  return std::wstring(buffer, length);
}
