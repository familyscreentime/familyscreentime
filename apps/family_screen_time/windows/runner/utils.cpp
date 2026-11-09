#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>
// clang-format off
#include <dbghelp.h>
#include <shlobj.h>
// clang-format on

#include <iostream>

#pragma comment(lib, "dbghelp.lib")

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

namespace {

std::wstring g_log_dir;
std::wstring g_log_name;

// Says what crashed in the log, and writes a minidump next to it.
LONG WINAPI OnCrash(EXCEPTION_POINTERS* info) {
  const EXCEPTION_RECORD* record = info->ExceptionRecord;
  SYSTEMTIME now;
  ::GetLocalTime(&now);
  fprintf(stderr, "\n*** Crash at %02d:%02d:%02d: exception 0x%08lx at %p\n",
          now.wHour, now.wMinute, now.wSecond,
          static_cast<unsigned long>(record->ExceptionCode),
          record->ExceptionAddress);
  if (record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION &&
      record->NumberParameters >= 2) {
    ULONG_PTR kind = record->ExceptionInformation[0];
    fprintf(stderr, "*** %s %p\n",
            kind == 8u ? "executing" : kind == 1u ? "writing" : "reading",
            reinterpret_cast<void*>(record->ExceptionInformation[1]));
  }
  fflush(stderr);
  std::wstring path = g_log_dir + L"\\" + g_log_name + L".dmp";
  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    MINIDUMP_EXCEPTION_INFORMATION exception = {::GetCurrentThreadId(), info,
                                                FALSE};
    ::MiniDumpWriteDump(
        ::GetCurrentProcess(), ::GetCurrentProcessId(), file,
        static_cast<MINIDUMP_TYPE>(MiniDumpWithIndirectlyReferencedMemory |
                                   MiniDumpWithFullMemoryInfo |
                                   MiniDumpWithThreadInfo),
        &exception, nullptr, nullptr);
    ::CloseHandle(file);
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void StartLog(const wchar_t* name) {
  PWSTR local = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                    &local))) {
    ::CoTaskMemFree(local);
    return;
  }
  std::wstring dir = std::wstring(local) + L"\\FamilyScreenTime";
  ::CoTaskMemFree(local);
  ::CreateDirectoryW(dir.c_str(), nullptr);
  dir += L"\\logs";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  g_log_dir = dir;
  g_log_name = name;
  std::wstring path = dir + L"\\" + name + L".log";
  // Started afresh past 1 MB.
  WIN32_FILE_ATTRIBUTE_DATA data = {};
  bool big = ::GetFileAttributesExW(path.c_str(), GetFileExInfoStandard,
                                    &data) &&
             (data.nFileSizeHigh > 0 || data.nFileSizeLow > (1u << 20));
  FILE* unused = nullptr;
  if (_wfreopen_s(&unused, path.c_str(), big ? L"w" : L"a", stdout) != 0 ||
      _wfreopen_s(&unused, path.c_str(), L"a", stderr) != 0) {
    return;
  }
  setvbuf(stdout, nullptr, _IONBF, 0);
  setvbuf(stderr, nullptr, _IONBF, 0);
  std::ios::sync_with_stdio();
  FlutterDesktopResyncOutputStreams();
  SYSTEMTIME now;
  ::GetLocalTime(&now);
  fprintf(stdout, "\n--- %ls started %04d-%02d-%02d %02d:%02d:%02d, process %lu\n",
          name, now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
          now.wSecond, static_cast<unsigned long>(::GetCurrentProcessId()));
  ::SetUnhandledExceptionFilter(OnCrash);
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
