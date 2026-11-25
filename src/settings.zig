//! Réglages conservés d'un lancement à l'autre, dans HKCU\Software\AutoCurseur.
//! (La clé n'est créée que lorsque l'utilisateur change un réglage dans le menu.)

const std = @import("std");
const core = @import("core.zig");
const i18n = @import("i18n.zig");
const w = @import("win32.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const KEY = L("Software\\AutoCurseur");
pub const RATE_VALUE = L("LecturesParSeconde");
pub const LANG_VALUE = L("Langue");
pub const SHAKE_VALUE = L("SecouerPourRetrouver");
/// Couleurs des curseurs (0xRRGGBB) : celle affichée sur les fonds clairs, celle sur les fonds sombres.
pub const DARK_VALUE = L("CouleurSurFondClair");
pub const LIGHT_VALUE = L("CouleurSurFondSombre");

/// Identifiant de l'entrée « secouer pour retrouver » du menu (les autres entrées fixes
/// sont dans main.zig, toutes en dessous de 100).
pub const MENU_SHAKE = 4;
/// Entrées « couleur personnalisée » du menu : sur fond clair, sur fond sombre.
pub const MENU_COLOR_DARK = 5;
pub const MENU_COLOR_LIGHT = 6;

/// Identifiants des entrées « lectures par seconde » du menu : RATE_MENU_BASE + indice dans core.RATES.
pub const RATE_MENU_BASE = 100;
/// Identifiants des entrées « langue » du menu : LANG_MENU_BASE + valeur de i18n.Choice.
pub const LANG_MENU_BASE = 200;
/// Identifiants des couples de couleurs du menu : COLOR_MENU_BASE + indice dans core.PRESETS.
pub const COLOR_MENU_BASE = 300;

/// Valeur brute enregistrée sous `name`, ou null si aucune.
pub fn readDword(name: [*:0]const u16) ?u32 {
    var v: u32 = 0;
    var cb: u32 = @sizeOf(u32);
    if (w.RegGetValueW(w.HKCU, KEY, name, w.RRF_RT_REG_DWORD, null, &v, &cb) != 0) return null;
    return v;
}

pub fn writeDword(name: [*:0]const u16, v: u32) void {
    var k: w.HKEY = null;
    if (w.RegCreateKeyExW(w.HKCU, KEY, 0, null, 0, w.KEY_SET_VALUE, null, &k, null) != 0) return;
    defer _ = w.RegCloseKey(k);
    _ = w.RegSetValueExW(k, name, 0, w.REG_DWORD, &v, @sizeOf(u32));
}

/// Valeur brute enregistrée, ou null si aucune.
pub fn readRate() ?u32 {
    return readDword(RATE_VALUE);
}

/// Rythme à utiliser : celui enregistré s'il est valide, sinon le défaut.
pub fn loadRate() u32 {
    return core.validRate(readRate() orelse core.DEFAULT_RATE);
}

pub fn saveRate(rate: u32) void {
    writeDword(RATE_VALUE, core.validRate(rate));
}

/// Langue choisie : celle enregistrée si elle est valide, sinon automatique.
pub fn loadLang() i18n.Choice {
    return i18n.Choice.fromInt(readDword(LANG_VALUE) orelse 0) orelse .auto;
}

pub fn saveLang(c: i18n.Choice) void {
    writeDword(LANG_VALUE, @backingInt(c));
}

/// « Secouer pour retrouver » : actif sauf si l'utilisateur l'a désactivé.
pub fn loadShake() bool {
    return (readDword(SHAKE_VALUE) orelse 1) != 0;
}

pub fn saveShake(on: bool) void {
    writeDword(SHAKE_VALUE, @intFromBool(on));
}

/// Couleurs à utiliser : celles enregistrées si elles forment un couple valide (une sombre,
/// une claire), sinon noir et blanc.
pub fn loadColors() core.Colors {
    const c: core.Colors = .{
        .dark = readDword(DARK_VALUE) orelse core.BLACK,
        .light = readDword(LIGHT_VALUE) orelse core.WHITE,
    };
    return if (core.validColors(c)) c else .{};
}

/// Mémorise un couple de couleurs valide (un couple refusé n'est pas enregistré).
pub fn saveColors(c: core.Colors) void {
    if (!core.validColors(c)) return;
    writeDword(DARK_VALUE, c.dark);
    writeDword(LIGHT_VALUE, c.light);
}

/// Efface tous les réglages (supprime la clé) : retour aux valeurs par défaut, sans trace.
pub fn reset() void {
    _ = w.RegDeleteKeyW(w.HKCU, KEY);
}

/// Rythme de l'entrée de menu `id`, ou null si ce n'en est pas une.
pub fn rateFromMenuId(id: usize) ?u32 {
    if (id < RATE_MENU_BASE or id >= RATE_MENU_BASE + core.RATES.len) return null;
    return core.RATES[id - RATE_MENU_BASE];
}

/// Langue de l'entrée de menu `id`, ou null si ce n'en est pas une.
pub fn langFromMenuId(id: usize) ?i18n.Choice {
    if (id < LANG_MENU_BASE or id >= LANG_MENU_BASE + i18n.CHOICES.len) return null;
    return i18n.Choice.fromInt(@intCast(id - LANG_MENU_BASE));
}

/// Couple de couleurs de l'entrée de menu `id`, ou null si ce n'en est pas une.
pub fn colorsFromMenuId(id: usize) ?core.Colors {
    if (id < COLOR_MENU_BASE or id >= COLOR_MENU_BASE + core.PRESETS.len) return null;
    return core.PRESETS[id - COLOR_MENU_BASE];
}

test "colorsFromMenuId : seules les entrées du sous-menu donnent un couple de couleurs" {
    try std.testing.expect(colorsFromMenuId(COLOR_MENU_BASE).?.eql(.{}));
    for (core.PRESETS, 0..) |p, i| try std.testing.expect(colorsFromMenuId(COLOR_MENU_BASE + i).?.eql(p));
    try std.testing.expectEqual(@as(?core.Colors, null), colorsFromMenuId(COLOR_MENU_BASE + core.PRESETS.len));
    try std.testing.expectEqual(@as(?core.Colors, null), colorsFromMenuId(COLOR_MENU_BASE - 1));
    try std.testing.expectEqual(@as(?core.Colors, null), colorsFromMenuId(MENU_COLOR_DARK));
    try std.testing.expectEqual(@as(?core.Colors, null), colorsFromMenuId(LANG_MENU_BASE));
}

test "rateFromMenuId : seules les entrées du sous-menu donnent un rythme" {
    try std.testing.expectEqual(@as(?u32, 3), rateFromMenuId(RATE_MENU_BASE));
    try std.testing.expectEqual(@as(?u32, 20), rateFromMenuId(RATE_MENU_BASE + 3));
    try std.testing.expectEqual(@as(?u32, null), rateFromMenuId(RATE_MENU_BASE + core.RATES.len));
    try std.testing.expectEqual(@as(?u32, null), rateFromMenuId(1));
    try std.testing.expectEqual(@as(?u32, null), rateFromMenuId(0));
}

test "langFromMenuId : seules les entrées du sous-menu donnent une langue" {
    try std.testing.expectEqual(@as(?i18n.Choice, .auto), langFromMenuId(LANG_MENU_BASE));
    try std.testing.expectEqual(@as(?i18n.Choice, .en), langFromMenuId(LANG_MENU_BASE + 1));
    try std.testing.expectEqual(@as(?i18n.Choice, .fr), langFromMenuId(LANG_MENU_BASE + 2));
    try std.testing.expectEqual(@as(?i18n.Choice, null), langFromMenuId(LANG_MENU_BASE + i18n.CHOICES.len));
    try std.testing.expectEqual(@as(?i18n.Choice, null), langFromMenuId(LANG_MENU_BASE - 1));
    try std.testing.expectEqual(@as(?i18n.Choice, null), langFromMenuId(RATE_MENU_BASE));
}

test "identifiants de menu : les plages ne se chevauchent pas" {
    // les entrées fixes du menu (Actif, Démarrage, Quitter) sont en dessous de 100
    try std.testing.expect(RATE_MENU_BASE + core.RATES.len <= LANG_MENU_BASE);
    try std.testing.expect(LANG_MENU_BASE + i18n.CHOICES.len <= COLOR_MENU_BASE);
    try std.testing.expect(MENU_SHAKE < RATE_MENU_BASE and MENU_COLOR_DARK < RATE_MENU_BASE and MENU_COLOR_LIGHT < RATE_MENU_BASE);
    try std.testing.expect(MENU_COLOR_DARK != MENU_COLOR_LIGHT and MENU_COLOR_DARK != MENU_SHAKE and MENU_COLOR_LIGHT != MENU_SHAKE);
    for (0..RATE_MENU_BASE + 1000) |id| {
        const n = @as(u32, @intFromBool(rateFromMenuId(id) != null)) + @intFromBool(langFromMenuId(id) != null) + @intFromBool(colorsFromMenuId(id) != null);
        try std.testing.expect(n <= 1);
    }
}
