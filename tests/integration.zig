//! Tests d'intégration : vrais fichiers de curseurs de Windows, lecture d'images dessinées
//! en mémoire (texte, frontières, damiers). Ils ne touchent pas au curseur du système.

const std = @import("std");
const app = @import("autocurseur");
const h = @import("helpers.zig");
const core = app.core;
const w = app.win32;
const cursors = app.cursors;
const curfile = app.curfile;
const sampler = app.sampler;
const testing = std.testing;
const L = h.L;

const BOX = 60; // zone lue pour un curseur de 80 px (écran à 250 %)

/// Pour les tests qui vérifient les images au pixel près : prévus pour la taille 1 du pointeur
/// (agrandi dans les Paramètres, Windows charge les images de curseur autrement).
fn skipIfEnlarged() !void {
    if (cursors.pointerBase() > 32) {
        std.debug.print("  pointeur agrandi dans les Paramètres : test prévu pour la taille 1, ignoré\n", .{});
        return error.SkipZigTest;
    }
}

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
        // mêmes pixels visibles ; parmi les gris, les blancs de l'un sont les noirs de l'autre
        // (les parties colorées, comme le rouge de « indisponible », sont gardées ; tolérance de
        // 2 % pour les pixels d'anticrénelage proches du gris moyen)
        const expected_white = sb.gray_px - sb.gray_white_px;
        const diff = @max(sw.gray_white_px, expected_white) - @min(sw.gray_white_px, expected_white);
        errdefer std.debug.print("curseur n°{d} : {d} blancs attendus, {d} trouvés sur {d} gris\n", .{ i, expected_white, sw.gray_white_px, sw.gray_px });
        try testing.expectEqual(sb.opaque_px, sw.opaque_px);
        try testing.expectEqual(sb.gray_px, sw.gray_px);
        try testing.expect(diff * 50 <= sb.gray_px);
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
    // Les fichiers de Windows contiennent des images de 32, 48, 64, 96 et 128 px. La flèche
    // vient du style blanc (bords adoucis) : son corps ne touche jamais un pixel transparent.
    defer cursors.free();
    for ([_]i32{ 32, 48, 64, 96, 128 }) |size| {
        cursors.load(size);
        errdefer std.debug.print("flèche à {d} px\n", .{size});
        try testing.expectEqual(@as(?usize, 0), try h.outlineGaps(cursors.black[0], false));
        try testing.expectEqual(@as(?usize, 0), try h.outlineGaps(cursors.white[0], true));
    }
}

test "contour : aux tailles des fichiers, la version blanche a exactement le même contour que la noire" {
    // (certains fichiers de Windows ont des trous d'origine, comme le « ? » du curseur
    // d'aide en 32 px : l'inversion doit les reproduire à l'identique, sans en ajouter).
    // À une taille absente des fichiers, chaque fichier est étiré séparément par Windows,
    // et cet étirement n'est pas symétrique entre noir et blanc : pas de comparaison.
    defer cursors.free();
    for ([_]i32{ 32, 48, 64, 96, 128 }) |size| {
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
    // une image monochrome casse son contour d'un pixel (ici, les curseurs « Windows Black »).
    defer cursors.free();
    cursors.load(80);
    var total: usize = 0;
    for (cursors.black, 0..) |b, i| {
        if (!(try h.stats(b)).mono) continue;
        const gaps = (try h.outlineGaps(b, false)).?;
        std.debug.print("  curseur {d} (1 bit) à 80 px : {d} trous dans le contour\n", .{ cursors.defs[i].id, gaps });
        total += gaps;
    }
    try testing.expect(total > 0);
}

// ---------------------------------------------------------------------
// Fichiers .cur fabriqués
// ---------------------------------------------------------------------

/// Contenu du fichier de Windows du curseur `i` (à libérer avec testing.allocator).
fn windowsFile(i: usize) ![]u8 {
    var buf: [2 * w.MAX_PATH]u16 = undefined;
    var wd: [w.MAX_PATH]u16 = undefined;
    const n = w.GetWindowsDirectoryW(&wd, wd.len);
    const path = core.join(&buf, &.{ wd[0..n], L("\\Cursors\\"), cursors.defs[i].file });
    return h.readFile(path.ptr);
}

fn frameSizes(file: []const u8, out: []usize) []usize {
    const n = curfile.frameCount(file) orelse return out[0..0];
    var k: usize = 0;
    for (0..n) |i| {
        if (curfile.frame(file, i)) |f| {
            out[k] = f.w;
            k += 1;
        }
    }
    std.mem.sort(usize, out[0..k], {}, std.sort.asc(usize));
    return out[0..k];
}

test "fichiers de Windows : versions inversée et rouge avec toutes les tailles, de 32 à 128 px" {
    for (0..cursors.COUNT) |i| {
        const src = try windowsFile(i);
        defer testing.allocator.free(src);
        var a: [16]usize = undefined;
        const sizes = frameSizes(src, &a);
        try testing.expect(std.mem.indexOfScalar(usize, sizes, 32) != null);
        try testing.expect(std.mem.indexOfScalar(usize, sizes, 128) != null);
        for ([_]curfile.Op{ .invert, .red, .invert_red }) |op| {
            const len = curfile.derive(src, op, &cursors.out_buf) orelse return error.Derive;
            var b: [16]usize = undefined;
            try testing.expectEqualSlices(usize, sizes, frameSizes(cursors.out_buf[0..len], &b));
            try testing.expect(len <= cursors.out_buf.len);
        }
    }
}

test "fichiers de Windows : inverser deux fois redonne exactement les images d'origine" {
    const copy = try testing.allocator.alignedAlloc(u8, .@"4", cursors.out_buf.len);
    defer testing.allocator.free(copy);
    const once = try testing.allocator.alignedAlloc(u8, .@"4", cursors.out_buf.len);
    defer testing.allocator.free(once);
    for (0..cursors.COUNT) |i| {
        const src = try windowsFile(i);
        defer testing.allocator.free(src);
        const c = curfile.derive(src, .copy, copy).?;
        const o = curfile.derive(src, .invert, once).?;
        const t = curfile.derive(once[0..o], .invert, &cursors.out_buf).?;
        try testing.expectEqualSlices(u8, copy[0..c], cursors.out_buf[0..t]);
    }
}

extern "kernel32" fn RemoveDirectoryW([*:0]const u16) callconv(.winapi) w.BOOL;

test "fichiers fabriqués : écrits une fois, pas réécrits s'ils sont à jour, réécrits s'ils sont abîmés" {
    var name_buf: [64]u16 = undefined;
    var num: [16]u8 = undefined;
    const tag = try std.fmt.bufPrint(&num, "{d}", .{w.GetTickCount()});
    var n: usize = 0;
    for (L("AutoCurseur-tests\\")) |c| {
        name_buf[n] = c;
        n += 1;
    }
    for (tag) |c| {
        name_buf[n] = c;
        n += 1;
    }
    try testing.expect(cursors.setDir(L("TEMP"), name_buf[0..n]));
    defer {
        // ménage : fichiers puis dossier, et retour au dossier de l'application
        var p: [2 * w.MAX_PATH]u16 = undefined;
        for (0..cursors.COUNT) |i| {
            for ([_]cursors.Set{ .black, .white, .red }) |set| {
                if (cursors.pathOf(set, i, &p)) |path| {
                    if (std.mem.startsWith(u16, path, cursors.dirPath())) _ = w.DeleteFileW(path.ptr);
                }
            }
        }
        var d: [w.MAX_PATH]u16 = undefined;
        const dp = cursors.dirPath();
        @memcpy(d[0..dp.len], dp);
        d[dp.len] = 0;
        _ = RemoveDirectoryW(@ptrCast(&d));
        _ = cursors.useDefaultDir();
    }

    // fichier laissé par une version précédente (flèche « Windows Black » inversée)
    var old_buf: [2 * w.MAX_PATH]u16 = undefined;
    const old = core.join(&old_buf, &.{ cursors.dirPath(), L("blanc-arrow_r.cur") });
    const oh = w.CreateFileW(old.ptr, w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    try testing.expect(oh != w.INVALID_HANDLE_VALUE);
    _ = w.CloseHandle(oh);

    // 17 versions inversées (noires pour le style blanc, blanches pour « Windows Black ») + 17 rouges
    try testing.expectEqual(@as(usize, 2 * cursors.COUNT), cursors.prepare(true));
    // l'ancien fichier a été supprimé avec l'écriture des nouveaux
    try testing.expectEqual(w.INVALID_FILE_ATTRIBUTES, w.GetFileAttributesW(old.ptr));
    try testing.expectEqual(@as(usize, 0), cursors.prepare(true));
    for (0..cursors.COUNT) |i| {
        var p: [2 * w.MAX_PATH]u16 = undefined;
        try testing.expect(cursors.pathOf(.white, i, &p) != null);
        try testing.expect(cursors.pathOf(.red, i, &p) != null);
    }

    // un fichier abîmé (tronqué) est réécrit, et seulement lui : celui fabriqué pour la flèche,
    // jamais le fichier de Windows
    var p: [2 * w.MAX_PATH]u16 = undefined;
    const made: cursors.Set = if (cursors.defs[0].file_is_white) .black else .white;
    const arrow_made = cursors.pathOf(made, 0, &p).?;
    try testing.expect(std.mem.startsWith(u16, arrow_made, cursors.dirPath()));
    const fh = w.CreateFileW(arrow_made.ptr, w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    try testing.expect(fh != w.INVALID_HANDLE_VALUE);
    _ = w.CloseHandle(fh);
    try testing.expectEqual(@as(usize, 1), cursors.prepare(true));

    // les curseurs se chargent depuis ces fichiers, à toutes les tailles
    for ([_]i32{ 32, 48, 64, 96, 128 }) |px| {
        const c = cursors.loadOne(made, 0, px) orelse return error.Chargement;
        defer _ = w.DestroyCursor(c);
        try testing.expectEqual(px, (try h.stats(c)).width);
    }
}

test "fichiers fabriqués : à chaque taille native, l'image blanche 1 bit est l'inverse exact de la noire" {
    defer cursors.free();
    for ([_]i32{ 32, 48, 64, 96, 128 }) |px| {
        cursors.load(px);
        for (cursors.black, cursors.white) |b, wh| {
            const sb = try h.stats(b.?);
            const sw = try h.stats(wh.?);
            if (!sb.mono) continue; // mains en 32 bits : voir le test de l'inverse exact plus haut
            try testing.expectEqual(sb.width, px);
            try testing.expectEqual(sb.opaque_px, sw.opaque_px);
            try testing.expectEqual(sb.white_px, sw.opaque_px - sw.white_px);
        }
    }
}

test "recharger plusieurs fois ne perd rien (pas de fuite visible de curseurs)" {
    defer cursors.free();
    var i: u32 = 0;
    while (i < 30) : (i += 1) cursors.load(if (i % 2 == 0) 32 else 80);
    for (cursors.black, cursors.white) |b, wh| try testing.expect(b != null and wh != null);
}

test "curseur affiché : chaque curseur du système est reconnu à sa poignée, les autres non" {
    for (cursors.defs, 0..) |d, i| {
        try testing.expectEqual(@as(?usize, i), cursors.indexOf(w.LoadCursorW(null, @ptrFromInt(d.id))));
    }
    // un curseur chargé par un programme (même depuis un fichier de Windows) n'en est pas un
    defer cursors.free();
    cursors.load(32);
    for (cursors.black) |c| try testing.expectEqual(@as(?usize, null), cursors.indexOf(c));
    try testing.expectEqual(@as(?usize, null), cursors.indexOf(null));
}

test "curseur affiché : sans couleur voulue, fix et forget ne touchent à rien" {
    try testing.expectEqual(@as(?cursors.Set, null), cursors.wanted);
    cursors.fix(); // ne doit rien installer
    for (cursors.installed) |s| try testing.expectEqual(@as(?cursors.Set, null), s);
    cursors.forget();
    for (cursors.installed) |s| try testing.expectEqual(@as(?cursors.Set, null), s);
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
        const ico = app.icon.create(on, .{}) orelse return error.Icon;
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

// ---------------------------------------------------------------------
// Jeu rouge agrandi (secouer pour retrouver)
// ---------------------------------------------------------------------

test "jeu rouge : les 17 curseurs, deux fois plus grands, avec du rouge, à plusieurs tailles" {
    try skipIfEnlarged();
    h.dpiAware();
    defer cursors.freeRed();
    for ([_]i32{ 32, 48, 64, 96, 128 }) |px| {
        cursors.loadRed(px);
        for (cursors.red, 0..) |c, i| {
            const cur = c orelse {
                std.debug.print("  curseur rouge manquant : n° {d} à {d} px\n", .{ i, px });
                return error.CurseurManquant;
            };
            const s = try h.redStats(cur);
            try testing.expectEqual(core.bigSize(px), s.width);
            try testing.expect(s.red_px > 0);
            try testing.expect(s.opaque_px > s.red_px); // il reste un contour
        }
    }
}

test "jeu rouge : la flèche est la noire agrandie, corps rouge, contour blanc sans trou" {
    try skipIfEnlarged();
    h.dpiAware();
    defer cursors.free();
    defer cursors.freeRed();
    for ([_]i32{ 32, 48, 64 }) |px| {
        cursors.loadRed(px);
        cursors.load(core.bigSize(px)); // version noire chargée directement à la grande taille
        const r = try h.redStats(cursors.red[0].?);
        const b = try h.stats(cursors.black[0].?);
        try testing.expectEqual(b.width, r.width);
        try testing.expectEqual(b.hot_x, r.hot_x);
        try testing.expectEqual(b.hot_y, r.hot_y);
        try testing.expectEqual(b.opaque_px, r.opaque_px); // même dessin
        // le noir, et lui seul, devient rouge (les pixels gris foncés des bords adoucis
        // deviennent d'un rouge plus pâle : 10 % de tolérance ; 93 % mesurés à 48 px)
        const dark = b.opaque_px - b.white_px;
        errdefer std.debug.print("  à {d} px : {d} pixels noirs, {d} rouges\n", .{ px, dark, r.red_px });
        try testing.expect(r.red_px <= dark and r.red_px * 100 >= dark * 90);
        try testing.expectEqual(@as(usize, 0), r.gaps);
    }
}

test "jeu rouge : le point chaud suit l'agrandissement" {
    h.dpiAware();
    defer cursors.free();
    defer cursors.freeRed();
    cursors.load(32);
    cursors.loadRed(32);
    const n = try h.stats(cursors.black[0].?);
    const r = try h.redStats(cursors.red[0].?);
    try testing.expect(@abs(@as(i64, r.hot_x) - 2 * @as(i64, n.hot_x)) <= 1);
    try testing.expect(@abs(@as(i64, r.hot_y) - 2 * @as(i64, n.hot_y)) <= 1);
}

test "jeu rouge : la main (curseur couleur avec transparence) devient rouge" {
    h.dpiAware();
    defer cursors.freeRed();
    cursors.loadRed(32);
    const hand = for (cursors.defs, 0..) |d, i| {
        if (d.id == 32649) break cursors.red[i].?;
    } else return error.MainIntrouvable;
    const s = try h.redStats(hand);
    try testing.expect(s.red_px * 3 > s.opaque_px); // corps en bonne partie rouge
    try testing.expect(s.opaque_px < @as(usize, @intCast(s.width * s.width)) / 2); // fond transparent
}

test "jeu rouge : charger et libérer 20 fois ne fait fuir aucun objet Windows" {
    h.dpiAware();
    cursors.loadRed(48);
    cursors.freeRed();
    const before = h.guiObjects();
    for (0..20) |_| cursors.loadRed(48);
    cursors.freeRed();
    try testing.expectEqual(before, h.guiObjects());
    for (cursors.red) |c| try testing.expect(c == null);
}

test "jeux noir et blanc : charger et libérer 20 fois ne fait fuir aucun objet Windows" {
    h.dpiAware();
    cursors.load(48);
    cursors.free();
    const before = h.guiObjects();
    for (0..20) |_| cursors.load(48);
    cursors.free();
    try testing.expectEqual(before, h.guiObjects());
}

// ---------------------------------------------------------------------
// Curseurs dessinés à partir des dessins vectoriels de Windows 11 (pointeur agrandi)
// ---------------------------------------------------------------------

const svgcur = app.svgcur;

fn skipWithoutVectorShapes() !void {
    if (!cursors.hasVectorShapes()) {
        std.debug.print("  pas de dessins vectoriels de curseurs (Windows 10 ?) : test ignoré\n", .{});
        return error.SkipZigTest;
    }
}

/// Contenu du fichier vectoriel du jeu `set` pour le curseur `i` (à libérer).
fn vectorFile(set: cursors.Set, i: usize) ![]u8 {
    var buf: [2 * w.MAX_PATH]u16 = undefined;
    const was = cursors.usingVector();
    cursors.useVector(true);
    defer cursors.useVector(was);
    const path = cursors.pathOf(set, i, &buf) orelse return error.FichierAbsent;
    return h.readFile(path.ptr);
}

/// Pixel (x, y) visible (de haut en bas) dans l'image `f` d'un fichier de curseur.
fn visibleAt(f: curfile.Frame, x: usize, y: usize) bool {
    const row = f.h - 1 - y; // lignes de bas en haut
    const ms = curfile.stride(f.w, 1);
    if (f.bpp == 32) return std.mem.readInt(u32, f.xor_bits[(row * f.w + x) * 4 ..][0..4], .little) >> 24 != 0;
    const a = core.maskBit(f.and_bits, ms, x, row);
    const c = core.maskBit(f.xor_bits, ms, x, row);
    return !(a == 1 and c == 0);
}

test "dessins vectoriels : les 17 curseurs noirs, blancs et rouges, en 240 x 240" {
    try skipWithoutVectorShapes();
    _ = cursors.prepareVector(true);
    try testing.expect(cursors.vectorReady());
    for (0..cursors.COUNT) |i| {
        for ([_]cursors.Set{ .black, .white, .red }) |set| {
            const file = try vectorFile(set, i);
            defer testing.allocator.free(file);
            try testing.expectEqual(@as(?usize, 1), curfile.frameCount(file));
            const f = curfile.frame(file, 0) orelse return error.ImageIllisible;
            try testing.expectEqual(@as(usize, svgcur.SIZE), f.w);
            try testing.expectEqual(@as(u16, if (set == .red) 32 else 1), f.bpp);
            try testing.expectEqual(svgcur.shapes[i].hot_x, f.hot_x);
            try testing.expectEqual(svgcur.shapes[i].hot_y, f.hot_y);
        }
    }
}

test "dessins vectoriels : même forme et mêmes points chauds que les curseurs agrandis de Windows" {
    try skipWithoutVectorShapes();
    _ = cursors.prepareVector(false);
    var env: [w.MAX_PATH]u16 = undefined;
    const n = w.GetEnvironmentVariableW(L("LOCALAPPDATA"), &env, env.len);
    var compared: usize = 0;
    for (svgcur.shapes, 0..) |sh, i| {
        var pbuf: [2 * w.MAX_PATH]u16 = undefined;
        const p = core.join(&pbuf, &.{ env[0..n], L("\\Microsoft\\Windows\\Cursors\\"), sh.name, L("_eoa.cur") });
        const theirs = h.readFile(p.ptr) catch continue; // Windows ne les écrit qu'après un réglage
        defer testing.allocator.free(theirs);
        const ours = try vectorFile(.black, i);
        defer testing.allocator.free(ours);
        const a = curfile.frame(theirs, 0) orelse continue;
        const b = curfile.frame(ours, 0).?;
        if (a.w != b.w) continue;
        var visible: usize = 0;
        var diff: usize = 0;
        for (0..a.w) |y| {
            for (0..a.w) |x| {
                const va = visibleAt(a, x, y);
                if (va) visible += 1;
                if (va != visibleAt(b, x, y)) diff += 1;
            }
        }
        std.debug.print("  {f} : {d} pixels de différence sur {d}, point chaud {d},{d} (Windows {d},{d})\n", .{
            std.unicode.fmtUtf16Le(sh.name), diff, visible, b.hot_x, b.hot_y, a.hot_x, a.hot_y,
        });
        try testing.expectEqual(a.hot_x, b.hot_x);
        try testing.expectEqual(a.hot_y, b.hot_y);
        try testing.expect(diff * 100 <= visible * 2); // moins de 2 % : bords seulement
        compared += 1;
    }
    if (compared == 0) {
        std.debug.print("  aucun curseur agrandi de Windows à comparer : test ignoré\n", .{});
        return error.SkipZigTest;
    }
}

test "dessins vectoriels : le blanc est l'inverse exact du noir" {
    try skipWithoutVectorShapes();
    _ = cursors.prepareVector(false);
    for (0..cursors.COUNT) |i| {
        const black = try vectorFile(.black, i);
        defer testing.allocator.free(black);
        const white = try vectorFile(.white, i);
        defer testing.allocator.free(white);
        const b = curfile.frame(black, 0).?;
        const wh = curfile.frame(white, 0).?;
        try testing.expectEqualSlices(u8, b.and_bits, wh.and_bits);
        for (b.xor_bits, wh.xor_bits, b.and_bits) |x0, x1, m| try testing.expectEqual(x0 ^ ~m, x1);
    }
}

test "dessins vectoriels : le rouge a le corps rouge, le contour blanc et des bords adoucis" {
    try skipWithoutVectorShapes();
    _ = cursors.prepareVector(true);
    const file = try vectorFile(.red, 0);
    defer testing.allocator.free(file);
    const f = curfile.frame(file, 0).?;
    var red: usize = 0;
    var white: usize = 0;
    var soft: usize = 0;
    for (0..f.w * f.h) |k| {
        const c = std.mem.readInt(u32, f.xor_bits[k * 4 ..][0..4], .little);
        const a = c >> 24;
        if (a == 0) continue;
        if (a < 255) soft += 1;
        if (c & 0xFFFFFF == core.RED) red += 1;
        if (c & 0xFFFFFF == 0xFFFFFF) white += 1;
    }
    try testing.expect(red > white); // la flèche : corps plus grand que son contour
    try testing.expect(white > 0);
    try testing.expect(soft > 0);
}

test "dessins vectoriels : les curseurs se chargent à toutes les tailles depuis leur image de 240" {
    try skipWithoutVectorShapes();
    _ = cursors.prepareVector(true);
    cursors.useVector(true);
    defer cursors.useVector(false);
    h.dpiAware();
    for ([_]i32{ 48, 120, 240 }) |px| {
        const c = cursors.loadOne(.black, 0, px) orelse return error.Chargement;
        defer _ = w.DestroyCursor(c);
        try testing.expectEqual(px, (try h.stats(c)).width);
        const r = cursors.loadOne(.red, 0, px) orelse return error.Chargement;
        defer _ = w.DestroyCursor(r);
        try testing.expect((try h.redStats(r)).red_px > 0);
    }
}

test "dessins vectoriels : déjà prêts, rien n'est réécrit, et Direct2D est déchargé ensuite" {
    try skipWithoutVectorShapes();
    _ = cursors.prepareVector(true);
    try testing.expect(cursors.useDefaultDir()); // oublie l'état : tout est revérifié
    try testing.expectEqual(@as(usize, 0), cursors.prepareVector(true));
    try testing.expect(w.GetModuleHandleW(L("d2d1.dll")) == null);
}

// ---------------------------------------------------------------------
// Fil de lecture de l'écran
// ---------------------------------------------------------------------

const WM_TEST_SAMPLE = w.WM_APP + 7;
extern "user32" fn PeekMessageW(*w.MSG, w.HWND, u32, u32, u32) callconv(.winapi) w.BOOL;
const PM_REMOVE = 1;

/// Fenêtre « message seulement » qui reçoit les résultats du fil de lecture.
fn messageWindow() !w.HWND {
    const hi = w.GetModuleHandleW(null);
    const wc: w.WNDCLASSW = .{ .lpfnWndProc = w.DefWindowProcW, .hInstance = hi, .lpszClassName = L("AutoCurseurTestLecture") };
    _ = w.RegisterClassW(&wc);
    const HWND_MESSAGE: w.HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -3))));
    return w.CreateWindowExW(0, L("AutoCurseurTestLecture"), L(""), 0, 0, 0, 0, 0, HWND_MESSAGE, null, hi, null) orelse error.Fenetre;
}

/// Résultats reçus pendant `ms` millisecondes (on s'arrête au premier si `first`).
fn collect(hwnd: w.HWND, ms: u32, first: bool, out: *std.ArrayList(usize)) !void {
    const t0 = w.GetTickCount();
    while (w.GetTickCount() -% t0 < ms) {
        var m: w.MSG = undefined;
        while (PeekMessageW(&m, hwnd, WM_TEST_SAMPLE, WM_TEST_SAMPLE, PM_REMOVE) != 0) {
            try out.append(testing.allocator, m.wParam);
            if (first) return;
        }
        w.Sleep(5);
    }
}

test "fil de lecture : répond, ne garde que la dernière demande, s'arrête proprement" {
    h.dpiAware();
    sampler.deinit(); // le fil crée lui-même son DC de travail
    const hwnd = try messageWindow();
    defer _ = w.DestroyWindow(hwnd);
    try testing.expect(sampler.startWorker(hwnd, WM_TEST_SAMPLE));
    var got: std.ArrayList(usize) = .empty;
    defer got.deinit(testing.allocator);

    // une demande : une réponse, une luminance valide
    var p: core.Point = .{};
    _ = w.GetCursorPos(&p);
    sampler.request(p, 48);
    try collect(hwnd, 3000, true, &got);
    try testing.expectEqual(@as(usize, 1), got.items.len);
    try testing.expect(got.items[0] == sampler.NO_RESULT or got.items[0] <= 255);

    // 50 demandes d'affilée : jamais plus de réponses que de demandes, et au moins une
    got.clearRetainingCapacity();
    const before = @atomicLoad(u32, &sampler.reads, .seq_cst);
    for (0..50) |i| sampler.request(.{ .x = p.x + @as(i32, @intCast(i % 7)), .y = p.y }, 48);
    try collect(hwnd, 1500, false, &got);
    const reads = @atomicLoad(u32, &sampler.reads, .seq_cst) - before;
    std.debug.print("  50 demandes d'affilée : {d} lectures, {d} réponses\n", .{ reads, got.items.len });
    try testing.expect(got.items.len >= 1 and got.items.len <= 50);
    try testing.expectEqual(@as(usize, reads), got.items.len);

    // arrêt : le fil se termine ; une demande se fait ensuite sur place
    sampler.stopWorker(3000);
    got.clearRetainingCapacity();
    sampler.request(p, 48);
    try collect(hwnd, 1000, true, &got);
    try testing.expectEqual(@as(usize, 1), got.items.len);
    sampler.deinit();
}

// ---------------------------------------------------------------------
// Couleurs choisies pour les deux jeux
// ---------------------------------------------------------------------

const NAVY_YELLOW: core.Colors = core.PRESETS[1];

/// Dossier temporaire pour les fichiers fabriqués d'un test (ceux de l'application ne sont
/// pas touchés). `leave` remet le dossier et les couleurs de l'application.
const TempDir = struct {
    fn enter(comptime tag: []const u8) !void {
        var name: [64]u16 = undefined;
        var num: [16]u8 = undefined;
        const tick = try std.fmt.bufPrint(&num, "{d}", .{w.GetTickCount()});
        var n: usize = 0;
        for (L("AutoCurseur-tests\\" ++ tag ++ "-")) |c| {
            name[n] = c;
            n += 1;
        }
        for (tick) |c| {
            name[n] = c;
            n += 1;
        }
        try testing.expect(cursors.setDir(L("TEMP"), name[0..n]));
    }

    fn leave() void {
        h.removeDir(cursors.dirPath());
        cursors.useVector(false);
        cursors.setColors(.{});
        _ = cursors.useDefaultDir();
    }
};

/// Le chemin `path` est-il dans le dossier des fichiers fabriqués ?
fn isMade(path: []const u16) bool {
    return std.mem.startsWith(u16, path, cursors.dirPath());
}

test "couleurs : les deux jeux sont fabriqués aux couleurs choisies, contour de la couleur opposée" {
    h.dpiAware();
    defer cursors.free();
    // forme de référence : la flèche et la sélection de texte en noir et blanc
    cursors.load(48);
    const ref_arrow = try h.stats(cursors.black[0]);
    const ref_beam = try h.stats(cursors.black[1]);
    cursors.free();

    try TempDir.enter("couleurs");
    defer TempDir.leave();
    cursors.setColors(NAVY_YELLOW);
    try testing.expect(cursors.currentColors().eql(NAVY_YELLOW));

    // aucun fichier de Windows ne sert tel quel : 17 sombres + 17 clairs + 17 rouges
    try testing.expectEqual(@as(usize, 3 * cursors.COUNT), cursors.prepare(true));
    try testing.expectEqual(@as(usize, 0), cursors.prepare(true)); // déjà à jour
    try testing.expectEqual(@as(usize, 3 * cursors.COUNT), h.fileCount(cursors.dirPath()));
    var p: [2 * w.MAX_PATH]u16 = undefined;
    for (0..cursors.COUNT) |i| {
        for ([_]cursors.Set{ .black, .white, .red }) |set| try testing.expect(isMade(cursors.pathOf(set, i, &p).?));
    }

    cursors.load(48);
    for ([_]usize{ 0, 1 }, [_]h.Stats{ ref_arrow, ref_beam }) |i, ref| {
        errdefer std.debug.print("  curseur n° {d}\n", .{i});
        const dark = cursors.black[i];
        const light = cursors.white[i];
        // jeu sombre : corps bleu nuit, contour blanc, plus aucun noir
        try testing.expect(try h.colorCount(dark, NAVY_YELLOW.dark) > 20);
        try testing.expect(try h.colorNear(dark, core.WHITE, 60) > 20);
        try testing.expectEqual(@as(usize, 0), try h.colorNear(dark, core.BLACK, 60));
        // jeu clair : corps jaune, contour noir, plus aucun blanc
        try testing.expect(try h.colorCount(light, NAVY_YELLOW.light) > 20);
        try testing.expect(try h.colorNear(light, core.BLACK, 60) > 20);
        try testing.expectEqual(@as(usize, 0), try h.colorNear(light, core.WHITE, 60));
        // même dessin et même point chaud qu'en noir et blanc
        for ([_]w.HCURSOR{ dark, light }) |c| {
            const s = try h.stats(c);
            try testing.expect(!s.mono);
            try testing.expectEqual(ref.opaque_px, s.opaque_px);
            try testing.expectEqual(ref.hot_x, s.hot_x);
            try testing.expectEqual(ref.hot_y, s.hot_y);
            try testing.expectEqual(ref.width, s.width);
        }
        // le corps du jeu sombre et celui du jeu clair occupent les mêmes pixels
        try testing.expectEqual(try h.colorCount(dark, NAVY_YELLOW.dark), try h.colorCount(light, NAVY_YELLOW.light));
    }
    // les couleurs franches sont gardées : le rouge de « indisponible » dans les deux jeux
    const no = for (cursors.defs, 0..) |d, i| {
        if (d.id == 32648) break i;
    } else unreachable;
    const red_dark = (try h.redStats(cursors.black[no])).red_px;
    try testing.expect(red_dark > 20);
    try testing.expectEqual(red_dark, (try h.redStats(cursors.white[no])).red_px);
}

test "couleurs : une seule couleur changée, l'autre jeu garde les fichiers de Windows" {
    h.dpiAware();
    defer cursors.free();
    try TempDir.enter("une-couleur");
    defer TempDir.leave();
    cursors.setColors(.{ .dark = NAVY_YELLOW.dark });
    // 17 sombres teintés + 4 clairs inversés (jeu « Windows Black ») + 17 rouges
    var native_white: usize = 0;
    for (cursors.defs) |d| native_white += @intFromBool(d.file_is_white);
    try testing.expectEqual(@as(usize, 2 * cursors.COUNT + (cursors.COUNT - native_white)), cursors.prepare(true));
    var p: [2 * w.MAX_PATH]u16 = undefined;
    for (cursors.defs, 0..) |d, i| {
        try testing.expect(isMade(cursors.pathOf(.black, i, &p).?));
        try testing.expectEqual(!d.file_is_white, isMade(cursors.pathOf(.white, i, &p).?));
    }
    cursors.load(48);
    try testing.expect(try h.colorCount(cursors.black[0], NAVY_YELLOW.dark) > 20);
    try testing.expect(try h.colorCount(cursors.white[0], core.WHITE) > 20); // flèche blanche de Windows
}

test "couleurs : retour au noir et blanc, les fichiers de Windows resservent et les doublons sont supprimés" {
    h.dpiAware();
    defer cursors.free();
    cursors.load(48);
    const ref_black = try h.stats(cursors.black[0]);
    const ref_white = try h.stats(cursors.white[0]);
    cursors.free();

    try TempDir.enter("retour");
    defer TempDir.leave();
    cursors.setColors(NAVY_YELLOW);
    _ = cursors.prepare(true);
    try testing.expectEqual(@as(usize, 3 * cursors.COUNT), h.fileCount(cursors.dirPath()));

    cursors.setColors(.{});
    // les 17 versions inversées sont refaites (le rouge n'a pas changé)
    try testing.expectEqual(@as(usize, cursors.COUNT), cursors.prepare(true));
    // il ne reste que les 17 inversés et les 17 rouges
    try testing.expectEqual(@as(usize, 2 * cursors.COUNT), h.fileCount(cursors.dirPath()));
    var p: [2 * w.MAX_PATH]u16 = undefined;
    for (cursors.defs, 0..) |d, i| {
        try testing.expectEqual(d.file_is_white, isMade(cursors.pathOf(.black, i, &p).?));
        try testing.expectEqual(!d.file_is_white, isMade(cursors.pathOf(.white, i, &p).?));
    }
    cursors.load(48);
    try testing.expect((try h.stats(cursors.black[0])).sameImage(ref_black));
    try testing.expect((try h.stats(cursors.white[0])).sameImage(ref_white));
    try testing.expectEqual(@as(usize, 0), try h.colorCount(cursors.black[0], NAVY_YELLOW.dark));
}

test "couleurs : le curseur agrandi change de couleur quand le rouge ressemble à une des deux" {
    h.dpiAware();
    defer cursors.freeRed();
    try testing.expectEqual(core.RED, cursors.shakeColor());
    try TempDir.enter("secousse");
    defer TempDir.leave();
    const reddish: core.Colors = .{ .dark = 0xB00020, .light = core.WHITE };
    cursors.setColors(reddish);
    const shake = cursors.shakeColor();
    try testing.expect(shake != core.RED);
    _ = cursors.prepare(true);
    cursors.loadRed(48);
    // flèche agrandie : corps de la couleur de secousse, contour blanc, sans rouge
    try testing.expect(try h.colorCount(cursors.red[0], shake) > 50);
    try testing.expect(try h.colorNear(cursors.red[0], core.WHITE, 60) > 50);
    try testing.expectEqual(@as(usize, 0), try h.colorNear(cursors.red[0], core.RED, 60));
    // retour à des couleurs sans rouge : le curseur agrandi redevient rouge
    cursors.setColors(NAVY_YELLOW);
    try testing.expectEqual(core.RED, cursors.shakeColor());
}

test "couleurs : pointeur agrandi, les dessins vectoriels sont teintés en 32 bits, même forme" {
    try skipWithoutVectorShapes();
    // forme de référence : la flèche noire d'origine (1 bit)
    _ = cursors.prepareVector(false);
    const ref_file = try vectorFile(.black, 0);
    defer testing.allocator.free(ref_file);
    const ref = curfile.frame(ref_file, 0).?;

    try TempDir.enter("vectoriel");
    defer TempDir.leave();
    cursors.setColors(NAVY_YELLOW);
    try testing.expectEqual(@as(usize, 3 * cursors.COUNT), cursors.prepareVector(true));
    try testing.expectEqual(@as(usize, 0), cursors.prepareVector(true));
    try testing.expect(cursors.vectorReady());
    for (0..cursors.COUNT) |i| {
        for ([_]cursors.Set{ .black, .white }) |set| {
            const file = try vectorFile(set, i);
            defer testing.allocator.free(file);
            const f = curfile.frame(file, 0) orelse return error.ImageIllisible;
            try testing.expectEqual(@as(u16, 32), f.bpp);
            try testing.expectEqual(@as(usize, svgcur.SIZE), f.w);
            try testing.expectEqual(svgcur.shapes[i].hot_x, f.hot_x);
            try testing.expectEqual(svgcur.shapes[i].hot_y, f.hot_y);
            // corps de la couleur du jeu, contour de la couleur opposée
            const body: u32 = if (set == .black) NAVY_YELLOW.dark else NAVY_YELLOW.light;
            const outline: u32 = if (set == .black) core.WHITE else core.BLACK;
            var n_body: usize = 0;
            var n_outline: usize = 0;
            for (std.mem.bytesAsSlice(u32, f.xor_bits)) |c| {
                if (c >> 24 != 255) continue;
                if (c & 0xFFFFFF == body) n_body += 1;
                if (c & 0xFFFFFF == outline) n_outline += 1;
            }
            errdefer std.debug.print("  curseur n° {d}, jeu {s} : {d} pixels du corps, {d} du contour\n", .{ i, @tagName(set), n_body, n_outline });
            try testing.expect(n_body > 300 and n_outline > 300);
            // mêmes pixels visibles que la version d'origine
            if (i == 0) {
                for (0..f.w) |y| {
                    for (0..f.w) |x| try testing.expectEqual(visibleAt(ref, x, y), visibleAt(f, x, y));
                }
            }
        }
    }
    // une seule couleur changée : l'autre jeu reste en 1 bit, comme ceux de Windows
    cursors.setColors(.{ .light = NAVY_YELLOW.light });
    _ = cursors.prepareVector(false);
    const plain = try vectorFile(.black, 0);
    defer testing.allocator.free(plain);
    try testing.expectEqual(@as(u16, 1), curfile.frame(plain, 0).?.bpp);
    try testing.expectEqualSlices(u8, ref_file, plain);
    const tinted = try vectorFile(.white, 0);
    defer testing.allocator.free(tinted);
    try testing.expectEqual(@as(u16, 32), curfile.frame(tinted, 0).?.bpp);
    // les curseurs teintés se chargent à toutes les tailles
    cursors.useVector(true);
    for ([_]i32{ 32, 48, 64, 128, 256 }) |px| {
        const c = cursors.loadOne(.white, 0, px) orelse return error.Chargement;
        defer _ = w.DestroyCursor(c);
        try testing.expectEqual(px, (try h.stats(c)).width);
    }
}
