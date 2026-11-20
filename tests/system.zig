//! Tests système (`zig build test-system`) : ils changent réellement le curseur de Windows
//! pendant quelques secondes et lancent l'exécutable. Quittez AutoCurseur avant de les lancer.

const std = @import("std");
const app = @import("autocurseur");
const options = @import("build_options");
const h = @import("helpers.zig");
const w = app.win32;
const cursors = app.cursors;
const testing = std.testing;
const L = h.L;

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
    const saved = app.settings.readRate(); // on remet l'état d'origine à la fin
    defer if (saved) |v| app.settings.saveRate(v) else app.settings.reset();
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
