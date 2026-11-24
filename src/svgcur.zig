//! Curseurs dessinés à partir des dessins vectoriels de Windows 11 (C:\Windows\Cursors\*.svg).
//!
//! Quand on agrandit le pointeur dans les Paramètres d'accessibilité, Windows 11 n'utilise plus
//! ses images classiques : il dessine ces SVG une fois en 240 x 240 (fichiers *_eoa.cur de
//! %LOCALAPPDATA%\Microsoft\Windows\Cursors) et les réduit à la taille voulue. On fait pareil :
//! - rendu en 240 x 240 avec Direct2D, corps noir et contour blanc ;
//! - les dessins sont rangés à l'envers : l'image est retournée (c'est l'ordre des lignes, de
//!   bas en haut, des images de curseur qui s'en charge) ;
//! - un pixel touché, même en partie, par le dessin est visible, comme chez Windows ;
//! - jeux noir et blanc en 1 bit, jeu rouge en 32 bits avec bords adoucis ;
//! - points chauds relevés dans les fichiers produits par Windows.
//!
//! Direct2D n'est chargé que le temps du dessin (LoadLibrary, puis FreeLibrary).

const std = @import("std");
const core = @import("core.zig");
const w = @import("win32.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

/// Côté des images, comme les fichiers *_eoa.cur de Windows.
pub const SIZE = 240;

/// Dessin de chaque curseur, dans l'ordre de cursors.defs, et son point chaud en 240 x 240
/// (celui des fichiers *_eoa.cur produits par Windows 11).
pub const Shape = struct { name: []const u16, hot_x: u16, hot_y: u16 };
pub const shapes = blk: {
    @setEvalBranchQuota(20_000);
    break :blk [_]Shape{
        .{ .name = L("arrow"), .hot_x = 5, .hot_y = 1 }, // 32512 flèche
        .{ .name = L("ibeam"), .hot_x = 119, .hot_y = 119 }, // 32513 sélection de texte
        .{ .name = L("wait"), .hot_x = 120, .hot_y = 116 }, // 32514 occupé (sablier seul)
        .{ .name = L("cross"), .hot_x = 119, .hot_y = 119 }, // 32515 précision
        .{ .name = L("up"), .hot_x = 44, .hot_y = 0 }, // 32516 autre sélection
        .{ .name = L("pen"), .hot_x = 2, .hot_y = 2 }, // 32631 stylet
        .{ .name = L("nwse"), .hot_x = 66, .hot_y = 66 }, // 32642 redim. NO-SE
        .{ .name = L("nesw"), .hot_x = 66, .hot_y = 66 }, // 32643 redim. NE-SO
        .{ .name = L("ew"), .hot_x = 89, .hot_y = 44 }, // 32644 redim. horizontal
        .{ .name = L("ns"), .hot_x = 36, .hot_y = 89 }, // 32645 redim. vertical
        .{ .name = L("move"), .hot_x = 89, .hot_y = 89 }, // 32646 déplacer
        .{ .name = L("unavail"), .hot_x = 67, .hot_y = 66 }, // 32648 indisponible
        .{ .name = L("link"), .hot_x = 56, .hot_y = 0 }, // 32649 main (lien)
        .{ .name = L("busy"), .hot_x = 5, .hot_y = 6 }, // 32650 arrière-plan (flèche et sablier)
        .{ .name = L("helpsel"), .hot_x = 5, .hot_y = 6 }, // 32651 aide
        .{ .name = L("pin"), .hot_x = 58, .hot_y = 2 }, // 32671 emplacement
        .{ .name = L("person"), .hot_x = 54, .hot_y = 1 }, // 32672 personne
    };
};

// ---------------------------------------------------------------- logique pure

/// Couleurs « corps » et « contour » prévues par Windows dans ses dessins : il les remplace
/// selon le style de pointeur choisi. On les remplace par `body` et `outline` (« RRGGBB »).
pub fn colorize(svg: []u8, body: *const [6]u8, outline: *const [6]u8) void {
    var i: usize = 0;
    while (i + 7 <= svg.len) : (i += 1) {
        if (svg[i] != '#') continue;
        const hex = svg[i + 1 ..][0..6];
        if (std.ascii.eqlIgnoreCase(hex, "FFFFFE")) {
            @memcpy(hex, body);
        } else if (std.ascii.eqlIgnoreCase(hex, "000001")) {
            @memcpy(hex, outline);
        }
    }
}

/// Image 1 bit d'un rendu en 32 bits prémultipliés (`px`, `s` x `s`, lignes dans le sens du
/// dessin, qui deviennent les lignes de bas en haut de l'image de curseur). Un pixel touché par
/// le dessin est visible ; sombre, c'est le corps (couleur 0, noir), sinon le contour (1, blanc).
pub fn toMono(px: []const u32, s: usize, xor_bits: []u8, and_bits: []u8) void {
    const ms = (s + 31) / 32 * 4;
    std.debug.assert(px.len == s * s and xor_bits.len == ms * s and and_bits.len == ms * s);
    @memset(xor_bits, 0);
    @memset(and_bits, 0);
    for (0..s) |y| {
        for (0..s) |x| {
            const c = px[y * s + x];
            const a = c >> 24;
            const bit = @as(u8, 0x80) >> @intCast(x % 8);
            const at = y * ms + x / 8;
            if (a == 0) {
                and_bits[at] |= bit; // transparent
            } else if (core.luma(unpremultiply(c)) >= 128) {
                xor_bits[at] |= bit; // contour blanc
            }
        }
    }
}

/// Couleur d'un pixel prémultiplié ramenée à sa valeur réelle (alpha gardé).
pub fn unpremultiply(c: u32) u32 {
    const a = c >> 24;
    if (a == 0 or a == 255) return c;
    var out = c & 0xFF000000;
    inline for (.{ 16, 8, 0 }) |sh| {
        const v = (c >> sh) & 255;
        out |= @as(u32, @min(255, (v * 255 + a / 2) / a)) << sh;
    }
    return out;
}

test "shapes : un dessin par curseur, points chauds dans l'image" {
    try std.testing.expectEqual(@as(usize, 17), shapes.len);
    for (shapes, 0..) |a, i| {
        try std.testing.expect(a.hot_x < SIZE and a.hot_y < SIZE);
        for (shapes[i + 1 ..]) |b| try std.testing.expect(!std.mem.eql(u16, a.name, b.name));
    }
}

test "colorize : remplace corps et contour, majuscules ou minuscules, rien d'autre" {
    var svg = "fill:#FFFFFE;stroke:#000001; fill:#fffffe;stroke:#000001;stroke:#000000;fill:#FFFFFF".*;
    colorize(&svg, "E81123", "FFFFFF");
    try std.testing.expectEqualStrings("fill:#E81123;stroke:#FFFFFF; fill:#E81123;stroke:#FFFFFF;stroke:#000000;fill:#FFFFFF", &svg);
    var tail = "#FFFF".*; // « # » trop près de la fin : rien
    colorize(&tail, "000000", "FFFFFF");
    try std.testing.expectEqualStrings("#FFFF", &tail);
}

test "unpremultiply : opaque et transparent inchangés, demi-teintes rétablies" {
    try std.testing.expectEqual(@as(u32, 0xFF123456), unpremultiply(0xFF123456));
    try std.testing.expectEqual(@as(u32, 0), unpremultiply(0));
    try std.testing.expectEqual(@as(u32, 0x80FFFFFF), unpremultiply(0x80808080)); // blanc à moitié
    try std.testing.expectEqual(@as(u32, 0x80000000), unpremultiply(0x80000000)); // noir à moitié
}

test "toMono : transparent, corps sombre, contour clair, même à peine touché" {
    // 4 pixels sur une ligne (s = 2, deux lignes)
    const px = [_]u32{ 0x00000000, 0xFF000000, 0xFFFFFFFF, 0x01010101 };
    var xb: [8]u8 = undefined;
    var ab: [8]u8 = undefined;
    toMono(&px, 2, &xb, &ab);
    try std.testing.expectEqual(@as(u8, 0b1000_0000), ab[0]); // ligne 0 : pixel 0 transparent
    try std.testing.expectEqual(@as(u8, 0b0000_0000), xb[0]); // pixel 1 : corps noir
    try std.testing.expectEqual(@as(u8, 0b0000_0000), ab[4]); // ligne 1 : tout visible
    try std.testing.expectEqual(@as(u8, 0b1100_0000), xb[4]); // contour blanc, et blanc à peine touché
}

// ---------------------------------------------------------------- Direct2D

const GUID = extern struct { d1: u32, d2: u16, d3: u16, d4: [8]u8 };
const IID_ID2D1Factory: GUID = .{ .d1 = 0x06152247, .d2 = 0x6f50, .d3 = 0x465a, .d4 = .{ 0x92, 0x45, 0x11, 0x8b, 0xfd, 0x3b, 0x60, 0x07 } };
const IID_ID2D1DeviceContext5: GUID = .{ .d1 = 0x7836d248, .d2 = 0x68cc, .d3 = 0x4df6, .d4 = .{ 0xb9, 0xe8, 0xde, 0x99, 0x1b, 0xf6, 0x2e, 0xb7 } };

const RenderTargetProps = extern struct {
    kind: u32 = 0, // D2D1_RENDER_TARGET_TYPE_DEFAULT
    format: u32 = 87, // DXGI_FORMAT_B8G8R8A8_UNORM
    alpha: u32 = 1, // D2D1_ALPHA_MODE_PREMULTIPLIED
    dpi_x: f32 = 96, // 1 unité = 1 pixel, quel que soit l'agrandissement de l'écran
    dpi_y: f32 = 96,
    usage: u32 = 0,
    min_level: u32 = 0,
};
const SizeF = extern struct { width: f32, height: f32 };
const ColorF = extern struct { r: f32, g: f32, b: f32, a: f32 };

// Positions des méthodes dans les tables COM, relevées avec un programme C++ compilé sur les
// en-têtes d2d1*.h (pointeurs de méthodes virtuelles). Une position fausse ferait échouer
// le dessin : les tests d'intégration comparent nos 17 dessins à ceux de Windows.
const SLOT_QUERY_INTERFACE = 0;
const SLOT_RELEASE = 2;
const SLOT_CREATE_DC_RENDER_TARGET = 16; // ID2D1Factory
const SLOT_CLEAR = 47; // ID2D1RenderTarget
const SLOT_BEGIN_DRAW = 48;
const SLOT_END_DRAW = 49;
const SLOT_BIND_DC = 57; // ID2D1DCRenderTarget
const SLOT_CREATE_SVG_DOCUMENT = 115; // ID2D1DeviceContext5
const SLOT_DRAW_SVG_DOCUMENT = 116;

const Obj = *anyopaque;

fn method(comptime F: type, obj: Obj, slot: usize) F {
    const vtbl: *const [*]const *const anyopaque = @ptrCast(@alignCast(obj));
    return @ptrCast(vtbl.*[slot]);
}

fn release(obj: ?Obj) void {
    const o = obj orelse return;
    _ = method(*const fn (Obj) callconv(.winapi) u32, o, SLOT_RELEASE)(o);
}

const CreateFactoryFn = *const fn (u32, *const GUID, ?*const anyopaque, *?Obj) callconv(.winapi) i32;
const CreateMemStreamFn = *const fn ([*]const u8, u32) callconv(.winapi) ?Obj;

/// Dessinateur Direct2D : une cible « DC » posée sur une image 32 bits de 240 x 240.
pub const Renderer = struct {
    d2d: w.HMODULE = null,
    shl: w.HMODULE = null,
    create_stream: CreateMemStreamFn = undefined,
    factory: ?Obj = null,
    target: ?Obj = null,
    context: ?Obj = null,
    dc: w.HDC = null,
    dib: w.HBITMAP = null,
    old: w.HGDIOBJ = null,
    /// pixels du dernier rendu (BGRA prémultiplié, lignes dans le sens du dessin)
    bits: [*]u32 = undefined,

    /// Charge Direct2D et prépare la cible ; null si c'est impossible (Windows trop ancien…).
    pub fn init() ?Renderer {
        var r: Renderer = .{};
        if (!r.setup()) {
            r.deinit();
            return null;
        }
        return r;
    }

    fn setup(r: *Renderer) bool {
        r.d2d = w.LoadLibraryW(L("d2d1.dll"));
        r.shl = w.LoadLibraryW(L("shlwapi.dll"));
        const create_factory: CreateFactoryFn = @ptrCast(w.GetProcAddress(r.d2d orelse return false, "D2D1CreateFactory") orelse return false);
        r.create_stream = @ptrCast(w.GetProcAddress(r.shl orelse return false, "SHCreateMemStream") orelse return false);
        if (create_factory(0, &IID_ID2D1Factory, null, &r.factory) < 0) return false; // mono-fil
        const props: RenderTargetProps = .{};
        const factory = r.factory orelse return false;
        if (method(*const fn (Obj, *const RenderTargetProps, *?Obj) callconv(.winapi) i32, factory, SLOT_CREATE_DC_RENDER_TARGET)(factory, &props, &r.target) < 0) return false;
        const target = r.target orelse return false;
        if (method(*const fn (Obj, *const GUID, *?Obj) callconv(.winapi) i32, target, SLOT_QUERY_INTERFACE)(target, &IID_ID2D1DeviceContext5, &r.context) < 0) return false;

        r.dc = w.CreateCompatibleDC(null) orelse return false;
        var bi = w.bmi(SIZE, SIZE); // de haut en bas, 32 bits
        var bits: ?[*]u32 = null;
        r.dib = w.CreateDIBSection(r.dc, &bi, w.DIB_RGB_COLORS, &bits, null, 0) orelse return false;
        r.bits = bits orelse return false;
        r.old = w.SelectObject(r.dc, r.dib);
        const rect: w.RECT = .{ .left = 0, .top = 0, .right = SIZE, .bottom = SIZE };
        return method(*const fn (Obj, w.HDC, *const w.RECT) callconv(.winapi) i32, target, SLOT_BIND_DC)(target, r.dc, &rect) >= 0;
    }

    /// Libère tout, Direct2D compris.
    pub fn deinit(r: *Renderer) void {
        release(r.context);
        release(r.target);
        release(r.factory);
        if (r.dc) |dc| {
            if (r.old) |o| _ = w.SelectObject(dc, o);
            _ = w.DeleteDC(dc);
        }
        if (r.dib) |b| _ = w.DeleteObject(b);
        if (r.d2d) |m| _ = w.FreeLibrary(m);
        if (r.shl) |m| _ = w.FreeLibrary(m);
        r.* = .{};
    }

    /// Dessine le SVG `svg` (texte) en 240 x 240 dans `bits`. Faux si Direct2D le refuse.
    pub fn draw(r: *Renderer, svg: []const u8) bool {
        const target = r.target orelse return false;
        const context = r.context orelse return false;
        const stream = r.create_stream(svg.ptr, @intCast(svg.len)) orelse return false;
        defer release(stream);
        var doc: ?Obj = null;
        const size: SizeF = .{ .width = SIZE, .height = SIZE };
        if (method(*const fn (Obj, Obj, SizeF, *?Obj) callconv(.winapi) i32, context, SLOT_CREATE_SVG_DOCUMENT)(context, stream, size, &doc) < 0) return false;
        defer release(doc);
        method(*const fn (Obj) callconv(.winapi) void, target, SLOT_BEGIN_DRAW)(target);
        const clear: ColorF = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
        method(*const fn (Obj, *const ColorF) callconv(.winapi) void, target, SLOT_CLEAR)(target, &clear);
        method(*const fn (Obj, Obj) callconv(.winapi) void, context, SLOT_DRAW_SVG_DOCUMENT)(context, doc.?);
        if (method(*const fn (Obj, ?*u64, ?*u64) callconv(.winapi) i32, target, SLOT_END_DRAW)(target, null, null) < 0) return false;
        _ = w.GdiFlush();
        return true;
    }

    pub fn pixels(r: *const Renderer) []u32 {
        return r.bits[0 .. SIZE * SIZE];
    }
};
