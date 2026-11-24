//! AutoCurseur — curseur noir sur fond clair, blanc sur fond sombre.
//!
//! Ce fichier ne fait que relier les morceaux : fenêtre cachée, icône de notification,
//! menu, minuterie. La logique est dans core.zig (testée), l'accès à Windows dans
//! cursors.zig et sampler.zig.
//!
//! Mémoire : aucune allocation dynamique. Tous les tampons sont des tableaux globaux
//! de taille fixe ; seuls les objets Windows (curseurs, bitmaps, fenêtre, icônes)
//! sont créés par le système. Les versions inversée et rouge des curseurs sont écrites
//! une fois dans %LOCALAPPDATA%\AutoCurseur\cursors (voir cursors.zig).

const std = @import("std");
const core = @import("core.zig");
const w = @import("win32.zig");
const cursors = @import("cursors.zig");
const sampler = @import("sampler.zig");
const icon = @import("icon.zig");
const settings = @import("settings.zig");
const i18n = @import("i18n.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const APP_NAME = L("AutoCurseur");
const RUN_KEY = L("Software\\Microsoft\\Windows\\CurrentVersion\\Run");
const WM_TRAY = w.WM_APP + 1;
const WM_SAMPLE = w.WM_APP + 2; // résultat d'une lecture d'écran (fil de lecture, voir sampler.zig)
const TIMER_ID = 1;
const TIMER_SHAKE = 2;
const TIMER_SETTLE = 3; // remises en place après un changement de réglages
const ID_ACTIVE = 1;
const ID_STARTUP = 2;
const ID_QUIT = 3;
const ID_SHAKE = settings.MENU_SHAKE;

var shade: core.Shade = .unknown;
var active = false;
var rate: u32 = core.DEFAULT_RATE; // lectures par seconde quand la souris bouge
var lang: i18n.Choice = .auto;
var text: *const i18n.Text = &i18n.en; // textes du menu dans la langue affichée
var ticker: core.Ticker = .{};
var shake_on = true; // option « secouer pour retrouver »
var shake: core.Shake = core.Shake.init(32);
var shake_timer = false; // la minuterie rapide de détection tourne-t-elle ?
var big = false; // le jeu rouge agrandi est-il affiché ?
var base: u32 = 32; // réglage « taille du pointeur » au dernier chargement
var settle_step: usize = 0; // prochaine étape de core.SETTLE_MS
var shape_hook: w.HWINEVENTHOOK = null; // avis de Windows quand la forme du pointeur change
var wnd: w.HWND = null;
var msg_taskbar: u32 = 0;
var ico_on: w.HICON = null;
var ico_off: w.HICON = null;
var nid: w.NOTIFYICONDATAW = .{};
var box_side: i32 = core.BOX_MIN; // côté de la zone d'écran lue
var exe_buf: [w.MAX_PATH]u16 = undefined;
var reg_buf: [w.MAX_PATH + 4]u16 = undefined;

// ---------- curseurs ----------

fn reload() void {
    // Recharge d'abord les curseurs de Windows : la taille se mesure sur les siens, jamais
    // sur des curseurs laissés par un lancement précédent (arrêté de force, par exemple).
    cursors.restore();
    const s = cursors.systemSize();
    base = cursors.pointerBase();
    cursors.base = base;
    useVectorIfEnlarged();
    cursors.size = s; // les curseurs sont relus depuis leurs fichiers à chaque application
    shake = core.Shake.init(s);
    big = false;
    // la zone lue couvre le curseur tel qu'il est affiché, agrandi par l'accessibilité
    box_side = core.boxSize(core.displayedSize(s, base));
    shade = .unknown;
}

/// Demande une lecture de l'écran sous `p` au fil de lecture ; la réponse arrive en WM_SAMPLE.
fn update(p: core.Point) void {
    sampler.request(p, box_side);
}

fn setOf(s: core.Shade) cursors.Set {
    return if (s == .black) .black else .white;
}

/// Luminance lue sous la souris : choix du jeu noir ou blanc.
fn onSample(l: u32) void {
    if (!active) return; // réponse arrivée après la mise en pause
    const want = core.decide(shade, l, .{});
    if (want != shade) {
        shade = want;
        if (!big) cursors.show(setOf(want)); // agrandi : on attend la fin pour changer
    }
}

/// Fin de l'agrandissement : retour au jeu noir ou blanc qui convient au fond.
fn showNormal() void {
    big = false;
    if (shade == .unknown) cursors.restore() else cursors.show(setOf(shade));
}

/// Windows prévient (pour tout le système) qu'un nom a changé ; pour le pointeur, c'est sa
/// forme : la nouvelle forme prend tout de suite la couleur voulue.
fn onWinEvent(_: w.HWINEVENTHOOK, _: w.DWORD, _: w.HWND, obj: i32, _: i32, _: w.DWORD, _: w.DWORD) callconv(.winapi) void {
    if (obj == w.OBJID_CURSOR and active) cursors.fix();
}

/// Écoute (ou non) les changements de forme du pointeur, sans DLL injectée : les avis
/// arrivent dans la boucle de messages de ce fil.
fn listenShapes(on: bool) void {
    if (on and shape_hook == null) {
        shape_hook = w.SetWinEventHook(w.EVENT_OBJECT_NAMECHANGE, w.EVENT_OBJECT_NAMECHANGE, null, onWinEvent, 0, 0, w.WINEVENT_OUTOFCONTEXT | w.WINEVENT_SKIPOWNPROCESS);
    } else if (!on and shape_hook != null) {
        _ = w.UnhookWinEvent(shape_hook);
        shape_hook = null;
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
    // filet de sécurité si un avis de changement de forme s'est perdu
    cursors.fix();
    // la détection de secousse ne tourne que pendant que la souris bouge
    if (shake_on) {
        if (ticker.slow) stopShake() else startShake();
    }
    if (a.sample) update(p);
}

/// Pointeur agrandi dans les Paramètres d'accessibilité : comme Windows 11, curseurs dessinés à
/// partir de ses dessins vectoriels (fabriqués à la première utilisation) ; sinon, classiques.
fn useVectorIfEnlarged() void {
    if (base > 32) {
        _ = cursors.prepareVector(shake_on);
        cursors.useVector(cursors.vectorReady());
    } else {
        cursors.useVector(false);
    }
}

// ---------- après un changement de réglages ----------

/// Notification de changement de réglages : (re)démarre le compte à rebours.
fn startSettle() void {
    settle_step = 0;
    _ = w.SetCoalescableTimer(wnd, TIMER_SETTLE, core.SETTLE_MS[0], null, 0); // remplace un compte en cours
}

fn onSettle() void {
    if (settle_step == 0) {
        // la taille (agrandissement d'écran) ou le réglage d'accessibilité ont pu changer
        reload();
    } else {
        // force la remise en place : Windows a pu remettre ses curseurs sans prévenir
        shade = .unknown;
        cursors.forget();
    }
    var p: core.Point = .{};
    if (w.GetCursorPos(&p) != 0) update(p); // tout de suite, sans attendre le prochain tic
    settle_step += 1;
    if (settle_step < core.SETTLE_MS.len) {
        _ = w.SetCoalescableTimer(wnd, TIMER_SETTLE, core.SETTLE_MS[settle_step] - core.SETTLE_MS[settle_step - 1], null, 0);
    } else {
        _ = w.KillTimer(wnd, TIMER_SETTLE);
    }
}

// ---------- secouer pour retrouver ----------

fn startShake() void {
    if (shake_timer) return;
    shake_timer = true;
    _ = w.SetCoalescableTimer(wnd, TIMER_SHAKE, core.SHAKE_TICK_MS, null, core.SHAKE_TICK_MS / 10);
}

/// Arrête la détection ; vrai si le curseur était agrandi.
fn killShake() bool {
    if (shake_timer) _ = w.KillTimer(wnd, TIMER_SHAKE);
    shake_timer = false;
    big = false;
    return shake.stop();
}

fn stopShake() void {
    if (killShake()) showNormal();
}

fn onShakeTimer() void {
    var p: core.Point = .{};
    if (w.GetCursorPos(&p) == 0) return;
    switch (shake.feed(w.GetTickCount(), p)) {
        .start => {
            big = true;
            cursors.show(.red);
        },
        .stop => showNormal(),
        .none => {},
    }
}

/// Active ou non « secouer pour retrouver », tout de suite, et le mémorise.
fn setShake(on: bool) void {
    shake_on = on;
    settings.saveShake(on);
    if (on) {
        _ = cursors.prepare(true); // fichiers du jeu rouge
        if (cursors.usingVector()) _ = cursors.prepareVector(true);
    } else {
        stopShake();
    }
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
    listenShapes(on);
    if (on) {
        shade = .unknown;
        ticker = core.Ticker.init(rate);
        setTimer(ticker.tick_ms);
    } else {
        _ = w.KillTimer(wnd, TIMER_ID);
        _ = w.KillTimer(wnd, TIMER_SETTLE);
        _ = killShake();
        restore();
    }
    refreshIcon();
}

fn refreshIcon() void {
    nid.uFlags = w.NIF_ICON | w.NIF_TIP | w.NIF_MESSAGE;
    nid.hIcon = if (active) ico_on else ico_off;
    setTip(if (active) APP_NAME else text.paused_tip);
    _ = w.Shell_NotifyIconW(w.NIM_MODIFY, &nid);
}

/// Langue des textes : celle choisie, ou celle de Windows en automatique.
fn applyLang(c: i18n.Choice) void {
    lang = c;
    text = i18n.text(i18n.resolve(c, w.GetUserDefaultUILanguage()));
}

/// Change la langue du menu, l'applique tout de suite (info-bulle comprise) et la mémorise.
fn setLang(c: i18n.Choice) void {
    applyLang(c);
    settings.saveLang(c);
    refreshIcon();
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
    defer _ = w.DestroyMenu(m); // détruit aussi les sous-menus
    const active_flag: u32 = if (active) w.MF_CHECKED else 0;
    const startup_flag: u32 = if (getStartup()) w.MF_CHECKED else 0;
    _ = w.AppendMenuW(m, w.MF_STRING | active_flag, ID_ACTIVE, text.active);

    if (w.CreatePopupMenu()) |sub| {
        for (core.RATES, text.rates, 0..) |r, label, i| {
            const flag: u32 = if (r == rate) w.MF_CHECKED else 0;
            _ = w.AppendMenuW(sub, w.MF_STRING | w.MFT_RADIOCHECK | flag, settings.RATE_MENU_BASE + i, label.ptr);
        }
        _ = w.AppendMenuW(m, w.MF_POPUP, @intFromPtr(sub), text.rate_menu);
    }

    if (w.CreatePopupMenu()) |sub| {
        for (i18n.CHOICES) |c| {
            const flag: u32 = if (c == lang) w.MF_CHECKED else 0;
            const id = settings.LANG_MENU_BASE + @backingInt(c);
            _ = w.AppendMenuW(sub, w.MF_STRING | w.MFT_RADIOCHECK | flag, id, i18n.choiceLabel(text, c));
        }
        _ = w.AppendMenuW(m, w.MF_POPUP, @intFromPtr(sub), text.language_menu);
    }

    const shake_flag: u32 = if (shake_on) w.MF_CHECKED else 0;
    _ = w.AppendMenuW(m, w.MF_STRING | shake_flag, ID_SHAKE, text.shake);
    _ = w.AppendMenuW(m, w.MF_STRING | startup_flag, ID_STARTUP, text.startup);
    _ = w.AppendMenuW(m, w.MF_SEPARATOR, 0, null);
    _ = w.AppendMenuW(m, w.MF_STRING, ID_QUIT, text.quit);
    var p: core.Point = .{};
    _ = w.GetCursorPos(&p);
    _ = w.SetForegroundWindow(wnd);
    _ = w.TrackPopupMenu(m, w.TPM_RIGHTBUTTON | w.TPM_BOTTOMALIGN, p.x, p.y, 0, wnd, null);
    _ = w.PostMessageW(wnd, w.WM_NULL, 0, 0);
}

fn wndProc(h: w.HWND, msg: u32, wp: w.WPARAM, lp: w.LPARAM) callconv(.winapi) w.LRESULT {
    switch (msg) {
        WM_SAMPLE => {
            if (wp != sampler.NO_RESULT) onSample(@intCast(wp));
            return 0;
        },
        w.WM_TIMER => {
            switch (wp) {
                TIMER_SHAKE => onShakeTimer(),
                TIMER_SETTLE => onSettle(),
                else => onTimer(),
            }
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
                ID_SHAKE => setShake(!shake_on),
                ID_QUIT => _ = w.DestroyWindow(h),
                else => if (settings.rateFromMenuId(id)) |r| {
                    setRate(r);
                } else if (settings.langFromMenuId(id)) |c| {
                    setLang(c);
                },
            }
            return 0;
        },
        w.WM_SETTINGCHANGE, w.WM_DISPLAYCHANGE => {
            // Taille du pointeur changée dans les Paramètres (notification 0x2029), écran
            // branché… Windows remet alors ses propres curseurs, parfois après sa notification
            // et sans en envoyer d'autre. On ne touche à rien pendant qu'il travaille : on remet
            // les nôtres une fois le calme revenu, en plusieurs fois (core.SETTLE_MS).
            if (active) startSettle();
            return 0;
        },
        w.WM_DESTROY => {
            _ = w.KillTimer(h, TIMER_ID);
            _ = w.KillTimer(h, TIMER_SETTLE);
            listenShapes(false);
            sampler.stopWorker(1000);
            _ = killShake();
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
    applyLang(settings.loadLang());
    shake_on = settings.loadShake();
    // fichiers des versions inversée et rouge (réécrits seulement s'ils ont changé)
    _ = cursors.useDefaultDir();
    _ = cursors.prepare(shake_on);
    _ = sampler.startWorker(wnd, WM_SAMPLE); // sans fil, les lectures se font sur place
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
