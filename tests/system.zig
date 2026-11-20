//! Tests système (`zig build test-system`) : ils changent réellement le curseur de Windows
//! pendant quelques secondes et lancent l'exécutable. Quittez AutoCurseur avant de les lancer.

const std = @import("std");
const app = @import("autocurseur");
const options = @import("build_options");
const h = @import("helpers.zig");
const w = app.win32;
const cursors = app.cursors;
const core = app.core;
const settings = app.settings;
const testing = std.testing;
const L = h.L;

/// Réglages de l'utilisateur, relevés avant un test et remis à l'identique après.
const Saved = struct {
    rate: ?u32,
    lang: ?u32,
    shake: ?u32,

    fn take() Saved {
        return .{
            .rate = settings.readDword(settings.RATE_VALUE),
            .lang = settings.readDword(settings.LANG_VALUE),
            .shake = settings.readDword(settings.SHAKE_VALUE),
        };
    }

    fn put(v: Saved) void {
        settings.reset();
        if (v.rate) |x| settings.writeDword(settings.RATE_VALUE, x);
        if (v.lang) |x| settings.writeDword(settings.LANG_VALUE, x);
        if (v.shake) |x| settings.writeDword(settings.SHAKE_VALUE, x);
    }
};

fn systemArrow() !h.Stats {
    return h.stats(w.LoadCursorW(null, w.IDC_ARROW));
}

fn skipIfRunning() !void {
    h.dpiAware(); // comme l'application, sinon tailles et coordonnées sont « virtuelles »
    if (w.FindWindowW(L("AutoCurseur"), null) != null) {
        std.debug.print("  AutoCurseur est déjà lancé : test ignoré\n", .{});
        return error.SkipZigTest;
    }
}

const Proc = struct {
    pi: w.PROCESS_INFORMATION = .{},

    fn start() !Proc {
        const path = try std.unicode.utf8ToUtf16LeAllocZ(testing.allocator, options.exe_path);
        defer testing.allocator.free(path);
        var si: w.STARTUPINFOW = .{};
        var p: Proc = .{};
        if (w.CreateProcessW(path.ptr, null, null, null, 0, 0, null, null, &si, &p.pi) == 0) return error.CreateProcess;
        return p;
    }

    fn exitedWithin(p: Proc, ms: u32) bool {
        return w.WaitForSingleObject(p.pi.hProcess, ms) == w.WAIT_OBJECT_0;
    }

    fn kill(p: Proc) void {
        if (!p.exitedWithin(0)) _ = w.TerminateProcess(p.pi.hProcess, 1);
        _ = w.CloseHandle(p.pi.hProcess);
        _ = w.CloseHandle(p.pi.hThread);
    }
};

test "système : appliquer noir puis blanc, puis restaurer rend le curseur d'origine" {
    try skipIfRunning();
    const before = try systemArrow();
    defer cursors.restore();
    defer cursors.free();
    cursors.load(cursors.systemSize());
    const black = try h.stats(cursors.black[0]);
    const white = try h.stats(cursors.white[0]);

    cursors.apply(true);
    try testing.expect((try systemArrow()).sameImage(black));
    cursors.apply(false);
    try testing.expect((try systemArrow()).sameImage(white));
    cursors.restore();
    try testing.expect((try systemArrow()).sameImage(before));
}

test "système : les curseurs générés ont la taille de ceux de Windows" {
    try skipIfRunning();
    const before = try systemArrow();
    defer cursors.free();
    cursors.load(cursors.systemSize());
    try testing.expectEqual(before.width, (try h.stats(cursors.black[0])).width);
}

test "système : des curseurs d'une autre taille laissés par un ancien lancement ne sont pas repris" {
    try skipIfRunning();
    const before = try systemArrow();
    defer cursors.restore();
    defer cursors.free();
    // simule un lancement précédent arrêté de force, avec des curseurs de 80 px restés en place
    cursors.load(if (before.width == 80) 96 else 80);
    cursors.apply(true);
    try testing.expect((try systemArrow()).width != before.width);

    const p = try Proc.start();
    defer p.kill();
    w.Sleep(1500);
    const now = try systemArrow();
    h.report("taille des curseurs appliqués", @floatFromInt(now.width), "px", @floatFromInt(before.width));
    try testing.expectEqual(before.width, now.width);

    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
    try testing.expect((try systemArrow()).sameImage(before));
}

test "système : le réglage « vérifications par seconde » du menu est appliqué et mémorisé" {
    try skipIfRunning();
    const saved = Saved.take(); // on remet l'état d'origine à la fin
    defer saved.put();
    defer cursors.restore();

    app.settings.reset();
    try testing.expectEqual(@as(u32, app.core.DEFAULT_RATE), app.settings.loadRate());

    const p = try Proc.start();
    defer p.kill();
    w.Sleep(1000);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    // même chemin qu'un clic dans le sous-menu
    for (app.core.RATES, 0..) |r, i| {
        _ = w.PostMessageW(hwnd, w.WM_COMMAND, app.settings.RATE_MENU_BASE + i, 0);
        w.Sleep(200);
        try testing.expectEqual(@as(?u32, r), app.settings.readRate());
    }
    // une entrée de menu inconnue ne change rien
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, app.settings.RATE_MENU_BASE + app.core.RATES.len, 0);
    w.Sleep(200);
    try testing.expectEqual(@as(?u32, 20), app.settings.readRate());

    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
}

test "système : basculer 200 fois ne fait rien fuir et reste rapide" {
    try skipIfRunning();
    defer cursors.restore();
    defer cursors.free();
    cursors.load(cursors.systemSize());
    const n = 200;
    const t = h.Timer.start();
    for (0..n) |i| cursors.apply(i % 2 == 0);
    const r = t.perIteration(n);
    h.report("bascule complète des 17 curseurs", r.wall_us / 1000, "ms", 20);
    try testing.expect(r.wall_us < 20_000);
}

test "système : l'exécutable bascule, consomme peu, reste unique et se ferme proprement" {
    try skipIfRunning();
    const before = try systemArrow();
    defer cursors.free();
    cursors.load(cursors.systemSize());
    const black = try h.stats(cursors.black[0]);
    const white = try h.stats(cursors.white[0]);

    const p = try Proc.start();
    defer p.kill();
    defer cursors.restore(); // filet de sécurité si le test échoue en route

    // 1. au bout d'un moment, la fenêtre cachée existe et un des deux jeux est appliqué
    w.Sleep(1500);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    const now = try systemArrow();
    try testing.expect(now.sameImage(black) or now.sameImage(white));

    // 2. consommation sur 10 s
    const per_us = h.cyclesPerUs();
    const cyc0 = h.processCycles(p.pi.hProcess);
    w.Sleep(10_000);
    const cpu_ms = @as(f64, @floatFromInt(h.processCycles(p.pi.hProcess) - cyc0)) / per_us / 1000;
    var mem: w.PROCESS_MEMORY_COUNTERS_EX = .{};
    _ = w.K32GetProcessMemoryInfo(p.pi.hProcess, &mem, @sizeOf(w.PROCESS_MEMORY_COUNTERS_EX));
    const private_mb = @as(f64, @floatFromInt(mem.PrivateUsage)) / (1024 * 1024);
    h.report("processeur consommé en 10 s", cpu_ms, "ms", 100);
    h.report("mémoire privée", private_mb, "Mo", 6);
    try testing.expect(cpu_ms < 100); // moins de 1 % d'un cœur
    try testing.expect(private_mb < 6);

    // 3. une deuxième instance s'arrête tout de suite
    const second = try Proc.start();
    defer second.kill();
    try testing.expect(second.exitedWithin(3000));

    // 4. fermeture propre : le processus s'arrête et le curseur d'origine revient
    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
    try testing.expect((try systemArrow()).sameImage(before));
}

test "système : la langue choisie dans le menu est appliquée et mémorisée" {
    try skipIfRunning();
    const saved = Saved.take();
    defer saved.put();
    defer cursors.restore();

    app.settings.reset();
    try testing.expectEqual(app.i18n.Choice.auto, app.settings.loadLang());

    const p = try Proc.start();
    defer p.kill();
    w.Sleep(1000);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    for ([_]app.i18n.Choice{ .fr, .en, .auto }) |c| {
        _ = w.PostMessageW(hwnd, w.WM_COMMAND, app.settings.LANG_MENU_BASE + @backingInt(c), 0);
        w.Sleep(200);
        try testing.expectEqual(c, app.settings.loadLang());
    }
    // une entrée de menu inconnue ne change rien
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, app.settings.LANG_MENU_BASE + app.i18n.CHOICES.len, 0);
    w.Sleep(200);
    try testing.expectEqual(app.i18n.Choice.auto, app.settings.loadLang());

    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
}

test "système : « secouer pour retrouver » se désactive et se réactive depuis le menu" {
    try skipIfRunning();
    const saved = Saved.take();
    defer saved.put();
    defer cursors.restore();

    app.settings.reset();
    try testing.expect(app.settings.loadShake()); // actif par défaut

    const p = try Proc.start();
    defer p.kill();
    w.Sleep(1000);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, app.settings.MENU_SHAKE, 0);
    w.Sleep(300);
    try testing.expect(!app.settings.loadShake());
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, app.settings.MENU_SHAKE, 0);
    w.Sleep(300);
    try testing.expect(app.settings.loadShake());

    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
}

/// Déplace la souris en va-et-vient horizontal (`hz` allers-retours par seconde,
/// amplitude totale `amp` px autour de `c`) pendant `ms` millisecondes.
fn shakeMouse(c: core.Point, amp: i32, hz: f32, ms: u32) void {
    var t: u32 = 0;
    while (t < ms) : (t += 10) {
        const phase = @as(f32, @floatFromInt(t)) / 1000 * hz * 2 * std.math.pi;
        const dx: i32 = @intFromFloat(@as(f32, @floatFromInt(amp)) / 2 * @sin(phase));
        _ = w.SetCursorPos(c.x + dx, c.y);
        w.Sleep(10);
    }
}

test "système : secouer la souris affiche le curseur rouge agrandi, qui disparaît ensuite" {
    try skipIfRunning();
    const saved = Saved.take();
    defer saved.put();
    app.settings.reset(); // option active par défaut

    // la souris peut-elle être déplacée ici ? (pas toujours sur une machine sans session ouverte)
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    const c: core.Point = .{ .x = @divTrunc(w.GetSystemMetrics(w.SM_CXSCREEN), 2), .y = @divTrunc(w.GetSystemMetrics(w.SM_CYSCREEN), 2) };
    _ = w.SetCursorPos(c.x + 7, c.y);
    var now_pos: core.Point = .{};
    _ = w.GetCursorPos(&now_pos);
    if (now_pos.x != c.x + 7 or now_pos.y != c.y) {
        std.debug.print("  la souris ne peut pas être déplacée dans cette session : test ignoré\n", .{});
        return error.SkipZigTest;
    }

    const before = try systemArrow();
    const size = cursors.systemSize();
    defer cursors.free();
    cursors.load(size);
    const black = try h.stats(cursors.black[0]);
    const white = try h.stats(cursors.white[0]);

    const p = try Proc.start();
    defer p.kill();
    defer cursors.restore();
    w.Sleep(1500);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;

    // 1. va-et-vient franc (4 par seconde, 6 fois la taille du curseur) pendant 1,5 s
    const amp = @min(6 * size, w.GetSystemMetrics(w.SM_CXSCREEN) - 40);
    const per_us = h.cyclesPerUs();
    const cyc0 = h.processCycles(p.pi.hProcess);
    shakeMouse(c, amp, 4, 1500);
    const cpu_ms = @as(f64, @floatFromInt(h.processCycles(p.pi.hProcess) - cyc0)) / per_us / 1000;
    const big = h.redStats(w.LoadCursorW(null, w.IDC_ARROW)) catch |e| {
        std.debug.print("  la flèche affichée n'est pas le curseur rouge ({s})\n", .{@errorName(e)});
        return e;
    };
    h.report("taille de la flèche en secouant", @floatFromInt(big.width), "px", @floatFromInt(core.bigSize(size)));
    h.report("processeur pendant 1,5 s de secousse", cpu_ms, "ms", 150);
    try testing.expectEqual(core.bigSize(size), big.width);
    try testing.expect(big.red_px > 0);
    try testing.expect(cpu_ms < 150); // moins de 10 % d'un cœur, lectures d'écran comprises

    // 2. souris arrêtée : le curseur normal revient
    _ = w.SetCursorPos(c.x, c.y);
    w.Sleep(1500);
    const back = try systemArrow();
    try testing.expect(back.sameImage(black) or back.sameImage(white));

    // 3. un simple déplacement ne déclenche rien
    var x: i32 = c.x - @divTrunc(amp, 2);
    while (x < c.x + @divTrunc(amp, 2)) : (x += 8) {
        _ = w.SetCursorPos(x, c.y);
        w.Sleep(10);
    }
    const moved = try systemArrow();
    try testing.expect(moved.sameImage(black) or moved.sameImage(white));

    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
    try testing.expect((try systemArrow()).sameImage(before));
}

test "système : option désactivée, secouer ne change rien" {
    try skipIfRunning();
    const saved = Saved.take();
    defer saved.put();
    app.settings.reset();
    app.settings.saveShake(false);

    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    const c: core.Point = .{ .x = @divTrunc(w.GetSystemMetrics(w.SM_CXSCREEN), 2), .y = @divTrunc(w.GetSystemMetrics(w.SM_CYSCREEN), 2) };
    _ = w.SetCursorPos(c.x + 7, c.y);
    var now_pos: core.Point = .{};
    _ = w.GetCursorPos(&now_pos);
    if (now_pos.x != c.x + 7) return error.SkipZigTest;

    const size = cursors.systemSize();
    defer cursors.free();
    cursors.load(size);
    const black = try h.stats(cursors.black[0]);
    const white = try h.stats(cursors.white[0]);

    const p = try Proc.start();
    defer p.kill();
    defer cursors.restore();
    w.Sleep(1500);
    shakeMouse(c, @min(6 * size, w.GetSystemMetrics(w.SM_CXSCREEN) - 40), 4, 1500);
    const now = try systemArrow();
    try testing.expect(now.sameImage(black) or now.sameImage(white));

    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
}
