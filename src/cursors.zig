//! Jeux de curseurs noir et blanc : chargement depuis les fichiers fournis avec Windows,
//! fabrication de la version inversée, application au système.

const std = @import("std");
const core = @import("core.zig");
const w = @import("win32.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const CurDef = struct { id: u32, file: []const u16, file_is_white: bool };

/// Jeu « Windows Black » livré avec Windows. Il n'a pas de main noire
/// (et ses curseurs emplacement/personne ont une main blanche) :
/// pour ceux-là on prend la version blanche standard et on l'inverse.
pub const defs = blk: {
    @setEvalBranchQuota(20_000); // conversion UTF-16 des noms à la compilation
    break :blk [_]CurDef{
        .{ .id = 32512, .file = L("arrow_r.cur"), .file_is_white = false }, // flèche normale
        .{ .id = 32513, .file = L("beam_r.cur"), .file_is_white = false }, // sélection de texte
        .{ .id = 32514, .file = L("busy_r.cur"), .file_is_white = false }, // occupé
        .{ .id = 32515, .file = L("cross_r.cur"), .file_is_white = false }, // précision
        .{ .id = 32516, .file = L("up_r.cur"), .file_is_white = false }, // autre sélection
        .{ .id = 32631, .file = L("pen_r.cur"), .file_is_white = false }, // stylet
        .{ .id = 32642, .file = L("size2_r.cur"), .file_is_white = false }, // redim. NO-SE
        .{ .id = 32643, .file = L("size1_r.cur"), .file_is_white = false }, // redim. NE-SO
        .{ .id = 32644, .file = L("size3_r.cur"), .file_is_white = false }, // redim. horizontal
        .{ .id = 32645, .file = L("size4_r.cur"), .file_is_white = false }, // redim. vertical
        .{ .id = 32646, .file = L("move_r.cur"), .file_is_white = false }, // déplacer
        .{ .id = 32648, .file = L("no_r.cur"), .file_is_white = false }, // indisponible
        .{ .id = 32649, .file = L("aero_link.cur"), .file_is_white = true }, // main (lien)
        .{ .id = 32650, .file = L("wait_r.cur"), .file_is_white = false }, // arrière-plan
        .{ .id = 32651, .file = L("help_r.cur"), .file_is_white = false }, // aide
        .{ .id = 32671, .file = L("aero_pin.cur"), .file_is_white = true }, // emplacement
        .{ .id = 32672, .file = L("aero_person.cur"), .file_is_white = true }, // personne
    };
};
pub const COUNT = defs.len;

pub var black: [COUNT]w.HCURSOR = @splat(null);
pub var white: [COUNT]w.HCURSOR = @splat(null);
/// jeu agrandi et rouge, affiché quand on secoue la souris (chargé seulement si l'option est active)
pub var red: [COUNT]w.HCURSOR = @splat(null);
/// taille (px) des jeux actuellement chargés
pub var size: i32 = 0;

// Tampons de taille fixe (en .bss : rien dans l'exe, seules les pages utilisées comptent).
pub var px_buf: [core.MAX_CUR * core.MAX_CUR]u32 = undefined; // pixels couleur d'un curseur
pub var mask_buf: [core.MAX_CUR / 8 * core.MAX_CUR * 2]u8 = undefined; // masque 1 bit/pixel
var windir: [w.MAX_PATH]u16 = undefined;
var path_buf: [2 * w.MAX_PATH]u16 = undefined;

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

/// Taille des curseurs du système : celle de la flèche actuelle, sinon réglage × échelle.
pub fn systemSize() i32 {
    var base: u32 = 32;
    var cb: u32 = @sizeOf(u32);
    _ = w.RegGetValueW(w.HKCU, L("Control Panel\\Cursors"), L("CursorBaseSize"), w.RRF_RT_REG_DWORD, null, &base, &cb);
    return core.cursorSize(currentArrowWidth(), base, w.GetSystemMetrics(w.SM_CXCURSOR));
}

/// Copie de `src` dont le noir et le blanc sont échangés (voir core.invertColorPixels
/// et core.invertMonoMask). Renvoie null en cas d'échec ; `src` n'est pas modifié.
pub fn invert(src: w.HCURSOR) w.HCURSOR {
    var ii: w.ICONINFO = undefined;
    if (w.GetIconInfo(src, &ii) == 0) return null;
    defer _ = w.DeleteObject(ii.hbmMask);

    var mbm: w.BITMAP = undefined;
    _ = w.GetObjectW(ii.hbmMask, @sizeOf(w.BITMAP), &mbm);
    const stride: usize = @intCast(mbm.bmWidthBytes);
    const mask_len = stride * @as(usize, @intCast(mbm.bmHeight));
    if (mask_len > mask_buf.len) return null;
    if (w.GetBitmapBits(ii.hbmMask, @intCast(mask_len), &mask_buf) != mask_len) return null;

    if (ii.hbmColor) |color| {
        // Curseur couleur (souvent 32 bits avec transparence).
        defer _ = w.DeleteObject(color);
        var bm: w.BITMAP = undefined;
        _ = w.GetObjectW(color, @sizeOf(w.BITMAP), &bm);
        const width: usize = @intCast(bm.bmWidth);
        const height: usize = @intCast(bm.bmHeight);
        if (width > core.MAX_CUR or height > core.MAX_CUR) return null;
        var bi = w.bmi(bm.bmWidth, bm.bmHeight);
        const dc = w.GetDC(null);
        defer _ = w.ReleaseDC(null, dc);
        if (w.GetDIBits(dc, color, 0, @intCast(height), &px_buf, &bi, w.DIB_RGB_COLORS) == 0) return null;
        core.invertColorPixels(px_buf[0 .. width * height], width, mask_buf[0..mask_len], stride);
        const nb = w.CreateBitmap(bm.bmWidth, bm.bmHeight, 1, 32, &px_buf) orelse return null;
        defer _ = w.DeleteObject(nb);
        var ni: w.ICONINFO = .{ .fIcon = 0, .xHotspot = ii.xHotspot, .yHotspot = ii.yHotspot, .hbmMask = ii.hbmMask, .hbmColor = nb };
        return w.CreateIconIndirect(&ni);
    } else {
        // Curseur monochrome : masque ET + OU exclusif, de hauteur double.
        core.invertMonoMask(mask_buf[0..mask_len]);
        const nm = w.CreateBitmap(mbm.bmWidth, mbm.bmHeight, 1, 1, &mask_buf) orelse return null;
        defer _ = w.DeleteObject(nm);
        var ni: w.ICONINFO = .{ .fIcon = 0, .xHotspot = ii.xHotspot, .yHotspot = ii.yHotspot, .hbmMask = nm, .hbmColor = null };
        return w.CreateIconIndirect(&ni);
    }
}

/// Copie rouge de `src`, qui doit être un curseur de la version noire (corps noir,
/// contour blanc) : corps rouge, contour blanc, voir core.reddenColorPixels et
/// core.monoToRed. Le résultat est toujours un curseur 32 bits avec transparence.
pub fn redden(src: w.HCURSOR) w.HCURSOR {
    var ii: w.ICONINFO = undefined;
    if (w.GetIconInfo(src, &ii) == 0) return null;
    defer _ = w.DeleteObject(ii.hbmMask);

    var mbm: w.BITMAP = undefined;
    _ = w.GetObjectW(ii.hbmMask, @sizeOf(w.BITMAP), &mbm);
    const stride: usize = @intCast(mbm.bmWidthBytes);
    const mask_len = stride * @as(usize, @intCast(mbm.bmHeight));
    if (mask_len > mask_buf.len) return null;
    if (w.GetBitmapBits(ii.hbmMask, @intCast(mask_len), &mask_buf) != mask_len) return null;

    var width: i32 = undefined;
    var height: i32 = undefined;
    var and_mask: w.HBITMAP = ii.hbmMask;
    var own_mask: w.HBITMAP = null;
    defer if (own_mask) |m| {
        _ = w.DeleteObject(m);
    };
    if (ii.hbmColor) |color| {
        defer _ = w.DeleteObject(color);
        var bm: w.BITMAP = undefined;
        _ = w.GetObjectW(color, @sizeOf(w.BITMAP), &bm);
        width = bm.bmWidth;
        height = bm.bmHeight;
        const uw: usize = @intCast(width);
        const uh: usize = @intCast(height);
        if (uw > core.MAX_CUR or uh > core.MAX_CUR) return null;
        var bi = w.bmi(width, height);
        const dc = w.GetDC(null);
        defer _ = w.ReleaseDC(null, dc);
        if (w.GetDIBits(dc, color, 0, @intCast(uh), &px_buf, &bi, w.DIB_RGB_COLORS) == 0) return null;
        core.reddenColorPixels(px_buf[0 .. uw * uh], uw, mask_buf[0..mask_len], stride);
    } else {
        // monochrome : la moitié haute du masque (ET) sert de masque au curseur couleur
        width = mbm.bmWidth;
        height = @divTrunc(mbm.bmHeight, 2);
        const uw: usize = @intCast(width);
        const uh: usize = @intCast(height);
        if (uw > core.MAX_CUR or uh > core.MAX_CUR) return null;
        core.monoToRed(mask_buf[0..mask_len], stride, uw, uh, px_buf[0 .. uw * uh]);
        own_mask = w.CreateBitmap(width, height, 1, 1, &mask_buf) orelse return null;
        and_mask = own_mask;
    }
    const nb = w.CreateBitmap(width, height, 1, 32, &px_buf) orelse return null;
    defer _ = w.DeleteObject(nb);
    var ni: w.ICONINFO = .{ .fIcon = 0, .xHotspot = ii.xHotspot, .yHotspot = ii.yHotspot, .hbmMask = and_mask, .hbmColor = nb };
    return w.CreateIconIndirect(&ni);
}

/// Libère le jeu rouge.
pub fn freeRed() void {
    for (&red) |*r| {
        if (r.*) |c| _ = w.DestroyCursor(c);
        r.* = null;
    }
}

/// Charge le jeu rouge, agrandi (core.bigSize) par rapport à des curseurs de `px`.
pub fn loadRed(px: i32) void {
    freeRed();
    const big = core.bigSize(px);
    const wn = w.GetWindowsDirectoryW(&windir, windir.len);
    for (defs, 0..) |d, i| {
        const path = core.join(&path_buf, &.{ windir[0..wn], L("\\Cursors\\"), d.file });
        const base = w.LoadImageW(null, path.ptr, w.IMAGE_CURSOR, big, big, w.LR_LOADFROMFILE) orelse continue;
        defer _ = w.DestroyCursor(base);
        if (d.file_is_white) {
            const blk = invert(base) orelse continue;
            defer _ = w.DestroyCursor(blk);
            red[i] = redden(blk);
        } else {
            red[i] = redden(base);
        }
    }
}

/// Libère les deux jeux.
pub fn free() void {
    for (&black, &white) |*b, *wh| {
        if (b.*) |c| _ = w.DestroyCursor(c);
        if (wh.*) |c| _ = w.DestroyCursor(c);
        b.* = null;
        wh.* = null;
    }
}

/// Charge les deux jeux à la taille `px`. Les curseurs introuvables restent à null
/// (le système garde alors le sien pour ce type de curseur).
pub fn load(px: i32) void {
    free();
    size = px;
    const wn = w.GetWindowsDirectoryW(&windir, windir.len);
    for (defs, 0..) |d, i| {
        const path = core.join(&path_buf, &.{ windir[0..wn], L("\\Cursors\\"), d.file });
        const base = w.LoadImageW(null, path.ptr, w.IMAGE_CURSOR, px, px, w.LR_LOADFROMFILE) orelse continue;
        const inv = invert(base) orelse {
            _ = w.DestroyCursor(base);
            continue;
        };
        if (d.file_is_white) {
            white[i] = base;
            black[i] = inv;
        } else {
            black[i] = base;
            white[i] = inv;
        }
    }
}

/// Remplace les curseurs du système par le jeu noir ou blanc.
pub fn apply(want_black: bool) void {
    applySet(if (want_black) &black else &white);
}

/// Remplace les curseurs du système par le jeu rouge agrandi.
pub fn applyRed() void {
    applySet(&red);
}

fn applySet(set: *const [COUNT]w.HCURSOR) void {
    for (set, defs) |cur, d| {
        const src = cur orelse continue;
        const copy = w.CopyIcon(src) orelse continue; // SetSystemCursor détruit la copie
        if (w.SetSystemCursor(copy, d.id) == 0) _ = w.DestroyCursor(copy);
    }
}

/// Recharge les curseurs choisis par l'utilisateur (ceux du registre).
pub fn restore() void {
    _ = w.SystemParametersInfoW(w.SPI_SETCURSORS, 0, null, 0);
}

test "defs : identifiants uniques et noms de fichiers en .cur" {
    for (defs, 0..) |a, i| {
        for (defs[i + 1 ..]) |b| try std.testing.expect(a.id != b.id);
        try std.testing.expect(std.mem.endsWith(u16, a.file, L(".cur")));
    }
}
