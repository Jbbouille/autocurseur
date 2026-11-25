//! Sélecteur de couleur standard de Windows (ChooseColor), pour les couleurs personnalisées
//! des curseurs. comdlg32.dll n'est chargée que le temps du choix (LoadLibrary, puis
//! FreeLibrary) : AutoCurseur n'a aucune fenêtre de réglages à lui.

const std = @import("std");
const core = @import("core.zig");
const w = @import("win32.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const HookFn = *const fn (w.HWND, u32, usize, isize) callconv(.winapi) usize;
const CHOOSECOLORW = extern struct {
    lStructSize: u32 = @sizeOf(CHOOSECOLORW),
    hwndOwner: w.HWND = null,
    hInstance: w.HANDLE = null,
    rgbResult: u32 = 0,
    lpCustColors: *[16]u32,
    Flags: u32 = 0,
    lCustData: isize = 0,
    lpfnHook: ?HookFn = null,
    lpTemplateName: ?w.LPCWSTR = null,
};
comptime {
    if (@sizeOf(CHOOSECOLORW) != 72) @compileError("CHOOSECOLORW mal aligné");
}
const CC_RGBINIT = 0x01;
const CC_FULLOPEN = 0x02;
const CC_ENABLEHOOK = 0x10;

/// Convertit 0xRRGGBB en couleur de Windows (0x00BBGGRR), et inversement.
pub fn swapRedBlue(c: u32) u32 {
    return ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF);
}

/// Les 16 cases « couleurs personnalisées » du sélecteur : d'abord les couleurs des couples du
/// menu, pour les retrouver d'un clic. Ce que l'utilisateur y range est gardé jusqu'à la
/// fermeture d'AutoCurseur.
var custom: [16]u32 = blk: {
    var a: [16]u32 = @splat(0x00FFFFFF);
    for (core.PRESETS, 0..) |p, i| {
        a[2 * i] = swapRedBlue(p.dark);
        a[2 * i + 1] = swapRedBlue(p.light);
    }
    break :blk a;
};
var title: w.LPCWSTR = L("");

/// À l'ouverture du sélecteur : titre qui dit quelle couleur on choisit, et fenêtre placée
/// près de la souris (il s'ouvrirait sinon dans un coin de l'écran principal).
fn hook(dlg: w.HWND, msg: u32, _: usize, _: isize) callconv(.winapi) usize {
    if (msg != w.WM_INITDIALOG) return 0;
    _ = w.SetWindowTextW(dlg, title);
    var r: w.RECT = undefined;
    var p: core.Point = .{};
    var mi: w.MONITORINFO = .{};
    if (w.GetWindowRect(dlg, &r) != 0 and w.GetCursorPos(&p) != 0 and
        w.GetMonitorInfoW(w.MonitorFromPoint(p, w.MONITOR_DEFAULTTONEAREST), &mi) != 0)
    {
        const work: core.Rect = .{ .x = mi.rcWork.left, .y = mi.rcWork.top, .w = mi.rcWork.right - mi.rcWork.left, .h = mi.rcWork.bottom - mi.rcWork.top };
        const at = core.placeNear(p, r.right - r.left, r.bottom - r.top, work);
        _ = w.SetWindowPos(dlg, null, at.x, at.y, 0, 0, w.SWP_NOSIZE | w.SWP_NOZORDER);
    }
    _ = w.SetForegroundWindow(dlg);
    return 0;
}

/// Ouvre le sélecteur de couleur sur `initial` (0xRRGGBB) et attend le choix. Renvoie la
/// couleur choisie, ou null si l'utilisateur annule ou si le sélecteur est indisponible.
/// Les messages de l'application continuent d'être traités pendant ce temps.
pub fn pick(initial: u32, dialog_title: w.LPCWSTR) ?u32 {
    const lib = w.LoadLibraryW(L("comdlg32.dll")) orelse return null;
    defer _ = w.FreeLibrary(lib);
    const choose: *const fn (*CHOOSECOLORW) callconv(.winapi) w.BOOL = @ptrCast(w.GetProcAddress(lib, "ChooseColorW") orelse return null);
    title = dialog_title;
    var cc: CHOOSECOLORW = .{
        .rgbResult = swapRedBlue(initial),
        .lpCustColors = &custom,
        .Flags = CC_RGBINIT | CC_FULLOPEN | CC_ENABLEHOOK,
        .lpfnHook = hook,
    };
    if (choose(&cc) == 0) return null;
    return swapRedBlue(cc.rgbResult & 0xFFFFFF);
}

test "swapRedBlue : rouge et bleu échangés, vert gardé, aller-retour" {
    try std.testing.expectEqual(@as(u32, 0x563412), swapRedBlue(0x123456));
    try std.testing.expectEqual(@as(u32, 0x0000FF), swapRedBlue(0xFF0000));
    try std.testing.expectEqual(@as(u32, 0x00FF00), swapRedBlue(0x00FF00));
    for ([_]u32{ 0, 0xFFFFFF, 0x00205B, 0xFFE600 }) |c| try std.testing.expectEqual(c, swapRedBlue(swapRedBlue(c)));
}

test "cases personnalisées : les couleurs des couples du menu y sont, au format de Windows" {
    for (core.PRESETS, 0..) |p, i| {
        try std.testing.expectEqual(swapRedBlue(p.dark), custom[2 * i]);
        try std.testing.expectEqual(swapRedBlue(p.light), custom[2 * i + 1]);
    }
    try std.testing.expect(2 * core.PRESETS.len <= custom.len);
}
