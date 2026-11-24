//! Déclarations Win32 utilisées par AutoCurseur et ses tests (seulement ce qui sert).

const core = @import("core.zig");

pub const BOOL = c_int;
pub const UINT = c_uint;
pub const DWORD = u32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const HANDLE = ?*anyopaque;
pub const HWND = HANDLE;
pub const HDC = HANDLE;
pub const HMODULE = HANDLE;
pub const HBITMAP = HANDLE;
pub const HGDIOBJ = HANDLE;
pub const HCURSOR = HANDLE;
pub const HICON = HANDLE;
pub const HMENU = HANDLE;
pub const HINSTANCE = HANDLE;
pub const HKEY = HANDLE;
pub const HFONT = HANDLE;
pub const HBRUSH = HANDLE;
pub const LPCWSTR = [*:0]const u16;
pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;
pub const POINT = core.Point;

pub const MAX_PATH = 260;
pub const GENERIC_READ: DWORD = 0x80000000;
pub const GENERIC_WRITE: DWORD = 0x40000000;
pub const FILE_SHARE_READ: DWORD = 1;
pub const CREATE_ALWAYS: DWORD = 2;
pub const OPEN_EXISTING: DWORD = 3;
pub const FILE_ATTRIBUTE_NORMAL: DWORD = 0x80;
pub const INVALID_FILE_ATTRIBUTES: DWORD = 0xFFFFFFFF;
pub const MOVEFILE_REPLACE_EXISTING: DWORD = 1;
pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(~@as(usize, 0));
pub const WM_NULL = 0x0000;
pub const WM_DESTROY = 0x0002;
pub const WM_CLOSE = 0x0010;
pub const WM_SETTINGCHANGE = 0x001A;
pub const WM_DISPLAYCHANGE = 0x007E;
pub const WM_COMMAND = 0x0111;
pub const WM_TIMER = 0x0113;
pub const WM_LBUTTONDBLCLK = 0x0203;
pub const WM_RBUTTONUP = 0x0205;
pub const WM_APP = 0x8000;
pub const SM_CXSCREEN = 0;
pub const SM_CYSCREEN = 1;
pub const SM_CXCURSOR = 13;
pub const GR_GDIOBJECTS = 0;
pub const GR_USEROBJECTS = 1;
pub const SM_CXSMICON = 49;
pub const SM_XVIRTUALSCREEN = 76;
pub const SM_YVIRTUALSCREEN = 77;
pub const SM_CXVIRTUALSCREEN = 78;
pub const SM_CYVIRTUALSCREEN = 79;
pub const IMAGE_CURSOR = 2;
pub const LR_LOADFROMFILE = 0x10;
pub const SPI_SETCURSORS = 0x0057;
pub const SRCCOPY = 0x00CC0020;
pub const DIB_RGB_COLORS = 0;
pub const DI_NORMAL = 3;
pub const MF_STRING = 0x0000;
pub const MF_CHECKED = 0x0008;
pub const MF_SEPARATOR = 0x0800;
pub const MF_POPUP = 0x0010;
pub const MFT_RADIOCHECK = 0x0200;
pub const TPM_RIGHTBUTTON = 0x0002;
pub const TPM_BOTTOMALIGN = 0x0020;
pub const NIM_ADD = 0;
pub const NIM_MODIFY = 1;
pub const NIM_DELETE = 2;
pub const NIF_MESSAGE = 0x1;
pub const NIF_ICON = 0x2;
pub const NIF_TIP = 0x4;
pub const ERROR_ALREADY_EXISTS = 183;
pub const RRF_RT_REG_SZ = 0x02;
pub const RRF_RT_REG_DWORD = 0x10;
pub const KEY_SET_VALUE = 0x0002;
pub const REG_SZ = 1;
pub const REG_DWORD = 4;
pub const TRANSPARENT = 1;
pub const FW_NORMAL = 400;
pub const FW_BOLD = 700;
pub const WAIT_OBJECT_0 = 0;
pub const INFINITE: DWORD = 0xFFFFFFFF;
pub const STACK_SIZE_PARAM_IS_A_RESERVATION: DWORD = 0x10000;
pub const IDC_ARROW: LPCWSTR = @ptrFromInt(32512);
pub const HKCU: HKEY = @ptrFromInt(0x80000001);
pub const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));

pub const MSG = extern struct { hwnd: HWND, message: UINT, wParam: WPARAM, lParam: LPARAM, time: DWORD, pt: POINT, lPrivate: DWORD };
pub const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
pub const WNDCLASSW = extern struct {
    style: UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: HINSTANCE = null,
    hIcon: HICON = null,
    hCursor: HCURSOR = null,
    hbrBackground: HBRUSH = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
};
pub const CURSORINFO = extern struct { cbSize: DWORD = @sizeOf(CURSORINFO), flags: DWORD = 0, hCursor: HCURSOR = null, ptScreenPos: POINT = .{} };
pub const ICONINFO = extern struct { fIcon: BOOL, xHotspot: DWORD, yHotspot: DWORD, hbmMask: HBITMAP, hbmColor: HBITMAP };
pub const BITMAP = extern struct { bmType: i32, bmWidth: i32, bmHeight: i32, bmWidthBytes: i32, bmPlanes: u16, bmBitsPixel: u16, bmBits: ?*anyopaque };
pub const BITMAPINFOHEADER = extern struct {
    biSize: DWORD = @sizeOf(BITMAPINFOHEADER),
    biWidth: i32,
    biHeight: i32,
    biPlanes: u16 = 1,
    biBitCount: u16 = 32,
    biCompression: DWORD = 0, // BI_RGB
    biSizeImage: DWORD = 0,
    biXPelsPerMeter: i32 = 0,
    biYPelsPerMeter: i32 = 0,
    biClrUsed: DWORD = 0,
    biClrImportant: DWORD = 0,
};
pub const BITMAPINFO = extern struct { bmiHeader: BITMAPINFOHEADER, bmiColors: [1]DWORD = .{0} };
pub const GUID = extern struct { a: u32 = 0, b: u16 = 0, c: u16 = 0, d: [8]u8 = @splat(0) };
pub const NOTIFYICONDATAW = extern struct {
    cbSize: DWORD = @sizeOf(NOTIFYICONDATAW),
    hWnd: HWND = null,
    uID: UINT = 0,
    uFlags: UINT = 0,
    uCallbackMessage: UINT = 0,
    hIcon: HICON = null,
    szTip: [128]u16 = @splat(0),
    dwState: DWORD = 0,
    dwStateMask: DWORD = 0,
    szInfo: [256]u16 = @splat(0),
    uVersion: UINT = 0,
    szInfoTitle: [64]u16 = @splat(0),
    dwInfoFlags: DWORD = 0,
    guidItem: GUID = .{},
    hBalloonIcon: HICON = null,
};
pub const STARTUPINFOW = extern struct {
    cb: DWORD = @sizeOf(STARTUPINFOW),
    lpReserved: ?LPCWSTR = null,
    lpDesktop: ?LPCWSTR = null,
    lpTitle: ?LPCWSTR = null,
    dwX: DWORD = 0,
    dwY: DWORD = 0,
    dwXSize: DWORD = 0,
    dwYSize: DWORD = 0,
    dwXCountChars: DWORD = 0,
    dwYCountChars: DWORD = 0,
    dwFillAttribute: DWORD = 0,
    dwFlags: DWORD = 0,
    wShowWindow: u16 = 0,
    cbReserved2: u16 = 0,
    lpReserved2: ?*anyopaque = null,
    hStdInput: HANDLE = null,
    hStdOutput: HANDLE = null,
    hStdError: HANDLE = null,
};
pub const PROCESS_INFORMATION = extern struct { hProcess: HANDLE = null, hThread: HANDLE = null, dwProcessId: DWORD = 0, dwThreadId: DWORD = 0 };
pub const PROCESS_MEMORY_COUNTERS_EX = extern struct {
    cb: DWORD = @sizeOf(PROCESS_MEMORY_COUNTERS_EX),
    PageFaultCount: DWORD = 0,
    PeakWorkingSetSize: usize = 0,
    WorkingSetSize: usize = 0,
    QuotaPeakPagedPoolUsage: usize = 0,
    QuotaPagedPoolUsage: usize = 0,
    QuotaPeakNonPagedPoolUsage: usize = 0,
    QuotaNonPagedPoolUsage: usize = 0,
    PagefileUsage: usize = 0,
    PeakPagefileUsage: usize = 0,
    PrivateUsage: usize = 0,
};

comptime {
    if (@sizeOf(NOTIFYICONDATAW) != 976) @compileError("NOTIFYICONDATAW mal aligné");
    if (@sizeOf(STARTUPINFOW) != 104) @compileError("STARTUPINFOW mal aligné");
    if (@sizeOf(CURSORINFO) != 24) @compileError("CURSORINFO mal aligné");
}

/// En-tête d'image 32 bits de haut en bas.
pub fn bmi(w: i32, h: i32) BITMAPINFO {
    return .{ .bmiHeader = .{ .biWidth = w, .biHeight = -h } };
}

pub extern "user32" fn RegisterClassW(*const WNDCLASSW) callconv(.winapi) u16;
pub extern "user32" fn CreateWindowExW(DWORD, LPCWSTR, LPCWSTR, DWORD, c_int, c_int, c_int, c_int, HWND, HMENU, HINSTANCE, ?*anyopaque) callconv(.winapi) HWND;
pub extern "user32" fn DefWindowProcW(HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn GetMessageW(*MSG, HWND, UINT, UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(*const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostQuitMessage(c_int) callconv(.winapi) void;
pub extern "user32" fn PostMessageW(HWND, UINT, WPARAM, LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyWindow(HWND) callconv(.winapi) BOOL;
pub extern "user32" fn FindWindowW(?LPCWSTR, ?LPCWSTR) callconv(.winapi) HWND;
pub extern "user32" fn RegisterWindowMessageW(LPCWSTR) callconv(.winapi) UINT;
pub extern "user32" fn SetCoalescableTimer(HWND, usize, UINT, ?*const anyopaque, c_ulong) callconv(.winapi) usize;
pub extern "user32" fn KillTimer(HWND, usize) callconv(.winapi) BOOL;
pub extern "user32" fn GetCursorPos(*POINT) callconv(.winapi) BOOL;
pub extern "user32" fn GetDC(HWND) callconv(.winapi) HDC;
pub extern "user32" fn ReleaseDC(HWND, HDC) callconv(.winapi) c_int;
pub extern "user32" fn GetSystemMetrics(c_int) callconv(.winapi) c_int;
pub extern "user32" fn SetCursorPos(c_int, c_int) callconv(.winapi) BOOL;
pub extern "user32" fn GetGuiResources(HANDLE, DWORD) callconv(.winapi) DWORD;
pub extern "user32" fn LoadImageW(HINSTANCE, LPCWSTR, UINT, c_int, c_int, UINT) callconv(.winapi) HANDLE;
/// Le nom peut être un numéro de curseur du système (souvent impair : pas un vrai pointeur u16).
pub extern "user32" fn LoadCursorW(HINSTANCE, ?*const anyopaque) callconv(.winapi) HCURSOR;
pub extern "user32" fn GetCursorInfo(*CURSORINFO) callconv(.winapi) BOOL;
pub const HWINEVENTHOOK = HANDLE;
pub const WINEVENTPROC = *const fn (HWINEVENTHOOK, DWORD, HWND, i32, i32, DWORD, DWORD) callconv(.winapi) void;
pub const EVENT_OBJECT_NAMECHANGE: DWORD = 0x800C;
pub const OBJID_CURSOR: i32 = -9;
pub const WINEVENT_OUTOFCONTEXT: DWORD = 0x0000;
pub const WINEVENT_SKIPOWNPROCESS: DWORD = 0x0002;
pub extern "user32" fn SetWinEventHook(DWORD, DWORD, HMODULE, WINEVENTPROC, DWORD, DWORD, DWORD) callconv(.winapi) HWINEVENTHOOK;
pub extern "user32" fn UnhookWinEvent(HWINEVENTHOOK) callconv(.winapi) BOOL;
pub extern "user32" fn CopyIcon(HICON) callconv(.winapi) HICON;
pub extern "user32" fn SetSystemCursor(HCURSOR, DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyCursor(HCURSOR) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyIcon(HICON) callconv(.winapi) BOOL;
pub extern "user32" fn GetIconInfo(HICON, *ICONINFO) callconv(.winapi) BOOL;
pub extern "user32" fn CreateIconIndirect(*ICONINFO) callconv(.winapi) HICON;
pub extern "user32" fn DrawIconEx(HDC, c_int, c_int, HICON, c_int, c_int, UINT, HBRUSH, UINT) callconv(.winapi) BOOL;
pub extern "user32" fn SystemParametersInfoW(UINT, UINT, ?*anyopaque, UINT) callconv(.winapi) BOOL;
pub extern "user32" fn CreatePopupMenu() callconv(.winapi) HMENU;
pub extern "user32" fn AppendMenuW(HMENU, UINT, usize, ?LPCWSTR) callconv(.winapi) BOOL;
pub extern "user32" fn TrackPopupMenu(HMENU, UINT, c_int, c_int, c_int, HWND, ?*const anyopaque) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyMenu(HMENU) callconv(.winapi) BOOL;
pub extern "user32" fn SetForegroundWindow(HWND) callconv(.winapi) BOOL;
pub extern "user32" fn FillRect(HDC, *const RECT, HBRUSH) callconv(.winapi) c_int;
pub extern "user32" fn GetDpiForSystem() callconv(.winapi) UINT;
pub extern "user32" fn SetProcessDpiAwarenessContext(HANDLE) callconv(.winapi) BOOL;

pub extern "gdi32" fn CreateCompatibleDC(HDC) callconv(.winapi) HDC;
pub extern "gdi32" fn DeleteDC(HDC) callconv(.winapi) BOOL;
pub extern "gdi32" fn CreateCompatibleBitmap(HDC, c_int, c_int) callconv(.winapi) HBITMAP;
pub extern "gdi32" fn CreateBitmap(c_int, c_int, UINT, UINT, ?*const anyopaque) callconv(.winapi) HBITMAP;
pub extern "gdi32" fn CreateDIBSection(HDC, *const BITMAPINFO, UINT, *?[*]u32, HANDLE, DWORD) callconv(.winapi) HBITMAP;
pub extern "gdi32" fn SelectObject(HDC, HGDIOBJ) callconv(.winapi) HGDIOBJ;
pub extern "gdi32" fn DeleteObject(HGDIOBJ) callconv(.winapi) BOOL;
pub extern "gdi32" fn BitBlt(HDC, c_int, c_int, c_int, c_int, HDC, c_int, c_int, DWORD) callconv(.winapi) BOOL;
pub extern "gdi32" fn GetDIBits(HDC, HBITMAP, UINT, UINT, ?*anyopaque, *BITMAPINFO, UINT) callconv(.winapi) c_int;
pub extern "gdi32" fn GetObjectW(HANDLE, c_int, ?*anyopaque) callconv(.winapi) c_int;
pub extern "gdi32" fn GetBitmapBits(HBITMAP, c_long, ?*anyopaque) callconv(.winapi) c_long;
pub extern "gdi32" fn GdiFlush() callconv(.winapi) BOOL;
pub extern "gdi32" fn CreateSolidBrush(DWORD) callconv(.winapi) HBRUSH;
pub extern "gdi32" fn CreateFontW(c_int, c_int, c_int, c_int, c_int, DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, LPCWSTR) callconv(.winapi) HFONT;
pub extern "gdi32" fn SetTextColor(HDC, DWORD) callconv(.winapi) DWORD;
pub extern "gdi32" fn SetBkMode(HDC, c_int) callconv(.winapi) c_int;
pub extern "gdi32" fn TextOutW(HDC, c_int, c_int, [*]const u16, c_int) callconv(.winapi) BOOL;

pub extern "shell32" fn Shell_NotifyIconW(DWORD, *NOTIFYICONDATAW) callconv(.winapi) BOOL;

pub extern "kernel32" fn CreateMutexW(?*anyopaque, BOOL, LPCWSTR) callconv(.winapi) HANDLE;
pub extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;
pub extern "kernel32" fn GetModuleHandleW(?LPCWSTR) callconv(.winapi) HINSTANCE;
pub extern "kernel32" fn GetModuleFileNameW(HINSTANCE, [*]u16, DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn GetWindowsDirectoryW([*]u16, UINT) callconv(.winapi) UINT;
pub extern "kernel32" fn QueryPerformanceCounter(*i64) callconv(.winapi) BOOL;
pub extern "kernel32" fn QueryPerformanceFrequency(*i64) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetCurrentThread() callconv(.winapi) HANDLE;
pub extern "kernel32" fn QueryThreadCycleTime(HANDLE, *u64) callconv(.winapi) BOOL;
pub extern "kernel32" fn QueryProcessCycleTime(HANDLE, *u64) callconv(.winapi) BOOL;
pub extern "kernel32" fn K32GetProcessMemoryInfo(HANDLE, *PROCESS_MEMORY_COUNTERS_EX, DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateProcessW(?LPCWSTR, ?[*:0]u16, ?*anyopaque, ?*anyopaque, BOOL, DWORD, ?*anyopaque, ?LPCWSTR, *STARTUPINFOW, *PROCESS_INFORMATION) callconv(.winapi) BOOL;
pub extern "kernel32" fn WaitForSingleObject(HANDLE, DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn TerminateProcess(HANDLE, UINT) callconv(.winapi) BOOL;
pub extern "kernel32" fn CloseHandle(HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateEventW(?*anyopaque, BOOL, BOOL, ?LPCWSTR) callconv(.winapi) HANDLE;
pub extern "kernel32" fn SetEvent(HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateThread(?*anyopaque, usize, *const fn (?*anyopaque) callconv(.winapi) u32, ?*anyopaque, DWORD, ?*DWORD) callconv(.winapi) HANDLE;
pub extern "kernel32" fn LoadLibraryW(LPCWSTR) callconv(.winapi) HMODULE;
pub extern "kernel32" fn GetProcAddress(HMODULE, [*:0]const u8) callconv(.winapi) ?*const anyopaque;
pub extern "kernel32" fn FreeLibrary(HMODULE) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetEnvironmentVariableW(LPCWSTR, [*]u16, DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn CreateDirectoryW(LPCWSTR, ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileAttributesW(LPCWSTR) callconv(.winapi) DWORD;
pub extern "kernel32" fn CreateFileW(LPCWSTR, DWORD, DWORD, ?*anyopaque, DWORD, DWORD, HANDLE) callconv(.winapi) HANDLE;
pub extern "kernel32" fn GetFileSizeEx(HANDLE, *i64) callconv(.winapi) BOOL;
pub extern "kernel32" fn ReadFile(HANDLE, [*]u8, DWORD, *DWORD, ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn WriteFile(HANDLE, [*]const u8, DWORD, *DWORD, ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn MoveFileExW(LPCWSTR, LPCWSTR, DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn DeleteFileW(LPCWSTR) callconv(.winapi) BOOL;
pub extern "kernel32" fn Sleep(DWORD) callconv(.winapi) void;
pub extern "kernel32" fn GetUserDefaultUILanguage() callconv(.winapi) u16;
pub extern "kernel32" fn GetTickCount() callconv(.winapi) DWORD;
pub extern "kernel32" fn GetCurrentProcess() callconv(.winapi) HANDLE;

pub extern "advapi32" fn RegGetValueW(HKEY, LPCWSTR, LPCWSTR, DWORD, ?*DWORD, ?*anyopaque, ?*DWORD) callconv(.winapi) i32;
pub extern "advapi32" fn RegCreateKeyExW(HKEY, LPCWSTR, DWORD, ?LPCWSTR, DWORD, DWORD, ?*anyopaque, *HKEY, ?*DWORD) callconv(.winapi) i32;
pub extern "advapi32" fn RegOpenKeyExW(HKEY, LPCWSTR, DWORD, DWORD, *HKEY) callconv(.winapi) i32;
pub extern "advapi32" fn RegSetValueExW(HKEY, LPCWSTR, DWORD, DWORD, ?*const anyopaque, DWORD) callconv(.winapi) i32;
pub extern "advapi32" fn RegDeleteKeyW(HKEY, LPCWSTR) callconv(.winapi) i32;
pub extern "advapi32" fn RegDeleteValueW(HKEY, LPCWSTR) callconv(.winapi) i32;
pub extern "advapi32" fn RegCloseKey(HKEY) callconv(.winapi) i32;
