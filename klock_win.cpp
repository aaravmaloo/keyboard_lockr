// klock_win.cpp
// Windows: blocks all keyboard input when locked, toggled with Ctrl+Shift+X.
// Tray icon (keyboard glyph + lock badge) is drawn at runtime with GDI, no image files needed.
// Build (MinGW):  g++ -O2 -mwindows -o klock.exe klock_win.cpp -lgdi32 -lshell32
// Build (MSVC):   cl klock_win.cpp /link user32.lib gdi32.lib shell32.lib

#include <windows.h>
#include <string>

static bool locked = false;
static HHOOK hook = NULL;
static NOTIFYICONDATAW nid = {};
static HICON iconLocked = NULL;
static HICON iconUnlocked = NULL;
static const UINT WM_TRAYICON = WM_APP + 1;
static const UINT ID_TRAY_TOGGLE = 1001;
static const UINT ID_TRAY_EXIT = 1002;

// Draws a keyboard glyph with a lock badge (front, bottom-right) onto a 32x32 DIB and returns an HICON.
HICON DrawTrayIcon(bool isLocked) {
    HDC screenDC = GetDC(NULL);
    HDC memDC = CreateCompatibleDC(screenDC);

    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = 32;
    bmi.bmiHeader.biHeight = -32; // top-down
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    void* bits = nullptr;
    HBITMAP color = CreateDIBSection(memDC, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
    HBITMAP oldBmp = (HBITMAP)SelectObject(memDC, color);

    RECT full = {0, 0, 32, 32};
    HBRUSH transparent = (HBRUSH)GetStockObject(NULL_BRUSH);
    HBRUSH bg = CreateSolidBrush(RGB(0, 0, 0));
    FillRect(memDC, &full, transparent); // keep alpha 0 where untouched, filled below via masking

    HPEN penFg = CreatePen(PS_SOLID, 2, RGB(0, 0, 0));
    HPEN oldPen = (HPEN)SelectObject(memDC, penFg);
    SelectObject(memDC, GetStockObject(NULL_BRUSH));

    // Keyboard outline (rounded rect)
    RoundRect(memDC, 3, 8, 26, 22, 4, 4);

    // Keys: two rows of dots + a wide spacebar bar
    HBRUSH dotBrush = CreateSolidBrush(RGB(0, 0, 0));
    SelectObject(memDC, dotBrush);
    int rowY1 = 11, rowY2 = 15;
    int xs[6] = {6, 9, 12, 15, 18, 21};
    for (int i = 0; i < 6; i++) {
        Ellipse(memDC, xs[i] - 1, rowY1 - 1, xs[i] + 1, rowY1 + 1);
        Ellipse(memDC, xs[i] - 1, rowY2 - 1, xs[i] + 1, rowY2 + 1);
    }
    RECT spacebar = {8, 17, 21, 19};
    FillRect(memDC, &spacebar, dotBrush);

    // Lock badge, bottom-right, drawn in front (on top of keyboard edge)
    COLORREF lockColor = isLocked ? RGB(200, 30, 30) : RGB(60, 60, 60);
    HBRUSH lockBrush = CreateSolidBrush(lockColor);
    HPEN lockPen = CreatePen(PS_SOLID, 2, lockColor);
    SelectObject(memDC, lockPen);
    SelectObject(memDC, lockBrush);

    // Body of the padlock
    RoundRect(memDC, 18, 19, 30, 29, 3, 3);
    // Shackle (arc)
    SelectObject(memDC, transparent);
    Arc(memDC, 20, 13, 28, 23, 20, 18, 28, 18);
    // Keyhole dot
    HBRUSH holeBrush = CreateSolidBrush(RGB(255, 255, 255));
    SelectObject(memDC, holeBrush);
    Ellipse(memDC, 23, 22, 25, 24);

    SelectObject(memDC, oldPen);
    SelectObject(memDC, oldBmp);
    DeleteObject(penFg);
    DeleteObject(dotBrush);
    DeleteObject(lockBrush);
    DeleteObject(lockPen);
    DeleteObject(holeBrush);
    DeleteObject(bg);
    DeleteDC(memDC);
    ReleaseDC(NULL, screenDC);

    // Build a matching 1-bit mask (opaque everywhere we drew; simplest is "all opaque" 32x32)
    HBITMAP mask = CreateBitmap(32, 32, 1, 1, NULL);
    HDC maskDC = CreateCompatibleDC(NULL);
    HBITMAP oldMask = (HBITMAP)SelectObject(maskDC, mask);
    RECT maskRect = {0, 0, 32, 32};
    FillRect(maskDC, &maskRect, (HBRUSH)GetStockObject(BLACK_BRUSH)); // 0 = opaque in AND mask
    SelectObject(maskDC, oldMask);
    DeleteDC(maskDC);

    ICONINFO ii = {};
    ii.fIcon = TRUE;
    ii.hbmMask = mask;
    ii.hbmColor = color;

    HICON result = CreateIconIndirect(&ii);
    DeleteObject(mask);
    DeleteObject(color);
    return result;
}

void UpdateTrayIcon(HWND hwnd) {
    HICON icon = locked ? iconLocked : iconUnlocked;
    nid.hIcon = icon;
    wcscpy_s(nid.szTip, locked ? L"klock - LOCKED (Ctrl+Shift+X to unlock)" : L"klock - unlocked (Ctrl+Shift+X to lock)");
    Shell_NotifyIconW(NIM_MODIFY, &nid);
}

LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode == HC_ACTION) {
        KBDLLHOOKSTRUCT* kb = (KBDLLHOOKSTRUCT*)lParam;
        bool ctrl = GetAsyncKeyState(VK_CONTROL) & 0x8000;
        bool shift = GetAsyncKeyState(VK_SHIFT) & 0x8000;
        bool isX = kb->vkCode == 'X';

        if (ctrl && shift && isX && wParam == WM_KEYDOWN) {
            locked = !locked;
            UpdateTrayIcon(nid.hWnd);
            return 1; // swallow the toggle combo itself
        }
        if (locked) {
            return 1; // block everything else
        }
    }
    return CallNextHookEx(hook, nCode, wParam, lParam);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_TRAYICON:
            if (lParam == WM_RBUTTONUP || lParam == WM_LBUTTONUP) {
                POINT pt;
                GetCursorPos(&pt);
                HMENU menu = CreatePopupMenu();
                AppendMenuW(menu, MF_STRING, ID_TRAY_TOGGLE, locked ? L"Unlock (Ctrl+Shift+X)" : L"Lock (Ctrl+Shift+X)");
                AppendMenuW(menu, MF_SEPARATOR, 0, NULL);
                AppendMenuW(menu, MF_STRING, ID_TRAY_EXIT, L"Exit");
                SetForegroundWindow(hwnd); // required so the menu dismisses correctly
                TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, NULL);
                DestroyMenu(menu);
            }
            return 0;
        case WM_COMMAND:
            if (LOWORD(wParam) == ID_TRAY_TOGGLE) {
                locked = !locked;
                UpdateTrayIcon(hwnd);
            } else if (LOWORD(wParam) == ID_TRAY_EXIT) {
                DestroyWindow(hwnd);
            }
            return 0;
        case WM_DESTROY:
            Shell_NotifyIconW(NIM_DELETE, &nid);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = L"KlockWndClass";
    RegisterClassW(&wc);

    HWND hwnd = CreateWindowW(L"KlockWndClass", L"klock", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, hInstance, NULL);

    iconUnlocked = DrawTrayIcon(false);
    iconLocked = DrawTrayIcon(true);

    nid.cbSize = sizeof(nid);
    nid.hWnd = hwnd;
    nid.uID = 1;
    nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    nid.uCallbackMessage = WM_TRAYICON;
    nid.hIcon = iconUnlocked;
    wcscpy_s(nid.szTip, L"klock - unlocked (Ctrl+Shift+X to lock)");
    Shell_NotifyIconW(NIM_ADD, &nid);

    hook = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc, NULL, 0);

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    UnhookWindowsHookEx(hook);
    DestroyIcon(iconLocked);
    DestroyIcon(iconUnlocked);
    return 0;
}
