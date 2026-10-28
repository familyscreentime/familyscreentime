// Apps on Windows: which one a window belongs to, their names and icons,
// those installed, and the programs of the session.
//
// An app is named by the file name of its program, in lower case
// ("msedge.exe", "minecraft.windows.exe"): it stays the same across
// versions, unlike its folder.
#ifndef RUNNER_APP_INFO_H_
#define RUNNER_APP_INFO_H_

#include <windows.h>

#include <cstdint>
#include <map>
#include <string>
#include <vector>

// UTF-8 to UTF-16.
std::wstring Utf16FromUtf8(const std::string& utf8);

// UTF-16 to UTF-8.
std::string Utf8(const std::wstring& utf16);

// The app id of the program at [path].
std::string AppIdOfPath(const std::wstring& path);

// The program of process [pid], or an empty string.
std::wstring ProcessPath(DWORD pid);

// The app of window [hwnd] and its program, or an empty id. For an app of
// the Store, the app inside the frame window, not the frame.
struct WindowApp {
  std::string id;
  std::wstring path;
  DWORD pid = 0;
};
WindowApp AppOfWindow(HWND hwnd);

// What is known of the apps: their program and name. Kept in a file of the
// account, read and written by both processes.
struct KnownApp {
  std::wstring path;
  std::wstring label;
};
std::map<std::string, KnownApp> LoadKnownApps();

// Remembers [id]'s program (and [label], when given) in the file.
void RememberApp(const std::string& id, const std::wstring& path,
                 const std::wstring& label = L"");

// The apps of the Start menu (this account's and every account's), and
// those already seen in use here.
std::map<std::string, KnownApp> InstalledApps();

// The name of the program at [path]: its description, or its file name.
std::wstring ProgramLabel(const std::wstring& path);

// The name of app [id]: from the Start menu, or its program.
std::wstring AppLabel(const std::string& id);

// [path]'s icon, [size] pixels wide, as PNG; empty when none.
std::vector<uint8_t> IconPng(const std::wstring& path, int size);

// The processes of app [id] in this session.
std::vector<DWORD> ProcessesOf(const std::string& id);

// The visible windows of app [id] in this session.
std::vector<HWND> WindowsOf(const std::string& id);

// This program.
std::wstring SelfPath();

#endif  // RUNNER_APP_INFO_H_
