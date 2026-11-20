//! Outils communs aux tests : analyse d'un curseur, toile de dessin en mémoire, chronométrage.

const std = @import("std");
const app = @import("autocurseur");
const core = app.core;
const w = app.win32;
const testing = std.testing;
pub const L = std.unicode.utf8ToUtf16LeStringLiteral;

/// Comme l'application : le processus gère l'agrandissement d'écran, sinon Windows lui
/// présente des tailles de curseur et des coordonnées « virtuelles » à 96 DPI.
pub fn dpiAware() void {
    _ = w.SetProcessDpiAwarenessContext(w.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
}

/// Ce que contient un curseur : taille, point chaud, pixels opaques et part de blancs parmi eux.
pub const Stats = struct {
    width: i32,
    hot_x: u32,
    hot_y: u32,
    mono: bool,
    opaque_px: usize = 0,
    white_px: usize = 0,

    pub fn whiteRatio(s: Stats) f32 {
        if (s.opaque_px == 0) return 0;
        return @as(f32, @floatFromInt(s.white_px)) / @as(f32, @floatFromInt(s.opaque_px));
    }

    pub fn sameImage(a: Stats, b: Stats) bool {
        return a.width == b.width and a.hot_x == b.hot_x and a.hot_y == b.hot_y and
            a.opaque_px == b.opaque_px and a.white_px == b.white_px;
    }
};

pub fn stats(c: w.HCURSOR) !Stats {
    var ii: w.ICONINFO = undefined;
    if (w.GetIconInfo(c, &ii) == 0) return error.GetIconInfo;
    defer _ = w.DeleteObject(ii.hbmMask);
    var s: Stats = .{ .width = 0, .hot_x = ii.xHotspot, .hot_y = ii.yHotspot, .mono = ii.hbmColor == null };

    var mbm: w.BITMAP = undefined;
    _ = w.GetObjectW(ii.hbmMask, @sizeOf(w.BITMAP), &mbm);
    const stride: usize = @intCast(mbm.bmWidthBytes);
    const mlen = stride * @as(usize, @intCast(mbm.bmHeight));
    const mask = try testing.allocator.alloc(u8, mlen);
    defer testing.allocator.free(mask);
    _ = w.GetBitmapBits(ii.hbmMask, @intCast(mlen), @ptrCast(mask.ptr));

    if (ii.hbmColor) |color| {
        defer _ = w.DeleteObject(color);
        var bm: w.BITMAP = undefined;
        _ = w.GetObjectW(color, @sizeOf(w.BITMAP), &bm);
        s.width = bm.bmWidth;
        const width: usize = @intCast(bm.bmWidth);
        const n = width * @as(usize, @intCast(bm.bmHeight));
        const px = try testing.allocator.alloc(u32, n);
        defer testing.allocator.free(px);
        var bi = w.bmi(bm.bmWidth, bm.bmHeight);
        const dc = w.GetDC(null);
        defer _ = w.ReleaseDC(null, dc);
        if (w.GetDIBits(dc, color, 0, @intCast(bm.bmHeight), @ptrCast(px.ptr), &bi, w.DIB_RGB_COLORS) == 0) return error.GetDIBits;
        const has_alpha = for (px) |p| {
            if (p >> 24 != 0) break true;
        } else false;
        for (px, 0..) |p, i| {
            const visible = if (has_alpha) (p >> 24) > 128 else core.maskBit(mask, stride, i % width, i / width) == 0;
            if (!visible) continue;
            s.opaque_px += 1;
            if (core.luma(p) > 128) s.white_px += 1;
        }
    } else {
        s.width = mbm.bmWidth;
        const width: usize = @intCast(mbm.bmWidth);
        const h: usize = @intCast(@divTrunc(mbm.bmHeight, 2));
        for (0..h) |y| {
            for (0..width) |x| {
                if (core.maskBit(mask, stride, x, y) == 0) {
                    s.opaque_px += 1;
                    if (core.maskBit(mask, stride, x, y + h) == 1) s.white_px += 1;
                }
            }
        }
    }
    return s;
}

/// Pour un curseur monochrome : nombre de pixels du corps (blancs si `core_white`, sinon noirs)
/// qui touchent directement un pixel transparent, c'est-à-dire les trous du contour.
/// Renvoie null pour un curseur couleur (bords anticrénelés, la notion ne s'applique pas).
pub fn outlineGaps(c: w.HCURSOR, core_white: bool) !?usize {
    var ii: w.ICONINFO = undefined;
    if (w.GetIconInfo(c, &ii) == 0) return error.GetIconInfo;
    defer _ = w.DeleteObject(ii.hbmMask);
    if (ii.hbmColor) |color| {
        _ = w.DeleteObject(color);
        return null;
    }
    var mbm: w.BITMAP = undefined;
    _ = w.GetObjectW(ii.hbmMask, @sizeOf(w.BITMAP), &mbm);
    const stride: usize = @intCast(mbm.bmWidthBytes);
    const width: usize = @intCast(mbm.bmWidth);
    const h: usize = @intCast(@divTrunc(mbm.bmHeight, 2));
    const mask = try testing.allocator.alloc(u8, stride * h * 2);
    defer testing.allocator.free(mask);
    _ = w.GetBitmapBits(ii.hbmMask, @intCast(mask.len), @ptrCast(mask.ptr));

    const Px = struct {
        fn transparent(m: []const u8, s: usize, x: usize, y: usize, hh: usize) bool {
            return core.maskBit(m, s, x, y) == 1 and core.maskBit(m, s, x, y + hh) == 0;
        }
    };
    var gaps: usize = 0;
    for (0..h) |y| {
        for (0..width) |x| {
            if (core.maskBit(mask, stride, x, y) != 0) continue; // pas opaque
            if ((core.maskBit(mask, stride, x, y + h) == 1) != core_white) continue; // pas le corps
            const touches = (x > 0 and Px.transparent(mask, stride, x - 1, y, h)) or
                (x + 1 < width and Px.transparent(mask, stride, x + 1, y, h)) or
                (y > 0 and Px.transparent(mask, stride, x, y - 1, h)) or
                (y + 1 < h and Px.transparent(mask, stride, x, y + 1, h));
            if (touches) gaps += 1;
        }
    }
    return gaps;
}

/// Image 32 bits en mémoire sur laquelle on peut dessiner du texte avec GDI.
pub const Canvas = struct {
    dc: w.HDC,
    bmp: w.HBITMAP,
    px: [*]u32,
    width: i32,
    height: i32,

    pub fn init(width: i32, height: i32) !Canvas {
        const dc = w.CreateCompatibleDC(null) orelse return error.CreateDC;
        var bi = w.bmi(width, height);
        var p: ?[*]u32 = null;
        const bmp = w.CreateDIBSection(dc, &bi, w.DIB_RGB_COLORS, &p, null, 0) orelse return error.CreateDIB;
        _ = w.SelectObject(dc, bmp);
        return .{ .dc = dc, .bmp = bmp, .px = p.?, .width = width, .height = height };
    }

    pub fn deinit(c: *Canvas) void {
        _ = w.DeleteDC(c.dc);
        _ = w.DeleteObject(c.bmp);
    }

    /// Remplit un rectangle avec une couleur 0xRRGGBB.
    pub fn rect(c: *Canvas, x: i32, y: i32, rw: i32, rh: i32, rgb: u32) void {
        _ = w.GdiFlush();
        var yy = @max(y, 0);
        while (yy < @min(y + rh, c.height)) : (yy += 1) {
            var xx = @max(x, 0);
            while (xx < @min(x + rw, c.width)) : (xx += 1) c.px[@intCast(yy * c.width + xx)] = rgb;
        }
    }

    pub fn fill(c: *Canvas, rgb: u32) void {
        c.rect(0, 0, c.width, c.height, rgb);
    }

    /// Écrit une ligne de texte (couleur 0xRRGGBB) en Segoe UI.
    pub fn text(c: *Canvas, x: i32, y: i32, s: []const u16, height: i32, bold: bool, rgb: u32) void {
        const font = w.CreateFontW(-height, 0, 0, 0, if (bold) w.FW_BOLD else w.FW_NORMAL, 0, 0, 0, 1, 0, 0, 5, 0, L("Segoe UI"));
        defer _ = w.DeleteObject(font);
        const old = w.SelectObject(c.dc, font);
        defer _ = w.SelectObject(c.dc, old);
        _ = w.SetBkMode(c.dc, w.TRANSPARENT);
        // COLORREF = 0x00BBGGRR
        const colorref = ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF);
        _ = w.SetTextColor(c.dc, colorref);
        _ = w.TextOutW(c.dc, x, y, s.ptr, @intCast(s.len));
        _ = w.GdiFlush();
    }
};

/// Chronomètre : temps réel (QueryPerformanceCounter) et temps processeur du thread.
/// Le temps processeur vient du compteur de cycles (QueryThreadCycleTime), précis à la
/// microseconde, alors que GetThreadTimes n'avance que par tranches de 15,6 ms.
pub const Timer = struct {
    wall0: i64,
    cycles0: u64,

    pub const Result = struct { wall_us: f64, cpu_us: f64 };

    pub fn start() Timer {
        _ = cyclesPerUs(); // calibrage avant de chronométrer
        return .{ .wall0 = qpc(), .cycles0 = threadCycles() };
    }

    /// Temps moyen par itération, en microsecondes.
    pub fn perIteration(t: Timer, n: u64) Result {
        const wall_us = @as(f64, @floatFromInt(qpc() - t.wall0)) * 1e6 / @as(f64, @floatFromInt(qpcFreq()));
        const cpu_us = @as(f64, @floatFromInt(threadCycles() - t.cycles0)) / cyclesPerUs();
        const nf: f64 = @floatFromInt(n);
        return .{ .wall_us = wall_us / nf, .cpu_us = cpu_us / nf };
    }
};

fn qpc() i64 {
    var t: i64 = 0;
    _ = w.QueryPerformanceCounter(&t);
    return t;
}

fn qpcFreq() i64 {
    var f: i64 = 1;
    _ = w.QueryPerformanceFrequency(&f);
    return f;
}

pub fn threadCycles() u64 {
    var c: u64 = 0;
    _ = w.QueryThreadCycleTime(w.GetCurrentThread(), &c);
    return c;
}

pub fn processCycles(h: w.HANDLE) u64 {
    var c: u64 = 0;
    _ = w.QueryProcessCycleTime(h, &c);
    return c;
}

var cycles_per_us: f64 = 0;

/// Cycles du compteur par microseconde, mesurés une fois en faisant tourner le processeur 100 ms.
pub fn cyclesPerUs() f64 {
    if (cycles_per_us > 0) return cycles_per_us;
    const f = qpcFreq();
    const t0 = qpc();
    const c0 = threadCycles();
    var x: u64 = 0;
    while (qpc() - t0 < @divTrunc(f, 10)) x +%= 1;
    std.mem.doNotOptimizeAway(x);
    const us = @as(f64, @floatFromInt(qpc() - t0)) * 1e6 / @as(f64, @floatFromInt(f));
    cycles_per_us = @as(f64, @floatFromInt(threadCycles() - c0)) / us;
    return cycles_per_us;
}

pub fn report(name: []const u8, value: f64, unit: []const u8, limit: f64) void {
    std.debug.print("  {s:<52} {d:>10.3} {s}   (seuil {d} {s})\n", .{ name, value, unit, limit, unit });
}
