//! Jeux de curseurs noir, blanc et rouge : fabrication des fichiers, application au système.
//!
//! Les formes viennent des curseurs fournis avec Windows : son style blanc habituel, et le jeu
//! « Windows Black » pour la sélection de texte, la précision et l'attente (voir `defs`).
//! Leurs versions inversée et rouge sont écrites dans des fichiers .cur (dossier choisi par
//! `setDir`) qui gardent
//! toutes les tailles du fichier d'origine (32 à 128 px). Les curseurs sont ensuite chargés
//! depuis ces fichiers : Windows choisit alors lui-même, écran par écran, l'image de la
//! bonne taille. Un curseur fabriqué en mémoire serait au contraire étiré par Windows sur
//! un écran d'un autre agrandissement, avec un contour irrégulier.
//!
//! Quand la couleur voulue change, seul le curseur affiché est rechargé ; chacun des autres
//! l'est quand il apparaît (voir `show` et `fix`).

const std = @import("std");
const core = @import("core.zig");
const curfile = @import("curfile.zig");
const svgcur = @import("svgcur.zig");
const w = @import("win32.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const CurDef = struct { id: u32, file: []const u16, file_is_white: bool };

/// Curseurs du style blanc habituel de Windows (« Windows Aero » : bords adoucis, 32 bits) ;
/// la version noire en est le négatif. Ce style n'a pas de fichier pour la sélection de texte
/// ni pour la précision (Windows utilise alors des curseurs qui inversent l'écran) : ceux-là
/// viennent du jeu « Windows Black », comme les deux curseurs d'attente, animés dans le style
/// blanc. Les flèche et sélection de texte « Windows Black » qui se succèdent laissent une
/// trace à l'écran ; la flèche du style blanc, non.
pub const defs = blk: {
    @setEvalBranchQuota(20_000); // conversion UTF-16 des noms à la compilation
    break :blk [_]CurDef{
        .{ .id = 32512, .file = L("aero_arrow.cur"), .file_is_white = true }, // flèche normale
        .{ .id = 32513, .file = L("beam_r.cur"), .file_is_white = false }, // sélection de texte
        .{ .id = 32514, .file = L("busy_r.cur"), .file_is_white = false }, // occupé
        .{ .id = 32515, .file = L("cross_r.cur"), .file_is_white = false }, // précision
        .{ .id = 32516, .file = L("aero_up.cur"), .file_is_white = true }, // autre sélection
        .{ .id = 32631, .file = L("aero_pen.cur"), .file_is_white = true }, // stylet
        .{ .id = 32642, .file = L("aero_nwse.cur"), .file_is_white = true }, // redim. NO-SE
        .{ .id = 32643, .file = L("aero_nesw.cur"), .file_is_white = true }, // redim. NE-SO
        .{ .id = 32644, .file = L("aero_ew.cur"), .file_is_white = true }, // redim. horizontal
        .{ .id = 32645, .file = L("aero_ns.cur"), .file_is_white = true }, // redim. vertical
        .{ .id = 32646, .file = L("aero_move.cur"), .file_is_white = true }, // déplacer
        .{ .id = 32648, .file = L("aero_unavail.cur"), .file_is_white = true }, // indisponible
        .{ .id = 32649, .file = L("aero_link.cur"), .file_is_white = true }, // main (lien)
        .{ .id = 32650, .file = L("wait_r.cur"), .file_is_white = false }, // arrière-plan
        .{ .id = 32651, .file = L("aero_helpsel.cur"), .file_is_white = true }, // aide
        .{ .id = 32671, .file = L("aero_pin.cur"), .file_is_white = true }, // emplacement
        .{ .id = 32672, .file = L("aero_person.cur"), .file_is_white = true }, // personne
    };
};
pub const COUNT = defs.len;

pub const Set = enum(u2) { black, white, red };
const SET_COUNT = 3;
const prefixes = [SET_COUNT][]const u16{ L("noir-"), L("blanc-"), L("rouge-") };
/// fichiers dessinés à partir des dessins vectoriels de Windows 11 (voir svgcur.zig)
const vector_prefixes = [SET_COUNT][]const u16{ L("noir-v-"), L("blanc-v-"), L("rouge-v-") };

/// Curseurs chargés pour être examinés (tests) : l'application, elle, ne garde aucun
/// curseur en mémoire et relit les fichiers à chaque application.
pub var black: [COUNT]w.HCURSOR = @splat(null);
pub var white: [COUNT]w.HCURSOR = @splat(null);
pub var red: [COUNT]w.HCURSOR = @splat(null);
/// taille (px) des curseurs demandés à Windows, pour l'écran principal
pub var size: i32 = 0;
/// réglage « taille du pointeur » de l'accessibilité (32 = taille 1), voir pointerBase
pub var base: u32 = 32;

// Tampons de taille fixe (en .bss : seules les pages utilisées comptent).
// Le plus gros fichier lu fait 133 Ko (mains en 32 bits) ; le plus gros écrit, 233 Ko (jeu
// rouge dessiné en 240 x 240, 32 bits).
pub var src_buf: [144 * 1024]u8 align(4) = undefined;
pub var out_buf: [236 * 1024]u8 align(4) = undefined;
var svg_buf: [8 * 1024]u8 = undefined;
var mono_xor: [curfile.stride(svgcur.SIZE, 1) * svgcur.SIZE]u8 = undefined;
var mono_and: [curfile.stride(svgcur.SIZE, 1) * svgcur.SIZE]u8 = undefined;
var cmp_buf: [4096]u8 = undefined;
var windir: [w.MAX_PATH]u16 = undefined;
var windir_len: usize = 0;
var dir: [w.MAX_PATH]u16 = undefined; // dossier des fichiers fabriqués, terminé par « \ »
var dir_len: usize = 0;
var path_buf: [2 * w.MAX_PATH]u16 = undefined;
var tmp_buf: [2 * w.MAX_PATH]u16 = undefined;
/// fichier fabriqué disponible, par jeu et par curseur
var ready: [SET_COUNT][COUNT]bool = @splat(@splat(false));
var prepared: [SET_COUNT]bool = @splat(false);
/// mêmes informations pour les fichiers dessinés à partir des dessins vectoriels
var ready_v: [SET_COUNT][COUNT]bool = @splat(@splat(false));
var prepared_v: [SET_COUNT]bool = @splat(false);
/// curseurs dessinés à partir des dessins vectoriels (pointeur agrandi), sinon classiques
var vector = false;

// ---------------------------------------------------------------- tailles

/// Largeur de la flèche que Windows affiche en ce moment (0 si illisible).
/// Le processus doit gérer l'agrandissement d'écran (DPI) pour obtenir la vraie taille.
pub fn currentArrowWidth() i32 {
    var ii: w.ICONINFO = undefined;
    if (w.GetIconInfo(w.LoadCursorW(null, w.IDC_ARROW), &ii) == 0) return 0;
    defer _ = w.DeleteObject(ii.hbmMask);
    var bm: w.BITMAP = undefined;
    if (ii.hbmColor) |color| {
        defer _ = w.DeleteObject(color);
        if (w.GetObjectW(color, @sizeOf(w.BITMAP), &bm) == 0) return 0;
    } else if (w.GetObjectW(ii.hbmMask, @sizeOf(w.BITMAP), &bm) == 0) return 0;
    return bm.bmWidth;
}

/// Taille des curseurs à demander à Windows : celle de sa flèche actuelle, sinon la taille
/// standard. Le réglage « taille du pointeur » n'y figure pas : Windows l'applique lui-même
/// à l'affichage (voir pointerBase).
pub fn systemSize() i32 {
    return core.cursorSize(currentArrowWidth(), w.GetSystemMetrics(w.SM_CXCURSOR));
}

/// Réglage « taille du pointeur » de l'accessibilité (32 pour la taille 1, puis par pas de 16).
pub fn pointerBase() u32 {
    var value: u32 = 32;
    var cb: u32 = @sizeOf(u32);
    _ = w.RegGetValueW(w.HKCU, L("Control Panel\\Cursors"), L("CursorBaseSize"), w.RRF_RT_REG_DWORD, null, &value, &cb);
    return core.pointerBase(value);
}

// ---------------------------------------------------------------- fichiers

/// Choisit le dossier des fichiers fabriqués : %`env`%\`sub`\ (créé au besoin, `sub` peut
/// contenir des « \ »). Renvoie false si la variable n'existe pas ou si le dossier ne peut
/// pas être créé. Les fichiers déjà fabriqués ailleurs sont oubliés.
pub fn setDir(env: [*:0]const u16, sub: []const u16) bool {
    const n = w.GetEnvironmentVariableW(env, &dir, dir.len);
    if (n == 0 or n + sub.len + 2 >= dir.len) return false;
    var len: usize = n;
    if (dir[len - 1] != '\\') {
        dir[len] = '\\';
        len += 1;
    }
    for (sub) |c| {
        dir[len] = c;
        len += 1;
        if (c == '\\') { // dossier intermédiaire
            dir[len] = 0;
            _ = w.CreateDirectoryW(@ptrCast(&dir), null);
        }
    }
    if (dir[len - 1] != '\\') {
        dir[len] = '\\';
        len += 1;
    }
    dir[len] = 0;
    _ = w.CreateDirectoryW(@ptrCast(&dir), null);
    if (w.GetFileAttributesW(@ptrCast(&dir)) == w.INVALID_FILE_ATTRIBUTES) return false;
    dir_len = len;
    ready = @splat(@splat(false));
    prepared = @splat(false);
    ready_v = @splat(@splat(false));
    prepared_v = @splat(false);
    return true;
}

/// Dossier de l'application : %LOCALAPPDATA%\AutoCurseur\cursors, sinon sous %TEMP%.
pub fn useDefaultDir() bool {
    return setDir(L("LOCALAPPDATA"), L("AutoCurseur\\cursors")) or setDir(L("TEMP"), L("AutoCurseur\\cursors"));
}

/// Dossier actuel (terminé par « \ »), vide si aucun.
pub fn dirPath() []const u16 {
    return dir[0..dir_len];
}

fn initWindir() void {
    if (windir_len == 0) windir_len = w.GetWindowsDirectoryW(&windir, windir.len);
}

fn sourcePath(buf: []u16, i: usize) [:0]const u16 {
    initWindir();
    return core.join(buf, &.{ windir[0..windir_len], L("\\Cursors\\"), defs[i].file });
}

/// Le jeu `set` du curseur `i` est-il fourni tel quel par Windows ?
fn isNative(set: Set, i: usize) bool {
    return switch (set) {
        .black => !defs[i].file_is_white,
        .white => defs[i].file_is_white,
        .red => false,
    };
}

/// Fichier du jeu `set` pour le curseur `i` : celui de Windows ou celui fabriqué ; null si
/// le fichier fabriqué n'est pas disponible.
pub fn pathOf(set: Set, i: usize, buf: []u16) ?[:0]const u16 {
    if (vector and ready_v[@backingInt(set)][i]) return vectorPath(buf, set, i);
    if (isNative(set, i)) return sourcePath(buf, i);
    if (dir_len == 0 or !ready[@backingInt(set)][i]) return null;
    return core.join(buf, &.{ dir[0..dir_len], prefixes[@backingInt(set)], defs[i].file });
}

/// Lit tout le fichier `path` dans `buf` ; null s'il n'existe pas ou dépasse le tampon.
fn readFile(path: [*:0]const u16, buf: []u8) ?usize {
    const h = w.CreateFileW(path, w.GENERIC_READ, w.FILE_SHARE_READ, null, w.OPEN_EXISTING, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == w.INVALID_HANDLE_VALUE) return null;
    defer _ = w.CloseHandle(h);
    var total: i64 = 0;
    if (w.GetFileSizeEx(h, &total) == 0 or total < 0 or total > buf.len) return null;
    var n: usize = 0;
    while (n < total) {
        var got: u32 = 0;
        if (w.ReadFile(h, buf[n..].ptr, @intCast(@as(usize, @intCast(total)) - n), &got, null) == 0 or got == 0) return null;
        n += got;
    }
    return n;
}

/// Vrai si le fichier `path` contient exactement `data`.
fn sameContent(path: [*:0]const u16, data: []const u8) bool {
    const h = w.CreateFileW(path, w.GENERIC_READ, w.FILE_SHARE_READ, null, w.OPEN_EXISTING, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == w.INVALID_HANDLE_VALUE) return false;
    defer _ = w.CloseHandle(h);
    var total: i64 = 0;
    if (w.GetFileSizeEx(h, &total) == 0 or total != data.len) return false;
    var n: usize = 0;
    while (n < data.len) {
        var got: u32 = 0;
        const want: u32 = @intCast(@min(cmp_buf.len, data.len - n));
        if (w.ReadFile(h, &cmp_buf, want, &got, null) == 0 or got == 0) return false;
        if (!std.mem.eql(u8, cmp_buf[0..got], data[n..][0..got])) return false;
        n += got;
    }
    return true;
}

/// Écrit `data` dans `path` en passant par un fichier temporaire, pour que Windows ne lise
/// jamais un fichier à moitié écrit.
fn writeFile(path: [:0]const u16, data: []const u8) bool {
    const tmp = core.join(&tmp_buf, &.{ path, L(".tmp") });
    const h = w.CreateFileW(tmp.ptr, w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == w.INVALID_HANDLE_VALUE) return false;
    var done: u32 = 0;
    const ok = w.WriteFile(h, data.ptr, @intCast(data.len), &done, null) != 0 and done == data.len;
    _ = w.CloseHandle(h);
    if (ok and w.MoveFileExW(tmp.ptr, path.ptr, w.MOVEFILE_REPLACE_EXISTING) != 0) return true;
    _ = w.DeleteFileW(tmp.ptr);
    return false;
}

/// Fabrique le fichier du jeu `set` pour le curseur `i` à partir de `src` (contenu du
/// fichier de Windows). Renvoie le nombre de fichiers écrits (0 s'il était déjà à jour).
fn produce(src: []const u8, set: Set, i: usize) usize {
    const op: curfile.Op = switch (set) {
        .black, .white => .invert,
        .red => if (defs[i].file_is_white) .invert_red else .red,
    };
    const s = @backingInt(set);
    ready[s][i] = false;
    const len = curfile.derive(src, op, &out_buf) orelse return 0;
    const path = core.join(&path_buf, &.{ dir[0..dir_len], prefixes[s], defs[i].file });
    if (sameContent(path.ptr, out_buf[0..len])) {
        ready[s][i] = true;
        return 0;
    }
    ready[s][i] = writeFile(path, out_buf[0..len]);
    return @intFromBool(ready[s][i]);
}

/// Fichiers fabriqués par les versions précédentes, avant que ces curseurs viennent du style
/// blanc de Windows : supprimés quand les nouveaux sont écrits.
const obsolete = blk: {
    @setEvalBranchQuota(20_000);
    break :blk [_][]const u16{
        L("arrow_r.cur"), L("up_r.cur"),    L("pen_r.cur"),  L("size1_r.cur"), L("size2_r.cur"),
        L("size3_r.cur"), L("size4_r.cur"), L("move_r.cur"), L("no_r.cur"),    L("help_r.cur"),
    };
};

fn removeObsolete() void {
    for (obsolete) |f| {
        for (prefixes) |pre| _ = w.DeleteFileW(core.join(&path_buf, &.{ dir[0..dir_len], pre, f }).ptr);
    }
}

/// Fabrique les fichiers qui ne sont pas fournis tels quels par Windows : la version
/// inversée des jeux noir et blanc, et le jeu rouge si `with_red`. Un fichier déjà à jour
/// n'est pas réécrit. Renvoie le nombre de fichiers écrits.
pub fn prepare(with_red: bool) usize {
    if (dir_len == 0 and !useDefaultDir()) return 0;
    var written: usize = 0;
    for (defs, 0..) |d, i| {
        const n = readFile(sourcePath(&path_buf, i).ptr, &src_buf) orelse continue;
        const src = src_buf[0..n];
        written += produce(src, if (d.file_is_white) .black else .white, i);
        if (with_red) written += produce(src, .red, i);
    }
    // de nouveaux fichiers écrits : peut-être une mise à jour, les anciens ne servent plus
    if (written > 0) removeObsolete();
    prepared[@backingInt(Set.black)] = true;
    prepared[@backingInt(Set.white)] = true;
    if (with_red) prepared[@backingInt(Set.red)] = true;
    return written;
}

// ---------------------------------------------------------------- dessins vectoriels

fn vectorPath(buf: []u16, set: Set, i: usize) [:0]const u16 {
    return core.join(buf, &.{ dir[0..dir_len], vector_prefixes[@backingInt(set)], svgcur.shapes[i].name, L(".cur") });
}

/// Windows fournit-il ses dessins vectoriels de curseurs (Windows 11) ?
pub fn hasVectorShapes() bool {
    initWindir();
    const p = core.join(&path_buf, &.{ windir[0..windir_len], L("\\Cursors\\arrow.svg") });
    return w.GetFileAttributesW(p.ptr) != w.INVALID_FILE_ATTRIBUTES;
}

/// Écrit `data` comme fichier vectoriel du jeu `set` pour le curseur `i`, s'il a changé.
/// Renvoie le nombre de fichiers écrits.
fn storeVector(set: Set, i: usize, data: []const u8) usize {
    const s = @backingInt(set);
    const path = vectorPath(&path_buf, set, i);
    if (sameContent(path.ptr, data)) {
        ready_v[s][i] = true;
        return 0;
    }
    ready_v[s][i] = writeFile(path, data);
    return @intFromBool(ready_v[s][i]);
}

/// Fabrique les fichiers des jeux noir et blanc (et rouge si `with_red`) à partir des dessins
/// vectoriels de Windows 11, comme Windows pour ses pointeurs agrandis (voir svgcur.zig).
/// Direct2D n'est chargé que pendant ce travail. Ne refait rien de ce qui est déjà prêt.
/// Renvoie le nombre de fichiers écrits.
pub fn prepareVector(with_red: bool) usize {
    const need_bw = !prepared_v[@backingInt(Set.black)];
    const need_red = with_red and !prepared_v[@backingInt(Set.red)];
    if (!need_bw and !need_red) return 0;
    if (dir_len == 0 and !useDefaultDir()) return 0;
    if (!hasVectorShapes()) return 0;
    var r = svgcur.Renderer.init() orelse return 0;
    defer r.deinit();
    const S = svgcur.SIZE;
    var written: usize = 0;
    for (svgcur.shapes, 0..) |sh, i| {
        const src_path = core.join(&path_buf, &.{ windir[0..windir_len], L("\\Cursors\\"), sh.name, L(".svg") });
        const n = readFile(src_path.ptr, &svg_buf) orelse continue;
        svgcur.colorize(svg_buf[0..n], "000000", "FFFFFF"); // corps noir, contour blanc
        if (!r.draw(svg_buf[0..n])) continue;
        if (need_bw) {
            svgcur.toMono(r.pixels(), S, &mono_xor, &mono_and);
            const len = curfile.monoFile(&out_buf, S, sh.hot_x, sh.hot_y, &mono_xor, &mono_and) orelse continue;
            written += storeVector(.black, i, out_buf[0..len]);
            @memcpy(src_buf[0..len], out_buf[0..len]);
            const wl = curfile.derive(src_buf[0..len], .invert, &out_buf) orelse continue;
            written += storeVector(.white, i, out_buf[0..wl]);
        }
        if (need_red) {
            const px = r.pixels();
            for (px) |*p| p.* = svgcur.unpremultiply(p.*);
            core.reddenColorPixels(px, S, &.{}, 0); // bords adoucis gardés
            const len = curfile.colorFile(&out_buf, S, sh.hot_x, sh.hot_y, px) orelse continue;
            written += storeVector(.red, i, out_buf[0..len]);
        }
    }
    if (need_bw) {
        prepared_v[@backingInt(Set.black)] = true;
        prepared_v[@backingInt(Set.white)] = true;
    }
    if (need_red) prepared_v[@backingInt(Set.red)] = true;
    return written;
}

/// Les fichiers vectoriels des jeux noir et blanc sont-ils prêts ?
pub fn vectorReady() bool {
    for (0..COUNT) |i| {
        if (!ready_v[@backingInt(Set.black)][i] or !ready_v[@backingInt(Set.white)][i]) return false;
    }
    return true;
}

/// Choisit les curseurs dessinés à partir des dessins vectoriels (pointeur agrandi) ou les
/// curseurs classiques (taille 1), comme Windows. Sans effet sur un jeu dont les fichiers
/// vectoriels ne sont pas prêts.
pub fn useVector(on: bool) void {
    vector = on;
}

pub fn usingVector() bool {
    return vector;
}

fn ensure(set: Set) void {
    if (!prepared[@backingInt(set)]) _ = prepare(set == .red);
}

/// Curseur `i` du jeu `set` à la taille `px`, lu depuis son fichier (null si indisponible).
pub fn loadOne(set: Set, i: usize, px: i32) w.HCURSOR {
    ensure(set);
    const path = pathOf(set, i, &path_buf) orelse return null;
    return w.LoadImageW(null, path.ptr, w.IMAGE_CURSOR, px, px, w.LR_LOADFROMFILE);
}

// ---------------------------------------------------------------- curseurs examinés

/// Libère les jeux noir et blanc chargés par `load`.
pub fn free() void {
    for (&black, &white) |*b, *wh| {
        if (b.*) |c| _ = w.DestroyCursor(c);
        if (wh.*) |c| _ = w.DestroyCursor(c);
        b.* = null;
        wh.* = null;
    }
}

/// Libère le jeu rouge chargé par `loadRed`.
pub fn freeRed() void {
    for (&red) |*r| {
        if (r.*) |c| _ = w.DestroyCursor(c);
        r.* = null;
    }
}

/// Règle la taille des curseurs appliqués et charge les jeux noir et blanc à cette taille
/// (pour les examiner).
pub fn load(px: i32) void {
    free();
    size = px;
    for (0..COUNT) |i| {
        black[i] = loadOne(.black, i, px);
        white[i] = loadOne(.white, i, px);
    }
}

/// Charge le jeu rouge, agrandi (core.bigSize) par rapport à des curseurs de `px`.
pub fn loadRed(px: i32) void {
    freeRed();
    for (0..COUNT) |i| red[i] = loadOne(.red, i, core.bigSize(px));
}

// ---------------------------------------------------------------- système
//
// Seul le curseur affiché est recoloré quand la couleur voulue change ; les autres le sont au
// moment où ils apparaissent (voir `show` et `fix`). Charger un curseur depuis son fichier
// coûte peu à la taille 1, mais environ 5 ms à la taille maximale du pointeur, où Windows en
// prépare une version géante : recharger les 17 à chaque bascule coûtait alors 90 ms.

/// Jeu installé en ce moment pour chaque curseur du système (null : celui de Windows).
pub var installed: [COUNT]?Set = @splat(null);
/// Couleur voulue (null : curseurs de Windows).
pub var wanted: ?Set = null;
/// Poignées des curseurs du système (les mêmes pendant toute la session), relevées au besoin.
var sys_handles: [COUNT]w.HCURSOR = @splat(null);

fn isSet(s: ?Set, set: Set) bool {
    return if (s) |x| x == set else false;
}

/// Taille de chargement des curseurs du jeu `set` (le rouge est agrandi, voir core.bigSizeFor).
fn pxOf(set: Set) i32 {
    return if (set == .red) core.bigSizeFor(size, base) else size;
}

/// Installe le curseur `i` du jeu `set`, lu depuis son fichier.
fn install(set: Set, i: usize) void {
    // un curseur neuf à chaque fois : SetSystemCursor le garde puis le détruit
    const c = loadOne(set, i, pxOf(set)) orelse return;
    if (w.SetSystemCursor(c, defs[i].id) == 0) {
        _ = w.DestroyCursor(c);
        return;
    }
    installed[i] = set;
}

/// Rang (dans `defs`) du curseur du système dont `c` est la poignée ; null pour un curseur
/// propre à un programme.
pub fn indexOf(c: w.HCURSOR) ?usize {
    const target = c orelse return null;
    for (defs, &sys_handles, 0..) |d, *s, i| {
        if (s.* == null) s.* = w.LoadCursorW(null, @ptrFromInt(d.id));
        if (s.* == target) return i;
    }
    return null;
}

/// Curseur du système affiché en ce moment ; null si aucun (ou un curseur propre au
/// programme sous la souris).
pub fn shown() ?usize {
    var ci: w.CURSORINFO = .{};
    if (w.GetCursorInfo(&ci) == 0) return null;
    return indexOf(ci.hCursor);
}

/// Change la couleur voulue. Seul le curseur affiché est recoloré tout de suite, avec ceux
/// restés rouges après une secousse (aucun ne doit réapparaître rouge).
pub fn show(set: Set) void {
    wanted = set;
    if (set != .red) {
        for (installed, 0..) |s, i| {
            if (isSet(s, .red)) install(set, i);
        }
    }
    fix();
}

/// Recolore le curseur affiché s'il n'a pas la couleur voulue : à appeler quand sa forme
/// change. Rien tant qu'aucune couleur n'est voulue.
pub fn fix() void {
    const set = wanted orelse return;
    const i = shown() orelse return;
    if (!isSet(installed[i], set)) install(set, i);
}

/// Oublie quels curseurs sont installés (Windows a pu remettre les siens sans prévenir) :
/// chacun sera réinstallé à sa prochaine apparition.
pub fn forget() void {
    installed = @splat(null);
}

/// Installe d'un coup les 17 curseurs du jeu `set` (tests et mesures).
pub fn applySet(set: Set) void {
    wanted = set;
    for (0..COUNT) |i| install(set, i);
}

/// Installe d'un coup les 17 curseurs du jeu noir ou blanc, à la taille `size`.
pub fn apply(want_black: bool) void {
    applySet(if (want_black) .black else .white);
}

/// Installe d'un coup les 17 curseurs du jeu rouge agrandi.
pub fn applyRed() void {
    applySet(.red);
}

/// Recharge les curseurs choisis par l'utilisateur (ceux du registre).
pub fn restore() void {
    _ = w.SystemParametersInfoW(w.SPI_SETCURSORS, 0, null, 0);
    installed = @splat(null);
    wanted = null;
}

test "defs : identifiants uniques et noms de fichiers en .cur" {
    for (defs, 0..) |a, i| {
        for (defs[i + 1 ..]) |b| try std.testing.expect(a.id != b.id);
        try std.testing.expect(std.mem.endsWith(u16, a.file, L(".cur")));
    }
}

test "isNative : chaque curseur a exactement un jeu, noir ou blanc, fourni par Windows" {
    for (0..COUNT) |i| {
        try std.testing.expect(isNative(.black, i) != isNative(.white, i));
        try std.testing.expect(!isNative(.red, i));
    }
}
