//! Réglages conservés d'un lancement à l'autre, dans HKCU\Software\AutoCurseur.
//! (La clé n'est créée que lorsque l'utilisateur change un réglage dans le menu.)

const std = @import("std");
const core = @import("core.zig");
const w = @import("win32.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const KEY = L("Software\\AutoCurseur");
pub const RATE_VALUE = L("LecturesParSeconde");

/// Identifiants des entrées « lectures par seconde » du menu : RATE_MENU_BASE + indice dans core.RATES.
pub const RATE_MENU_BASE = 100;

/// Valeur brute enregistrée, ou null si aucune.
pub fn readRate() ?u32 {
    var v: u32 = 0;
    var cb: u32 = @sizeOf(u32);
    if (w.RegGetValueW(w.HKCU, KEY, RATE_VALUE, w.RRF_RT_REG_DWORD, null, &v, &cb) != 0) return null;
    return v;
}

/// Rythme à utiliser : celui enregistré s'il est valide, sinon le défaut.
pub fn loadRate() u32 {
    return core.validRate(readRate() orelse core.DEFAULT_RATE);
}

pub fn saveRate(rate: u32) void {
    var k: w.HKEY = null;
    if (w.RegCreateKeyExW(w.HKCU, KEY, 0, null, 0, w.KEY_SET_VALUE, null, &k, null) != 0) return;
    defer _ = w.RegCloseKey(k);
    const v: u32 = core.validRate(rate);
    _ = w.RegSetValueExW(k, RATE_VALUE, 0, w.REG_DWORD, &v, @sizeOf(u32));
}

/// Efface tous les réglages (supprime la clé) : retour aux valeurs par défaut, sans trace.
pub fn reset() void {
    _ = w.RegDeleteKeyW(w.HKCU, KEY);
}

/// Indice dans core.RATES de l'entrée de menu `id`, ou null si ce n'en est pas une.
pub fn rateFromMenuId(id: usize) ?u32 {
    if (id < RATE_MENU_BASE or id >= RATE_MENU_BASE + core.RATES.len) return null;
    return core.RATES[id - RATE_MENU_BASE];
}

test "rateFromMenuId : seules les entrées du sous-menu donnent un rythme" {
    try std.testing.expectEqual(@as(?u32, 3), rateFromMenuId(RATE_MENU_BASE));
    try std.testing.expectEqual(@as(?u32, 20), rateFromMenuId(RATE_MENU_BASE + 3));
    try std.testing.expectEqual(@as(?u32, null), rateFromMenuId(RATE_MENU_BASE + core.RATES.len));
    try std.testing.expectEqual(@as(?u32, null), rateFromMenuId(1));
    try std.testing.expectEqual(@as(?u32, null), rateFromMenuId(0));
}
