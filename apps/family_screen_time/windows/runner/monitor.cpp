#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wtsapi32.h>
#include <shellapi.h>
#include <powrprof.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <algorithm>
#include <unordered_map>
#include "flutter/generated_plugin_registrant.h"
#include "app_info.h"
#include "encodable.h"
#include "ipc.h"
#include "notice_windows.h"
#include "platform_channel.h"
#include "monitor.h"

#pragma comment(lib, "Wtsapi32.lib")
#pragma comment(lib, "Powrprof.lib")
#pragma comment(lib, "Shell32.lib")
#pragma comment(lib, "Ole32.lib")
#pragma comment(lib, "Mmdevapi.lib")

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::EncodableList;

// ─── État, miroir d'Enforcer.kt ───────────────────────────────────────
std::unique_ptr<flutter::FlutterEngine> g_engine;
std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;
PlatformChannel* g_platform = nullptr;
HANDLE g_single_instance = nullptr;

HWND g_hwnd = nullptr;
HWINEVENTHOOK g_fg_hook = nullptr;
HPOWERNOTIFY g_display_notify = nullptr;
UINT g_taskbar_created = 0;
UINT_PTR g_parent_timer = 0;

std::string g_last_foreground;
bool g_screen_on = true;
bool g_session_locked = false;
bool g_parent_mode = false;

bool g_device_locked = false;
bool g_settings_locked = false;
std::wstring g_lock_title, g_lock_message, g_lock_open;
std::vector<std::string> g_lock_exempt;
std::wstring g_settings_title, g_settings_message;

NoticeWindow* g_block_notice = nullptr;
LockWindow* g_device_lock = nullptr;
OverlayWindow* g_overlay = nullptr;
EyeNoticeWindow* g_eye_notice = nullptr;
EyeVeilWindow* g_eye_veil = nullptr;

// Takes the eye break's notice and veil down.
void HideEyeBreak() {
    if (g_eye_notice) g_eye_notice->Hide();
    if (g_eye_veil) g_eye_veil->Hide();
}

NOTIFYICONDATAW g_nid = {};

// ─── Réduction différée après WM_CLOSE ────────────────────────────────
constexpr UINT_PTR kMinimizeTimerBase = 20000;
UINT_PTR g_next_minimize_timer = kMinimizeTimerBase;
std::unordered_map<UINT_PTR, std::string> g_pending_minimize;

void ScheduleMinimizeIfStillVisible(const std::string& pkg) {
    if (pkg.empty() || !g_hwnd) return;
    UINT_PTR id = g_next_minimize_timer++;
    g_pending_minimize[id] = pkg;
    ::SetTimer(g_hwnd, id, 5000, nullptr);
}

// ─── VolumeGuard : ne fait que baisser, et surveille ──────────────────
// (La gestion des casques reste à faire : réabonnement au périphérique
// par défaut via IMMNotificationClient, et distinction speaker/headphones.)
class VolumeGuard : public IAudioEndpointVolumeCallback {
public:
    VolumeGuard() : ref_(1), cap_(-1), volume_(nullptr), enforcing_(false) {}

    bool Init() {
        IMMDeviceEnumerator* en = nullptr;
        if (FAILED(::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                      CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                      (void**)&en)))
            return false;
        IMMDevice* dev = nullptr;
        HRESULT hr = en->GetDefaultAudioEndpoint(eRender, eConsole, &dev);
        en->Release();
        if (FAILED(hr)) return false;
        hr = dev->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL,
                           nullptr, (void**)&volume_);
        dev->Release();
        if (FAILED(hr)) return false;
        volume_->RegisterControlChangeNotify(this);
        return true;
    }

    // -1 = pas de plafond (ne touche plus au volume).
    void SetCap(int percent) {
        cap_ = percent;
        Enforce();
    }

    // Ne baisse jamais en dessous du plafond actuel : seulement vers le bas.
    void Enforce() {
        if (cap_ < 0 || !volume_) return;
        float cur = 0.0f;
        volume_->GetMasterVolumeLevelScalar(&cur);
        float cap = cap_ / 100.0f;
        if (cur > cap) {
            enforcing_ = true;
            volume_->SetMasterVolumeLevelScalar(cap, nullptr);
            enforcing_ = false;
        }
    }

    HRESULT STDMETHODCALLTYPE OnNotify(PAUDIO_VOLUME_NOTIFICATION_DATA) override {
        if (!enforcing_) Enforce();
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** ppv) override {
        if (iid == IID_IUnknown || iid == __uuidof(IAudioEndpointVolumeCallback)) {
            *ppv = static_cast<IAudioEndpointVolumeCallback*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++ref_; }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG r = --ref_;
        if (r == 0) delete this;
        return r;
    }

private:
    ULONG ref_;
    int cap_;
    IAudioEndpointVolume* volume_;
    bool enforcing_;
};
VolumeGuard* g_volume = nullptr;

// ─── Utilitaires ──────────────────────────────────────────────────────
void SendToDart(const std::string& method,
                std::unique_ptr<EncodableValue> args = nullptr) {
    if (g_channel) g_channel->InvokeMethod(method, std::move(args));
}

int64_t Int64Field(const EncodableMap* m, const char* key, int64_t def = 0) {
    if (!m) return def;
    auto it = m->find(EncodableValue(key));
    if (it == m->end()) return def;
    if (auto* v = std::get_if<int64_t>(&it->second)) return *v;
    if (auto* v = std::get_if<int32_t>(&it->second)) return *v;
    return def;
}

void SendScreen(bool on) {
    g_screen_on = on;
    auto a = std::make_unique<EncodableValue>(EncodableMap{
        {EncodableValue("on"), EncodableValue(on)}});
    SendToDart("screen", std::move(a));
}

void SendForeground(const std::string& pkg) {
    g_last_foreground = pkg;
    auto a = std::make_unique<EncodableValue>(EncodableMap{
        {EncodableValue("package"), EncodableValue(pkg)}});
    SendToDart("foreground", std::move(a));
}

void SendForegroundNow() {
    if (HWND h = ::GetForegroundWindow()) SendForeground(AppOfWindow(h).id);
}

// Bulle sur l'icône existante (g_nid, uID 1). Ne vole jamais le premier
// plan : un jeu plein écran n'est pas interrompu.
void ShowBubble(const std::wstring& title, const std::wstring& text) {
    NOTIFYICONDATAW n = g_nid;
    n.uFlags = NIF_INFO;
    n.dwInfoFlags = NIIF_INFO;
    n.uTimeout = 5000;
    wcsncpy_s(n.szInfoTitle, title.c_str(), _TRUNCATE);
    wcsncpy_s(n.szInfo, text.c_str(), _TRUNCATE);
    Shell_NotifyIconW(NIM_MODIFY, &n);
}

void ShowBubbleUtf8(const std::string& title, const std::string& text) {
    ShowBubble(Utf16FromUtf8(title), Utf16FromUtf8(text));
}

bool IsProtectedSettingsPkg(const std::string& pkg) {
    return pkg == "systemsettings.exe" || pkg == "taskmgr.exe" ||
           pkg == "regedit.exe";
}

void CloseProtectedSettings() {
    for (const char* p : {"systemsettings.exe", "taskmgr.exe", "regedit.exe"})
        for (HWND h : WindowsOf(p)) ::PostMessageW(h, WM_CLOSE, 0, 0);
}

void LaunchApp(const std::string& id) {
    auto known = LoadKnownApps();
    auto it = known.find(id);
    if (it != known.end() && !it->second.path.empty())
        ::ShellExecuteW(nullptr, L"open", it->second.path.c_str(),
                        nullptr, nullptr, SW_SHOWNORMAL);
}

void CreateTrayIcon() {
    g_nid.cbSize = sizeof(g_nid);
    g_nid.hWnd = g_hwnd;
    g_nid.uID = 1;
    g_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_nid.uCallbackMessage = kMsgTray;
    g_nid.hIcon = ::LoadIconW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101));
    wcscpy_s(g_nid.szTip, L"Family Screen Time");
    Shell_NotifyIconW(NIM_ADD, &g_nid);
}

// ─── Enforcer.kt updateDeviceLock ─────────────────────────────────────
void UpdateDeviceLock() {
    if (!g_device_lock) return;
    const std::string& fg = g_last_foreground;
    bool exempt = !fg.empty() &&
        (fg == kSelfAppId ||
         std::find(g_lock_exempt.begin(), g_lock_exempt.end(), fg) !=
             g_lock_exempt.end());
    bool show = g_device_locked && g_screen_on && !g_session_locked &&
                !exempt && !g_parent_mode;
    if (show) {
        if (g_block_notice) g_block_notice->Hide();
        HideEyeBreak();
        std::vector<std::wstring> labels;
        for (auto& e : g_lock_exempt) labels.push_back(AppLabel(e));
        g_device_lock->Show(g_lock_title, g_lock_message, g_lock_open, labels);
    } else {
        g_device_lock->Hide();
    }
}

// Réglages protégés ouverts alors qu'ils doivent être fermés : les fermer
// et dire pourquoi. Vérifié à CHAQUE changement de fenêtre.
void CheckProtectedSettings(const std::string& pkg) {
    if (!g_settings_locked || g_parent_mode) return;
    if (!IsProtectedSettingsPkg(pkg)) return;
    CloseProtectedSettings();
    ShowBubble(g_settings_title, g_settings_message);
}

// ─── Enforcer.kt onForegroundApp ──────────────────────────────────────
void OnForegroundApp(const std::string& pkg) {
    if (g_volume) g_volume->Enforce();
    if (!g_screen_on || g_session_locked) return;
    if (pkg == g_last_foreground) return;
    g_last_foreground = pkg;
    UpdateDeviceLock();
    CheckProtectedSettings(pkg);
}

// ─── Enforcer.kt block ────────────────────────────────────────────────
// Ferme poliment (WM_CLOSE). Si l'appli ignore WM_CLOSE, réduit ses
// fenêtres après 5 secondes (pas de TerminateProcess : protège les
// devoirs non enregistrés).
void DoBlock(const EncodableValue* args) {
    if (g_parent_mode) return;
    HideEyeBreak();
    std::string app = StringField(args, "package");
    if (app.empty()) app = g_last_foreground;

    std::string title = StringField(args, "title");
    std::string message = StringField(args, "message");
    std::string closed = StringField(args, "closed");
    std::string ok = StringField(args, "ok");
    if (ok.empty()) ok = "OK";
    std::string open = StringField(args, "open");
    if (open.empty()) open = "Family Screen Time";
    bool background = BoolField(args, "background");

    // Enforcer.kt : "$message\n${closed.replace("{app}", appLabel(app))}".
    std::wstring detail;
    if (!closed.empty() && !app.empty()) {
        detail = L"\n" + Utf16FromUtf8(closed);
        size_t pos = detail.find(L"{app}");
        if (pos != std::wstring::npos) detail.replace(pos, 5, AppLabel(app));
    }

    if (!app.empty()) {
        bool saw_window = false;
        for (HWND h : WindowsOf(app)) {
            saw_window = true;
            if (background) ::ShowWindow(h, SW_MINIMIZE);
            else ::PostMessageW(h, WM_CLOSE, 0, 0);
        }
        if (saw_window && !background) {
            ScheduleMinimizeIfStillVisible(app);
        }
    }

    // Le verrouillage de l'appareil dit tout : pas de notice par-dessus.
    if (g_device_locked) {
        UpdateDeviceLock();
        if (g_device_lock->Visible() || !g_screen_on) return;
    }
    if (g_block_notice)
        g_block_notice->Show(Utf16FromUtf8(title),
                             Utf16FromUtf8(message) + detail,
                             L"", Utf16FromUtf8(ok), Utf16FromUtf8(open));
}

// ─── Enforcer.kt lockState ────────────────────────────────────────────
void DoLockState(const EncodableValue* args) {
    const auto* map = std::get_if<EncodableMap>(args);
    if (!map) return;

    g_settings_locked = BoolField(args, "settingsLocked");
    g_device_locked = BoolField(args, "deviceLocked");
    g_lock_title = Utf16FromUtf8(StringField(args, "title"));
    g_lock_message = Utf16FromUtf8(StringField(args, "message"));
    g_lock_open = Utf16FromUtf8(StringField(args, "open"));
    g_settings_title = Utf16FromUtf8(StringField(args, "settingsTitle"));
    g_settings_message = Utf16FromUtf8(StringField(args, "settingsMessage"));

    g_lock_exempt.clear();
    auto it = map->find(EncodableValue("exempt"));
    if (it != map->end())
        if (auto* list = std::get_if<EncodableList>(&it->second))
            for (auto& item : *list)
                if (auto* s = std::get_if<std::string>(&item))
                    g_lock_exempt.push_back(*s);

    UpdateDeviceLock();
    CheckProtectedSettings(g_last_foreground);
}

// ─── Handler Dart → C++ ───────────────────────────────────────────────
void HandleCall(const flutter::MethodCall<EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const std::string& m = call.method_name();
    const EncodableValue* args = call.arguments();
    const auto* map = args ? std::get_if<EncodableMap>(args) : nullptr;

    if (m == "state") {
        std::string fg;
        if (HWND h = ::GetForegroundWindow()) fg = AppOfWindow(h).id;
        g_last_foreground = fg;
        EncodableMap res;
        res[EncodableValue("screenOn")] =
            EncodableValue(g_screen_on && !g_session_locked);
        if (fg.empty()) res[EncodableValue("foreground")] = EncodableValue();
        else res[EncodableValue("foreground")] = EncodableValue(fg);
        result->Success(EncodableValue(res));
        return;
    }
    if (m == "unwanted") { ::DestroyWindow(g_hwnd); result->Success(); return; }
    if (m == "block") { DoBlock(args); result->Success(); return; }
    if (m == "unblock") {
        if (g_block_notice) g_block_notice->Hide();
        UpdateDeviceLock();
        result->Success();
        return;
    }
    if (m == "lockState") { DoLockState(args); result->Success(); return; }
    if (m == "warn") {
        ShowBubbleUtf8(StringField(args, "title"), StringField(args, "text"));
        result->Success();
        return;
    }
    if (m == "overlay") {
        if (g_overlay) g_overlay->Show(Int64Field(map, "endsAt"));
        result->Success();
        return;
    }
    if (m == "overlayHide") {
        if (g_overlay) g_overlay->Hide();
        result->Success();
        return;
    }
    if (m == "countdown") {
        NOTIFYICONDATAW n = g_nid;
        n.uFlags = NIF_TIP;
        wcsncpy_s(n.szTip, Utf16FromUtf8(StringField(args, "title")).c_str(),
                  _TRUNCATE);
        Shell_NotifyIconW(NIM_MODIFY, &n);
        result->Success();
        return;
    }
    if (m == "rulesChanged") {
        std::string title = StringField(args, "title");
        std::string text = StringField(args, "text");
        if (!title.empty() || !text.empty()) ShowBubbleUtf8(title, text);
        result->Success();
        return;
    }
    // Eye breaks: the notice, then the veil. When they cannot show (the
    // device locked, parent mode, the screen off), "busy": Dart counts the
    // time after all and tries again later.
    if (m == "eyeNotice" || m == "eyeVeil") {
        bool waits = (g_device_lock && g_device_lock->Visible()) ||
                     g_parent_mode || !g_screen_on || g_session_locked;
        if (waits || !g_eye_notice || !g_eye_veil) {
            HideEyeBreak();
            auto a = std::make_unique<EncodableValue>(EncodableMap{
                {EncodableValue("action"), EncodableValue("busy")}});
            SendToDart("eyeBreak", std::move(a));
        } else if (m == "eyeNotice") {
            g_eye_notice->Show(Utf16FromUtf8(StringField(args, "title")),
                               Utf16FromUtf8(StringField(args, "text")),
                               Utf16FromUtf8(StringField(args, "now")),
                               Utf16FromUtf8(StringField(args, "later")),
                               Int64Field(map, "endsAt"));
        } else {
            g_eye_notice->Hide();
            g_eye_veil->Show(Utf16FromUtf8(StringField(args, "title")),
                             Utf16FromUtf8(StringField(args, "text")),
                             Int64Field(map, "endsAt"));
        }
        result->Success();
        return;
    }
    if (m == "eyeHide") { HideEyeBreak(); result->Success(); return; }
    if (m == "pauseMedia") {
        // V1 Windows : pas de browserMedia natif, donc pas de pause média
        // ciblée. On ne tente pas de pause globale : elle pourrait viser
        // Spotify au lieu de la vidéo du navigateur.
        result->Success();
        return;
    }
    if (m == "volumeCap") {
        if (map) {
            auto it = map->find(EncodableValue("speaker"));
            if (it != map->end()) {
                int cap = 100;
                if (auto* v = std::get_if<int32_t>(&it->second)) cap = *v;
                else if (auto* w = std::get_if<int64_t>(&it->second)) cap = (int)*w;
                g_volume->SetCap(cap);
            } else {
                g_volume->SetCap(-1);
            }
        }
        result->Success();
        return;
    }
    if (m == "familyChanged") {
        if (HWND ui = ::FindWindowW(kUiWindowClass, kUiWindowTitle))
            ::PostMessageW(ui, kMsgFamilyChanged, 0, 0);
        result->Success();
        return;
    }
    result->NotImplemented();
}

// ─── Procédure de fenêtre ─────────────────────────────────────────────
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_TIMER: {
            auto it = g_pending_minimize.find(wp);
            if (it != g_pending_minimize.end()) {
                std::string pkg = it->second;
                g_pending_minimize.erase(it);
                ::KillTimer(hwnd, wp);
                if (!g_parent_mode) {
                    for (HWND h : WindowsOf(pkg)) {
                        if (::IsWindowVisible(h) && !::IsIconic(h)) {
                            ::ShowWindow(h, SW_MINIMIZE);
                        }
                    }
                }
                return 0;
            }
            if (wp == 9999) {
                g_parent_mode = false;
                ::KillTimer(hwnd, 9999);
                g_parent_timer = 0;
                SendToDart("reload");
                UpdateDeviceLock();
                return 0;
            }
            break;
        }

        case kMsgParentMode:
            if (wp == 1) {
                g_parent_mode = true;
                if (g_parent_timer) ::KillTimer(hwnd, g_parent_timer);
                g_parent_timer = ::SetTimer(hwnd, 9999, (UINT)lp * 1000, nullptr);
            } else {
                g_parent_mode = false;
                if (g_parent_timer) {
                    ::KillTimer(hwnd, g_parent_timer);
                    g_parent_timer = 0;
                }
                SendToDart("reload");
            }
            UpdateDeviceLock();
            return 0;

        case kMsgReload: SendToDart("reload"); return 0;
        case kMsgFamilyChanged: SendToDart("familyChanged"); return 0;

        case WM_WTSSESSION_CHANGE:
            if (wp == WTS_SESSION_LOCK) {
                g_session_locked = true;
                SendScreen(false);
            } else if (wp == WTS_SESSION_UNLOCK) {
                g_session_locked = false;
                SendScreen(true);
                SendForegroundNow();
            } else if (wp == WTS_SESSION_LOGON || wp == WTS_SESSION_LOGOFF) {
                SendScreen(false);
            }
            UpdateDeviceLock();
            return 0;

        case WM_POWERBROADCAST:
            if (wp == PBT_APMSUSPEND) {
                if (!g_session_locked) SendScreen(false);
            } else if (wp == PBT_APMRESUMEAUTOMATIC || wp == PBT_APMRESUMESUSPEND) {
                if (!g_session_locked) { SendScreen(true); SendForegroundNow(); }
            } else if (wp == PBT_POWERSETTINGCHANGE) {
                auto* s = reinterpret_cast<POWERBROADCAST_SETTING*>(lp);
                if (s && s->PowerSetting == GUID_CONSOLE_DISPLAY_STATE &&
                    !g_session_locked) {
                    bool on = s->Data[0] != 0;
                    SendScreen(on);
                    if (on) SendForegroundNow();
                }
            }
            UpdateDeviceLock();
            return TRUE;

        case kMsgTray:
            if (lp == WM_LBUTTONDBLCLK) OpenInterface();
            return 0;

        case WM_DESTROY: ::PostQuitMessage(0); return 0;
    }
    if (msg == g_taskbar_created) { CreateTrayIcon(); return 0; }
    return ::DefWindowProcW(hwnd, msg, wp, lp);
}

// ─── Hook premier plan : tout est signalé, y compris explorer et FST ──
void CALLBACK OnForeground(HWINEVENTHOOK, DWORD, HWND hwnd, LONG, LONG,
                           DWORD, DWORD) {
    if (!hwnd) return;
    WindowApp app = AppOfWindow(hwnd);
    OnForegroundApp(app.id);
    SendForeground(app.id);
}

} // namespace

void RunMonitorProcess(HINSTANCE instance) {
    ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    g_single_instance = ::CreateMutexW(nullptr, TRUE,
                                       L"Local\\FamilyScreenTimeMonitor");
    if (!g_single_instance || ::GetLastError() == ERROR_ALREADY_EXISTS) {
        ::CoUninitialize();
        return;
    }

    WNDCLASSW wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = instance;
    wc.lpszClassName = kMonitorWindowClass;
    ::RegisterClassW(&wc);
    g_hwnd = ::CreateWindowW(kMonitorWindowClass, L"FamilyScreenTimeMonitor",
                             0, 0, 0, 0, 0, nullptr, nullptr, instance, nullptr);
    ::ShowWindow(g_hwnd, SW_HIDE);

    g_taskbar_created = ::RegisterWindowMessageW(L"TaskbarCreated");
    ::WTSRegisterSessionNotification(g_hwnd, NOTIFY_FOR_THIS_SESSION);
    g_display_notify = ::RegisterPowerSettingNotification(
        g_hwnd, &GUID_CONSOLE_DISPLAY_STATE, DEVICE_NOTIFY_WINDOW_HANDLE);
    CreateTrayIcon();

    g_volume = new VolumeGuard();
    g_volume->Init();

    flutter::DartProject project(L"data");
    project.set_dart_entrypoint("monitorMain");
    project.set_dart_entrypoint_arguments({"--monitor"});

    g_engine = std::make_unique<flutter::FlutterEngine>(project);

    // Enregistrer les plugins et canaux AVANT Run() pour que monitorMain
    // puisse les utiliser immédiatement.
    RegisterPlugins(g_engine.get());

    auto* messenger = g_engine->messenger();
    g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        messenger, "org.familyscreentime/monitor",
        &flutter::StandardMethodCodec::GetInstance());
    g_channel->SetMethodCallHandler(HandleCall);
    g_platform = new PlatformChannel(messenger);

    g_block_notice = new NoticeWindow([]{ OpenInterface(); });
    g_device_lock = new LockWindow([](int id) {
        if (id == -1) {
            OpenInterface();
        } else if (id >= 0 && id < (int)g_lock_exempt.size()) {
            LaunchApp(g_lock_exempt[id]);
        }
    });
    g_overlay = new OverlayWindow();
    g_eye_notice = new EyeNoticeWindow([](const char* action) {
        // The child's answer: the break now, or in a minute.
        auto a = std::make_unique<EncodableValue>(EncodableMap{
            {EncodableValue("action"), EncodableValue(action)}});
        SendToDart("eyeBreak", std::move(a));
    });
    g_eye_veil = new EyeVeilWindow();

    if (!g_engine->Run()) {
        delete g_block_notice;
        delete g_device_lock;
        delete g_overlay;
        delete g_eye_notice;
        delete g_eye_veil;
        delete g_platform;
        delete g_volume;
        ::CloseHandle(g_single_instance);
        ::CoUninitialize();
        return;
    }

    g_fg_hook = ::SetWinEventHook(EVENT_SYSTEM_FOREGROUND,
                                  EVENT_SYSTEM_FOREGROUND,
                                  nullptr, OnForeground, 0, 0,
                                  WINEVENT_OUTOFCONTEXT);

    MSG msg;
    while (::GetMessageW(&msg, nullptr, 0, 0)) {
        ::TranslateMessage(&msg);
        ::DispatchMessageW(&msg);
    }

    if (g_fg_hook) ::UnhookWinEvent(g_fg_hook);
    if (g_display_notify) ::UnregisterPowerSettingNotification(g_display_notify);
    ::WTSUnRegisterSessionNotification(g_hwnd);
    Shell_NotifyIconW(NIM_DELETE, &g_nid);
    delete g_block_notice;
    delete g_device_lock;
    delete g_overlay;
    delete g_eye_notice;
    delete g_eye_veil;
    delete g_platform;
    delete g_volume;
    g_channel.reset();
    g_engine.reset();
    if (g_single_instance) ::CloseHandle(g_single_instance);
    ::CoUninitialize();
}
