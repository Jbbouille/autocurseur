//! AutoCurseur — curseur noir sur fond clair, blanc sur fond sombre.
//!
//! Ce fichier ne fait que relier les morceaux : fenêtre cachée, icône de notification,
//! menu, minuterie. La logique est dans core.zig (testée), l'accès à Windows dans
//! cursors.zig et sampler.zig.
//!
//! Mémoire : aucune allocation dynamique. Tous les tampons sont des tableaux globaux
//! de taille fixe ; seuls les objets Windows (curseurs, bitmaps, fenêtre, icônes)
//! sont créés par le système.

const std = @import("std");
const core = @import("core.zig");
const w = @import("win32.zig");
const cursors = @import("cursors.zig");
const sampler = @import("sampler.zig");
const icon = @import("icon.zig");
const settings = @import("settings.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

/// Libellés du sous-menu, dans l'ordre de core.RATES.
const rate_labels = [core.RATES.len][:0]const u16{ L("3"), L("5"), L("10 (par défaut)"), L("20") };

const APP_NAME = L("AutoCurseur");
const RUN_KEY = L("Software\\Microsoft\\Windows\\CurrentVersion\\Run");
const WM_TRAY = w.WM_APP + 1;
const TIMER_ID = 1;
const ID_ACTIVE = 1;
const ID_STARTUP = 2;
const ID_QUIT = 3;

var shade: core.Shade = .unknown;
var active = false;
var rate: u32 = core.DEFAULT_RATE; // lectures par seconde quand la souris bouge
var ticker: core.Ticker = .{};
var wnd: w.HWND = null;
var msg_taskbar: u32 = 0;
var ico_on: w.HICON = null;
var ico_off: w.HICON = null;
var nid: w.NOTIFYICONDATAW = .{};
var exe_buf: [w.MAX_PATH]u16 = undefined;
var reg_buf: [w.MAX_PATH + 4]u16 = undefined;

// ---------- curseurs ----------

fn reload() void {
    // Recharge d'abord les curseurs de Windows : la taille se mesure sur les siens, jamais
    // sur des curseurs laissés par un lancement précédent (arrêté de force, par exemple).
    cursors.restore();
    const s = cursors.systemSize();
    cursors.load(s);
    sampler.resize(core.boxSize(s));
    shade = .unknown;
}

fn update(p: core.Point) void {
    const l = sampler.sampleScreen(p) orelse return;
    const want = core.decide(shade, l, .{});
    if (want != shade) {
        cursors.apply(want == .black);
        shade = want;
    }
}

fn restore() void {
    cursors.restore();
    shade = .unknown;
}

fn setTimer(ms: u32) void {
    _ = w.SetCoalescableTimer(wnd, TIMER_ID, ms, null, ms / 10);
}

fn onTimer() void {
    var p: core.Point = .{};
    if (w.GetCursorPos(&p) == 0) return;
    const a = ticker.tick(p);
    if (a.interval_ms) |ms| setTimer(ms);
    if (a.sample) update(p);
}

// ---------- démarrage automatique ----------

fn getStartup() bool {
    return w.RegGetValueW(w.HKCU, RUN_KEY, APP_NAME, w.RRF_RT_REG_SZ, null, null, null) == 0;
}

fn setStartup(on: bool) void {
    var k: w.HKEY = null;
    if (w.RegOpenKeyExW(w.HKCU, RUN_KEY, 0, w.KEY_SET_VALUE, &k) != 0) return;
    defer _ = w.RegCloseKey(k);
    if (on) {
        const n = w.GetModuleFileNameW(null, &exe_buf, exe_buf.len);
        const q = L("\"");
        const val = core.join(&reg_buf, &.{ q, exe_buf[0..n], q });
        _ = w.RegSetValueExW(k, APP_NAME, 0, w.REG_SZ, val.ptr, @intCast((val.len + 1) * 2));
    } else {
        _ = w.RegDeleteValueW(k, APP_NAME);
    }
}

// ---------- icône et menu ----------

fn setTip(s: []const u16) void {
    @memset(&nid.szTip, 0);
    @memcpy(nid.szTip[0..s.len], s);
}

fn setActive(on: bool) void {
    active = on;
    if (on) {
        shade = .unknown;
        ticker = core.Ticker.init(rate);
        setTimer(ticker.tick_ms);
    } else {
        _ = w.KillTimer(wnd, TIMER_ID);
        restore();
    }
    nid.uFlags = w.NIF_ICON | w.NIF_TIP | w.NIF_MESSAGE;
    nid.hIcon = if (on) ico_on else ico_off;
    const tip: []const u16 = if (on) APP_NAME else L("AutoCurseur (en pause)");
    setTip(tip);
    _ = w.Shell_NotifyIconW(w.NIM_MODIFY, &nid);
}

/// Change le rythme de lecture en mouvement, l'applique tout de suite et le mémorise.
fn setRate(r: u32) void {
    rate = core.validRate(r);
    settings.saveRate(rate);
    if (active) {
        ticker = core.Ticker.init(rate);
        setTimer(ticker.tick_ms);
    }
}

fn showMenu() void {
    const m = w.CreatePopupMenu();
    defer _ = w.DestroyMenu(m); // détruit aussi le sous-menu
    const active_flag: u32 = if (active) w.MF_CHECKED else 0;
    const startup_flag: u32 = if (getStartup()) w.MF_CHECKED else 0;
    _ = w.AppendMenuW(m, w.MF_STRING | active_flag, ID_ACTIVE, L("Actif"));

    if (w.CreatePopupMenu()) |sub| {
        for (core.RATES, rate_labels, 0..) |r, label, i| {
            const flag: u32 = if (r == rate) w.MF_CHECKED else 0;
            _ = w.AppendMenuW(sub, w.MF_STRING | w.MFT_RADIOCHECK | flag, settings.RATE_MENU_BASE + i, label.ptr);
        }
        _ = w.AppendMenuW(m, w.MF_POPUP, @intFromPtr(sub), L("Vérifications par seconde (souris en mouvement)"));
    }

    _ = w.AppendMenuW(m, w.MF_STRING | startup_flag, ID_STARTUP, L("Lancer au démarrage de Windows"));
    _ = w.AppendMenuW(m, w.MF_SEPARATOR, 0, null);
    _ = w.AppendMenuW(m, w.MF_STRING, ID_QUIT, L("Quitter"));
    var p: core.Point = .{};
    _ = w.GetCursorPos(&p);
    _ = w.SetForegroundWindow(wnd);
    _ = w.TrackPopupMenu(m, w.TPM_RIGHTBUTTON | w.TPM_BOTTOMALIGN, p.x, p.y, 0, wnd, null);
    _ = w.PostMessageW(wnd, w.WM_NULL, 0, 0);
}

fn wndProc(h: w.HWND, msg: u32, wp: w.WPARAM, lp: w.LPARAM) callconv(.winapi) w.LRESULT {
    switch (msg) {
        w.WM_TIMER => {
            onTimer();
            return 0;
        },
        WM_TRAY => {
            if (lp == w.WM_RBUTTONUP) {
                showMenu();
            } else if (lp == w.WM_LBUTTONDBLCLK) {
                setActive(!active);
            }
            return 0;
        },
        w.WM_COMMAND => {
            const id = wp & 0xFFFF;
            switch (id) {
                ID_ACTIVE => setActive(!active),
                ID_STARTUP => setStartup(!getStartup()),
                ID_QUIT => _ = w.DestroyWindow(h),
                else => if (settings.rateFromMenuId(id)) |r| setRate(r),
            }
            return 0;
        },
        w.WM_SETTINGCHANGE, w.WM_DISPLAYCHANGE => {
            // taille du pointeur changée dans les Paramètres : on recharge
            if (cursors.systemSize() != cursors.size) reload();
            // quelqu'un a rechargé les curseurs système : on réapplique au prochain tic
            if (msg == w.WM_SETTINGCHANGE and wp == w.SPI_SETCURSORS) shade = .unknown;
            return 0;
        },
        w.WM_DESTROY => {
            _ = w.KillTimer(h, TIMER_ID);
            if (active) restore();
            _ = w.Shell_NotifyIconW(w.NIM_DELETE, &nid);
            w.PostQuitMessage(0);
            return 0;
        },
        else => if (msg_taskbar != 0 and msg == msg_taskbar) {
            // l'Explorateur a redémarré : on remet l'icône
            nid.uFlags = w.NIF_ICON | w.NIF_TIP | w.NIF_MESSAGE;
            _ = w.Shell_NotifyIconW(w.NIM_ADD, &nid);
            return 0;
        },
    }
    return w.DefWindowProcW(h, msg, wp, lp);
}

pub fn main() void {
    _ = w.CreateMutexW(null, 1, L("Local\\AutoCurseur"));
    if (w.GetLastError() == w.ERROR_ALREADY_EXISTS) return; // déjà lancé

    _ = w.SetProcessDpiAwarenessContext(w.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    const hi = w.GetModuleHandleW(null);
    const wc: w.WNDCLASSW = .{ .lpfnWndProc = wndProc, .hInstance = hi, .lpszClassName = APP_NAME };
    _ = w.RegisterClassW(&wc);
    wnd = w.CreateWindowExW(0, APP_NAME, APP_NAME, 0, 0, 0, 0, 0, null, null, hi, null);
    msg_taskbar = w.RegisterWindowMessageW(L("TaskbarCreated"));

    rate = settings.loadRate();
    sampler.init();
    reload();
    ico_on = icon.create(true);
    ico_off = icon.create(false);

    nid.hWnd = wnd;
    nid.uID = 1;
    nid.uFlags = w.NIF_ICON | w.NIF_TIP | w.NIF_MESSAGE;
    nid.uCallbackMessage = WM_TRAY;
    nid.hIcon = ico_on;
    setTip(APP_NAME);
    _ = w.Shell_NotifyIconW(w.NIM_ADD, &nid);

    setActive(true);

    var m: w.MSG = undefined;
    while (w.GetMessageW(&m, null, 0, 0) > 0) {
        _ = w.TranslateMessage(&m);
        _ = w.DispatchMessageW(&m);
    }
}
