//! Tests d'intégration : vrais fichiers de curseurs de Windows, lecture d'images dessinées
//! en mémoire (texte, frontières, damiers). Ils ne touchent pas au curseur du système.

const std = @import("std");
const app = @import("autocurseur");
const h = @import("helpers.zig");
const core = app.core;
const w = app.win32;
const cursors = app.cursors;
const sampler = app.sampler;
const testing = std.testing;
const L = h.L;

const BOX = 60; // zone lue pour un curseur de 80 px (écran à 250 %)

fn setupSampler() void {
    sampler.init();
    sampler.resize(BOX);
}

// ---------------------------------------------------------------------
// Curseurs
// ---------------------------------------------------------------------

test "les 17 curseurs se chargent dans les deux couleurs, à toutes les tailles" {
    defer cursors.free();
    for ([_]i32{ 32, 48, 64, 80, 96, 128, 256 }) |size| {
        cursors.load(size);
        try testing.expectEqual(size, cursors.size);
        for (cursors.black, cursors.white, 0..) |b, wh, i| {
            errdefer std.debug.print("curseur n°{d} à {d} px\n", .{ i, size });
            try testing.expect(b != null and wh != null);
            const sb = try h.stats(b);
            const sw = try h.stats(wh);
            try testing.expectEqual(size, sb.width);
            try testing.expectEqual(size, sw.width);
            try testing.expect(sb.opaque_px > 0 and sw.opaque_px > 0);
        }
    }
}

test "chaque curseur blanc est l'inverse exact du noir correspondant" {
    defer cursors.free();
    cursors.load(64);
    for (cursors.black, cursors.white, 0..) |b, wh, i| {
        const sb = try h.stats(b);
        const sw = try h.stats(wh);
        // mêmes pixels visibles ; les blancs de l'un sont les noirs de l'autre
        // (tolérance de 2 % pour les pixels d'anticrénelage proches du gris moyen)
        const expected_white = sb.opaque_px - sb.white_px;
        const diff = @max(sw.white_px, expected_white) - @min(sw.white_px, expected_white);
        errdefer std.debug.print("curseur n°{d} : {d} blancs attendus, {d} trouvés sur {d}\n", .{ i, expected_white, sw.white_px, sw.opaque_px });
        try testing.expectEqual(sb.opaque_px, sw.opaque_px);
        try testing.expect(diff * 50 <= sb.opaque_px);
    }
}

test "flèche et main : corps nettement noir dans un jeu, nettement blanc dans l'autre" {
    // (pour les formes fines comme le curseur texte, le contour pèse autant que le corps)
    defer cursors.free();
    cursors.load(64);
    for ([_]usize{ 0, 12 }) |i| {
        try testing.expect((try h.stats(cursors.black[i])).whiteRatio() < 0.45);
        try testing.expect((try h.stats(cursors.white[i])).whiteRatio() > 0.55);
    }
}

test "noir et blanc ont la même forme et le même point chaud" {
    defer cursors.free();
    cursors.load(80);
    for (cursors.black, cursors.white) |b, wh| {
        const sb = try h.stats(b);
        const sw = try h.stats(wh);
        try testing.expectEqual(sb.opaque_px, sw.opaque_px);
        try testing.expectEqual(sb.hot_x, sw.hot_x);
        try testing.expectEqual(sb.hot_y, sw.hot_y);
    }
}

test "contour : la flèche n'a aucun trou aux tailles présentes dans les fichiers de Windows" {
    // Les fichiers « Windows Black » contiennent des images de 32, 48, 64, 96 et 128 px.
    defer cursors.free();
    for ([_]i32{ 32, 48, 64, 96, 128 }) |size| {
        cursors.load(size);
        errdefer std.debug.print("flèche à {d} px\n", .{size});
        try testing.expectEqual(@as(?usize, 0), try h.outlineGaps(cursors.black[0], false));
        try testing.expectEqual(@as(?usize, 0), try h.outlineGaps(cursors.white[0], true));
    }
}

test "contour : la version blanche a exactement le même contour que la noire" {
    // (certains fichiers de Windows ont des trous d'origine, comme le « ? » du curseur
    // d'aide en 32 px : l'inversion doit les reproduire à l'identique, sans en ajouter)
    defer cursors.free();
    for ([_]i32{ 32, 48, 64, 80, 96, 128 }) |size| {
        cursors.load(size);
        for (cursors.black, cursors.white, 0..) |b, wh, i| {
            const gb = (try h.outlineGaps(b, false)) orelse continue;
            const gw = (try h.outlineGaps(wh, true)) orelse continue;
            errdefer std.debug.print("curseur n°{d} à {d} px : {d} trous (noir), {d} (blanc)\n", .{ i, size, gb, gw });
            try testing.expectEqual(gb, gw);
        }
    }
}

test "diagnostic : à une taille absente des fichiers (80 px), Windows abîme le contour" {
    // Ce test documente pourquoi la taille doit être celle de Windows : redimensionner
    // une image monochrome casse son contour d'un pixel.
    defer cursors.free();
    cursors.load(80);
    const gaps = (try h.outlineGaps(cursors.black[0], false)).?;
    std.debug.print("  flèche à 80 px : {d} trous dans le contour\n", .{gaps});
    try testing.expect(gaps > 0);
}

test "inverser deux fois redonne exactement le curseur d'origine" {
    defer cursors.free();
    cursors.load(48);
    for (cursors.black) |b| {
        const once = cursors.invert(b) orelse return error.Invert;
        defer _ = w.DestroyCursor(once);
        const twice = cursors.invert(once) orelse return error.Invert;
        defer _ = w.DestroyCursor(twice);
        try testing.expect((try h.stats(b)).sameImage(try h.stats(twice)));
    }
}

test "inverser ne modifie pas le curseur source" {
    defer cursors.free();
    cursors.load(48);
    const before = try h.stats(cursors.black[0]);
    const inv = cursors.invert(cursors.black[0]) orelse return error.Invert;
    defer _ = w.DestroyCursor(inv);
    try testing.expect(before.sameImage(try h.stats(cursors.black[0])));
}

test "recharger plusieurs fois ne perd rien (pas de fuite visible de curseurs)" {
    defer cursors.free();
    var i: u32 = 0;
    while (i < 30) : (i += 1) cursors.load(if (i % 2 == 0) 32 else 80);
    for (cursors.black, cursors.white) |b, wh| try testing.expect(b != null and wh != null);
}

test "la taille choisie est exactement celle des curseurs de Windows" {
    h.dpiAware();
    const s = cursors.systemSize();
    try testing.expect(s >= 16 and s <= core.MAX_CUR);
    try testing.expectEqual(cursors.currentArrowWidth(), s);
    // et Windows annonce la même taille standard (au réglage de taille par défaut)
    std.debug.print("  taille des curseurs : {d} px (taille standard annoncée : {d} px)\n", .{ s, w.GetSystemMetrics(w.SM_CXCURSOR) });
}

test "l'icône de notification est créée, avec transparence et deux tons" {
    for ([_]bool{ true, false }) |on| {
        const ico = app.icon.create(on) orelse return error.Icon;
        defer _ = w.DestroyIcon(ico);
        const s = try h.stats(ico);
        try testing.expect(s.opaque_px > 0);
        try testing.expect(s.white_px > 0 and s.white_px < s.opaque_px);
    }
}

// ---------------------------------------------------------------------
// Lecture d'images et décision
// ---------------------------------------------------------------------

/// Parcourt `canvas` en déplaçant la zone lue par pas de `step` pixels et renvoie
/// la couleur finale, le nombre de bascules et la luminance min / max rencontrées.
const Scan = struct { shade: core.Shade, switches: u32, min_l: u32, max_l: u32 };

fn scan(c: *h.Canvas, start: core.Shade, step: i32) !Scan {
    var r: Scan = .{ .shade = start, .switches = 0, .min_l = 255, .max_l = 0 };
    var y: i32 = 0;
    while (y + BOX <= c.height) : (y += step) {
        var x: i32 = 0;
        while (x + BOX <= c.width) : (x += step) {
            const l = sampler.sampleFrom(c.dc, .{ .x = x, .y = y }) orelse return error.Sample;
            r.min_l = @min(r.min_l, l);
            r.max_l = @max(r.max_l, l);
            const n = core.decide(r.shade, l, .{});
            if (r.shade != .unknown and n != r.shade) r.switches += 1;
            r.shade = n;
        }
    }
    return r;
}

test "fond blanc uni : curseur noir ; fond noir uni : curseur blanc" {
    setupSampler();
    var c = try h.Canvas.init(200, 200);
    defer c.deinit();
    c.fill(0xFFFFFF);
    try testing.expectEqual(@as(?u32, 255), sampler.sampleFrom(c.dc, .{ .x = 50, .y = 50 }));
    try testing.expectEqual(core.Shade.black, core.decide(.unknown, 255, .{}));
    c.fill(0x000000);
    try testing.expectEqual(@as(?u32, 0), sampler.sampleFrom(c.dc, .{ .x = 50, .y = 50 }));
}

test "la luminance lue correspond à la couleur de fond (dégradé de gris)" {
    setupSampler();
    var c = try h.Canvas.init(100, 100);
    defer c.deinit();
    var v: u32 = 0;
    while (v <= 255) : (v += 15) {
        c.fill((v << 16) | (v << 8) | v);
        const l = sampler.sampleFrom(c.dc, .{ .x = 10, .y = 10 }) orelse return error.Sample;
        try testing.expect(@abs(@as(i32, @intCast(l)) - @as(i32, @intCast(v))) <= 1);
    }
}

const lorem = blk: {
    @setEvalBranchQuota(100_000); // conversion UTF-16 des phrases à la compilation
    break :blk [_][]const u16{
        L("Le curseur doit rester visible sur une page de texte ordinaire,"),
        L("qu'il s'agisse d'un article, d'un courriel ou d'un document."),
        L("AutoCurseur lit une petite zone sous la souris et fait la moyenne."),
        L("Les lettres n'occupent qu'une petite partie de cette zone : le fond l'emporte."),
    };
};

test "texte noir sur page blanche : le curseur reste noir partout, sans bascule" {
    setupSampler();
    var c = try h.Canvas.init(900, 420);
    defer c.deinit();
    c.fill(0xFFFFFF);
    var y: i32 = 10;
    for ([_]i32{ 14, 16, 20, 28 }, [_]bool{ false, false, false, true }) |size, bold| {
        for (lorem) |line| {
            c.text(10, y, line, size, bold, 0x000000);
            y += size + 6;
        }
    }
    const r = try scan(&c, .unknown, 7);
    std.debug.print("  texte noir sur blanc : luminance de {d} à {d}\n", .{ r.min_l, r.max_l });
    try testing.expectEqual(core.Shade.black, r.shade);
    try testing.expectEqual(@as(u32, 0), r.switches);
    try testing.expect(r.min_l > 105);
}

test "titre très gras en noir sur blanc : toujours noir" {
    setupSampler();
    var c = try h.Canvas.init(900, 200);
    defer c.deinit();
    c.fill(0xFFFFFF);
    c.text(10, 20, L("GROS TITRE EN GRAS"), 64, true, 0x000000);
    const r = try scan(&c, .unknown, 5);
    std.debug.print("  gros titre gras : luminance de {d} à {d}\n", .{ r.min_l, r.max_l });
    try testing.expectEqual(core.Shade.black, r.shade);
    try testing.expectEqual(@as(u32, 0), r.switches);
}

test "éditeur de code sombre (texte clair et coloré) : le curseur reste blanc partout" {
    setupSampler();
    var c = try h.Canvas.init(900, 420);
    defer c.deinit();
    c.fill(0x1E1E1E);
    const lines = comptime blk: {
        @setEvalBranchQuota(100_000);
        break :blk [_][]const u16{
            L("const std = @import(\"std\");"),
            L("pub fn main() void {"),
            L("    const message = \"Bonjour\"; // commentaire"),
            L("    std.debug.print(\"{s}\\n\", .{message});"),
            L("}"),
        };
    };
    const colors = [_]u32{ 0xD4D4D4, 0x569CD6, 0xCE9178, 0x6A9955, 0xDCDCAA };
    var y: i32 = 10;
    var k: usize = 0;
    while (y < 400) : (y += 22) {
        c.text(10, y, lines[k % lines.len], 16, false, colors[k % colors.len]);
        k += 1;
    }
    const r = try scan(&c, .unknown, 7);
    std.debug.print("  éditeur sombre : luminance de {d} à {d}\n", .{ r.min_l, r.max_l });
    try testing.expectEqual(core.Shade.white, r.shade);
    try testing.expectEqual(@as(u32, 0), r.switches);
    try testing.expect(r.max_l < 150);
}

test "frontière blanc | noir parcourue pixel par pixel : une seule bascule dans chaque sens" {
    setupSampler();
    var c = try h.Canvas.init(400, 100);
    defer c.deinit();
    c.fill(0xFFFFFF);
    c.rect(200, 0, 200, 100, 0x000000);
    var shade: core.Shade = .unknown;
    var switches: u32 = 0;
    var x: i32 = 0;
    while (x <= 400 - BOX) : (x += 1) { // aller : du blanc vers le noir
        const n = core.decide(shade, sampler.sampleFrom(c.dc, .{ .x = x, .y = 20 }).?, .{});
        if (shade != .unknown and n != shade) switches += 1;
        shade = n;
    }
    try testing.expectEqual(core.Shade.white, shade);
    try testing.expectEqual(@as(u32, 1), switches);
    while (x > 0) { // retour
        x -= 1;
        const n = core.decide(shade, sampler.sampleFrom(c.dc, .{ .x = x, .y = 20 }).?, .{});
        if (n != shade) switches += 1;
        shade = n;
    }
    try testing.expectEqual(core.Shade.black, shade);
    try testing.expectEqual(@as(u32, 2), switches);
}

test "damier fin noir et blanc : aucune bascule, quel que soit l'état de départ" {
    setupSampler();
    var c = try h.Canvas.init(300, 300);
    defer c.deinit();
    var yy: i32 = 0;
    while (yy < 300) : (yy += 1) {
        var xx: i32 = 0;
        while (xx < 300) : (xx += 1) {
            c.px[@intCast(yy * 300 + xx)] = if (@mod(@divTrunc(xx, 2) + @divTrunc(yy, 2), 2) == 0) 0xFFFFFF else 0;
        }
    }
    for ([_]core.Shade{ .white, .black }) |start| {
        const r = try scan(&c, start, 3);
        try testing.expectEqual(start, r.shade);
        try testing.expectEqual(@as(u32, 0), r.switches);
    }
}

test "fond gris moyen : la couleur actuelle est gardée" {
    setupSampler();
    var c = try h.Canvas.init(200, 200);
    defer c.deinit();
    c.fill(0x808080);
    for ([_]core.Shade{ .white, .black }) |start| {
        const r = try scan(&c, start, 10);
        try testing.expectEqual(start, r.shade);
        try testing.expectEqual(@as(u32, 0), r.switches);
    }
}

test "image colorée vive : rouge et bleu foncés -> blanc, jaune et cyan -> noir" {
    setupSampler();
    var c = try h.Canvas.init(100, 100);
    defer c.deinit();
    const cases = [_]struct { rgb: u32, want: core.Shade }{
        .{ .rgb = 0xC00000, .want = .white },
        .{ .rgb = 0x0000C0, .want = .white },
        .{ .rgb = 0xFFFF00, .want = .black },
        .{ .rgb = 0x00FFFF, .want = .black },
    };
    for (cases) |case| {
        c.fill(case.rgb);
        const l = sampler.sampleFrom(c.dc, .{ .x = 10, .y = 10 }).?;
        try testing.expectEqual(case.want, core.decide(.unknown, l, .{}));
    }
}

test "lecture de l'écran réel : renvoie une luminance valide sous la souris" {
    setupSampler();
    var p: core.Point = .{};
    _ = w.GetCursorPos(&p);
    // null si l'écran n'est pas lisible (session verrouillée) : accepté
    if (sampler.sampleScreen(p)) |l| try testing.expect(l <= 255);
}

test "redimensionner la zone lue plusieurs fois reste cohérent" {
    sampler.init();
    var c = try h.Canvas.init(200, 200);
    defer c.deinit();
    c.fill(0xFFFFFF);
    for ([_]i32{ 16, 24, 60, 96, 200, 32 }) |side| {
        sampler.resize(side);
        try testing.expect(sampler.box <= core.BOX_MAX);
        try testing.expectEqual(@as(?u32, 255), sampler.sampleFrom(c.dc, .{ .x = 0, .y = 0 }));
    }
}
