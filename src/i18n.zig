//! Textes de l'interface (menu et info-bulle) en anglais et en français.
//!
//! Le choix « automatique » suit la langue d'affichage de Windows : français si c'est
//! une variante du français (France, Canada, Belgique, Suisse…), anglais sinon.
//! Tous les textes sont des littéraux UTF-16 construits à la compilation : rien n'est
//! alloué à l'exécution.

const std = @import("std");
const core = @import("core.zig");

fn L(comptime s: []const u8) *const [std.unicode.calcUtf16LeLen(s) catch unreachable:0]u16 {
    @setEvalBranchQuota(20_000);
    return std.unicode.utf8ToUtf16LeStringLiteral(s);
}

/// Langue effectivement affichée.
pub const Lang = enum { en, fr };

/// Réglage choisi dans le menu, dans l'ordre du sous-menu (la valeur est aussi celle
/// enregistrée dans le registre).
pub const Choice = enum(u32) {
    auto = 0,
    en = 1,
    fr = 2,

    pub fn fromInt(v: u32) ?Choice {
        return switch (v) {
            0 => .auto,
            1 => .en,
            2 => .fr,
            else => null,
        };
    }
};

pub const CHOICES = [_]Choice{ .auto, .en, .fr };

/// Identifiant de langue principal du français dans un LANGID Windows (bits 0 à 9).
pub const LANG_FRENCH = 0x0C;

/// Langue à afficher pour un réglage, `ui_langid` étant la langue d'affichage de Windows
/// (GetUserDefaultUILanguage).
pub fn resolve(choice: Choice, ui_langid: u16) Lang {
    return switch (choice) {
        .en => .en,
        .fr => .fr,
        .auto => if (ui_langid & 0x3FF == LANG_FRENCH) .fr else .en,
    };
}

pub const Text = struct {
    active: [:0]const u16,
    rate_menu: [:0]const u16,
    /// Libellés du sous-menu, dans l'ordre de core.RATES.
    rates: [core.RATES.len][:0]const u16,
    language_menu: [:0]const u16,
    language_auto: [:0]const u16,
    colors_menu: [:0]const u16,
    /// Libellés des couples de couleurs, dans l'ordre de core.PRESETS.
    presets: [core.PRESETS.len][:0]const u16,
    /// Entrées qui ouvrent le sélecteur de couleur de Windows, et titres de celui-ci.
    color_dark: [:0]const u16,
    color_light: [:0]const u16,
    pick_dark_title: [:0]const u16,
    pick_light_title: [:0]const u16,
    /// Message quand la couleur choisie ne se distingue pas assez de l'autre.
    colors_too_close: [:0]const u16,
    shake: [:0]const u16,
    startup: [:0]const u16,
    quit: [:0]const u16,
    paused_tip: [:0]const u16,
};

pub const en: Text = .{
    .active = L("Active"),
    .rate_menu = L("Checks per second (while the mouse moves)"),
    .rates = .{ L("3"), L("5"), L("10 (default)"), L("20") },
    .language_menu = L("Language"),
    .language_auto = L("Automatic (Windows language)"),
    .colors_menu = L("Colors"),
    .presets = .{ L("Black / White (default)"), L("Navy / Yellow"), L("Dark green / Light green"), L("Purple / Pink") },
    .color_dark = L("Over light backgrounds…"),
    .color_light = L("Over dark backgrounds…"),
    .pick_dark_title = L("Pointer color over light backgrounds"),
    .pick_light_title = L("Pointer color over dark backgrounds"),
    .colors_too_close = L("These two colors are too close. The pointer needs a dark color over light backgrounds and a light color over dark backgrounds.\n\nThe color was not changed."),
    .shake = L("Shake to find the pointer (bigger, in red)"),
    .startup = L("Start with Windows"),
    .quit = L("Quit"),
    .paused_tip = L("AutoCurseur (paused)"),
};

pub const fr: Text = .{
    .active = L("Actif"),
    .rate_menu = L("Vérifications par seconde (souris en mouvement)"),
    .rates = .{ L("3"), L("5"), L("10 (par défaut)"), L("20") },
    .language_menu = L("Langue"),
    .language_auto = L("Automatique (langue de Windows)"),
    .colors_menu = L("Couleurs"),
    .presets = .{ L("Noir / Blanc (par défaut)"), L("Bleu nuit / Jaune"), L("Vert sapin / Vert clair"), L("Violet / Rose") },
    .color_dark = L("Sur fond clair…"),
    .color_light = L("Sur fond sombre…"),
    .pick_dark_title = L("Couleur du curseur sur fond clair"),
    .pick_light_title = L("Couleur du curseur sur fond sombre"),
    .colors_too_close = L("Ces deux couleurs sont trop proches. Il faut une couleur sombre sur fond clair et une couleur claire sur fond sombre.\n\nLa couleur n'a pas été changée."),
    .shake = L("Secouer pour retrouver le curseur (agrandi, en rouge)"),
    .startup = L("Lancer au démarrage de Windows"),
    .quit = L("Quitter"),
    .paused_tip = L("AutoCurseur (en pause)"),
};

pub fn text(lang: Lang) *const Text {
    return switch (lang) {
        .en => &en,
        .fr => &fr,
    };
}

/// Libellé d'une entrée du sous-menu « Langue ». Les langues sont écrites dans leur
/// propre langue, pour qu'on retrouve la sienne même si le menu est dans une autre.
pub fn choiceLabel(t: *const Text, c: Choice) [:0]const u16 {
    return switch (c) {
        .auto => t.language_auto,
        .en => L("English"),
        .fr => L("Français"),
    };
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn utf8(buf: []u8, s: []const u16) []const u8 {
    const n = std.unicode.utf16LeToUtf8(buf, s) catch unreachable;
    return buf[0..n];
}

test "resolve : le choix automatique suit la langue d'affichage de Windows" {
    try testing.expectEqual(Lang.fr, resolve(.auto, 0x040C)); // français (France)
    try testing.expectEqual(Lang.fr, resolve(.auto, 0x0C0C)); // français (Canada)
    try testing.expectEqual(Lang.fr, resolve(.auto, 0x080C)); // français (Belgique)
    try testing.expectEqual(Lang.fr, resolve(.auto, 0x100C)); // français (Suisse)
    try testing.expectEqual(Lang.en, resolve(.auto, 0x0409)); // anglais (États-Unis)
    try testing.expectEqual(Lang.en, resolve(.auto, 0x0809)); // anglais (Royaume-Uni)
    try testing.expectEqual(Lang.en, resolve(.auto, 0x0407)); // allemand : anglais par défaut
    try testing.expectEqual(Lang.en, resolve(.auto, 0x0411)); // japonais : anglais par défaut
    try testing.expectEqual(Lang.en, resolve(.auto, 0));
}

test "resolve : un choix explicite ignore la langue de Windows" {
    for ([_]u16{ 0x040C, 0x0409, 0x0407, 0 }) |ui| {
        try testing.expectEqual(Lang.en, resolve(.en, ui));
        try testing.expectEqual(Lang.fr, resolve(.fr, ui));
    }
}

test "Choice.fromInt : aller-retour, valeurs inconnues refusées" {
    for (CHOICES) |c| try testing.expectEqual(@as(?Choice, c), Choice.fromInt(@backingInt(c)));
    try testing.expectEqual(@as(?Choice, null), Choice.fromInt(3));
    try testing.expectEqual(@as(?Choice, null), Choice.fromInt(0xFFFF_FFFF));
    // l'ordre du sous-menu est celui des valeurs
    for (CHOICES, 0..) |c, i| try testing.expectEqual(i, @backingInt(c));
}

test "textes : tous présents, sans espace en trop, et traduits" {
    const info = @typeInfo(Text).@"struct";
    var checked: usize = 0;
    inline for (info.field_names, info.field_types) |name, T| {
        if (T == [:0]const u16) {
            inline for (.{ en, fr }) |t| {
                const v = @field(t, name);
                try testing.expect(v.len > 0);
                try testing.expect(v[0] != ' ' and v[v.len - 1] != ' ');
                try testing.expect(v[v.len] == 0);
            }
            // les libellés qui ne sont pas des nombres diffèrent d'une langue à l'autre
            try testing.expect(!std.mem.eql(u16, @field(en, name), @field(fr, name)));
            checked += 1;
        }
    }
    try testing.expectEqual(info.field_names.len - 2, checked); // tous sauf `rates` et `presets`
    // couples de couleurs : un libellé par couple, traduit, seul le premier annoté « par défaut »
    for (en.presets, fr.presets, 0..) |a, b, i| {
        try testing.expect(a.len > 0 and b.len > 0);
        try testing.expect(!std.mem.eql(u16, a, b));
        try testing.expectEqual(i == 0, std.mem.indexOfScalar(u16, a, '(') != null);
        try testing.expectEqual(i == 0, std.mem.indexOfScalar(u16, b, '(') != null);
    }
}

test "textes : l'info-bulle tient dans les 128 caractères de Windows" {
    inline for (.{ en, fr }) |t| try testing.expect(t.paused_tip.len < 128);
}

test "textes : chaque libellé du sous-menu commence par son rythme, seul le défaut est annoté" {
    var buf: [64]u8 = undefined;
    var num: [8]u8 = undefined;
    inline for (.{ en, fr }) |t| {
        for (core.RATES, t.rates) |r, label| {
            const s = utf8(&buf, label);
            const n = try std.fmt.bufPrint(&num, "{d}", .{r});
            try testing.expect(std.mem.startsWith(u8, s, n));
            try testing.expectEqual(r == core.DEFAULT_RATE, s.len > n.len);
        }
    }
}

test "text : renvoie la table de la langue demandée" {
    try testing.expectEqual(&en, text(.en));
    try testing.expectEqual(&fr, text(.fr));
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("Quit", utf8(&buf, text(.en).quit));
    try testing.expectEqualStrings("Quitter", utf8(&buf, text(.fr).quit));
}

test "choiceLabel : les langues sont écrites dans leur propre langue" {
    var a: [64]u8 = undefined;
    var b: [64]u8 = undefined;
    for ([_]*const Text{ &en, &fr }) |t| {
        try testing.expectEqualStrings("English", utf8(&a, choiceLabel(t, .en)));
        try testing.expectEqualStrings("Français", utf8(&b, choiceLabel(t, .fr)));
    }
    try testing.expectEqualStrings("Automatic (Windows language)", utf8(&a, choiceLabel(&en, .auto)));
    try testing.expectEqualStrings("Automatique (langue de Windows)", utf8(&b, choiceLabel(&fr, .auto)));
}
