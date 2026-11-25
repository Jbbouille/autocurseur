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
    dark: ?u32,
    light: ?u32,

    fn take() Saved {
        return .{
            .rate = settings.readDword(settings.RATE_VALUE),
            .lang = settings.readDword(settings.LANG_VALUE),
            .shake = settings.readDword(settings.SHAKE_VALUE),
            .dark = settings.readDword(settings.DARK_VALUE),
            .light = settings.readDword(settings.LIGHT_VALUE),
        };
    }

    fn put(v: Saved) void {
        settings.reset();
        if (v.rate) |x| settings.writeDword(settings.RATE_VALUE, x);
        if (v.lang) |x| settings.writeDword(settings.LANG_VALUE, x);
        if (v.shake) |x| settings.writeDword(settings.SHAKE_VALUE, x);
        if (v.dark) |x| settings.writeDword(settings.DARK_VALUE, x);
        if (v.light) |x| settings.writeDword(settings.LIGHT_VALUE, x);
    }
};

/// Réglages par défaut le temps d'un test (noir et blanc, 10 lectures par seconde…) : renvoie
/// ceux de l'utilisateur, à remettre à la fin avec `put`.
fn defaults() Saved {
    const saved = Saved.take();
    settings.reset();
    return saved;
}

fn systemArrow() !h.Stats {
    return h.stats(w.LoadCursorW(null, w.IDC_ARROW));
}

fn skipIfRunning() !void {
    h.dpiAware(); // comme l'application, sinon tailles et coordonnées sont « virtuelles »
    if (w.FindWindowW(L("AutoCurseur"), null) != null) {
        std.debug.print("  AutoCurseur est déjà lancé : test ignoré\n", .{});
        return error.SkipZigTest;
    }
    likeTheApp();
}

/// Comme l'application : curseurs dessinés à partir des dessins vectoriels si le pointeur est
/// agrandi (Paramètres > Accessibilité), classiques sinon, et même taille de curseur rouge.
fn likeTheApp() void {
    cursors.base = cursors.pointerBase();
    if (cursors.base > 32) {
        _ = cursors.prepareVector(true);
        cursors.useVector(cursors.vectorReady());
    } else {
        cursors.useVector(false);
    }
}

/// Pour les tests qui vérifient les images classiques au pixel près : prévus pour la taille 1
/// du pointeur (agrandi, Windows charge les images autrement).
fn skipIfEnlarged() !void {
    if (cursors.pointerBase() > 32) {
        std.debug.print("  pointeur agrandi dans les Paramètres : test prévu pour la taille 1, ignoré\n", .{});
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

    /// Lance AutoCurseur et attend qu'il réponde : son démarrage prend environ 1 s quand le
    /// pointeur est très agrandi (Windows fabrique des curseurs bien plus grands).
    fn startReady() !Proc {
        const p = try start();
        errdefer p.kill();
        const t0 = w.GetTickCount();
        while (w.GetTickCount() -% t0 < 10_000) {
            if (p.exitedWithin(0)) return error.ArretAuDemarrage;
            if (w.FindWindowW(L("AutoCurseur"), null)) |hwnd| {
                if (responds(hwnd)) return p;
            }
            w.Sleep(20);
        }
        return error.PasDeReponseAuDemarrage;
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

// ---------------------------------------------------------------------
// Surface de test : fenêtre au premier plan, d'une couleur unie, qui affiche le curseur du
// système choisi. La souris posée dessus, on sait quel curseur est affiché et sur quel fond.
// Elle a son propre fil, qui traite ses messages pendant que le test attend.
// ---------------------------------------------------------------------

extern "user32" fn SetCursor(w.HCURSOR) callconv(.winapi) w.HCURSOR;
extern "user32" fn InvalidateRect(w.HWND, ?*const w.RECT, w.BOOL) callconv(.winapi) w.BOOL;
extern "user32" fn GetClientRect(w.HWND, *w.RECT) callconv(.winapi) w.BOOL;
const WM_SETCURSOR = 0x0020;
const WM_ERASEBKGND = 0x0014;
const WM_DESTROY = 0x0002;
const WS_POPUP: u32 = 0x80000000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_EX_TOPMOST: u32 = 0x00000008;
const WS_EX_TOOLWINDOW: u32 = 0x00000080;
const WS_EX_NOACTIVATE: u32 = 0x08000000;
const LIGHT: u32 = 0xF0F0F0; // couleurs Windows : 0x00BBGGRR
const DARK: u32 = 0x101010;
const ID_ARROW: u32 = 32512;
const ID_HAND: u32 = 32649;

var surface_color: u32 = LIGHT;
var surface_cursor: u32 = ID_ARROW;
var surface_rect: w.RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
var surface_hwnd: w.HWND = null;
var surface_ready: w.HANDLE = null;

fn sysCursor(id: u32) w.HCURSOR {
    return w.LoadCursorW(null, @ptrFromInt(id));
}

/// Rang dans cursors.defs du curseur du système `id`.
fn rankOf(id: u32) usize {
    for (cursors.defs, 0..) |d, i| {
        if (d.id == id) return i;
    }
    unreachable;
}

fn surfaceProc(hwnd: w.HWND, msg: u32, wp: w.WPARAM, lp: w.LPARAM) callconv(.winapi) w.LRESULT {
    switch (msg) {
        WM_SETCURSOR => {
            _ = SetCursor(sysCursor(@atomicLoad(u32, &surface_cursor, .seq_cst)));
            return 1;
        },
        WM_ERASEBKGND => {
            var r: w.RECT = undefined;
            _ = GetClientRect(hwnd, &r);
            const brush = w.CreateSolidBrush(@atomicLoad(u32, &surface_color, .seq_cst));
            defer _ = w.DeleteObject(brush);
            _ = w.FillRect(@ptrFromInt(wp), &r, brush);
            return 1;
        },
        WM_DESTROY => {
            w.PostQuitMessage(0);
            return 0;
        },
        else => return w.DefWindowProcW(hwnd, msg, wp, lp),
    }
}

fn surfaceMain(_: ?*anyopaque) callconv(.winapi) u32 {
    const hi = w.GetModuleHandleW(null);
    const wc: w.WNDCLASSW = .{ .lpfnWndProc = surfaceProc, .hInstance = hi, .lpszClassName = L("AutoCurseurTestSurface") };
    _ = w.RegisterClassW(&wc); // déjà enregistrée au deuxième test : sans importance
    const r = surface_rect;
    surface_hwnd = w.CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, L("AutoCurseurTestSurface"), L(""), WS_POPUP | WS_VISIBLE, r.left, r.top, r.right - r.left, r.bottom - r.top, null, null, hi, null);
    _ = w.SetEvent(surface_ready);
    if (surface_hwnd == null) return 1;
    var m: w.MSG = undefined;
    while (w.GetMessageW(&m, null, 0, 0) > 0) _ = w.DispatchMessageW(&m);
    return 0;
}

const Surface = struct {
    thread: w.HANDLE,
    center: core.Point,

    /// Ouvre la surface (carré de 800 px autour du centre de l'écran principal), y pose la
    /// souris et attend que le curseur `id` soit affiché. Ignore le test si la souris ne peut
    /// pas être déplacée dans cette session.
    fn open(color: u32, id: u32) !Surface {
        h.dpiAware();
        const c: core.Point = .{ .x = @divTrunc(w.GetSystemMetrics(w.SM_CXSCREEN), 2), .y = @divTrunc(w.GetSystemMetrics(w.SM_CYSCREEN), 2) };
        surface_color = color;
        surface_cursor = id;
        surface_rect = .{ .left = c.x - 400, .top = c.y - 400, .right = c.x + 400, .bottom = c.y + 400 };
        surface_ready = w.CreateEventW(null, 0, 0, null);
        defer _ = w.CloseHandle(surface_ready);
        const t = w.CreateThread(null, 0, surfaceMain, null, 0, null) orelse return error.CreateThread;
        _ = w.WaitForSingleObject(surface_ready, 5000);
        const s: Surface = .{ .thread = t, .center = c };
        errdefer s.close();
        if (surface_hwnd == null) return error.SurfaceImpossible;
        _ = w.SetCursorPos(c.x, c.y);
        var pos: core.Point = .{};
        _ = w.GetCursorPos(&pos);
        if (pos.x != c.x or pos.y != c.y) {
            std.debug.print("  la souris ne peut pas être déplacée dans cette session : test ignoré\n", .{});
            return error.SkipZigTest;
        }
        s.useCursor(id) catch {
            // machine sans pointeur affiché (intégration continue, session sans souris) : Windows
            // n'y montre aucun curseur, AutoCurseur n'a donc rien à recolorer
            var ci: w.CURSORINFO = .{};
            _ = w.GetCursorInfo(&ci);
            std.debug.print("  aucun pointeur affiché dans cette session (état {d}, curseur {?d}) : test ignoré\n", .{ ci.flags, cursors.indexOf(ci.hCursor) });
            return error.SkipZigTest;
        };
        return s;
    }

    fn close(s: Surface) void {
        _ = w.PostMessageW(surface_hwnd, w.WM_CLOSE, 0, 0);
        _ = w.WaitForSingleObject(s.thread, 5000);
        _ = w.CloseHandle(s.thread);
        surface_hwnd = null;
    }

    /// Repeint la surface (AutoCurseur la verra à sa prochaine lecture).
    fn paint(_: Surface, color: u32) void {
        @atomicStore(u32, &surface_color, color, .seq_cst);
        _ = InvalidateRect(surface_hwnd, null, 1);
    }

    /// Affiche le curseur du système `id` (petit mouvement de souris pour que Windows le
    /// redemande) et attend qu'il le soit.
    fn useCursor(s: Surface, id: u32) !void {
        @atomicStore(u32, &surface_cursor, id, .seq_cst);
        const t0 = w.GetTickCount();
        while (w.GetTickCount() -% t0 < 2000) {
            _ = w.SetCursorPos(s.center.x + 1, s.center.y);
            _ = w.SetCursorPos(s.center.x, s.center.y);
            w.Sleep(20);
            if (cursors.shown()) |i| if (i == rankOf(id)) return;
        }
        return error.CurseurPasAffiche;
    }
};

/// Attend (au plus `ms`) que le curseur du système `id` ait l'image `want` ; renvoie le délai.
fn waitImage(id: u32, want: h.Stats, ms: u32) !u32 {
    const t0 = w.GetTickCount();
    while (true) {
        const t = w.GetTickCount() -% t0;
        if ((try h.stats(sysCursor(id))).sameImage(want)) return t;
        if (t > ms) return error.ImageAttendueAbsente;
        w.Sleep(2);
    }
}

test "système : seul le curseur affiché change de couleur, chacun des autres quand il apparaît" {
    try skipIfRunning();
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    cursors.restore();
    const hand_before = try h.stats(sysCursor(ID_HAND));
    const s = try Surface.open(LIGHT, ID_ARROW);
    defer s.close();
    defer cursors.restore();
    defer cursors.free();
    cursors.load(cursors.systemSize());
    const A = rankOf(ID_ARROW);
    const H = rankOf(ID_HAND);
    const white_arrow = try h.stats(cursors.white[A]);
    const white_hand = try h.stats(cursors.white[H]);
    const black_hand = try h.stats(cursors.black[H]);

    // la flèche est affichée : elle seule devient blanche
    cursors.show(.white);
    try testing.expect((try systemArrow()).sameImage(white_arrow));
    try testing.expect((try h.stats(sysCursor(ID_HAND))).sameImage(hand_before));
    try testing.expectEqual(@as(?cursors.Set, .white), cursors.installed[A]);
    try testing.expectEqual(@as(?cursors.Set, null), cursors.installed[H]);

    // la main apparaît : fix la recolore
    try s.useCursor(ID_HAND);
    cursors.fix();
    try testing.expect((try h.stats(sysCursor(ID_HAND))).sameImage(white_hand));

    // retour au noir : la main, affichée, change ; la flèche, cachée, reste blanche
    cursors.show(.black);
    try testing.expect((try h.stats(sysCursor(ID_HAND))).sameImage(black_hand));
    try testing.expect((try systemArrow()).sameImage(white_arrow));

    // secousse : les curseurs passés au rouge reviennent tous à la fin, pas seulement l'affiché
    cursors.show(.red);
    try testing.expectEqual(@as(?cursors.Set, .red), cursors.installed[H]);
    try s.useCursor(ID_ARROW);
    cursors.fix();
    try testing.expectEqual(@as(?cursors.Set, .red), cursors.installed[A]);
    cursors.show(.black);
    for (cursors.installed) |set| try testing.expect(set == null or set.? != .red);
    try testing.expect((try h.stats(sysCursor(ID_HAND))).sameImage(black_hand));

    // pause : tous ceux de Windows reviennent d'un coup
    cursors.restore();
    try testing.expect((try h.stats(sysCursor(ID_HAND))).sameImage(hand_before));
    for (cursors.installed) |set| try testing.expectEqual(@as(?cursors.Set, null), set);
}

test "système : changer la couleur du seul curseur affiché est rapide, même pointeur agrandi" {
    try skipIfRunning();
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    const s = try Surface.open(LIGHT, ID_ARROW);
    defer s.close();
    defer cursors.restore();
    cursors.restore();
    cursors.size = cursors.systemSize();
    const n = 40;
    const t = h.Timer.start();
    for (0..n) |i| cursors.show(if (i % 2 == 0) .black else .white);
    const r = t.perIteration(n);
    // à la taille maximale du pointeur, Windows met environ 5 ms à préparer chaque curseur
    const limit_ms = 2 * @as(f64, @floatFromInt(cursors.base)) / 32;
    h.report("bascule du curseur affiché", r.wall_us / 1000, "ms", limit_ms);
    try testing.expect(r.wall_us / 1000 < limit_ms);
    // un seul des 17 a été rechargé
    var n_installed: usize = 0;
    for (cursors.installed) |set| n_installed += @intFromBool(set != null);
    try testing.expectEqual(@as(usize, 1), n_installed);
}

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
    const saved = defaults();
    defer saved.put();
    const before = try systemArrow();
    defer cursors.restore();
    defer cursors.free();
    // simule un lancement précédent arrêté de force, avec des curseurs de 80 px restés en place
    cursors.load(if (before.width == 80) 96 else 80);
    cursors.apply(true);
    try testing.expect((try systemArrow()).width != before.width);

    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    // la flèche affichée sur un fond clair : AutoCurseur ne recolore que le curseur affiché
    const s = try Surface.open(LIGHT, ID_ARROW);
    defer s.close();
    const p = try Proc.startReady();
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

    const p = try Proc.startReady();
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
    // pointeur agrandi : Windows fabrique des curseurs bien plus grands (90 ms à la taille maximale)
    const limit_ms = 20 * @as(f64, @floatFromInt(cursors.base)) / 32;
    h.report("bascule complète des 17 curseurs", r.wall_us / 1000, "ms", limit_ms);
    try testing.expect(r.wall_us / 1000 < limit_ms);
}

test "système : l'exécutable bascule, consomme peu, reste unique et se ferme proprement" {
    try skipIfRunning();
    const saved = defaults();
    defer saved.put();
    const before = try systemArrow();
    defer cursors.free();
    cursors.load(cursors.systemSize());
    const black = try h.stats(cursors.black[0]);
    const white = try h.stats(cursors.white[0]);
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    // la flèche affichée sur un fond clair : AutoCurseur ne recolore que le curseur affiché
    const s = try Surface.open(LIGHT, ID_ARROW);
    defer s.close();

    const p = try Proc.startReady();
    defer p.kill();
    defer cursors.restore(); // filet de sécurité si le test échoue en route

    // 1. au bout d'un moment, la fenêtre cachée existe et la flèche est noire sur le fond
    // clair ; le fond devient sombre : elle devient blanche, puis noire à nouveau
    w.Sleep(1500);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    try testing.expect((try systemArrow()).sameImage(black));
    s.paint(DARK);
    _ = try waitImage(ID_ARROW, white, 3000);
    s.paint(LIGHT);
    _ = try waitImage(ID_ARROW, black, 3000);

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

test "système : l'exécutable recolore aussitôt la forme de pointeur qui apparaît" {
    try skipIfRunning();
    const saved = defaults();
    defer saved.put();
    const before = try systemArrow();
    cursors.restore();
    const hand_before = try h.stats(sysCursor(ID_HAND));
    defer cursors.free();
    cursors.load(cursors.systemSize());
    const A = rankOf(ID_ARROW);
    const H = rankOf(ID_HAND);
    const white_arrow = try h.stats(cursors.white[A]);
    const white_hand = try h.stats(cursors.white[H]);
    const black_hand = try h.stats(cursors.black[H]);
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    const s = try Surface.open(DARK, ID_ARROW);
    defer s.close();

    const p = try Proc.startReady();
    defer p.kill();
    defer cursors.restore();

    // fond sombre : la flèche affichée devient blanche ; la main, jamais affichée, n'a pas bougé
    _ = try waitImage(ID_ARROW, white_arrow, 3000);
    try testing.expect((try h.stats(sysCursor(ID_HAND))).sameImage(hand_before));

    // la main apparaît (survol d'un lien) : AutoCurseur, prévenu par Windows, la recolore
    try s.useCursor(ID_HAND);
    const delay = try waitImage(ID_HAND, white_hand, 1000);
    h.report("délai avant de recolorer une forme qui apparaît", @floatFromInt(delay), "ms", 100);
    try testing.expect(delay < 100);

    // fond clair : la main, affichée, devient noire ; la flèche, cachée, attend son tour
    s.paint(LIGHT);
    _ = try waitImage(ID_HAND, black_hand, 3000);
    try testing.expect((try systemArrow()).sameImage(white_arrow));

    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
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

    const p = try Proc.startReady();
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

    const p = try Proc.startReady();
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
/// amplitude totale `amp` px autour de `c`) pendant `ms` millisecondes. La position suit
/// le temps réellement écoulé : Sleep(10) peut durer 15,6 ms selon la machine.
fn shakeMouse(c: core.Point, amp: i32, hz: f32, ms: u32) void {
    const t0 = w.GetTickCount();
    while (true) {
        const t = w.GetTickCount() -% t0;
        if (t >= ms) break;
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
    // la flèche affichée, sur toute l'amplitude des va-et-vient
    const s = try Surface.open(LIGHT, ID_ARROW);
    defer s.close();

    const p = try Proc.startReady();
    defer p.kill();
    defer cursors.restore();
    w.Sleep(1500);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;

    // 1. va-et-vient franc (4 par seconde, 6 fois la taille du curseur) pendant 2 s
    const amp = @min(6 * size, w.GetSystemMetrics(w.SM_CXSCREEN) - 40);
    const per_us = h.cyclesPerUs();
    const cyc0 = h.processCycles(p.pi.hProcess);
    shakeMouse(c, amp, 4, 2000);
    const cpu_ms = @as(f64, @floatFromInt(h.processCycles(p.pi.hProcess) - cyc0)) / per_us / 1000;
    const big = h.redStats(w.LoadCursorW(null, w.IDC_ARROW)) catch |e| {
        std.debug.print("  la flèche affichée n'est pas le curseur rouge ({s})\n", .{@errorName(e)});
        return e;
    };
    h.report("taille de la flèche en secouant", @floatFromInt(big.width), "px", @floatFromInt(core.bigSizeFor(size, cursors.base)));
    // pointeur agrandi : chaque changement de curseur coûte bien plus à Windows (voir README)
    const cpu_limit = 200 * @as(f64, @floatFromInt(cursors.base)) / 32;
    h.report("processeur pendant 2 s de secousse", cpu_ms, "ms", cpu_limit);
    try testing.expectEqual(core.bigSizeFor(size, cursors.base), big.width);
    try testing.expect(big.red_px > 0);
    try testing.expect(cpu_ms < cpu_limit); // taille 1 : moins de 10 % d'un cœur

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

    // 4. un va-et-vient vif mais court (2 fois la taille du curseur) ne déclenche rien non plus
    shakeMouse(c, 2 * size, 4, 2000);
    const brisk = try systemArrow();
    try testing.expect(brisk.sameImage(black) or brisk.sameImage(white));

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
    const s = try Surface.open(LIGHT, ID_ARROW);
    defer s.close();

    const p = try Proc.startReady();
    defer p.kill();
    defer cursors.restore();
    w.Sleep(1500);
    shakeMouse(c, @min(6 * size, w.GetSystemMetrics(w.SM_CXSCREEN) - 40), 4, 2000);
    const now = try systemArrow();
    try testing.expect(now.sameImage(black) or now.sameImage(white));

    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
}

// ---------------------------------------------------------------------
// Plusieurs écrans d'agrandissements différents
// ---------------------------------------------------------------------

extern "kernel32" fn GetExitCodeProcess(w.HANDLE, *u32) callconv(.winapi) w.BOOL;

/// Forme du pointeur affichée, capturée par tests/tools/ptrcap.c.
const Shape = struct {
    kind: u32, // 1 monochrome, 2 couleur, 4 couleur masquée
    width: u32,
    height: u32,
    pitch: u32,
    hot_x: i32,
    hot_y: i32,
    /// identifiant du curseur système affiché (32512 pour la flèche…), 0 si inconnu
    id: u32,
    bits: []u8,

    fn deinit(s: Shape) void {
        testing.allocator.free(s.bits);
    }
};

/// Place la souris en `p` et capture la forme du pointeur sur l'écran qui contient ce point.
fn captureAt(p: core.Point) !Shape {
    var tmp: [w.MAX_PATH]u16 = undefined;
    const n = w.GetEnvironmentVariableW(L("TEMP"), &tmp, tmp.len);
    const tmp8 = try std.unicode.utf16LeToUtf8Alloc(testing.allocator, tmp[0..n]);
    defer testing.allocator.free(tmp8);
    const out = try std.fmt.allocPrint(testing.allocator, "{s}\\autocurseur-ptrcap", .{tmp8});
    defer testing.allocator.free(out);
    const cmd8 = try std.fmt.allocPrint(testing.allocator, "\"{s}\" {d} {d} \"{s}\"", .{ options.ptrcap_path, p.x, p.y, out });
    defer testing.allocator.free(cmd8);
    const cmd = try std.unicode.utf8ToUtf16LeAllocZ(testing.allocator, cmd8);
    defer testing.allocator.free(cmd);

    var si: w.STARTUPINFOW = .{};
    var pi: w.PROCESS_INFORMATION = .{};
    if (w.CreateProcessW(null, cmd.ptr, null, null, 0, 0, null, null, &si, &pi) == 0) return error.CreateProcess;
    defer _ = w.CloseHandle(pi.hProcess);
    defer _ = w.CloseHandle(pi.hThread);
    if (w.WaitForSingleObject(pi.hProcess, 20_000) != w.WAIT_OBJECT_0) return error.CaptureTropLongue;
    var code: u32 = 1;
    _ = GetExitCodeProcess(pi.hProcess, &code);
    if (code != 0) return error.CaptureImpossible;

    const txt_path = try std.fmt.allocPrint(testing.allocator, "{s}.txt", .{out});
    defer testing.allocator.free(txt_path);
    const bin_path = try std.fmt.allocPrint(testing.allocator, "{s}.bin", .{out});
    defer testing.allocator.free(bin_path);
    const txt16 = try std.unicode.utf8ToUtf16LeAllocZ(testing.allocator, txt_path);
    defer testing.allocator.free(txt16);
    const bin16 = try std.unicode.utf8ToUtf16LeAllocZ(testing.allocator, bin_path);
    defer testing.allocator.free(bin16);
    const txt = try h.readFile(txt16.ptr);
    defer testing.allocator.free(txt);
    var it = std.mem.tokenizeAny(u8, txt, " \r\n");
    var v: [7]i64 = undefined;
    for (&v) |*x| x.* = try std.fmt.parseInt(i64, it.next() orelse return error.Format, 10);
    return .{
        .kind = @intCast(v[0]),
        .width = @intCast(v[1]),
        .height = @intCast(v[2]),
        .pitch = @intCast(v[3]),
        .hot_x = @intCast(v[4]),
        .hot_y = @intCast(v[5]),
        .id = @intCast(v[6]),
        .bits = try h.readFile(bin16.ptr),
    };
}

/// Même pixel ? `file` a ses couleurs telles quelles (alpha à part), `shown` peut les avoir
/// prémultipliées par l'alpha (forme donnée à l'affichage) : à 1 près par arrondi.
fn samePixel(file: u32, shown: u32) bool {
    if (file == shown) return true;
    const a = file >> 24;
    if (a != shown >> 24) return false;
    inline for (.{ 16, 8, 0 }) |sh| {
        const pm = ((file >> sh) & 255) * a / 255;
        const d = @as(i32, @intCast(pm)) - @as(i32, @intCast((shown >> sh) & 255));
        if (d < -1 or d > 1) return false;
    }
    return true;
}

/// La forme capturée est-elle exactement l'image du curseur `c` (même taille, même point
/// chaud, mêmes pixels) ?
fn sameAsCursor(s: Shape, c: w.HCURSOR) !bool {
    var ii: w.ICONINFO = undefined;
    if (w.GetIconInfo(c, &ii) == 0) return error.GetIconInfo;
    defer _ = w.DeleteObject(ii.hbmMask);
    defer if (ii.hbmColor) |col| {
        _ = w.DeleteObject(col);
    };
    if (ii.xHotspot != s.hot_x or ii.yHotspot != s.hot_y) return false;
    if (ii.hbmColor) |col| {
        // couleur : pixels BGRA de haut en bas, comparés ligne par ligne
        if (s.kind != 2) return false;
        const n = s.width * s.height;
        const px = try testing.allocator.alloc(u32, n);
        defer testing.allocator.free(px);
        var bi = w.bmi(@intCast(s.width), @intCast(s.height));
        const dc = w.GetDC(null);
        defer _ = w.ReleaseDC(null, dc);
        if (w.GetDIBits(dc, col, 0, s.height, @ptrCast(px.ptr), &bi, w.DIB_RGB_COLORS) == 0) return error.GetDIBits;
        for (0..s.height) |y| {
            for (0..s.width) |x| {
                const shown = std.mem.readInt(u32, s.bits[y * s.pitch + x * 4 ..][0..4], .little);
                if (!samePixel(px[y * s.width + x], shown)) return false;
            }
        }
        return true;
    }
    // monochrome : masque ET puis OU exclusif, de haut en bas, comparés ligne par ligne
    if (s.kind != 1) return false;
    var bm: w.BITMAP = undefined;
    _ = w.GetObjectW(ii.hbmMask, @sizeOf(w.BITMAP), &bm);
    if (bm.bmWidth != s.width or bm.bmHeight != s.height * 2) return false;
    const stride: usize = @intCast(bm.bmWidthBytes);
    const mask = try testing.allocator.alloc(u8, stride * s.height * 2);
    defer testing.allocator.free(mask);
    _ = w.GetBitmapBits(ii.hbmMask, @intCast(mask.len), @ptrCast(mask.ptr));
    const row_bytes = s.width / 8;
    for (0..s.height * 2) |y| {
        if (!std.mem.eql(u8, mask[y * stride ..][0..row_bytes], s.bits[y * s.pitch ..][0..row_bytes])) return false;
    }
    return true;
}

test "système : sur chaque écran, le curseur affiché est l'image nette de la bonne taille, jamais étirée" {
    try skipIfRunning();
    try skipIfEnlarged();
    const ms = h.monitors();
    if (h.distinctDpis(ms) < 2) {
        std.debug.print("  un seul agrandissement d'écran : test ignoré\n", .{});
        return error.SkipZigTest;
    }
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    defer cursors.restore();
    defer cursors.free();

    // référence : la taille que Windows donne à ses propres curseurs sur chaque écran
    cursors.restore();
    var ref: [8]u32 = undefined;
    for (ms, 0..) |m, i| {
        const s = try captureAt(m.center);
        defer s.deinit();
        ref[i] = s.width;
        std.debug.print("  écran à {d} DPI : curseur de Windows de {d} px\n", .{ m.dpi, s.width });
    }

    // curseurs classiques, puis (Windows 11) ceux dessinés à partir des dessins vectoriels
    defer cursors.useVector(false);
    for ([_]bool{ false, true }) |vector| {
        if (vector) {
            if (!cursors.hasVectorShapes()) continue;
            _ = cursors.prepareVector(true);
        }
        cursors.useVector(vector);
        cursors.restore(); // la taille se mesure sur la flèche de Windows, pas sur notre rouge
        cursors.load(cursors.systemSize());
        for ([_]cursors.Set{ .black, .white, .red }) |set| {
            switch (set) {
                .black => cursors.apply(true),
                .white => cursors.apply(false),
                .red => cursors.applyRed(),
            }
            for (ms, 0..) |m, i| {
                const s = try captureAt(m.center);
                defer s.deinit();
                const want: u32 = if (set == .red) @min(2 * ref[i], core.MAX_CUR) else ref[i];
                // le curseur affiché dépend de la fenêtre sous la souris : on compare avec le
                // fichier de celui-là (flèche, sélection de texte, main…)
                const idx = for (cursors.defs, 0..) |d, k| {
                    if (d.id == s.id) break k;
                } else {
                    std.debug.print("  écran à {d} DPI : curseur propre à l'application sous la souris ({d})\n", .{ m.dpi, s.id });
                    return error.CurseurInconnu;
                };
                std.debug.print("  {s}jeu {s}, écran à {d} DPI : curseur {d}, {d} px (attendu {d})\n", .{ if (vector) "vectoriel, " else "", @tagName(set), m.dpi, s.id, s.width, want });
                try testing.expectEqual(want, s.width);
                const file_cursor = cursors.loadOne(set, idx, @intCast(s.width)) orelse return error.Chargement;
                defer _ = w.DestroyCursor(file_cursor);
                try testing.expect(try sameAsCursor(s, file_cursor));
            }
        }
    }
}

// ---------------------------------------------------------------------
// Changement de la taille du pointeur (Paramètres > Accessibilité)
// ---------------------------------------------------------------------

extern "user32" fn SendMessageTimeoutW(w.HWND, u32, usize, isize, u32, u32, ?*usize) callconv(.winapi) isize;
const SMTO_ABORTIFHUNG = 0x0002;
/// Notification envoyée par les Paramètres quand on déplace le curseur « Taille » du pointeur.
const SPI_CURSOR_SIZE_CHANGED = 0x2029;

/// La fenêtre répond-elle en moins d'une seconde ?
fn responds(hwnd: w.HWND) bool {
    var r: usize = 0;
    return SendMessageTimeoutW(hwnd, w.WM_NULL, 0, 0, SMTO_ABORTIFHUNG, 1000, &r) != 0;
}

test "système : après un changement de taille du pointeur, les curseurs reviennent même si Windows repasse après sa notification" {
    try skipIfRunning();
    const saved = defaults();
    defer saved.put();
    const before = try systemArrow();
    defer cursors.free();
    cursors.load(cursors.systemSize());
    const black = try h.stats(cursors.black[0]);
    const white = try h.stats(cursors.white[0]);
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    // la flèche affichée sur un fond clair : AutoCurseur ne recolore que le curseur affiché
    const s = try Surface.open(LIGHT, ID_ARROW);
    defer s.close();

    const p = try Proc.startReady();
    defer p.kill();
    defer cursors.restore();
    w.Sleep(1500);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    const ours = try systemArrow();
    errdefer std.debug.print("  flèche au départ : {any}\n  noire : {any}\n  blanche : {any}\n  de Windows : {any}\n", .{ ours, black, white, before });
    try testing.expect(ours.sameImage(black) or ours.sameImage(white));

    // Ce que font les Paramètres : la notification, puis Windows remet ses propres curseurs
    // un peu plus tard, sans rien dire (observé sur Windows 11 avec le curseur « Taille »).
    var r: usize = 0;
    _ = SendMessageTimeoutW(hwnd, w.WM_SETTINGCHANGE, SPI_CURSOR_SIZE_CHANGED, 0, SMTO_ABORTIFHUNG, 2000, &r);
    w.Sleep(300);
    cursors.restore();
    try testing.expect((try systemArrow()).sameImage(before));

    // AutoCurseur reste réactif pendant tout ce temps, puis remet les siens
    var t: u32 = 0;
    while (t < 4000) : (t += 250) {
        if (!responds(hwnd)) {
            std.debug.print("  AutoCurseur ne répond plus {d} ms après la notification\n", .{t});
            return error.NeRepondPlus;
        }
        w.Sleep(250);
    }
    const now = try systemArrow();
    errdefer std.debug.print("  flèche 4 s après : {any}\n", .{now});
    try testing.expect(now.sameImage(black) or now.sameImage(white));

    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
    try testing.expect((try systemArrow()).sameImage(before));
}

test "système : une rafale de notifications (curseur « Taille » qu'on fait glisser) ne bloque pas AutoCurseur" {
    try skipIfRunning();
    const saved = defaults();
    defer saved.put();
    defer cursors.free();
    cursors.load(cursors.systemSize());
    const black = try h.stats(cursors.black[0]);
    const white = try h.stats(cursors.white[0]);
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    // la flèche affichée sur un fond clair : AutoCurseur ne recolore que le curseur affiché
    const s = try Surface.open(LIGHT, ID_ARROW);
    defer s.close();

    const p = try Proc.startReady();
    defer p.kill();
    defer cursors.restore();
    w.Sleep(1500);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;

    // 10 notifications à 400 ms d'intervalle, avec Windows qui remet ses curseurs entre deux
    for (0..10) |_| {
        var r: usize = 0;
        try testing.expect(SendMessageTimeoutW(hwnd, w.WM_SETTINGCHANGE, SPI_CURSOR_SIZE_CHANGED, 0, SMTO_ABORTIFHUNG, 2000, &r) != 0);
        w.Sleep(200);
        cursors.restore();
        w.Sleep(200);
        try testing.expect(responds(hwnd));
    }
    w.Sleep(3500);
    const now = try systemArrow();
    try testing.expect(now.sameImage(black) or now.sameImage(white));

    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
}

// ---------------------------------------------------------------------
// Pointeur agrandi (Paramètres > Accessibilité) : curseurs vectoriels
// ---------------------------------------------------------------------

/// Pixel (x, y) visible dans une forme monochrome capturée.
fn shapeVisible(s: Shape, x: usize, y: usize) bool {
    const a = (s.bits[y * s.pitch + x / 8] >> @intCast(7 - x % 8)) & 1;
    const c = (s.bits[(y + s.height) * s.pitch + x / 8] >> @intCast(7 - x % 8)) & 1;
    return !(a == 1 and c == 0);
}

test "système : pointeur agrandi, nos curseurs ont la taille et la forme de ceux de Windows sur chaque écran" {
    try skipIfRunning();
    if (cursors.pointerBase() <= 32) {
        std.debug.print("  pointeur en taille 1 : test ignoré (agrandissez-le dans les Paramètres pour le lancer)\n", .{});
        return error.SkipZigTest;
    }
    if (!cursors.hasVectorShapes()) return error.SkipZigTest;
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    defer cursors.restore();
    defer cursors.useVector(false);
    defer cursors.free();

    const ms = h.monitors();
    var theirs: [8]?Shape = @splat(null);
    defer for (theirs) |t| if (t) |s| s.deinit();
    cursors.restore();
    for (ms, 0..) |m, i| {
        theirs[i] = captureAt(m.center) catch |e| {
            // au-delà de 255 px, Windows dessine le pointeur lui-même dans l'image de l'écran :
            // il ne fournit plus de forme à comparer
            std.debug.print("  écran à {d} DPI : pas de forme de pointeur fournie ({s}), pointeur trop grand : test ignoré\n", .{ m.dpi, @errorName(e) });
            return error.SkipZigTest;
        };
    }

    _ = cursors.prepareVector(false);
    cursors.useVector(true);
    cursors.load(cursors.systemSize());
    cursors.apply(true);
    for (ms, 0..) |m, i| {
        const ours = try captureAt(m.center);
        defer ours.deinit();
        const win = theirs[i].?;
        std.debug.print("  écran à {d} DPI : Windows {d} px (curseur {d}), nous {d} px (curseur {d})\n", .{ m.dpi, win.width, win.id, ours.width, ours.id });
        try testing.expectEqual(win.width, ours.width);
        if (win.id != ours.id or win.kind != 1 or ours.kind != 1) continue; // fenêtre différente sous la souris
        var visible: usize = 0;
        var diff: usize = 0;
        for (0..win.height) |y| {
            for (0..win.width) |x| {
                const a = shapeVisible(win, x, y);
                if (a) visible += 1;
                if (a != shapeVisible(ours, x, y)) diff += 1;
            }
        }
        std.debug.print("    forme : {d} pixels de différence sur {d}\n", .{ diff, visible });
        try testing.expect(diff * 100 <= visible * 3);
    }
}

test "système : pendant que la souris bouge, AutoCurseur répond toujours vite (lectures d'écran sur un fil à part)" {
    try skipIfRunning();
    const saved = defaults();
    defer saved.put();
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    const c: core.Point = .{ .x = @divTrunc(w.GetSystemMetrics(w.SM_CXSCREEN), 2), .y = @divTrunc(w.GetSystemMetrics(w.SM_CYSCREEN), 2) };
    _ = w.SetCursorPos(c.x + 7, c.y);
    var pos: core.Point = .{};
    _ = w.GetCursorPos(&pos);
    if (pos.x != c.x + 7) return error.SkipZigTest;

    const p = try Proc.startReady();
    defer p.kill();
    defer cursors.restore();
    w.Sleep(1500);
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;

    // 3 s de déplacements sur toute la largeur de l'écran (fonds variés, bascules), avec une
    // question toutes les 50 ms à la fenêtre d'AutoCurseur
    const width = w.GetSystemMetrics(w.SM_CXSCREEN);
    var worst: u32 = 0;
    var t: i32 = 0;
    while (t < 60) : (t += 1) {
        _ = w.SetCursorPos(@mod(t * 97, width), c.y + @mod(t * 53, 300) - 150);
        const t0 = w.GetTickCount();
        try testing.expect(responds(hwnd));
        worst = @max(worst, w.GetTickCount() -% t0);
        w.Sleep(50);
    }
    // pointeur agrandi : une bascule coûte jusqu'à 90 ms à Windows, sur le fil principal
    h.report("attente la plus longue d'une réponse", @floatFromInt(worst), "ms", 250);
    try testing.expect(worst < 250);

    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
}

// ---------------------------------------------------------------------
// Couleurs des curseurs
// ---------------------------------------------------------------------

/// Attend (au plus `ms`) que le curseur du système `id` ait au moins 20 pixels exactement de
/// la couleur `rgb` ; renvoie le délai.
fn waitColor(id: u32, rgb: u32, ms: u32) !u32 {
    const t0 = w.GetTickCount();
    while (true) {
        const t = w.GetTickCount() -% t0;
        if ((h.colorCount(sysCursor(id), rgb) catch 0) > 20) return t;
        if (t > ms) return error.CouleurAttendueAbsente;
        w.Sleep(5);
    }
}

/// Remet en noir et blanc les fichiers de curseurs de l'application : l'exécutable lancé par
/// un test a pu les refaire à d'autres couleurs.
fn restoreFiles() void {
    _ = cursors.useDefaultDir(); // oublie ce qui était prêt
    _ = cursors.prepare(true);
}

test "système : réglages de couleurs enregistrés et relus, un couple invalide est refusé" {
    const saved = defaults();
    defer saved.put();
    const pair = core.PRESETS[1];
    try testing.expect(settings.loadColors().eql(.{}));
    settings.saveColors(pair);
    try testing.expect(settings.loadColors().eql(pair));
    try testing.expectEqual(@as(?u32, pair.dark), settings.readDword(settings.DARK_VALUE));
    try testing.expectEqual(@as(?u32, pair.light), settings.readDword(settings.LIGHT_VALUE));
    // un couple refusé n'est pas enregistré
    settings.saveColors(.{ .dark = core.WHITE, .light = core.BLACK });
    try testing.expect(settings.loadColors().eql(pair));
    // valeurs incohérentes écrites à la main dans le registre : noir et blanc
    settings.writeDword(settings.DARK_VALUE, 0xFFFF00);
    try testing.expect(settings.loadColors().eql(.{}));
    settings.writeDword(settings.DARK_VALUE, 0xFFFFFFFF);
    try testing.expect(settings.loadColors().eql(.{}));
    // une seule valeur enregistrée : l'autre garde sa couleur par défaut
    settings.reset();
    settings.writeDword(settings.LIGHT_VALUE, pair.light);
    try testing.expect(settings.loadColors().eql(.{ .light = pair.light }));
}

test "système : un couple de couleurs choisi dans le menu est appliqué tout de suite, mémorisé, et repris au lancement suivant" {
    try skipIfRunning();
    const saved = defaults();
    defer saved.put();
    defer restoreFiles();
    const before = try systemArrow();
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    const s = try Surface.open(LIGHT, ID_ARROW);
    defer s.close();
    const pair = core.PRESETS[1]; // bleu nuit / jaune

    const p = try Proc.startReady();
    defer p.kill();
    defer cursors.restore();
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    _ = try waitColor(ID_ARROW, core.BLACK, 3000); // noir sur le fond clair, au départ

    // même chemin qu'un clic dans le sous-menu « Couleurs »
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, settings.COLOR_MENU_BASE + 1, 0);
    const delay = try waitColor(ID_ARROW, pair.dark, 3000);
    h.report("délai pour changer de couleurs depuis le menu", @floatFromInt(delay), "ms", 3000);
    try testing.expect(settings.loadColors().eql(pair));
    try testing.expectEqual(@as(usize, 0), try h.colorCount(sysCursor(ID_ARROW), core.BLACK));
    // fond sombre : la couleur claire du couple
    s.paint(DARK);
    _ = try waitColor(ID_ARROW, pair.light, 3000);
    // une entrée de menu inconnue ne change rien
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, settings.COLOR_MENU_BASE + core.PRESETS.len, 0);
    w.Sleep(200);
    try testing.expect(settings.loadColors().eql(pair));
    // fermeture : le curseur d'origine revient
    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
    try testing.expect((try systemArrow()).sameImage(before));

    // relancé : les couleurs enregistrées sont reprises (le fond est toujours sombre)
    const p2 = try Proc.startReady();
    defer p2.kill();
    _ = try waitColor(ID_ARROW, pair.light, 3000);
    s.paint(LIGHT);
    _ = try waitColor(ID_ARROW, pair.dark, 3000);
    // retour au noir et blanc depuis le menu
    const hwnd2 = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;
    _ = w.PostMessageW(hwnd2, w.WM_COMMAND, settings.COLOR_MENU_BASE, 0);
    _ = try waitColor(ID_ARROW, core.BLACK, 3000);
    try testing.expect(settings.loadColors().eql(.{}));
    _ = w.PostMessageW(hwnd2, w.WM_CLOSE, 0, 0);
    try testing.expect(p2.exitedWithin(5000));
    try testing.expect((try systemArrow()).sameImage(before));
}

extern "user32" fn GetDlgItem(w.HWND, c_int) callconv(.winapi) w.HWND;
const WM_SETTEXT = 0x000C;
const IDOK = 1;
const IDCANCEL = 2;
/// Champs « rouge », « vert », « bleu » du sélecteur de couleur de Windows (colordlg.h).
const COLOR_RED = 706;
const COLOR_GREEN = 707;
const COLOR_BLUE = 708;

/// Attend (au plus `ms`) une boîte de dialogue de Windows portant ce titre.
fn waitDialog(title: [*:0]const u16, ms: u32) ?w.HWND {
    const t0 = w.GetTickCount();
    while (w.GetTickCount() -% t0 < ms) {
        if (w.FindWindowW(L("#32770"), title)) |d| return d;
        w.Sleep(20);
    }
    return null;
}

/// Attend (au plus `ms`) qu'il n'y ait plus de boîte de dialogue portant ce titre.
fn dialogGone(title: [*:0]const u16, ms: u32) bool {
    const t0 = w.GetTickCount();
    while (w.GetTickCount() -% t0 < ms) {
        if (w.FindWindowW(L("#32770"), title) == null) return true;
        w.Sleep(20);
    }
    return false;
}

/// Écrit `value` dans le champ `id` du sélecteur de couleur, comme au clavier.
fn typeField(dlg: w.HWND, id: c_int, value: u8) !void {
    var txt: [8]u8 = undefined;
    const s = try std.fmt.bufPrint(&txt, "{d}", .{value});
    var wide: [8:0]u16 = @splat(0);
    for (s, 0..) |c, i| wide[i] = c;
    const field = GetDlgItem(dlg, id) orelse return error.ChampIntrouvable;
    var r: usize = 0;
    if (SendMessageTimeoutW(field, WM_SETTEXT, 0, @bitCast(@intFromPtr(&wide)), SMTO_ABORTIFHUNG, 2000, &r) == 0) return error.ChampSansReponse;
}

/// Choisit la couleur `rgb` dans le sélecteur ouvert et valide.
fn chooseColor(dlg: w.HWND, rgb: u32) !void {
    try typeField(dlg, COLOR_RED, @intCast((rgb >> 16) & 255));
    try typeField(dlg, COLOR_GREEN, @intCast((rgb >> 8) & 255));
    try typeField(dlg, COLOR_BLUE, @intCast(rgb & 255));
    _ = w.PostMessageW(dlg, w.WM_COMMAND, IDOK, 0);
}

/// Attend (au plus `ms`) que les couleurs enregistrées soient `want`.
fn waitSavedColors(want: core.Colors, ms: u32) bool {
    const t0 = w.GetTickCount();
    while (w.GetTickCount() -% t0 < ms) {
        if (settings.loadColors().eql(want)) return true;
        w.Sleep(20);
    }
    return false;
}

test "système : couleur personnalisée choisie dans le sélecteur de Windows ; trop proche de l'autre, elle est refusée" {
    try skipIfRunning();
    const saved = defaults();
    defer saved.put();
    defer restoreFiles();
    const text = app.i18n.text(app.i18n.resolve(.auto, w.GetUserDefaultUILanguage()));
    const navy: u32 = 0x00205B;

    const p = try Proc.startReady();
    defer p.kill();
    defer cursors.restore();
    const hwnd = w.FindWindowW(L("AutoCurseur"), null) orelse return error.FenetreIntrouvable;

    // 1. couleur sur fond clair : le sélecteur s'ouvre, titré, centré sur la souris et
    // entièrement visible sur son écran, et AutoCurseur continue de répondre
    var orig: core.Point = .{};
    _ = w.GetCursorPos(&orig);
    defer _ = w.SetCursorPos(orig.x, orig.y);
    const c: core.Point = .{ .x = @divTrunc(w.GetSystemMetrics(w.SM_CXSCREEN), 2), .y = @divTrunc(w.GetSystemMetrics(w.SM_CYSCREEN), 2) };
    _ = w.SetCursorPos(c.x, c.y);
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, settings.MENU_COLOR_DARK, 0);
    const dlg = waitDialog(text.pick_dark_title.ptr, 5000) orelse return error.SelecteurAbsent;
    var mouse: core.Point = .{};
    _ = w.GetCursorPos(&mouse);
    var mi: w.MONITORINFO = .{};
    _ = w.GetMonitorInfoW(w.MonitorFromPoint(mouse, w.MONITOR_DEFAULTTONEAREST), &mi);
    var r: w.RECT = undefined;
    _ = w.GetWindowRect(dlg, &r);
    errdefer std.debug.print("  sélecteur en {d},{d} - {d},{d} ; zone de travail {d},{d} - {d},{d}\n", .{ r.left, r.top, r.right, r.bottom, mi.rcWork.left, mi.rcWork.top, mi.rcWork.right, mi.rcWork.bottom });
    try testing.expect(r.left >= mi.rcWork.left and r.top >= mi.rcWork.top and r.right <= mi.rcWork.right and r.bottom <= mi.rcWork.bottom);
    if (mouse.x == c.x and mouse.y == c.y) { // la souris a pu être déplacée : le sélecteur est centré dessus
        try testing.expect(@abs(@divTrunc(r.left + r.right, 2) - c.x) <= 2);
        try testing.expect(@abs(@divTrunc(r.top + r.bottom, 2) - c.y) <= 2);
    }
    try testing.expect(responds(hwnd));
    // une deuxième demande pendant que le sélecteur est ouvert n'en ouvre pas un autre
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, settings.MENU_COLOR_LIGHT, 0);
    try testing.expect(waitDialog(text.pick_light_title.ptr, 500) == null);
    try chooseColor(dlg, navy);
    try testing.expect(waitSavedColors(.{ .dark = navy }, 3000));
    try testing.expect(dialogGone(text.pick_dark_title.ptr, 3000));

    // 2. couleur sur fond sombre trop sombre : message, et rien ne change
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, settings.MENU_COLOR_LIGHT, 0);
    const dlg2 = waitDialog(text.pick_light_title.ptr, 5000) orelse return error.SelecteurAbsent;
    try chooseColor(dlg2, 0x000080);
    const box = waitDialog(L("AutoCurseur"), 5000) orelse return error.MessageAbsent;
    try testing.expect(settings.loadColors().eql(.{ .dark = navy }));
    _ = w.PostMessageW(box, w.WM_CLOSE, 0, 0);
    try testing.expect(dialogGone(L("AutoCurseur"), 3000));

    // 3. une couleur claire valide est acceptée
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, settings.MENU_COLOR_LIGHT, 0);
    const dlg3 = waitDialog(text.pick_light_title.ptr, 5000) orelse return error.SelecteurAbsent;
    try chooseColor(dlg3, 0xFFE600);
    try testing.expect(waitSavedColors(.{ .dark = navy, .light = 0xFFE600 }, 3000));

    // 4. annuler ne change rien
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, settings.MENU_COLOR_DARK, 0);
    const dlg4 = waitDialog(text.pick_dark_title.ptr, 5000) orelse return error.SelecteurAbsent;
    _ = w.PostMessageW(dlg4, w.WM_COMMAND, IDCANCEL, 0);
    try testing.expect(dialogGone(text.pick_dark_title.ptr, 3000));
    try testing.expect(settings.loadColors().eql(.{ .dark = navy, .light = 0xFFE600 }));

    // 5. quitter pendant que le sélecteur est ouvert : tout se ferme proprement
    _ = w.PostMessageW(hwnd, w.WM_COMMAND, settings.MENU_COLOR_DARK, 0);
    _ = waitDialog(text.pick_dark_title.ptr, 5000) orelse return error.SelecteurAbsent;
    _ = w.PostMessageW(hwnd, w.WM_CLOSE, 0, 0);
    try testing.expect(p.exitedWithin(5000));
}
