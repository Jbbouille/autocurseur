//! Fichiers de curseurs (.cur) : lit les images d'un fichier de Windows et écrit un fichier
//! dérivé (inversé ou teinté) qui garde toutes ses tailles. Windows choisit ensuite lui-même,
//! écran par écran, l'image de la bonne taille : le curseur reste net partout, même quand
//! les écrans n'ont pas le même agrandissement.
//!
//! Format : ICONDIR (6 octets), une entrée de 16 octets par image, puis chaque image en DIB :
//! BITMAPINFOHEADER (hauteur doublée), palette (images 1 bit), couleur (OU exclusif), masque
//! de transparence (ET). Lignes de bas en haut, chacune alignée sur 4 octets.
//!
//! Logique pure, sans Windows : entièrement testée ici.

const std = @import("std");
const core = @import("core.zig");
const testing = std.testing;

/// Teinte : couleur (0xRRGGBB) donnée au noir et couleur donnée au blanc de l'image d'origine.
pub const Tint = struct { at0: u32, at255: u32 };

pub const Op = union(enum) {
    /// recopie
    copy,
    /// noir <-> blanc, dans le même format (1 bit ou 32 bits)
    invert,
    /// version teintée, toujours en 32 bits (voir core.tint)
    tint: Tint,

    /// version rouge d'une image noire (corps noir -> rouge, contour blanc gardé)
    pub const red: Op = .{ .tint = .{ .at0 = core.RED, .at255 = core.WHITE } };
    /// version rouge d'une image blanche (corps blanc -> rouge, contour noir -> blanc)
    pub const invert_red: Op = .{ .tint = .{ .at0 = core.WHITE, .at255 = core.RED } };
};

pub const MAX_FRAMES = 16;
const DIR = 6;
const ENTRY = 16;
const BIH = 40;

fn get16(b: []const u8, at: usize) u16 {
    return std.mem.readInt(u16, b[at..][0..2], .little);
}
fn get32(b: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, b[at..][0..4], .little);
}
fn put16(b: []u8, at: usize, v: u16) void {
    std.mem.writeInt(u16, b[at..][0..2], v, .little);
}
fn put32(b: []u8, at: usize, v: u32) void {
    std.mem.writeInt(u32, b[at..][0..4], v, .little);
}

/// Taille d'une ligne de `w` pixels à `bpp` bits, alignée sur 4 octets.
pub fn stride(w: usize, bpp: usize) usize {
    return (w * bpp + 31) / 32 * 4;
}

/// Une image du fichier source, vérifiée.
pub const Frame = struct {
    w: usize,
    h: usize,
    hot_x: u16,
    hot_y: u16,
    /// 1 ou 32
    bpp: u16,
    /// image 1 bit : le bit de couleur 1 désigne le blanc (palette habituelle)
    one_is_white: bool,
    /// image 1 bit : les 2 couleurs de la palette (8 octets)
    palette: []const u8,
    xor_bits: []const u8,
    and_bits: []const u8,
};

/// Nombre d'images annoncées, ou null si `src` n'est pas un fichier de curseur.
pub fn frameCount(src: []const u8) ?usize {
    if (src.len < DIR) return null;
    if (get16(src, 0) != 0 or get16(src, 2) != 2) return null;
    const n = get16(src, 4);
    if (n == 0 or n > MAX_FRAMES or src.len < DIR + ENTRY * @as(usize, n)) return null;
    return n;
}

/// Image `i` de `src` (i < frameCount), ou null si elle est tronquée ou dans un format non
/// pris en charge : PNG, compression, palette de plus de 2 couleurs, 4, 8 ou 24 bits.
pub fn frame(src: []const u8, i: usize) ?Frame {
    const e = DIR + ENTRY * i;
    const len: usize = get32(src, e + 8);
    const off: usize = get32(src, e + 12);
    if (off > src.len or len > src.len - off or len < BIH) return null;
    const d = src[off..][0..len];
    const bih: usize = get32(d, 0); // une image PNG commence par 89 50 4E 47 : valeur énorme
    if (bih < BIH or bih > len) return null;
    const wi: i32 = @bitCast(get32(d, 4));
    const hi: i32 = @bitCast(get32(d, 8));
    const bpp = get16(d, 14);
    if (wi <= 0 or hi <= 0 or @mod(hi, 2) != 0 or get16(d, 12) != 1 or get32(d, 16) != 0) return null;
    if (bpp != 1 and bpp != 32) return null;
    const w: usize = @intCast(wi);
    const h: usize = @intCast(@divExact(hi, 2));
    if (w > core.MAX_CUR or h > core.MAX_CUR) return null;

    var at = bih;
    var pal: []const u8 = &.{};
    if (bpp == 1) {
        const used = get32(d, 32);
        if (used != 0 and used != 2) return null;
        if (at + 8 > len) return null;
        pal = d[at..][0..8];
        at += 8;
    }
    const xs = stride(w, bpp) * h;
    const as_ = stride(w, 1) * h;
    if (at + xs + as_ > len) return null;
    return .{
        .w = w,
        .h = h,
        .hot_x = get16(src, e + 4),
        .hot_y = get16(src, e + 6),
        .bpp = bpp,
        // couleurs de la palette en B, G, R, 0 : lues comme 0x00RRGGBB
        .one_is_white = bpp != 1 or core.luma(get32(pal, 4)) >= core.luma(get32(pal, 0)),
        .palette = pal,
        .xor_bits = d[at..][0..xs],
        .and_bits = d[at + xs ..][0..as_],
    };
}

fn outBpp(f: Frame, op: Op) u16 {
    return switch (op) {
        .copy, .invert => f.bpp,
        .tint => 32,
    };
}

fn frameLen(f: Frame, op: Op) usize {
    const bpp = outBpp(f, op);
    const pal: usize = if (bpp == 1) 8 else 0;
    return BIH + pal + stride(f.w, bpp) * f.h + stride(f.w, 1) * f.h;
}

fn pixels(b: []u8) []u32 {
    return @alignCast(std.mem.bytesAsSlice(u32, b));
}

/// Écrit l'image `f` transformée par `op` dans `dst` (frameLen octets, dont la partie
/// couleur doit être alignée sur 4 octets).
fn writeFrame(f: Frame, op: Op, dst: []u8) void {
    const bpp = outBpp(f, op);
    const xs = stride(f.w, bpp) * f.h;
    const mask_stride = stride(f.w, 1);
    const as_ = mask_stride * f.h;
    @memset(dst[0..BIH], 0);
    put32(dst, 0, BIH);
    put32(dst, 4, @intCast(f.w));
    put32(dst, 8, @intCast(f.h * 2));
    put16(dst, 12, 1);
    put16(dst, 14, bpp);
    put32(dst, 20, @intCast(xs)); // comme les fichiers de Windows : taille de l'image couleur seule
    var at: usize = BIH;
    if (bpp == 1) {
        @memcpy(dst[at..][0..8], f.palette);
        at += 8;
    }
    const xor_out = dst[at..][0..xs];
    @memcpy(dst[at + xs ..][0..as_], f.and_bits); // la transparence ne change pas
    switch (op) {
        .copy => @memcpy(xor_out, f.xor_bits),
        .invert => {
            @memcpy(xor_out, f.xor_bits);
            if (f.bpp == 1) {
                core.invertMono(xor_out, f.and_bits);
            } else {
                core.invertColorPixels(pixels(xor_out), f.w, f.and_bits, mask_stride);
            }
        },
        .tint => |t| {
            const px = pixels(xor_out);
            if (f.bpp == 1) {
                core.monoToColor(f.and_bits, f.xor_bits, mask_stride, f.w, f.h, f.one_is_white, t.at0, t.at255, px);
            } else {
                @memcpy(xor_out, f.xor_bits);
                core.tintColorPixels(px, f.w, f.and_bits, mask_stride, t.at0, t.at255);
            }
        },
    }
}

/// Écrit dans `out` le fichier dérivé de `src` par `op` et renvoie sa taille, ou null si
/// `src` n'a aucune image utilisable ou si `out` est trop petit. Les images dans un format
/// non pris en charge sont laissées de côté ; celles qui restent gardent leurs tailles et
/// leurs points chauds.
pub fn derive(src: []const u8, op: Op, out: []align(4) u8) ?usize {
    const n = frameCount(src) orelse return null;
    var frames: [MAX_FRAMES]Frame = undefined;
    var k: usize = 0;
    for (0..n) |i| {
        if (frame(src, i)) |f| {
            frames[k] = f;
            k += 1;
        }
    }
    if (k == 0) return null;

    // table des images, puis chaque image à une position alignée sur 4 octets
    var at = std.mem.alignForward(usize, DIR + ENTRY * k, 4);
    if (at > out.len) return null;
    @memset(out[0..at], 0);
    put16(out, 2, 2);
    put16(out, 4, @intCast(k));
    var end = at;
    for (frames[0..k], 0..) |f, i| {
        const len = frameLen(f, op);
        if (at > out.len or len > out.len - at) return null;
        const e = DIR + ENTRY * i;
        out[e] = if (f.w >= 256) 0 else @intCast(f.w);
        out[e + 1] = if (f.h >= 256) 0 else @intCast(f.h);
        // nombre de couleurs : 2 pour une image 1 bit, comme Windows (sinon il l'étire autrement)
        out[e + 2] = if (outBpp(f, op) == 1) 2 else 0;
        put16(out, e + 4, f.hot_x);
        put16(out, e + 6, f.hot_y);
        put32(out, e + 8, @intCast(len));
        put32(out, e + 12, @intCast(at));
        writeFrame(f, op, out[at..][0..len]);
        end = at + len;
        at = std.mem.alignForward(usize, end, 4);
    }
    return end;
}

/// Taille maximale du fichier dérivé de `src` (pour vérifier un tampon à l'avance).
pub fn derivedLen(src: []const u8, op: Op) ?usize {
    const n = frameCount(src) orelse return null;
    var total = std.mem.alignForward(usize, DIR + ENTRY * n, 4);
    for (0..n) |i| {
        if (frame(src, i)) |f| total = std.mem.alignForward(usize, total + frameLen(f, op), 4);
    }
    return total;
}

/// En-tête d'un fichier d'une seule image `s` x `s` (table + BITMAPINFOHEADER), écrit au début
/// de `out` ; renvoie la position des données de l'image.
fn singleHeader(out: []u8, s: usize, hot_x: u16, hot_y: u16, bpp: u16, data_len: usize) usize {
    const at = std.mem.alignForward(usize, DIR + ENTRY, 4);
    @memset(out[0..at], 0);
    put16(out, 2, 2);
    put16(out, 4, 1);
    out[DIR] = if (s >= 256) 0 else @intCast(s);
    out[DIR + 1] = if (s >= 256) 0 else @intCast(s);
    out[DIR + 2] = if (bpp == 1) 2 else 0;
    put16(out, DIR + 4, hot_x);
    put16(out, DIR + 6, hot_y);
    put32(out, DIR + 8, @intCast(BIH + data_len));
    put32(out, DIR + 12, @intCast(at));
    const d = out[at..];
    @memset(d[0..BIH], 0);
    put32(d, 0, BIH);
    put32(d, 4, @intCast(s));
    put32(d, 8, @intCast(s * 2));
    put16(d, 12, 1);
    put16(d, 14, bpp);
    put32(d, 20, @intCast(stride(s, bpp) * s));
    return at + BIH;
}

/// Taille d'un fichier d'une seule image `s` x `s` à `bpp` bits (1 ou 32).
pub fn singleLen(s: usize, bpp: u16) usize {
    const pal: usize = if (bpp == 1) 8 else 0;
    return std.mem.alignForward(usize, DIR + ENTRY, 4) + BIH + pal + stride(s, bpp) * s + stride(s, 1) * s;
}

/// Fichier .cur d'une seule image 1 bit de `s` x `s` : `xor_bits` (couleur : 0 noir, 1 blanc)
/// et `and_bits` (1 = transparent), lignes de bas en haut de stride(s, 1) octets. Renvoie sa
/// taille, ou null si `out` est trop petit.
pub fn monoFile(out: []u8, s: usize, hot_x: u16, hot_y: u16, xor_bits: []const u8, and_bits: []const u8) ?usize {
    const n = stride(s, 1) * s;
    std.debug.assert(xor_bits.len == n and and_bits.len == n);
    const len = singleLen(s, 1);
    if (len > out.len) return null;
    var at = singleHeader(out, s, hot_x, hot_y, 1, 8 + 2 * n);
    put32(out, at, 0x000000); // index 0 : noir
    put32(out, at + 4, 0xFFFFFF); // index 1 : blanc
    at += 8;
    @memcpy(out[at..][0..n], xor_bits);
    @memcpy(out[at + n ..][0..n], and_bits);
    return len;
}

/// Fichier .cur d'une seule image 32 bits de `s` x `s` : pixels BGRA (alpha non prémultiplié),
/// lignes de bas en haut. Le masque ET (transparent là où alpha = 0) est calculé. Renvoie sa
/// taille, ou null si `out` est trop petit.
pub fn colorFile(out: []u8, s: usize, hot_x: u16, hot_y: u16, px: []const u32) ?usize {
    std.debug.assert(px.len == s * s);
    const len = singleLen(s, 32);
    if (len > out.len) return null;
    const ms = stride(s, 1);
    const at = singleHeader(out, s, hot_x, hot_y, 32, s * s * 4 + ms * s);
    for (px, 0..) |c, i| put32(out, at + i * 4, c);
    const mask = out[at + s * s * 4 ..][0 .. ms * s];
    @memset(mask, 0);
    for (px, 0..) |c, i| {
        const x = i % s;
        if (c >> 24 == 0) mask[(i / s) * ms + x / 8] |= @as(u8, 0x80) >> @intCast(x % 8);
    }
    return len;
}

// ---------------------------------------------------------------- tests

/// Fabrique un fichier de curseur de test dans `buf` : une image par taille de `sizes`,
/// en 1 bit (`bpp` = 1) ou 32 bits. Dessin : un carré plein (corps noir) entouré d'un
/// contour blanc d'un pixel, le reste transparent ; point chaud (1, 2).
fn makeCur(buf: []u8, sizes: []const usize, bpp: u16) []u8 {
    var at = DIR + ENTRY * sizes.len;
    @memset(buf[0..at], 0);
    put16(buf, 2, 2);
    put16(buf, 4, @intCast(sizes.len));
    for (sizes, 0..) |s, i| {
        const xs = stride(s, bpp) * s;
        const as_ = stride(s, 1) * s;
        const pal: usize = if (bpp == 1) 8 else 0;
        const len = BIH + pal + xs + as_;
        const e = DIR + ENTRY * i;
        buf[e] = @intCast(s);
        buf[e + 1] = @intCast(s);
        put16(buf, e + 4, 1);
        put16(buf, e + 6, 2);
        put32(buf, e + 8, @intCast(len));
        put32(buf, e + 12, @intCast(at));
        const d = buf[at..][0..len];
        @memset(d, 0);
        put32(d, 0, BIH);
        put32(d, 4, @intCast(s));
        put32(d, 8, @intCast(s * 2));
        put16(d, 12, 1);
        put16(d, 14, bpp);
        var p: usize = BIH;
        if (bpp == 1) {
            put32(d, p, 0x000000); // index 0 : noir
            put32(d, p + 4, 0xFFFFFF); // index 1 : blanc
            p += 8;
        }
        const ms = stride(s, 1);
        for (0..s) |y| {
            for (0..s) |x| {
                const edge = x == 0 or y == 0 or x == s - 1 or y == s - 1;
                const inside = x >= 1 and y >= 1 and x <= s - 2 and y <= s - 2;
                const opaque_px = edge or inside;
                // marge transparente : seul le carré central de s-2 avec son contour est opaque
                const visible = opaque_px and x < s - 1 and y < s - 1;
                if (!visible) d[p + xs + y * ms + x / 8] |= @as(u8, 0x80) >> @intCast(x % 8);
                const white = edge;
                if (bpp == 1) {
                    if (white) d[p + y * stride(s, 1) + x / 8] |= @as(u8, 0x80) >> @intCast(x % 8);
                } else {
                    const c: u32 = if (!visible) 0 else if (white) 0xFFFFFFFF else 0xFF000000;
                    put32(d, p + (y * s + x) * 4, c);
                }
            }
        }
        at += len;
    }
    return buf[0..at];
}

var test_src: [64 * 1024]u8 = undefined;
var test_out: [64 * 1024]u8 align(4) = undefined;
var test_out2: [64 * 1024]u8 align(4) = undefined;

test "frameCount : refuse ce qui n'est pas un fichier de curseur" {
    try testing.expectEqual(@as(?usize, null), frameCount(&.{}));
    try testing.expectEqual(@as(?usize, null), frameCount(&.{ 0, 0, 1, 0, 1, 0 })); // icône (type 1)
    try testing.expectEqual(@as(?usize, null), frameCount(&.{ 0, 0, 2, 0, 0, 0 })); // aucune image
    try testing.expectEqual(@as(?usize, null), frameCount(&.{ 0, 0, 2, 0, 3, 0 })); // table tronquée
    const src = makeCur(&test_src, &.{ 32, 48 }, 1);
    try testing.expectEqual(@as(?usize, 2), frameCount(src));
}

test "frame : lit tailles, point chaud, profondeur et palette" {
    const src = makeCur(&test_src, &.{ 32, 48 }, 1);
    const f = frame(src, 1).?;
    try testing.expectEqual(@as(usize, 48), f.w);
    try testing.expectEqual(@as(usize, 48), f.h);
    try testing.expectEqual(@as(u16, 1), f.hot_x);
    try testing.expectEqual(@as(u16, 2), f.hot_y);
    try testing.expectEqual(@as(u16, 1), f.bpp);
    try testing.expect(f.one_is_white);
    try testing.expectEqual(stride(48, 1) * 48, f.xor_bits.len);
    const c = frame(makeCur(&test_src, &.{64}, 32), 0).?;
    try testing.expectEqual(@as(u16, 32), c.bpp);
    try testing.expectEqual(@as(usize, 64 * 64 * 4), c.xor_bits.len);
}

test "frame : refuse PNG, compression, palette de 16 couleurs, données tronquées" {
    const src = makeCur(&test_src, &.{32}, 1);
    const off = get32(src, DIR + 12);
    var bad: [8 * 1024]u8 = undefined;
    @memcpy(bad[0..src.len], src);
    // PNG
    @memcpy(bad[off..][0..4], "\x89PNG");
    try testing.expectEqual(@as(?Frame, null), frame(bad[0..src.len], 0));
    // compression
    @memcpy(bad[0..src.len], src);
    put32(&bad, off + 16, 1);
    try testing.expectEqual(@as(?Frame, null), frame(bad[0..src.len], 0));
    // palette de 16 couleurs
    @memcpy(bad[0..src.len], src);
    put32(&bad, off + 32, 16);
    try testing.expectEqual(@as(?Frame, null), frame(bad[0..src.len], 0));
    // fichier coupé avant la fin de l'image
    try testing.expectEqual(@as(?Frame, null), frame(src[0 .. src.len - 1], 0));
    // hauteur impaire (pas de masque)
    @memcpy(bad[0..src.len], src);
    put32(&bad, off + 8, 33);
    try testing.expectEqual(@as(?Frame, null), frame(bad[0..src.len], 0));
}

test "derive : la recopie relue donne les mêmes images, à des positions alignées" {
    const src = makeCur(&test_src, &.{ 32, 48, 64 }, 1);
    const len = derive(src, .copy, &test_out).?;
    const out = test_out[0..len];
    try testing.expectEqual(@as(?usize, 3), frameCount(out));
    for (0..3) |i| {
        const a = frame(src, i).?;
        const b = frame(out, i).?;
        try testing.expectEqual(a.w, b.w);
        try testing.expectEqual(a.hot_x, b.hot_x);
        try testing.expectEqual(a.hot_y, b.hot_y);
        try testing.expectEqualSlices(u8, a.xor_bits, b.xor_bits);
        try testing.expectEqualSlices(u8, a.and_bits, b.and_bits);
        try testing.expectEqual(@as(u32, 0), get32(out, DIR + ENTRY * i + 12) % 4);
    }
    try testing.expectEqual(derivedLen(src, .copy).?, std.mem.alignForward(usize, len, 4));
}

test "derive : inversion 1 bit, couleur basculée là où c'est opaque, masque gardé" {
    const src = makeCur(&test_src, &.{32}, 1);
    const len = derive(src, .invert, &test_out).?;
    const a = frame(src, 0).?;
    const b = frame(test_out[0..len], 0).?;
    try testing.expectEqualSlices(u8, a.and_bits, b.and_bits);
    for (a.xor_bits, b.xor_bits, a.and_bits) |x0, x1, m| try testing.expectEqual(x0 ^ ~m, x1);
}

test "derive : inverser deux fois redonne exactement le fichier recopié" {
    for ([_]u16{ 1, 32 }) |bpp| {
        const src = makeCur(&test_src, &.{ 32, 48 }, bpp);
        const once = derive(src, .invert, &test_out).?;
        const twice = derive(test_out[0..once], .invert, &test_out2).?;
        const copy = derive(src, .copy, &test_out).?;
        try testing.expectEqualSlices(u8, test_out[0..copy], test_out2[0..twice]);
    }
}

test "derive : version rouge d'une image 1 bit, en 32 bits avec transparence" {
    const src = makeCur(&test_src, &.{32}, 1);
    const len = derive(src, .red, &test_out).?;
    const f = frame(test_out[0..len], 0).?;
    try testing.expectEqual(@as(u16, 32), f.bpp);
    const px = std.mem.bytesAsSlice(u32, f.xor_bits);
    // DIB de bas en haut : la ligne 0 du fichier est celle du bas de l'image
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), px[0]); // contour (bas-gauche)
    try testing.expectEqual(@as(u32, 0xFF000000 | core.RED), px[1 * 32 + 1]); // corps
    try testing.expectEqual(@as(u32, 0), px[31]); // marge transparente
}

test "derive : rouge d'une image blanche = rouge de son inverse, en 1 bit comme en 32 bits" {
    for ([_]u16{ 1, 32 }) |bpp| {
        const src = makeCur(&test_src, &.{ 32, 48 }, bpp);
        const inv = derive(src, .invert, &test_out).?;
        const a = derive(test_out[0..inv], .invert_red, &test_out2).?;
        const b = derive(src, .red, &test_out).?;
        try testing.expectEqualSlices(u8, test_out[0..b], test_out2[0..a]);
    }
}

test "derive : une image PNG au milieu est laissée de côté, les autres gardées" {
    const src = makeCur(&test_src, &.{ 32, 48, 64 }, 1);
    const off = get32(src, DIR + ENTRY * 1 + 12);
    @memcpy(test_src[off..][0..4], "\x89PNG");
    const len = derive(src, .copy, &test_out).?;
    try testing.expectEqual(@as(?usize, 2), frameCount(test_out[0..len]));
    try testing.expectEqual(@as(usize, 32), frame(test_out[0..len], 0).?.w);
    try testing.expectEqual(@as(usize, 64), frame(test_out[0..len], 1).?.w);
}

test "derive : tampon trop petit ou fichier sans image utilisable : null, sans débordement" {
    const src = makeCur(&test_src, &.{ 32, 48 }, 1);
    const need = derive(src, .red, &test_out).?;
    try testing.expectEqual(@as(?usize, null), derive(src, .red, test_out[0 .. need - 1]));
    try testing.expectEqual(@as(?usize, null), derive(src, .red, test_out[0..8]));
    try testing.expectEqual(@as(?usize, null), derive(&.{ 0, 0, 2, 0, 1, 0 }, .copy, &test_out));
}

test "derive : palette inversée (index 1 = noir) respectée par le rouge" {
    const src = makeCur(&test_src, &.{32}, 1);
    const off = get32(src, DIR + 12);
    put32(&test_src, off + BIH, 0xFFFFFF); // index 0 : blanc
    put32(&test_src, off + BIH + 4, 0x000000); // index 1 : noir
    const len = derive(src, .red, &test_out).?;
    const px = std.mem.bytesAsSlice(u32, frame(test_out[0..len], 0).?.xor_bits);
    // le contour (bit 1) est maintenant noir -> rouge ; le corps (bit 0) blanc
    try testing.expectEqual(@as(u32, 0xFF000000 | core.RED), px[0]);
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), px[1 * 32 + 1]);
}

test "derive : teinte d'une image 1 bit ou 32 bits, corps et contour aux couleurs demandées" {
    for ([_]u16{ 1, 32 }) |bpp| {
        const src = makeCur(&test_src, &.{ 32, 48 }, bpp);
        const len = derive(src, .{ .tint = .{ .at0 = 0x00205B, .at255 = core.WHITE } }, &test_out).?;
        try testing.expectEqual(@as(?usize, 2), frameCount(test_out[0..len]));
        const f = frame(test_out[0..len], 0).?;
        try testing.expectEqual(@as(u16, 32), f.bpp);
        try testing.expectEqual(@as(u16, 1), f.hot_x);
        try testing.expectEqual(@as(u16, 2), f.hot_y);
        const px = std.mem.bytesAsSlice(u32, f.xor_bits);
        try testing.expectEqual(@as(u32, 0xFFFFFFFF), px[0]); // contour gardé blanc
        try testing.expectEqual(@as(u32, 0xFF00205B), px[1 * 32 + 1]); // corps bleu nuit
        try testing.expectEqual(@as(u32, 0), px[31]); // marge transparente
        // corps clair, contour noir : la version pour les fonds sombres
        const len2 = derive(src, .{ .tint = .{ .at0 = 0xFFE600, .at255 = core.BLACK } }, &test_out).?;
        const px2 = std.mem.bytesAsSlice(u32, frame(test_out[0..len2], 0).?.xor_bits);
        try testing.expectEqual(@as(u32, 0xFF000000), px2[0]);
        try testing.expectEqual(@as(u32, 0xFFFFE600), px2[1 * 32 + 1]);
    }
}

test "derive : teinter le noir en blanc et le blanc en noir revient à inverser une image 32 bits" {
    const src = makeCur(&test_src, &.{ 32, 48 }, 32);
    const a = derive(src, .invert, &test_out).?;
    const b = derive(src, .{ .tint = .{ .at0 = core.WHITE, .at255 = core.BLACK } }, &test_out2).?;
    try testing.expectEqualSlices(u8, test_out[0..a], test_out2[0..b]);
}

test "derive : la même teinte, couleurs échangées, sur l'image inversée donne le même fichier" {
    for ([_]u16{ 1, 32 }) |bpp| {
        const src = makeCur(&test_src, &.{ 32, 48 }, bpp);
        const inv = derive(src, .invert, &test_out).?;
        const a = derive(test_out[0..inv], .{ .tint = .{ .at0 = core.WHITE, .at255 = 0x4B0082 } }, &test_out2).?;
        const b = derive(src, .{ .tint = .{ .at0 = 0x4B0082, .at255 = core.WHITE } }, &test_out).?;
        try testing.expectEqualSlices(u8, test_out[0..b], test_out2[0..a]);
    }
}

test "monoFile : une image 1 bit relue à l'identique, point chaud et palette compris" {
    const s = 40;
    const n = stride(s, 1) * s;
    var xb: [stride(40, 1) * 40]u8 = undefined;
    var ab: [stride(40, 1) * 40]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(3);
    prng.random().bytes(&xb);
    prng.random().bytes(&ab);
    const len = monoFile(&test_out, s, 7, 9, &xb, &ab).?;
    try testing.expectEqual(singleLen(s, 1), len);
    const f = frame(test_out[0..len], 0).?;
    try testing.expectEqual(@as(usize, s), f.w);
    try testing.expectEqual(@as(u16, 1), f.bpp);
    try testing.expectEqual(@as(u16, 7), f.hot_x);
    try testing.expectEqual(@as(u16, 9), f.hot_y);
    try testing.expect(f.one_is_white);
    try testing.expectEqualSlices(u8, &xb, f.xor_bits);
    try testing.expectEqualSlices(u8, &ab, f.and_bits);
    try testing.expectEqual(n, f.xor_bits.len);
    try testing.expectEqual(@as(u8, 2), test_out[DIR + 2]); // 2 couleurs, comme Windows
    // l'inversion (jeu blanc) s'applique telle quelle
    const inv = derive(test_out[0..len], .invert, &test_out2).?;
    const g = frame(test_out2[0..inv], 0).?;
    for (f.xor_bits, g.xor_bits, f.and_bits) |x0, x1, m| try testing.expectEqual(x0 ^ ~m, x1);
}

test "colorFile : une image 32 bits relue à l'identique, masque calculé depuis l'alpha" {
    const s = 33; // largeur impaire : lignes du masque complétées
    var px: [33 * 33]u32 = undefined;
    for (&px, 0..) |*p, i| p.* = if (i % 5 == 0) 0x00123456 else 0xFF000000 | @as(u32, @intCast(i));
    const len = colorFile(&test_out, s, 1, 2, &px).?;
    try testing.expectEqual(singleLen(s, 32), len);
    const f = frame(test_out[0..len], 0).?;
    try testing.expectEqual(@as(u16, 32), f.bpp);
    try testing.expectEqual(@as(u16, 1), f.hot_x);
    try testing.expectEqual(@as(u16, 2), f.hot_y);
    for (px, 0..) |c, i| {
        try testing.expectEqual(c, get32(f.xor_bits, i * 4));
        const bit = core.maskBit(f.and_bits, stride(s, 1), i % s, i / s);
        try testing.expectEqual(@as(u1, @intFromBool(c >> 24 == 0)), bit);
    }
}

test "monoFile / colorFile : tampon trop petit -> null" {
    var xb: [stride(32, 1) * 32]u8 = @splat(0);
    try testing.expectEqual(@as(?usize, null), monoFile(test_out[0..100], 32, 0, 0, &xb, &xb));
    var px: [32 * 32]u32 = @splat(0);
    try testing.expectEqual(@as(?usize, null), colorFile(test_out[0 .. singleLen(32, 32) - 1], 32, 0, 0, &px));
}
