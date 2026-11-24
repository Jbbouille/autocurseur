//! Lecture de la zone d'écran sous la souris, dans un tampon statique, sur un fil à part
//! (voir « fil de lecture » plus bas).

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

/// Libère le bitmap et le DC de travail.
pub fn deinit() void {
    if (bmp) |b| {
        _ = w.SelectObject(memdc, default_bmp);
        _ = w.DeleteObject(b);
    }
    if (memdc) |dc| _ = w.DeleteDC(dc);
    bmp = null;
    memdc = null;
    default_bmp = null;
}

// ---------------------------------------------------------------- fil de lecture
//
// Lire l'écran peut faire attendre longtemps : quand le pointeur est très agrandi, Windows le
// dessine lui-même dans l'image de l'écran, et chaque lecture prend alors 300 à 500 ms (contre
// 17 ms d'habitude), pour n'importe quel programme. Les lectures se font donc sur un fil à part :
// le fil principal (menu, minuteries, secousse, messages de Windows) ne les attend jamais.
// Le fil dort tant qu'on ne lui demande rien ; si une lecture est en cours, seule la dernière
// position demandée est gardée.

/// Résultat posté au fil principal (wParam) quand l'écran n'a pas pu être lu.
pub const NO_RESULT: usize = 0xFFFF;

var thread: w.HANDLE = null;
var wake: w.HANDLE = null; // événement à réinitialisation automatique : une demande attend
var target: w.HWND = null;
var result_msg: u32 = 0;
var req_point: u64 = 0; // dernière position demandée
var req_pending: bool = false; // une demande attend d'être prise par le fil
var req_side: i32 = core.BOX_MIN; // côté voulu pour la zone lue
var stopping: bool = false;

/// Nombre de lectures faites par le fil (pour les tests).
pub var reads: u32 = 0;

pub fn pack(p: core.Point) u64 {
    return @as(u64, @as(u32, @bitCast(p.x))) | (@as(u64, @as(u32, @bitCast(p.y))) << 32);
}

pub fn unpack(v: u64) core.Point {
    return .{ .x = @bitCast(@as(u32, @truncate(v))), .y = @bitCast(@as(u32, @truncate(v >> 32))) };
}

/// Démarre le fil de lecture : le résultat de chaque lecture est posté à `hwnd` sous la forme
/// du message `msg`, avec la luminance (0-255) en wParam, ou NO_RESULT.
pub fn startWorker(hwnd: w.HWND, msg: u32) bool {
    if (thread != null) return true;
    target = hwnd;
    result_msg = msg;
    @atomicStore(bool, &stopping, false, .seq_cst);
    @atomicStore(bool, &req_pending, false, .seq_cst);
    wake = w.CreateEventW(null, 0, 0, null) orelse return false;
    thread = w.CreateThread(null, 64 * 1024, workerMain, null, w.STACK_SIZE_PARAM_IS_A_RESERVATION, null) orelse {
        _ = w.CloseHandle(wake);
        wake = null;
        return false;
    };
    return true;
}

/// Demande une lecture sous `p`, sur une zone de `side` pixels de côté. Ne bloque jamais :
/// si le fil est occupé, cette demande remplace celle qui attendait. Sans fil (il n'a pas pu
/// démarrer), la lecture est faite tout de suite et son résultat posté de la même façon.
pub fn request(p: core.Point, side: i32) void {
    if (thread == null) {
        if (side != box or bmp == null) resize(side);
        _ = w.PostMessageW(target, result_msg, sampleScreen(p) orelse NO_RESULT, 0);
        return;
    }
    @atomicStore(i32, &req_side, side, .seq_cst);
    @atomicStore(u64, &req_point, pack(p), .seq_cst);
    @atomicStore(bool, &req_pending, true, .seq_cst);
    _ = w.SetEvent(wake);
}

fn workerMain(_: ?*anyopaque) callconv(.winapi) u32 {
    init(); // DC et bitmap de travail appartiennent à ce fil
    defer deinit();
    while (true) {
        _ = w.WaitForSingleObject(wake, w.INFINITE);
        if (@atomicLoad(bool, &stopping, .seq_cst)) break;
        if (!@atomicRmw(bool, &req_pending, .Xchg, false, .seq_cst)) continue;
        const v = @atomicLoad(u64, &req_point, .seq_cst);
        const side = @atomicLoad(i32, &req_side, .seq_cst);
        if (side != box or bmp == null) resize(side);
        const l = sampleScreen(unpack(v));
        _ = @atomicRmw(u32, &reads, .Add, 1, .seq_cst);
        _ = w.PostMessageW(target, result_msg, l orelse NO_RESULT, 0);
    }
    return 0;
}

/// Arrête le fil, en attendant au plus `ms` millisecondes qu'il finisse sa lecture en cours.
pub fn stopWorker(ms: u32) void {
    const t = thread orelse return;
    @atomicStore(bool, &stopping, true, .seq_cst);
    _ = w.SetEvent(wake);
    _ = w.WaitForSingleObject(t, ms);
    _ = w.CloseHandle(t);
    if (wake) |e| _ = w.CloseHandle(e);
    thread = null;
    wake = null;
}

test "pack / unpack : aller-retour, coordonnées négatives comprises" {
    const std = @import("std");
    for ([_]core.Point{ .{ .x = 0, .y = 0 }, .{ .x = -2560, .y = 1440 }, .{ .x = 7679, .y = -200 }, .{ .x = std.math.minInt(i32), .y = std.math.maxInt(i32) } }) |p| {
        const q = unpack(pack(p));
        try std.testing.expectEqual(p.x, q.x);
        try std.testing.expectEqual(p.y, q.y);
    }
}
