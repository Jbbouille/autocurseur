//! Tests de performance, compilés en ReleaseFast comme l'application.
//! Chaque test mesure, affiche le résultat et échoue si un seuil est dépassé.
//! Les seuils sont larges (environ 10 fois les valeurs mesurées) pour ne pas
//! échouer sur une machine plus lente, tout en attrapant une vraie régression.

const std = @import("std");
const app = @import("autocurseur");
const h = @import("helpers.zig");
const core = app.core;
const w = app.win32;
const cursors = app.cursors;
const sampler = app.sampler;
const testing = std.testing;

/// Mesures de chargement prévues pour la taille 1 du pointeur : agrandi dans les Paramètres,
/// Windows fabrique des curseurs bien plus grands (jusqu'à 13 fois plus lent à la taille maximale).
fn skipIfEnlarged() !void {
    if (cursors.pointerBase() > 32) {
        std.debug.print("  pointeur agrandi dans les Paramètres : mesure prévue pour la taille 1, ignorée\n", .{});
        return error.SkipZigTest;
    }
}

test "perf : luminance moyenne d'une zone 96x96" {
    var px: [core.BOX_MAX * core.BOX_MAX]u32 = undefined;
    var prng = std.Random.DefaultPrng.init(1);
    for (&px) |*p| p.* = prng.random().int(u32);
    const n = 20_000;
    const t = h.Timer.start();
    var acc: u64 = 0;
    for (0..n) |i| {
        px[i % px.len] ^= 1; // empêche le compilateur de sortir le calcul de la boucle
        acc += core.averageLuma(&px);
    }
    std.mem.doNotOptimizeAway(acc);
    const r = t.perIteration(n);
    h.report("luminance d'une zone 96x96", r.wall_us, "us", 100);
    try testing.expect(r.wall_us < 100);
}

test "perf : décision + minuterie, par tic" {
    const n = 2_000_000;
    var ticker: core.Ticker = .{};
    var shade: core.Shade = .unknown;
    const t = h.Timer.start();
    for (0..n) |i| {
        const a = ticker.tick(.{ .x = @intCast(i & 0xFF), .y = 0 });
        if (a.sample) shade = core.decide(shade, @intCast(i & 0xFF), .{});
    }
    std.mem.doNotOptimizeAway(shade);
    const r = t.perIteration(n);
    h.report("décision + minuterie (par tic)", r.wall_us, "us", 1);
    try testing.expect(r.wall_us < 1);
}

test "perf : inversion des pixels d'un curseur 256x256" {
    var px: [core.MAX_CUR * core.MAX_CUR]u32 = undefined;
    var prng = std.Random.DefaultPrng.init(2);
    for (&px) |*p| p.* = prng.random().int(u32) | 0xFF000000;
    const n = 200;
    const t = h.Timer.start();
    for (0..n) |_| core.invertColorPixels(&px, core.MAX_CUR, &.{}, 0);
    std.mem.doNotOptimizeAway(px[123]);
    const r = t.perIteration(n);
    h.report("inversion pixels 256x256", r.wall_us, "us", 5000);
    try testing.expect(r.wall_us < 5000);
}

test "perf : chargement complet des deux jeux (17 curseurs x 2) à 80 px" {
    try skipIfEnlarged();
    defer cursors.free();
    cursors.load(80); // premier chargement : fichiers mis en cache par le système
    const n = 10;
    const t = h.Timer.start();
    for (0..n) |_| cursors.load(80);
    const r = t.perIteration(n);
    h.report("chargement des 34 curseurs à 80 px", r.wall_us / 1000, "ms", 500);
    try testing.expect(r.wall_us < 500_000);
}

test "perf : fabrication d'un fichier rouge (flèche, 5 tailles), en mémoire" {
    var buf: [2 * w.MAX_PATH]u16 = undefined;
    const path = cursors.pathOf(.black, 0, &buf).?; // fichier de Windows
    const src = try h.readFile(path.ptr);
    defer testing.allocator.free(src);
    const n = 200;
    var len: usize = 0;
    const t = h.Timer.start();
    for (0..n) |_| len = app.curfile.derive(src, .red, &cursors.out_buf).?;
    const r = t.perIteration(n);
    std.mem.doNotOptimizeAway(len);
    h.report("fabrication du fichier rouge de la flèche", r.wall_us, "us", 5000);
    try testing.expect(r.wall_us < 5000);
}

test "perf : préparation au démarrage quand les fichiers sont déjà à jour" {
    _ = cursors.prepare(true);
    const n = 5;
    const t = h.Timer.start();
    for (0..n) |_| _ = cursors.prepare(true);
    const r = t.perIteration(n);
    h.report("vérification des 34 fichiers fabriqués", r.wall_us / 1000, "ms", 200);
    try testing.expect(r.wall_us < 200_000);
}

test "perf : chargement d'un curseur depuis son fichier (fait 17 fois par bascule)" {
    try skipIfEnlarged();
    h.dpiAware();
    _ = cursors.prepare(true);
    const n = 200;
    const t = h.Timer.start();
    for (0..n) |i| {
        const c = cursors.loadOne(if (i % 2 == 0) .white else .red, i % cursors.COUNT, 48) orelse return error.Chargement;
        _ = w.DestroyCursor(c);
    }
    const r = t.perIteration(n);
    h.report("chargement d'un curseur depuis son fichier", r.wall_us, "us", 3000);
    try testing.expect(r.wall_us < 3000);
}

test "perf : lecture d'une zone 60x60 depuis une image en mémoire" {
    sampler.init();
    sampler.resize(60);
    var c = try h.Canvas.init(400, 400);
    defer c.deinit();
    c.fill(0xFFFFFF);
    const n = 2_000;
    const t = h.Timer.start();
    for (0..n) |i| {
        const off: i32 = @intCast(i % 300);
        _ = sampler.sampleFrom(c.dc, .{ .x = off, .y = off }) orelse return error.Sample;
    }
    const r = t.perIteration(n);
    h.report("lecture zone 60x60 (mémoire)", r.wall_us, "us", 1000);
    try testing.expect(r.wall_us < 1000);
}

test "perf : lecture réelle de l'écran, coût processeur par lecture" {
    sampler.init();
    sampler.resize(60);
    var p: core.Point = .{};
    _ = w.GetCursorPos(&p);
    if (sampler.sampleScreen(p) == null) return error.SkipZigTest; // écran verrouillé
    const n = 60; // chaque lecture peut attendre l'image suivante (~16 ms) : on compte le processeur
    const t = h.Timer.start();
    for (0..n) |_| _ = sampler.sampleScreen(p);
    const r = t.perIteration(n);
    h.report("lecture écran : processeur par lecture", r.cpu_us, "us", 5000);
    h.report("lecture écran : temps réel par lecture", r.wall_us, "us", 0);
    try testing.expect(r.cpu_us < 5000);

    // Budget estimé de l'application à chaque rythme du menu, et à l'arrêt (~4 lectures/s).
    for (core.RATES) |rate| {
        var name_buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "budget estimé en mouvement à {d}/s (% d'un cœur)", .{rate}) catch unreachable;
        const pct = r.cpu_us * @as(f64, @floatFromInt(rate)) / 1e6 * 100;
        h.report(name, pct, "%", 2);
        try testing.expect(pct < 2);
    }
    const idle_pct = r.cpu_us * 4 / 1e6 * 100;
    h.report("budget estimé souris immobile (% d'un cœur)", idle_pct, "%", 1);
    try testing.expect(idle_pct < 1);
}

test "perf : détection de secousse, par lecture de position" {
    var s = core.Shake.init(64);
    const n = 1_000_000;
    var events: usize = 0;
    const t = h.Timer.start();
    for (0..n) |i| {
        // va-et-vient en dents de scie de 540 px, 10 lectures par aller
        const k: i32 = @intCast(i % 20);
        const x: i32 = if (k < 10) k * 60 else (20 - k) * 60;
        if (s.feed(@truncate(i * core.SHAKE_TICK_MS), .{ .x = x, .y = 0 }) != .none) events += 1;
    }
    const r = t.perIteration(n);
    std.mem.doNotOptimizeAway(events);
    h.report("détection de secousse, par lecture", r.wall_us * 1000, "ns", 500);
    try testing.expect(r.wall_us * 1000 < 500);
}

test "perf : chargement du jeu rouge agrandi (17 curseurs)" {
    try skipIfEnlarged();
    h.dpiAware();
    defer cursors.freeRed();
    cursors.loadRed(64);
    const n = 5;
    const t = h.Timer.start();
    for (0..n) |_| cursors.loadRed(64);
    const r = t.perIteration(n);
    h.report("chargement des 17 curseurs rouges à 128 px", r.wall_us / 1000, "ms", 500);
    try testing.expect(r.wall_us < 500_000);
}

fn privateMb() f64 {
    var mem: w.PROCESS_MEMORY_COUNTERS_EX = .{};
    _ = w.K32GetProcessMemoryInfo(w.GetCurrentProcess(), &mem, @sizeOf(w.PROCESS_MEMORY_COUNTERS_EX));
    return @as(f64, @floatFromInt(mem.PrivateUsage)) / (1024 * 1024);
}

test "perf : curseurs vectoriels, dessin avec Direct2D puis déchargement" {
    if (!cursors.hasVectorShapes()) return error.SkipZigTest;
    _ = cursors.prepareVector(true); // premier passage : bibliothèques mises en cache par Windows
    const before = privateMb();
    try testing.expect(cursors.useDefaultDir()); // oublie l'état : tout est redessiné et comparé
    const t = h.Timer.start();
    _ = cursors.prepareVector(true);
    const r = t.perIteration(1);
    const after = privateMb();
    h.report("dessin et vérification des 51 curseurs vectoriels", r.wall_us / 1000, "ms", 2000);
    h.report("mémoire privée gardée après déchargement de Direct2D", after - before, "Mo", 4);
    try testing.expect(r.wall_us < 2_000_000);
    try testing.expect(after - before < 4);
    try testing.expect(w.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("d2d1.dll")) == null);
}
