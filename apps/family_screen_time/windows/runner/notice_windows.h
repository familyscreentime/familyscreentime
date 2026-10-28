// The monitor's own windows, drawn without Flutter: the notice that an app
// was closed, the screen covering everything when the device is locked,
// and the floating countdown.
#ifndef RUNNER_NOTICE_WINDOWS_H_
#define RUNNER_NOTICE_WINDOWS_H_

#include <windows.h>

#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <vector>

// Milliseconds since 1970, as Dart counts them.
int64_t NowMs();

// A popup window that draws itself, with buttons.
class PaintedWindow {
 public:
  PaintedWindow() = default;
  virtual ~PaintedWindow();
  PaintedWindow(const PaintedWindow&) = delete;
  PaintedWindow& operator=(const PaintedWindow&) = delete;

  HWND hwnd() const { return hwnd_; }
  bool Visible() const;
  void Hide();

 protected:
  struct Button {
    RECT rect;
    std::wstring text;
    int id;
    bool primary;
  };

  // Creates the window, hidden, once.
  bool Ensure(const wchar_t* window_class, DWORD ex_style);

  virtual void Paint(HDC dc, const RECT& client) = 0;
  virtual void Clicked(int id) {}

  // Other messages; returns true when handled, with [result].
  virtual bool Message(UINT message, WPARAM wparam, LPARAM lparam,
                       LRESULT* result) {
    return false;
  }

  int Scale(int value) const;
  HFONT Font(int points, bool bold);
  void DrawButton(HDC dc, const Button& button, bool dark);

  // The height [text] takes in [width] pixels.
  int TextHeight(const std::wstring& text, HFONT font, int width);

  HWND hwnd_ = nullptr;
  UINT dpi_ = 96;
  std::vector<Button> buttons_;
  int hover_ = -1;

 private:
  static LRESULT CALLBACK Proc(HWND hwnd, UINT message, WPARAM wparam,
                               LPARAM lparam);
  LRESULT Handle(UINT message, WPARAM wparam, LPARAM lparam);
  int ButtonAt(POINT point) const;

  std::map<int, HFONT> fonts_;
  bool tracking_ = false;
};

// Says why an app was just closed.
class NoticeWindow : public PaintedWindow {
 public:
  explicit NoticeWindow(std::function<void()> on_open)
      : on_open_(std::move(on_open)) {}

  void Show(const std::wstring& title, const std::wstring& message,
            const std::wstring& detail, const std::wstring& ok,
            const std::wstring& open);

 protected:
  void Paint(HDC dc, const RECT& client) override;
  void Clicked(int id) override;
  bool Message(UINT message, WPARAM wparam, LPARAM lparam,
               LRESULT* result) override;

 private:
  void Layout();

  std::function<void()> on_open_;
  std::wstring title_, message_, detail_, ok_, open_;
  RECT title_rect_{}, message_rect_{}, detail_rect_{};
};

// Covers every screen while the device is locked.
class LockWindow : public PaintedWindow {
 public:
  // [on_click]: -1 for the app's button, else the index of an app that
  // stays open.
  explicit LockWindow(std::function<void(int)> on_click)
      : on_click_(std::move(on_click)) {}

  void Show(const std::wstring& title, const std::wstring& message,
            const std::wstring& open, const std::vector<std::wstring>& apps);

  // Back on top of the others.
  void Raise();

 protected:
  void Paint(HDC dc, const RECT& client) override;
  void Clicked(int id) override;
  bool Message(UINT message, WPARAM wparam, LPARAM lparam,
               LRESULT* result) override;

 private:
  void Layout();

  std::function<void(int)> on_click_;
  std::wstring title_, message_, open_;
  std::vector<std::wstring> apps_;
  RECT title_rect_{}, message_rect_{};
};

// The time left, in a small window over the others, moved with the mouse.
class OverlayWindow : public PaintedWindow {
 public:
  void Show(int64_t ends_at_ms);

  // Back on top of the others.
  void Raise();

 protected:
  void Paint(HDC dc, const RECT& client) override;
  bool Message(UINT message, WPARAM wparam, LPARAM lparam,
               LRESULT* result) override;

 private:
  int64_t ends_at_ = 0;
  bool placed_ = false;
};

#endif  // RUNNER_NOTICE_WINDOWS_H_
