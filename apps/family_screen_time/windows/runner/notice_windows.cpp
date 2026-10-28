#include "notice_windows.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <algorithm>

namespace {

constexpr COLORREF kPrimary = RGB(0x3A, 0x5B, 0xA0);
constexpr COLORREF kDark = RGB(0x1F, 0x2A, 0x44);
constexpr COLORREF kText = RGB(0x1B, 0x1B, 0x1F);
constexpr COLORREF kMuted = RGB(0x5F, 0x63, 0x6E);
constexpr COLORREF kLightText = RGB(0xC9, 0xD1, 0xE3);
constexpr UINT_PTR kTickTimer = 1;

void Fill(HDC dc, const RECT& rect, COLORREF color) {
  HBRUSH brush = ::CreateSolidBrush(color);
  ::FillRect(dc, &rect, brush);
  ::DeleteObject(brush);
}

void RoundRect(HDC dc, const RECT& rect, int radius, COLORREF fill,
               COLORREF border) {
  HBRUSH brush = ::CreateSolidBrush(fill);
  HPEN pen = ::CreatePen(PS_SOLID, 1, border);
  HGDIOBJ old_brush = ::SelectObject(dc, brush);
  HGDIOBJ old_pen = ::SelectObject(dc, pen);
  ::RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, radius,
              radius);
  ::SelectObject(dc, old_brush);
  ::SelectObject(dc, old_pen);
  ::DeleteObject(brush);
  ::DeleteObject(pen);
}

void Text(HDC dc, const std::wstring& text, RECT rect, HFONT font,
          COLORREF color, UINT format) {
  HGDIOBJ old = ::SelectObject(dc, font);
  ::SetTextColor(dc, color);
  ::SetBkMode(dc, TRANSPARENT);
  ::DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &rect,
              format | DT_NOPREFIX);
  ::SelectObject(dc, old);
}

int TextWidth(HDC dc, const std::wstring& text, HFONT font) {
  HGDIOBJ old = ::SelectObject(dc, font);
  RECT rect = {0, 0, 0, 0};
  ::DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &rect,
              DT_CALCRECT | DT_SINGLELINE | DT_NOPREFIX);
  ::SelectObject(dc, old);
  return rect.right - rect.left;
}

// The monitor the child is looking at: that of the window in front.
RECT ActiveMonitorRect(bool work_area) {
  HMONITOR monitor = ::MonitorFromWindow(::GetForegroundWindow(),
                                         MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  ::GetMonitorInfoW(monitor, &info);
  return work_area ? info.rcWork : info.rcMonitor;
}

RECT PrimaryMonitorRect(bool work_area) {
  POINT origin = {0, 0};
  HMONITOR monitor = ::MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  ::GetMonitorInfoW(monitor, &info);
  return work_area ? info.rcWork : info.rcMonitor;
}


}  // namespace

int64_t NowMs() {
  FILETIME time;
  ::GetSystemTimeAsFileTime(&time);
  ULARGE_INTEGER value;
  value.LowPart = time.dwLowDateTime;
  value.HighPart = time.dwHighDateTime;
  return static_cast<int64_t>(value.QuadPart / 10000ULL) - 11644473600000LL;
}

// --- PaintedWindow ---------------------------------------------------------

PaintedWindow::~PaintedWindow() {
  for (auto& [key, font] : fonts_) ::DeleteObject(font);
  if (hwnd_) ::DestroyWindow(hwnd_);
}

bool PaintedWindow::Visible() const {
  return hwnd_ && ::IsWindowVisible(hwnd_);
}

void PaintedWindow::Hide() {
  if (hwnd_) ::ShowWindow(hwnd_, SW_HIDE);
}

bool PaintedWindow::Ensure(const wchar_t* window_class, DWORD ex_style) {
  if (hwnd_) return true;
  HINSTANCE instance = ::GetModuleHandleW(nullptr);
  WNDCLASSEXW wc = {};
  if (!::GetClassInfoExW(instance, window_class, &wc)) {
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = Proc;
    wc.hInstance = instance;
    wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = window_class;
    wc.hIcon = ::LoadIconW(instance, MAKEINTRESOURCEW(101));
    ::RegisterClassExW(&wc);
  }
  hwnd_ = ::CreateWindowExW(ex_style, window_class, L"Family Screen Time",
                            WS_POPUP, 0, 0, 10, 10, nullptr, nullptr, instance,
                            this);
  if (!hwnd_) return false;
  dpi_ = ::GetDpiForWindow(hwnd_);
  if (dpi_ == 0) dpi_ = 96;
  return true;
}

int PaintedWindow::Scale(int value) const {
  return ::MulDiv(value, static_cast<int>(dpi_), 96);
}

HFONT PaintedWindow::Font(int points, bool bold) {
  int key = points * 2 + (bold ? 1 : 0);
  auto it = fonts_.find(key);
  if (it != fonts_.end()) return it->second;
  HFONT font = ::CreateFontW(-::MulDiv(points, static_cast<int>(dpi_), 72), 0,
                             0, 0, bold ? FW_SEMIBOLD : FW_NORMAL, FALSE,
                             FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                             CLEARTYPE_QUALITY, DEFAULT_PITCH,
                             L"Segoe UI");
  fonts_[key] = font;
  return font;
}

int PaintedWindow::TextHeight(const std::wstring& text, HFONT font,
                              int width) {
  if (text.empty()) return 0;
  HDC dc = ::GetDC(hwnd_);
  HGDIOBJ old = ::SelectObject(dc, font);
  RECT rect = {0, 0, width, 0};
  ::DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &rect,
              DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX);
  ::SelectObject(dc, old);
  ::ReleaseDC(hwnd_, dc);
  return rect.bottom - rect.top;
}

void PaintedWindow::DrawButton(HDC dc, const Button& button, bool dark) {
  bool hover = hover_ == button.id;
  COLORREF fill, border, text;
  if (button.primary) {
    fill = hover ? RGB(0x2F, 0x4C, 0x88) : kPrimary;
    border = fill;
    text = RGB(0xFF, 0xFF, 0xFF);
  } else if (dark) {
    fill = hover ? RGB(0x34, 0x40, 0x5E) : kDark;
    border = RGB(0x6B, 0x78, 0x99);
    text = RGB(0xFF, 0xFF, 0xFF);
  } else {
    fill = hover ? RGB(0xEE, 0xF1, 0xF8) : RGB(0xFF, 0xFF, 0xFF);
    border = RGB(0xB8, 0xC0, 0xD0);
    text = kPrimary;
  }
  RoundRect(dc, button.rect, Scale(18), fill, border);
  Text(dc, button.text, button.rect, Font(10, true), text,
       DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

int PaintedWindow::ButtonAt(POINT point) const {
  for (const auto& button : buttons_) {
    if (::PtInRect(&button.rect, point)) return button.id;
  }
  return -100;
}

LRESULT CALLBACK PaintedWindow::Proc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* self =
      reinterpret_cast<PaintedWindow*>(::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self && self->hwnd_ == hwnd) return self->Handle(message, wparam, lparam);
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT PaintedWindow::Handle(UINT message, WPARAM wparam, LPARAM lparam) {
  LRESULT result = 0;
  if (Message(message, wparam, lparam, &result)) return result;
  switch (message) {
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = ::BeginPaint(hwnd_, &ps);
      RECT client;
      ::GetClientRect(hwnd_, &client);
      // Drawn off screen first: no flicker.
      HDC memory = ::CreateCompatibleDC(dc);
      HBITMAP bitmap = ::CreateCompatibleBitmap(dc, client.right, client.bottom);
      HGDIOBJ old = ::SelectObject(memory, bitmap);
      Paint(memory, client);
      ::BitBlt(dc, 0, 0, client.right, client.bottom, memory, 0, 0, SRCCOPY);
      ::SelectObject(memory, old);
      ::DeleteObject(bitmap);
      ::DeleteDC(memory);
      ::EndPaint(hwnd_, &ps);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_MOUSEMOVE: {
      if (!tracking_) {
        TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE, hwnd_, 0};
        ::TrackMouseEvent(&track);
        tracking_ = true;
      }
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      int hover = ButtonAt(point);
      if (hover != hover_) {
        hover_ = hover;
        ::InvalidateRect(hwnd_, nullptr, FALSE);
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      tracking_ = false;
      if (hover_ != -100) {
        hover_ = -100;
        ::InvalidateRect(hwnd_, nullptr, FALSE);
      }
      return 0;
    case WM_SETCURSOR: {
      POINT point;
      ::GetCursorPos(&point);
      ::ScreenToClient(hwnd_, &point);
      ::SetCursor(::LoadCursorW(
          nullptr, ButtonAt(point) != -100 ? IDC_HAND : IDC_ARROW));
      return TRUE;
    }
    case WM_LBUTTONUP: {
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      int id = ButtonAt(point);
      if (id != -100) Clicked(id);
      return 0;
    }
    case WM_DPICHANGED:
      dpi_ = HIWORD(wparam);
      for (auto& [key, font] : fonts_) ::DeleteObject(font);
      fonts_.clear();
      return 0;
    case WM_CLOSE:
      // Alt+F4 hides it; it is never destroyed by the child.
      Hide();
      return 0;
  }
  return ::DefWindowProcW(hwnd_, message, wparam, lparam);
}

// --- NoticeWindow ----------------------------------------------------------

namespace {
constexpr int kOk = 1;
constexpr int kOpen = 2;
}  // namespace

void NoticeWindow::Show(const std::wstring& title, const std::wstring& message,
                        const std::wstring& detail, const std::wstring& ok,
                        const std::wstring& open) {
  if (!Ensure(L"FamilyScreenTimeNotice", WS_EX_TOPMOST | WS_EX_TOOLWINDOW)) {
    return;
  }
  title_ = title;
  message_ = message;
  detail_ = detail;
  ok_ = ok;
  open_ = open;
  Layout();
  ::ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  ::SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  ::SetForegroundWindow(hwnd_);
  ::InvalidateRect(hwnd_, nullptr, FALSE);
}

void NoticeWindow::Layout() {
  int pad = Scale(24);
  int width = Scale(440);
  int inner = width - 2 * pad;
  int y = Scale(8) + pad;
  int h = TextHeight(title_, Font(14, true), inner);
  title_rect_ = {pad, y, pad + inner, y + h};
  y += h + Scale(10);
  h = TextHeight(message_, Font(11, false), inner);
  message_rect_ = {pad, y, pad + inner, y + h};
  y += h + (detail_.empty() ? 0 : Scale(8));
  h = TextHeight(detail_, Font(10, false), inner);
  detail_rect_ = {pad, y, pad + inner, y + h};
  y += h + Scale(24);

  buttons_.clear();
  HDC dc = ::GetDC(hwnd_);
  int button_height = Scale(36);
  int right = width - pad;
  int ok_width = std::max(Scale(88), TextWidth(dc, ok_, Font(10, true)) +
                                         Scale(40));
  buttons_.push_back({{right - ok_width, y, right, y + button_height},
                      ok_,
                      kOk,
                      true});
  right -= ok_width + Scale(8);
  if (!open_.empty()) {
    int open_width = TextWidth(dc, open_, Font(10, true)) + Scale(40);
    buttons_.push_back({{right - open_width, y, right, y + button_height},
                        open_,
                        kOpen,
                        false});
  }
  ::ReleaseDC(hwnd_, dc);
  int height = y + button_height + pad;

  RECT area = ActiveMonitorRect(true);
  int x = area.left + (area.right - area.left - width) / 2;
  int top = area.top + (area.bottom - area.top - height) / 3;
  ::SetWindowPos(hwnd_, HWND_TOPMOST, x, top, width, height, SWP_NOACTIVATE);
  // Rounded on Windows 11.
  DWORD corners = 2;  // DWMWCP_ROUND
  ::DwmSetWindowAttribute(hwnd_, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */,
                          &corners, sizeof(corners));
}

void NoticeWindow::Paint(HDC dc, const RECT& client) {
  Fill(dc, client, RGB(0xFF, 0xFF, 0xFF));
  RECT band = {0, 0, client.right, Scale(6)};
  Fill(dc, band, kPrimary);
  HPEN pen = ::CreatePen(PS_SOLID, 1, RGB(0xC8, 0xCD, 0xD8));
  HGDIOBJ old_pen = ::SelectObject(dc, pen);
  HGDIOBJ old_brush = ::SelectObject(dc, ::GetStockObject(NULL_BRUSH));
  ::Rectangle(dc, 0, 0, client.right, client.bottom);
  ::SelectObject(dc, old_pen);
  ::SelectObject(dc, old_brush);
  ::DeleteObject(pen);
  Text(dc, title_, title_rect_, Font(14, true), kText, DT_WORDBREAK);
  Text(dc, message_, message_rect_, Font(11, false), kText, DT_WORDBREAK);
  Text(dc, detail_, detail_rect_, Font(10, false), kMuted, DT_WORDBREAK);
  for (const auto& button : buttons_) DrawButton(dc, button, false);
}

void NoticeWindow::Clicked(int id) {
  Hide();
  if (id == kOpen && on_open_) on_open_();
}

bool NoticeWindow::Message(UINT message, WPARAM wparam, LPARAM lparam,
                           LRESULT* result) {
  if (message == WM_KEYDOWN && (wparam == VK_RETURN || wparam == VK_ESCAPE)) {
    Hide();
    *result = 0;
    return true;
  }
  if (message == WM_DPICHANGED) {
    dpi_ = HIWORD(wparam);
    Layout();
    *result = 0;
    return true;
  }
  return false;
}

// --- LockWindow ------------------------------------------------------------

void LockWindow::Show(const std::wstring& title, const std::wstring& message,
                      const std::wstring& open,
                      const std::vector<std::wstring>& apps) {
  if (!Ensure(L"FamilyScreenTimeLock", WS_EX_TOPMOST | WS_EX_TOOLWINDOW)) {
    return;
  }
  bool changed = title != title_ || message != message_ || open != open_ ||
                 apps != apps_ || !Visible();
  title_ = title;
  message_ = message;
  open_ = open;
  apps_ = apps;
  if (changed) Layout();
  if (!Visible()) ::ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  Raise();
  if (changed) ::InvalidateRect(hwnd_, nullptr, FALSE);
}

void LockWindow::Raise() {
  if (!Visible()) return;
  ::SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void LockWindow::Layout() {
  int left = ::GetSystemMetrics(SM_XVIRTUALSCREEN);
  int top = ::GetSystemMetrics(SM_YVIRTUALSCREEN);
  int width = ::GetSystemMetrics(SM_CXVIRTUALSCREEN);
  int height = ::GetSystemMetrics(SM_CYVIRTUALSCREEN);
  ::SetWindowPos(hwnd_, HWND_TOPMOST, left, top, width, height,
                 SWP_NOACTIVATE);

  // The text on the main screen, in the window's coordinates.
  RECT screen = PrimaryMonitorRect(false);
  ::OffsetRect(&screen, -left, -top);
  int screen_width = screen.right - screen.left;
  int inner = std::min(Scale(600), screen_width - Scale(64));
  int x = screen.left + (screen_width - inner) / 2;
  int title_height = TextHeight(title_, Font(22, true), inner);
  int message_height = TextHeight(message_, Font(13, false), inner);
  int button_height = Scale(40);
  int block = title_height + Scale(16) + message_height + Scale(40) +
              button_height * 2 + Scale(12);
  int y = screen.top + (screen.bottom - screen.top - block) / 2;
  title_rect_ = {x, y, x + inner, y + title_height};
  y += title_height + Scale(16);
  message_rect_ = {x, y, x + inner, y + message_height};
  y += message_height + Scale(40);

  // The app's button, then those of the apps that stay open, centered in
  // rows.
  buttons_.clear();
  HDC dc = ::GetDC(hwnd_);
  std::vector<Button> row;
  int row_width = 0;
  int gap = Scale(12);
  auto flush = [&]() {
    int start = x + (inner - row_width) / 2;
    for (auto& b : row) {
      int w = b.rect.right;
      b.rect = {start, y, start + w, y + button_height};
      start += w + gap;
      buttons_.push_back(b);
    }
    row.clear();
    row_width = 0;
    y += button_height + gap;
  };
  auto add = [&](const std::wstring& text, int id, bool primary) {
    int w = TextWidth(dc, text, Font(10, true)) + Scale(48);
    w = std::min(w, inner);
    if (!row.empty() && row_width + gap + w > inner) flush();
    row_width += (row.empty() ? 0 : gap) + w;
    row.push_back({{0, 0, w, 0}, text, id, primary});
  };
  if (!open_.empty()) add(open_, -1, true);
  for (size_t i = 0; i < apps_.size() && i < 8; i++) {
    add(apps_[i], static_cast<int>(i), false);
  }
  if (!row.empty()) flush();
  ::ReleaseDC(hwnd_, dc);
}

void LockWindow::Paint(HDC dc, const RECT& client) {
  Fill(dc, client, kDark);
  Text(dc, title_, title_rect_, Font(22, true), RGB(0xFF, 0xFF, 0xFF),
       DT_CENTER | DT_WORDBREAK);
  Text(dc, message_, message_rect_, Font(13, false), kLightText,
       DT_CENTER | DT_WORDBREAK);
  for (const auto& button : buttons_) DrawButton(dc, button, true);
}

void LockWindow::Clicked(int id) {
  if (on_click_) on_click_(id);
}

bool LockWindow::Message(UINT message, WPARAM wparam, LPARAM lparam,
                         LRESULT* result) {
  switch (message) {
    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
      if (message == WM_DPICHANGED) dpi_ = HIWORD(wparam);
      Layout();
      ::InvalidateRect(hwnd_, nullptr, FALSE);
      *result = 0;
      return true;
    case WM_CLOSE:
      // Alt+F4 does not take it away.
      *result = 0;
      return true;
  }
  return false;
}

// --- OverlayWindow ---------------------------------------------------------

void OverlayWindow::Show(int64_t ends_at_ms) {
  if (!Ensure(L"FamilyScreenTimeOverlay",
              WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED |
                  WS_EX_NOACTIVATE)) {
    return;
  }
  ends_at_ = ends_at_ms;
  if (!placed_) {
    placed_ = true;
    ::SetLayeredWindowAttributes(hwnd_, 0, 235, LWA_ALPHA);
    RECT area = PrimaryMonitorRect(true);
    int width = Scale(104);
    int height = Scale(44);
    ::SetWindowPos(hwnd_, HWND_TOPMOST, area.right - width - Scale(16),
                   area.bottom - height - Scale(16), width, height,
                   SWP_NOACTIVATE);
    HRGN region = ::CreateRoundRectRgn(0, 0, width + 1, height + 1,
                                       Scale(22), Scale(22));
    ::SetWindowRgn(hwnd_, region, TRUE);
    ::SetTimer(hwnd_, kTickTimer, 1000, nullptr);
  }
  if (!Visible()) ::ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  Raise();
  ::InvalidateRect(hwnd_, nullptr, FALSE);
}

void OverlayWindow::Raise() {
  if (!Visible()) return;
  ::SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void OverlayWindow::Paint(HDC dc, const RECT& client) {
  Fill(dc, client, kDark);
  int64_t left = std::max<int64_t>(0, (ends_at_ - NowMs() + 999) / 1000);
  int64_t hours = left / 3600;
  int64_t minutes = (left / 60) % 60;
  int64_t seconds = left % 60;
  wchar_t text[32];
  if (hours > 0) {
    swprintf_s(text, L"%lld:%02lld:%02lld", hours, minutes, seconds);
  } else {
    swprintf_s(text, L"%lld:%02lld", minutes, seconds);
  }
  Text(dc, text, client, Font(15, true), RGB(0xFF, 0xFF, 0xFF),
       DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

bool OverlayWindow::Message(UINT message, WPARAM wparam, LPARAM lparam,
                            LRESULT* result) {
  switch (message) {
    case WM_TIMER:
      if (wparam == kTickTimer) {
        ::InvalidateRect(hwnd_, nullptr, FALSE);
        *result = 0;
        return true;
      }
      break;
    case WM_NCHITTEST:
      // Moved by dragging it anywhere.
      *result = HTCAPTION;
      return true;
    case WM_MOUSEACTIVATE:
      *result = MA_NOACTIVATE;
      return true;
  }
  return false;
}
