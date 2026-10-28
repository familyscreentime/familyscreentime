// How the interface and the monitor, two processes of the same program in
// the same Windows session, find and tell each other things: by their
// window classes and window messages.
#ifndef RUNNER_IPC_H_
#define RUNNER_IPC_H_

#include <windows.h>

// The interface's window (see win32_window.cpp) and its title.
constexpr wchar_t kUiWindowClass[] = L"FamilyScreenTimeWindow";
constexpr wchar_t kUiWindowTitle[] = L"Family Screen Time";

// The monitor's hidden window.
constexpr wchar_t kMonitorWindowClass[] = L"FamilyScreenTimeMonitor";

// Interface → monitor: the settings or the family changed, read them again.
constexpr UINT kMsgReload = WM_APP + 1;

// Interface → monitor: parent mode on (wparam 1) for lparam seconds, or off.
constexpr UINT kMsgParentMode = WM_APP + 2;

// Monitor → interface: the family changed (the monitor took in changes).
constexpr UINT kMsgFamilyChanged = WM_APP + 3;

// The tray icon's notifications, to the monitor's window.
constexpr UINT kMsgTray = WM_APP + 4;

// To the interface: come to the front.
constexpr UINT kMsgShowUi = WM_APP + 5;

// The program's own app id, as apps are named on Windows: the file name of
// their program, in lower case.
constexpr char kSelfAppId[] = "familyscreentime.exe";

// Program started at each sign-in to monitor the session.
constexpr wchar_t kMonitorArgument[] = L"--monitor";

// Name of the program in the Run keys (installer: all accounts; the app:
// this account).
constexpr wchar_t kRunValueName[] = L"FamilyScreenTime";
constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

#endif  // RUNNER_IPC_H_
