//! Lecture de la zone d'écran sous la souris, dans un tampon statique.

const core = @import("core.zig");
const w = @import("win32.zig");

/// pixels de la dernière zone lue
pub var buf: [core.BOX_MAX * core.BOX_MAX]u32 = undefined;
/// côté actuel de la zone lue
pub var box: i32 = core.BOX_MIN;

var memdc: w.HDC = null;
var bmp: w.HBITMAP = null;
var default_bmp: w.HGDIOBJ = null;

/// À appeler une fois au démarrage.
pub fn init() void {
    if (memdc == null) memdc = w.CreateCompatibleDC(null);
}

/// (Re)crée le bitmap de travail pour une zone de `side` pixels de côté (borné à BOX_MAX).
pub fn resize(side: i32) void {
    box = @min(side, core.BOX_MAX);
    if (bmp) |old| {
        _ = w.SelectObject(memdc, default_bmp);
        _ = w.DeleteObject(old);
    }
    const scr = w.GetDC(null);
    bmp = w.CreateCompatibleBitmap(scr, box, box);
    _ = w.ReleaseDC(null, scr);
    const prev = w.SelectObject(memdc, bmp);
    if (default_bmp == null) default_bmp = prev;
}

/// Luminance moyenne (0-255) du carré de `box` pixels dont le coin haut-gauche est `origin` dans `src`.
pub fn sampleFrom(src: w.HDC, origin: core.Point) ?u32 {
    if (w.BitBlt(memdc, 0, 0, box, box, src, origin.x, origin.y, w.SRCCOPY) == 0) return null;
    // GetDIBits demande un bitmap qui n'est sélectionné dans aucun DC
    _ = w.SelectObject(memdc, default_bmp);
    var bi = w.bmi(box, box);
    const rows = w.GetDIBits(memdc, bmp, 0, @intCast(box), &buf, &bi, w.DIB_RGB_COLORS);
    _ = w.SelectObject(memdc, bmp);
    if (rows == 0) return null;
    return core.averageLuma(buf[0..@intCast(box * box)]);
}

/// Rectangle englobant tous les écrans.
pub fn virtualScreen() core.Rect {
    return .{
        .x = w.GetSystemMetrics(w.SM_XVIRTUALSCREEN),
        .y = w.GetSystemMetrics(w.SM_YVIRTUALSCREEN),
        .w = w.GetSystemMetrics(w.SM_CXVIRTUALSCREEN),
        .h = w.GetSystemMetrics(w.SM_CYVIRTUALSCREEN),
    };
}

/// Luminance moyenne sous une souris placée en `p`, lue à l'écran.
/// null si l'écran n'est pas lisible (session verrouillée, etc.).
pub fn sampleScreen(p: core.Point) ?u32 {
    const origin = core.sampleOrigin(p, box, virtualScreen());
    const scr = w.GetDC(null) orelse return null;
    defer _ = w.ReleaseDC(null, scr);
    return sampleFrom(scr, origin);
}
