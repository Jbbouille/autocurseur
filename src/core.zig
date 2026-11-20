//! Logique pure d'AutoCurseur : aucune dépendance à Windows, entièrement testée.
//!
//! - `decide`      : choix noir / blanc avec hystérésis
//! - `luma`        : luminance perçue d'un pixel, `averageLuma` d'une zone
//! - `invertColorPixels` / `invertMonoMask` : fabrication de la version inversée d'un curseur
//! - `sampleOrigin`: position de la zone lue à l'écran
//! - `Ticker`      : rythme de la minuterie (rapide quand la souris bouge, lent sinon)
//! - `Shake`       : détection d'une souris secouée, et version rouge agrandie des curseurs

const std = @import("std");
const testing = std.testing;

pub const Point = extern struct { x: i32 = 0, y: i32 = 0 };
pub const Rect = struct { x: i32, y: i32, w: i32, h: i32 };

/// Taille max d'un curseur en pixels : dimensionne les tampons statiques.
pub const MAX_CUR = 256;
/// Côté min / max de la zone lue sous la souris.
pub const BOX_MIN = 16;
pub const BOX_MAX = 96;
/// Côté max de l'icône de notification.
pub const ICON_MAX = 64;

// =====================================================================
// Décision noir / blanc
// =====================================================================

pub const Shade = enum { unknown, white, black };

pub const Thresholds = struct {
    /// luminance moyenne (0-255) à partir de laquelle le curseur passe en noir
    to_black: u32 = 150,
    /// luminance en dessous de laquelle il repasse en blanc
    to_white: u32 = 105,
};

/// Couleur voulue pour une luminance moyenne `l` (0-255). Entre les deux seuils,
/// on garde la couleur actuelle : c'est ce qui évite le clignotement.
pub fn decide(current: Shade, l: u32, t: Thresholds) Shade {
    if (current != .black and l >= t.to_black) return .black;
    if (current != .white and l <= t.to_white) return .white;
    if (current == .unknown) return if (l >= 128) .black else .white;
    return current;
}

test "decide : fond clair -> noir, fond sombre -> blanc, quel que soit l'état" {
    for ([_]Shade{ .unknown, .white, .black }) |s| {
        try testing.expectEqual(Shade.black, decide(s, 255, .{}));
        try testing.expectEqual(Shade.black, decide(s, 150, .{}));
        try testing.expectEqual(Shade.white, decide(s, 0, .{}));
        try testing.expectEqual(Shade.white, decide(s, 105, .{}));
    }
}

test "decide : entre les seuils, on garde la couleur actuelle" {
    var l: u32 = 106;
    while (l < 150) : (l += 1) {
        try testing.expectEqual(Shade.white, decide(.white, l, .{}));
        try testing.expectEqual(Shade.black, decide(.black, l, .{}));
    }
}

test "decide : au démarrage, la moitié de l'échelle tranche" {
    try testing.expectEqual(Shade.white, decide(.unknown, 127, .{}));
    try testing.expectEqual(Shade.black, decide(.unknown, 128, .{}));
}

test "decide : jamais d'état inconnu en sortie" {
    var l: u32 = 0;
    while (l <= 255) : (l += 1) {
        for ([_]Shade{ .unknown, .white, .black }) |s| {
            try testing.expect(decide(s, l, .{}) != .unknown);
        }
    }
}

test "decide : seuils personnalisés respectés" {
    const t: Thresholds = .{ .to_black = 200, .to_white = 50 };
    try testing.expectEqual(Shade.white, decide(.white, 199, t));
    try testing.expectEqual(Shade.black, decide(.white, 200, t));
    try testing.expectEqual(Shade.black, decide(.black, 51, t));
    try testing.expectEqual(Shade.white, decide(.black, 50, t));
}

test "decide : une rampe aller-retour ne bascule qu'une fois dans chaque sens" {
    var s: Shade = .white;
    var switches: u32 = 0;
    var l: u32 = 0;
    while (l <= 255) : (l += 1) {
        const n = decide(s, l, .{});
        if (n != s) switches += 1;
        s = n;
    }
    try testing.expectEqual(@as(u32, 1), switches);
    l = 256;
    while (l > 0) {
        l -= 1;
        const n = decide(s, l, .{});
        if (n != s) switches += 1;
        s = n;
    }
    try testing.expectEqual(@as(u32, 2), switches);
}

test "decide : une luminance qui oscille dans la bande morte ne fait jamais clignoter" {
    var s: Shade = .black;
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const l: u32 = if (i % 2 == 0) 110 else 145;
        s = decide(s, l, .{});
        try testing.expectEqual(Shade.black, s);
    }
}

// =====================================================================
// Luminance
// =====================================================================

/// Luminance perçue (0-255) d'un pixel BGRA 32 bits : environ 30 % rouge, 59 % vert, 11 % bleu.
pub fn luma(c: u32) u32 {
    return (((c >> 16) & 255) * 77 + ((c >> 8) & 255) * 150 + (c & 255) * 29) >> 8;
}

/// Luminance moyenne d'une zone (0 si vide).
pub fn averageLuma(px: []const u32) u32 {
    if (px.len == 0) return 0;
    var sum: u64 = 0;
    for (px) |c| sum += luma(c);
    return @intCast(sum / px.len);
}

test "luma : blanc 255, noir 0, l'alpha est ignoré" {
    try testing.expectEqual(@as(u32, 255), luma(0x00FFFFFF));
    try testing.expectEqual(@as(u32, 255), luma(0xFFFFFFFF));
    try testing.expectEqual(@as(u32, 0), luma(0x00000000));
    try testing.expectEqual(@as(u32, 0), luma(0xFF000000));
}

test "luma : le vert pèse plus que le rouge, qui pèse plus que le bleu" {
    const r = luma(0x00FF0000);
    const g = luma(0x0000FF00);
    const b = luma(0x000000FF);
    try testing.expect(g > r and r > b);
    try testing.expectEqual(@as(u32, 76), r);
    try testing.expectEqual(@as(u32, 149), g);
    try testing.expectEqual(@as(u32, 28), b);
}

test "luma : un gris donne sa propre valeur" {
    var v: u32 = 0;
    while (v <= 255) : (v += 1) {
        const c = (v << 16) | (v << 8) | v;
        try testing.expect(@abs(@as(i32, @intCast(luma(c))) - @as(i32, @intCast(v))) <= 1);
    }
}

test "averageLuma : zone vide, uniforme, et moitié-moitié" {
    try testing.expectEqual(@as(u32, 0), averageLuma(&.{}));
    const white: [64]u32 = @splat(0xFFFFFF);
    try testing.expectEqual(@as(u32, 255), averageLuma(&white));
    var half: [64]u32 = undefined;
    for (&half, 0..) |*p, i| p.* = if (i < 32) 0xFFFFFF else 0;
    try testing.expectEqual(@as(u32, 127), averageLuma(&half));
}

test "averageLuma : texte noir clairsemé sur blanc reste clair" {
    var px: [100]u32 = undefined;
    for (&px, 0..) |*p, i| p.* = if (i % 5 == 0) 0x000000 else 0xFFFFFF; // 20 % d'encre
    try testing.expect(averageLuma(&px) >= 150);
}

test "averageLuma : pas de débordement sur la plus grande zone" {
    const big: [BOX_MAX * BOX_MAX]u32 = @splat(0xFFFFFF);
    try testing.expectEqual(@as(u32, 255), averageLuma(&big));
}

// =====================================================================
// Inversion des curseurs
// =====================================================================

/// Vrai pour un pixel « gris » (noir, blanc ou nuance) : seuls ceux-là sont inversés,
/// pour garder les parties colorées (cercle bleu d'attente, épingle...).
pub fn isGray(c: u32) bool {
    const r: i32 = @intCast((c >> 16) & 255);
    const g: i32 = @intCast((c >> 8) & 255);
    const b: i32 = @intCast(c & 255);
    return @max(r, g, b) - @min(r, g, b) <= 48;
}

/// Bit (x, y) d'un masque 1 bit/pixel, lignes de `stride` octets, pixel de gauche = bit de poids fort.
pub fn maskBit(mask: []const u8, stride: usize, x: usize, y: usize) u1 {
    return @intCast((mask[y * stride + x / 8] >> @intCast(7 - x % 8)) & 1);
}

/// Inverse noir <-> blanc les pixels gris visibles d'une image 32 bits BGRA de largeur `w`.
/// Si l'image a de la transparence (alpha), c'est elle qui dit ce qui est visible ;
/// sinon c'est le masque ET (`mask`, bit 0 = opaque). Alpha et couleurs sont conservés.
pub fn invertColorPixels(px: []u32, w: usize, mask: []const u8, mask_stride: usize) void {
    const has_alpha = for (px) |c| {
        if (c >> 24 != 0) break true;
    } else false;
    for (px, 0..) |*p, i| {
        const c = p.*;
        const visible = if (has_alpha) c >> 24 != 0 else maskBit(mask, mask_stride, i % w, i / w) == 0;
        if (visible and isGray(c)) p.* = (c & 0xFF000000) | (~c & 0x00FFFFFF);
    }
}

/// Inverse un curseur monochrome. Son masque fait deux fois la hauteur : moitié haute = ET,
/// moitié basse = OU exclusif. Pixel opaque (ET = 0) : OU exclusif 0 = noir, 1 = blanc -> on bascule.
/// Pixels transparents (ET = 1, OUX = 0) et « inverse l'écran » (ET = 1, OUX = 1) : inchangés.
pub fn invertMonoMask(mask: []u8) void {
    std.debug.assert(mask.len % 2 == 0);
    const half = mask.len / 2;
    for (mask[0..half], mask[half..]) |and_bits, *xor_bits| xor_bits.* ^= ~and_bits;
}

test "isGray : noir, blanc, gris oui ; couleurs franches non" {
    try testing.expect(isGray(0x000000));
    try testing.expect(isGray(0xFFFFFF));
    try testing.expect(isGray(0x808080));
    try testing.expect(isGray(0xFF7A7A80)); // gris légèrement teinté, alpha ignoré
    try testing.expect(!isGray(0xFF0000));
    try testing.expect(!isGray(0x0078D7)); // bleu Windows
    try testing.expect(!isGray(0x00FF00));
}

test "maskBit : ordre des bits de gauche à droite" {
    const mask = [_]u8{ 0b1000_0001, 0b0100_0000, 0, 0 }; // stride 2
    try testing.expectEqual(@as(u1, 1), maskBit(&mask, 2, 0, 0));
    try testing.expectEqual(@as(u1, 0), maskBit(&mask, 2, 1, 0));
    try testing.expectEqual(@as(u1, 1), maskBit(&mask, 2, 7, 0));
    try testing.expectEqual(@as(u1, 1), maskBit(&mask, 2, 9, 0));
    try testing.expectEqual(@as(u1, 0), maskBit(&mask, 2, 9, 1));
}

test "invertColorPixels : avec alpha, noir <-> blanc, couleurs et transparence gardées" {
    var px = [_]u32{
        0xFF000000, // noir opaque     -> blanc
        0xFFFFFFFF, // blanc opaque    -> noir
        0x80404040, // gris semi-transparent -> gris clair, alpha gardé
        0xFF0078D7, // bleu            -> inchangé
        0x00FFFFFF, // transparent     -> inchangé
    };
    invertColorPixels(&px, px.len, &.{}, 0);
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), px[0]);
    try testing.expectEqual(@as(u32, 0xFF000000), px[1]);
    try testing.expectEqual(@as(u32, 0x80BFBFBF), px[2]);
    try testing.expectEqual(@as(u32, 0xFF0078D7), px[3]);
    try testing.expectEqual(@as(u32, 0x00FFFFFF), px[4]);
}

test "invertColorPixels : sans alpha, c'est le masque ET qui décide" {
    // 4 pixels sur une ligne ; masque : pixels 0 et 1 opaques (bit 0), 2 et 3 transparents (bit 1)
    var px = [_]u32{ 0x000000, 0xFFFFFF, 0x000000, 0xFFFFFF };
    const mask = [_]u8{ 0b0011_0000, 0 };
    invertColorPixels(&px, 4, &mask, 2);
    try testing.expectEqualSlices(u32, &.{ 0xFFFFFF, 0x000000, 0x000000, 0xFFFFFF }, &px);
}

test "invertColorPixels : sans alpha, masque sur plusieurs lignes" {
    // image 2x2, stride 2 ; ligne 0 : (opaque, transparent), ligne 1 : (transparent, opaque)
    var px = [_]u32{ 0x000000, 0x000000, 0x000000, 0x000000 };
    const mask = [_]u8{ 0b0100_0000, 0, 0b1000_0000, 0 };
    invertColorPixels(&px, 2, &mask, 2);
    try testing.expectEqualSlices(u32, &.{ 0xFFFFFF, 0x000000, 0x000000, 0xFFFFFF }, &px);
}

test "invertColorPixels : deux inversions redonnent l'image d'origine" {
    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();
    var px: [1024]u32 = undefined;
    for (&px) |*p| p.* = rand.int(u32);
    const orig = px;
    invertColorPixels(&px, 32, &.{}, 0);
    invertColorPixels(&px, 32, &.{}, 0);
    try testing.expectEqualSlices(u32, &orig, &px);
}

test "invertMonoMask : opaques inversés, transparents et « inverse l'écran » gardés" {
    // une ligne de 8 pixels, stride 1 : moitié haute ET, moitié basse OUX
    //   pixel : 0 noir, 1 blanc, 2 transparent, 3 inverse-écran, 4-7 noir
    //   ET    : 0 0 1 1 0 0 0 0  = 0b0011_0000
    //   OUX   : 0 1 0 1 0 0 0 0  = 0b0101_0000
    var mask = [_]u8{ 0b0011_0000, 0b0101_0000 };
    invertMonoMask(&mask);
    try testing.expectEqual(@as(u8, 0b0011_0000), mask[0]); // ET inchangé
    //   OUX attendu : 1 0 0 1 1 1 1 1
    try testing.expectEqual(@as(u8, 0b1001_1111), mask[1]);
}

test "invertMonoMask : deux inversions redonnent le masque d'origine" {
    var prng = std.Random.DefaultPrng.init(7);
    var mask: [512]u8 = undefined;
    prng.random().bytes(&mask);
    const orig = mask;
    invertMonoMask(&mask);
    invertMonoMask(&mask);
    try testing.expectEqualSlices(u8, &orig, &mask);
}

// =====================================================================
// Géométrie et tailles
// =====================================================================

/// Coin haut-gauche de la zone lue (carré de côté `box`) pour une souris en `p` :
/// un peu au-dessus et à gauche de la pointe, surtout vers le bas à droite où se dessine
/// le curseur, et toujours à l'intérieur de l'écran virtuel `screen`.
pub fn sampleOrigin(p: Point, box: i32, screen: Rect) Point {
    const off = @divTrunc(box, 4);
    return .{
        .x = @max(screen.x, @min(p.x - off, screen.x + screen.w - box)),
        .y = @max(screen.y, @min(p.y - off, screen.y + screen.h - box)),
    };
}

/// Taille des curseurs en pixels.
/// - `measured` : largeur de la flèche que Windows utilise en ce moment. C'est la référence :
///   Windows arrondit par paliers (à 250 % d'affichage, il prend 64 px et non 32 × 2,5 = 80).
/// - repli si elle est illisible : `metric` (SM_CXCURSOR, taille standard à l'échelle actuelle)
///   × réglage « taille du pointeur » `base` / 32.
pub fn cursorSize(measured: i32, base: u32, metric: i32) i32 {
    if (measured >= 16 and measured <= MAX_CUR) return measured;
    const b: i32 = if (base < 16 or base > 256) 32 else @intCast(base);
    const m: i32 = if (metric < 16 or metric > 256) 32 else metric;
    return @min(@divTrunc(m * b, 32), MAX_CUR);
}

/// Côté de la zone lue : les trois quarts du curseur, borné.
pub fn boxSize(cursor_px: i32) i32 {
    return std.math.clamp(@divTrunc(cursor_px * 3, 4), BOX_MIN, BOX_MAX);
}

const screen_1080: Rect = .{ .x = 0, .y = 0, .w = 1920, .h = 1080 };

test "sampleOrigin : au milieu, la zone part un peu en haut à gauche de la pointe" {
    const o = sampleOrigin(.{ .x = 500, .y = 400 }, 60, screen_1080);
    try testing.expectEqual(@as(i32, 485), o.x);
    try testing.expectEqual(@as(i32, 385), o.y);
}

test "sampleOrigin : la zone reste dans l'écran aux quatre coins" {
    const pts = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 1919, .y = 0 }, .{ .x = 0, .y = 1079 }, .{ .x = 1919, .y = 1079 }, .{ .x = -50, .y = 5000 } };
    for (pts) |p| {
        const o = sampleOrigin(p, 60, screen_1080);
        try testing.expect(o.x >= 0 and o.y >= 0);
        try testing.expect(o.x + 60 <= 1920 and o.y + 60 <= 1080);
    }
}

test "sampleOrigin : écran virtuel à coordonnées négatives (écran à gauche du principal)" {
    const s: Rect = .{ .x = -2560, .y = -200, .w = 4480, .h = 1640 };
    const o = sampleOrigin(.{ .x = -2560, .y = -200 }, 60, s);
    try testing.expectEqual(@as(i32, -2560), o.x);
    try testing.expectEqual(@as(i32, -200), o.y);
    const o2 = sampleOrigin(.{ .x = -1000, .y = 300 }, 60, s);
    try testing.expectEqual(@as(i32, -1015), o2.x);
    try testing.expectEqual(@as(i32, 285), o2.y);
}

test "cursorSize : la taille mesurée sur Windows l'emporte" {
    try testing.expectEqual(@as(i32, 64), cursorSize(64, 32, 64));
    try testing.expectEqual(@as(i32, 64), cursorSize(64, 999, 0)); // même si le reste est absurde
    try testing.expectEqual(@as(i32, 48), cursorSize(48, 32, 64));
}

test "cursorSize : repli sur la taille standard × réglage de taille" {
    try testing.expectEqual(@as(i32, 64), cursorSize(0, 32, 64)); // 250 % : palier de 64 px
    try testing.expectEqual(@as(i32, 96), cursorSize(0, 48, 64)); // pointeur agrandi
    try testing.expectEqual(@as(i32, 32), cursorSize(0, 32, 32)); // 100 %
    try testing.expectEqual(@as(i32, 48), cursorSize(-1, 32, 48)); // 150 %
}

test "cursorSize : valeurs absurdes ramenées au défaut, résultat plafonné" {
    try testing.expectEqual(@as(i32, 64), cursorSize(0, 0, 64)); // réglage illisible -> 32
    try testing.expectEqual(@as(i32, 64), cursorSize(0, 100_000, 64));
    try testing.expectEqual(@as(i32, 32), cursorSize(0, 32, 0)); // métrique illisible -> 32
    try testing.expectEqual(@as(i32, 64), cursorSize(MAX_CUR + 1, 32, 64)); // mesure hors bornes ignorée
    try testing.expectEqual(@as(i32, MAX_CUR), cursorSize(0, 256, 256)); // plafonné
}

test "boxSize : trois quarts du curseur, bornés" {
    try testing.expectEqual(@as(i32, 24), boxSize(32));
    try testing.expectEqual(@as(i32, 60), boxSize(80));
    try testing.expectEqual(@as(i32, BOX_MIN), boxSize(8));
    try testing.expectEqual(@as(i32, BOX_MAX), boxSize(MAX_CUR));
}

// =====================================================================
// Rythme de la minuterie
// =====================================================================

/// Lectures par seconde proposées dans le menu quand la souris bouge.
pub const RATES = [_]u32{ 3, 5, 10, 20 };
pub const DEFAULT_RATE = 10;
pub const STILL_MS = 1000; // après 1 s sans mouvement...
pub const IDLE_MS = 250; // ...un coup d'œil toutes les 250 ms (jamais plus souvent qu'en mouvement)

/// Ramène une valeur lue (registre...) à l'un des rythmes proposés, sinon au défaut.
pub fn validRate(v: u32) u32 {
    for (RATES) |r| {
        if (r == v) return v;
    }
    return DEFAULT_RATE;
}

/// Période de la minuterie (ms) pour un rythme de lectures par seconde.
pub fn tickMs(rate: u32) u32 {
    return 1000 / validRate(rate);
}

pub const Ticker = struct {
    tick_ms: u32 = 1000 / DEFAULT_RATE,
    last: Point = .{ .x = std.math.minInt(i32), .y = std.math.minInt(i32) },
    still: u32 = 0,
    slow: bool = false,

    pub const Action = struct {
        /// faut-il lire l'écran maintenant ?
        sample: bool = false,
        /// nouvelle période de la minuterie, si elle change
        interval_ms: ?u32 = null,
    };

    pub fn init(rate: u32) Ticker {
        return .{ .tick_ms = tickMs(rate) };
    }

    /// Nombre de tics sans mouvement avant de passer en mode lent (environ 1 s).
    pub fn stillTicks(self: Ticker) u32 {
        return @max(1, STILL_MS / self.tick_ms);
    }

    /// Période en mode lent : 250 ms, ou celle du mode rapide si elle est plus longue.
    pub fn idleMs(self: Ticker) u32 {
        return @max(IDLE_MS, self.tick_ms);
    }

    /// À appeler à chaque tic de la minuterie avec la position de la souris.
    pub fn tick(self: *Ticker, p: Point) Action {
        if (p.x != self.last.x or p.y != self.last.y) {
            self.last = p;
            self.still = 0;
            if (self.slow) {
                self.slow = false;
                return .{ .sample = true, .interval_ms = self.tick_ms };
            }
            return .{ .sample = true };
        }
        if (self.slow) return .{ .sample = true }; // le contenu sous la souris a pu changer
        self.still += 1;
        if (self.still >= self.stillTicks()) {
            self.slow = true;
            return .{ .sample = true, .interval_ms = self.idleMs() };
        }
        return .{};
    }
};

test "validRate / tickMs : rythmes proposés gardés, le reste ramené au défaut" {
    for (RATES) |r| try testing.expectEqual(r, validRate(r));
    try testing.expectEqual(@as(u32, DEFAULT_RATE), validRate(0));
    try testing.expectEqual(@as(u32, DEFAULT_RATE), validRate(7));
    try testing.expectEqual(@as(u32, DEFAULT_RATE), validRate(1000));
    try testing.expectEqual(@as(u32, 333), tickMs(3));
    try testing.expectEqual(@as(u32, 200), tickMs(5));
    try testing.expectEqual(@as(u32, 100), tickMs(10));
    try testing.expectEqual(@as(u32, 50), tickMs(20));
    try testing.expectEqual(@as(u32, 100), tickMs(42));
}

test "Ticker : le premier tic lit toujours l'écran" {
    for (RATES) |r| {
        var t = Ticker.init(r);
        try testing.expect(t.tick(.{ .x = 0, .y = 0 }).sample);
    }
}

test "Ticker : souris en mouvement, une lecture à chaque tic, à tous les rythmes" {
    for (RATES) |r| {
        var t = Ticker.init(r);
        var i: i32 = 0;
        while (i < 50) : (i += 1) {
            const a = t.tick(.{ .x = i, .y = i });
            try testing.expect(a.sample);
            try testing.expectEqual(@as(?u32, null), a.interval_ms);
        }
    }
}

test "Ticker : souris immobile, rien pendant environ 1 s puis passage en mode lent" {
    for (RATES) |r| {
        var t = Ticker.init(r);
        const p: Point = .{ .x = 10, .y = 10 };
        _ = t.tick(p);
        var i: u32 = 1;
        while (i < t.stillTicks()) : (i += 1) {
            const a = t.tick(p);
            try testing.expect(!a.sample);
            try testing.expectEqual(@as(?u32, null), a.interval_ms);
        }
        // délai avant le mode lent : entre 0,9 et 1 s
        const delay = t.stillTicks() * t.tick_ms;
        try testing.expect(delay >= 900 and delay <= 1000);
        const a = t.tick(p);
        try testing.expect(a.sample);
        try testing.expectEqual(@as(?u32, t.idleMs()), a.interval_ms);
        // en mode lent : une lecture par tic, sans changer la période
        const b = t.tick(p);
        try testing.expect(b.sample);
        try testing.expectEqual(@as(?u32, null), b.interval_ms);
    }
}

test "Ticker : le mode lent n'est jamais plus fréquent que le mode rapide" {
    for (RATES) |r| {
        const t = Ticker.init(r);
        try testing.expect(t.idleMs() >= t.tick_ms);
        try testing.expect(t.idleMs() >= IDLE_MS);
    }
}

test "Ticker : un mouvement en mode lent repasse au rythme choisi" {
    for (RATES) |r| {
        var t = Ticker.init(r);
        const p: Point = .{ .x = 10, .y = 10 };
        var i: u32 = 0;
        while (i <= t.stillTicks()) : (i += 1) _ = t.tick(p);
        try testing.expect(t.slow);
        const a = t.tick(.{ .x = 11, .y = 10 });
        try testing.expect(a.sample);
        try testing.expectEqual(@as(?u32, tickMs(r)), a.interval_ms);
        try testing.expect(!t.slow);
    }
}

/// Simule `duration_ms` de fonctionnement et compte réveils et lectures d'écran.
fn simulate(rate: u32, duration_ms: u32, moving: bool) struct { wakeups: u32, samples: u32 } {
    var t = Ticker.init(rate);
    var now: u32 = 0;
    var interval: u32 = t.tick_ms;
    var wakeups: u32 = 0;
    var samples: u32 = 0;
    var x: i32 = 0;
    while (now < duration_ms) : (now += interval) {
        if (moving) x += 3;
        const a = t.tick(.{ .x = x, .y = 0 });
        wakeups += 1;
        if (a.sample) samples += 1;
        if (a.interval_ms) |ms| interval = ms;
    }
    return .{ .wakeups = wakeups, .samples = samples };
}

test "Ticker : budget souris immobile, au plus ~4 lectures par seconde, à tous les rythmes" {
    for (RATES) |r| {
        const s = simulate(r, 60_000, false);
        try testing.expect(s.samples <= 60 * 4 + 2);
        try testing.expect(s.wakeups <= 60 * 4 + 25);
    }
}

test "Ticker : budget souris en mouvement, exactement le rythme choisi" {
    for (RATES) |r| {
        const s = simulate(r, 10_000, true);
        errdefer std.debug.print("rythme {d}/s : {d} lectures en 10 s\n", .{ r, s.samples });
        // 10 s au rythme r : 10 x r lectures (à une près pour 3/s, période de 333 ms)
        try testing.expect(s.samples >= 10 * r and s.samples <= 10 * r + 1);
        try testing.expectEqual(s.samples, s.wakeups);
    }
}

// =====================================================================
// Secouer pour retrouver la souris : curseur agrandi et rouge
// =====================================================================

/// Rouge du curseur agrandi (0xRRGGBB), assez soutenu pour se voir sur fond clair
/// comme sur fond sombre (le contour reste blanc).
pub const RED: u32 = 0xE81123;
/// Facteur d'agrandissement : 2 tombe sur une taille présente dans les fichiers de
/// Windows (32 -> 64, 48 -> 96, 64 -> 128), donc un contour net.
pub const SHAKE_SCALE = 2;
/// Période de lecture de la position pendant que la souris bouge (ms).
pub const SHAKE_TICK_MS = 30;
/// Nombre de demi-tours rapides qui déclenchent l'agrandissement...
pub const SHAKE_TURNS = 4;
/// ...s'ils tiennent dans cette durée (ms).
pub const SHAKE_WINDOW_MS = 1000;
/// Durée pendant laquelle le curseur reste agrandi après le dernier demi-tour (ms).
pub const SHAKE_HOLD_MS = 600;

/// Taille du curseur agrandi pour un curseur normal de `px`.
pub fn bigSize(px: i32) i32 {
    return @min(px * SHAKE_SCALE, MAX_CUR);
}

/// Teinte d'un pixel gris de luminance `l` : rouge pour le noir, blanc pour le blanc,
/// dégradé entre les deux (bords adoucis des curseurs avec transparence).
pub fn redTint(l: u32) u32 {
    const k = @min(l, 255);
    var out: u32 = 0;
    inline for (.{ 16, 8, 0 }) |shift| {
        const c = (RED >> shift) & 255;
        out |= (c + (255 - c) * k / 255) << shift;
    }
    return out;
}

/// Version rouge d'un curseur 32 bits de la version noire (corps noir, contour blanc) :
/// les pixels gris visibles prennent la teinte rouge, les couleurs franches sont gardées.
/// Sans transparence d'origine, l'alpha est fabriqué à partir du masque ET.
pub fn reddenColorPixels(px: []u32, w: usize, mask: []const u8, mask_stride: usize) void {
    const has_alpha = for (px) |c| {
        if (c >> 24 != 0) break true;
    } else false;
    for (px, 0..) |*p, i| {
        const c = p.*;
        const visible = if (has_alpha) c >> 24 != 0 else maskBit(mask, mask_stride, i % w, i / w) == 0;
        if (!visible) {
            p.* = 0;
            continue;
        }
        const a: u32 = if (has_alpha) c & 0xFF000000 else 0xFF000000;
        p.* = a | if (isGray(c)) redTint(luma(c)) else c & 0x00FFFFFF;
    }
}

/// Version rouge 32 bits d'un curseur monochrome de la version noire (masque ET + OU
/// exclusif de hauteur 2h). Opaque noir -> rouge, opaque blanc -> blanc ; les pixels
/// transparents et « inverse l'écran » deviennent transparents.
pub fn monoToRed(mask: []const u8, stride: usize, w: usize, h: usize, out: []u32) void {
    std.debug.assert(out.len >= w * h and mask.len >= stride * h * 2);
    for (0..h) |y| {
        for (0..w) |x| {
            out[y * w + x] = if (maskBit(mask, stride, x, y) == 1)
                0
            else if (maskBit(mask, stride, x, y + h) == 1)
                0xFFFFFFFF
            else
                0xFF000000 | RED;
        }
    }
}

/// Mouvement de va-et-vient sur un axe : repère les demi-tours d'amplitude suffisante.
const ShakeAxis = struct {
    dir: i32 = 0, // sens de l'aller en cours : -1, 0 (pas encore), +1
    start: i32 = 0, // point de départ de l'aller en cours
    ext: i32 = 0, // point le plus loin atteint dans ce sens
    turns: [SHAKE_TURNS]u32 = @splat(0), // instants des derniers demi-tours amples
    n: u32 = 0, // nombre de demi-tours amples enregistrés (plafonné)
    next: usize = 0,

    fn reset(a: *ShakeAxis, v: i32) void {
        a.* = .{ .start = v, .ext = v };
    }

    /// Vrai si un demi-tour d'au moins `min_seg` px vient d'avoir lieu.
    fn feed(a: *ShakeAxis, v: i32, t: u32, min_seg: i32, jitter: i32) bool {
        if (a.dir == 0) {
            if (@abs(v - a.start) > jitter) {
                a.dir = if (v > a.start) 1 else -1;
                a.ext = v;
            }
            return false;
        }
        if ((v - a.ext) * a.dir > 0) { // on continue dans le même sens
            a.ext = v;
            return false;
        }
        if ((a.ext - v) * a.dir <= jitter) return false; // petit tremblement : ignoré
        const amp: i32 = @intCast(@abs(a.ext - a.start));
        a.start = a.ext;
        a.ext = v;
        a.dir = -a.dir;
        if (amp < min_seg) return false;
        a.turns[a.next] = t;
        a.next = (a.next + 1) % SHAKE_TURNS;
        a.n = @min(a.n + 1, SHAKE_TURNS);
        return true;
    }

    /// Vrai si les SHAKE_TURNS derniers demi-tours tiennent dans SHAKE_WINDOW_MS.
    fn shaking(a: ShakeAxis, t: u32) bool {
        if (a.n < SHAKE_TURNS) return false;
        const oldest = a.turns[a.next]; // le plus ancien, puisque le tampon est plein
        return t -% oldest <= SHAKE_WINDOW_MS;
    }
};

/// Détecte qu'on secoue la souris pour la retrouver : plusieurs allers-retours rapides
/// et amples, horizontaux ou verticaux. Reçoit la position environ toutes les 30 ms.
pub const Shake = struct {
    min_seg: i32,
    jitter: i32,
    x: ShakeAxis = .{},
    y: ShakeAxis = .{},
    started: bool = false,
    big: bool = false,
    until: u32 = 0,

    pub const Event = enum { none, start, stop };

    /// L'amplitude minimale d'un aller est le double de la taille du curseur : elle suit
    /// l'agrandissement de l'écran, et un petit ajustement de visée ne compte pas.
    pub fn init(cursor_px: i32) Shake {
        const seg = @max(32, cursor_px * 2);
        return .{ .min_seg = seg, .jitter = @max(2, @divTrunc(seg, 8)) };
    }

    /// À appeler à chaque lecture de la position, `t` en millisecondes (GetTickCount :
    /// le passage par zéro au bout de 49 jours est géré).
    pub fn feed(s: *Shake, t: u32, p: Point) Event {
        if (!s.started) {
            s.started = true;
            s.x.reset(p.x);
            s.y.reset(p.y);
            return .none;
        }
        const tx = s.x.feed(p.x, t, s.min_seg, s.jitter);
        const ty = s.y.feed(p.y, t, s.min_seg, s.jitter);
        if (tx or ty) {
            if (s.big) {
                s.until = t +% SHAKE_HOLD_MS;
            } else if (s.x.shaking(t) or s.y.shaking(t)) {
                s.big = true;
                s.until = t +% SHAKE_HOLD_MS;
                return .start;
            }
        }
        if (s.big and @as(i32, @bitCast(t -% s.until)) >= 0) {
            s.big = false;
            s.x.reset(p.x);
            s.y.reset(p.y);
            return .stop;
        }
        return .none;
    }

    /// Arrête la détection (souris immobile, pause) ; vrai si le curseur était agrandi.
    pub fn stop(s: *Shake) bool {
        const was = s.big;
        s.* = .{ .min_seg = s.min_seg, .jitter = s.jitter };
        return was;
    }
};

/// Simule une souris qui fait des allers-retours d'amplitude `amp` à `hz` allers-retours
/// par seconde sur l'axe x (ou y), lue toutes les SHAKE_TICK_MS. Renvoie l'instant (ms,
/// relatif à `t0`) du déclenchement, ou null.
fn shakeAt(s: *Shake, t0: u32, duration_ms: u32, amp: i32, hz: f32, vertical: bool) ?u32 {
    var t: u32 = 0;
    while (t <= duration_ms) : (t += SHAKE_TICK_MS) {
        const phase = @as(f32, @floatFromInt(t)) / 1000 * hz * 2 * std.math.pi;
        const d: i32 = @intFromFloat(@as(f32, @floatFromInt(amp)) / 2 * @sin(phase));
        const p: Point = if (vertical) .{ .x = 800, .y = 500 + d } else .{ .x = 800 + d, .y = 500 };
        if (s.feed(t0 +% t, p) == .start) return t;
    }
    return null;
}

test "bigSize : double, plafonné à la taille des tampons" {
    try testing.expectEqual(@as(i32, 64), bigSize(32));
    try testing.expectEqual(@as(i32, 128), bigSize(64));
    try testing.expectEqual(@as(i32, MAX_CUR), bigSize(200));
}

test "redTint : noir -> rouge, blanc -> blanc, dégradé entre les deux" {
    try testing.expectEqual(RED, redTint(0));
    try testing.expectEqual(@as(u32, 0xFFFFFF), redTint(255));
    try testing.expectEqual(@as(u32, 0xFFFFFF), redTint(1000));
    const mid = redTint(128);
    try testing.expect(luma(mid) > luma(RED) and luma(mid) < 255);
    try testing.expect((mid >> 16) & 255 >= (mid >> 8) & 255); // reste rougeâtre
}

test "reddenColorPixels : gris -> teinte rouge, couleurs et transparence gardées" {
    var px = [_]u32{ 0xFF000000, 0xFFFFFFFF, 0x00000000, 0xFF2060E0, 0x80000000 };
    reddenColorPixels(&px, 5, &.{0}, 1);
    try testing.expectEqual(@as(u32, 0xFF000000 | RED), px[0]); // corps noir -> rouge
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), px[1]); // contour blanc gardé
    try testing.expectEqual(@as(u32, 0), px[2]); // transparent
    try testing.expectEqual(@as(u32, 0xFF2060E0), px[3]); // bleu (cercle d'attente) gardé
    try testing.expectEqual(@as(u32, 0x80000000 | RED), px[4]); // bord adouci : alpha gardé
}

test "reddenColorPixels : sans alpha, le masque ET décide et l'alpha est fabriqué" {
    var px = [_]u32{ 0x000000, 0xFFFFFF, 0x000000, 0x123456 };
    reddenColorPixels(&px, 4, &.{0b0010_0000}, 1); // 3e pixel transparent
    try testing.expectEqual(@as(u32, 0xFF000000 | RED), px[0]);
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), px[1]);
    try testing.expectEqual(@as(u32, 0), px[2]);
    try testing.expectEqual(@as(u32, 0xFF123456), px[3]);
}

test "monoToRed : noir -> rouge, blanc -> blanc, transparent et « inverse l'écran » -> transparent" {
    // 4 pixels sur une ligne, stride 2 octets ; ET puis OU exclusif
    const mask = [_]u8{ 0b0011_0000, 0, 0b0101_0000, 0 };
    var out: [4]u32 = undefined;
    monoToRed(&mask, 2, 4, 1, &out);
    try testing.expectEqual(@as(u32, 0xFF000000 | RED), out[0]); // ET 0, OUX 0 : noir
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), out[1]); // ET 0, OUX 1 : blanc
    try testing.expectEqual(@as(u32, 0), out[2]); // ET 1, OUX 0 : transparent
    try testing.expectEqual(@as(u32, 0), out[3]); // ET 1, OUX 1 : inverse l'écran
}

test "Shake : seuils proportionnels à la taille du curseur" {
    const s32 = Shake.init(32);
    const s64 = Shake.init(64);
    try testing.expectEqual(@as(i32, 64), s32.min_seg);
    try testing.expectEqual(@as(i32, 128), s64.min_seg);
    try testing.expect(s64.jitter > s32.jitter);
    try testing.expectEqual(@as(i32, 32), Shake.init(0).min_seg);
}

test "Shake : secouer franchement déclenche en moins d'une seconde, à l'horizontale comme à la verticale" {
    for ([_]bool{ false, true }) |vertical| {
        for ([_]f32{ 2.5, 3, 4, 6 }) |hz| {
            var s = Shake.init(32);
            const t = shakeAt(&s, 0, 2000, 400, hz, vertical) orelse return error.PasDeclenche;
            try testing.expect(t < 1000);
            try testing.expect(s.big);
        }
    }
}

test "Shake : va-et-vient trop petit ou trop lent : rien" {
    var small = Shake.init(64); // seuil 128 px
    try testing.expectEqual(@as(?u32, null), shakeAt(&small, 0, 3000, 100, 4, false));
    var slow = Shake.init(32);
    try testing.expectEqual(@as(?u32, null), shakeAt(&slow, 0, 5000, 600, 1, false));
}

test "Shake : déplacements ordinaires, visée avec dépassement et correction : rien" {
    var s = Shake.init(32);
    var t: u32 = 0;
    const path = [_]Point{
        .{ .x = 0, .y = 0 },     .{ .x = 200, .y = 50 },  .{ .x = 600, .y = 150 }, .{ .x = 900, .y = 220 },
        .{ .x = 960, .y = 230 }, .{ .x = 930, .y = 228 }, .{ .x = 920, .y = 226 }, .{ .x = 924, .y = 226 },
        .{ .x = 700, .y = 400 }, .{ .x = 300, .y = 700 }, .{ .x = 100, .y = 760 }, .{ .x = 140, .y = 750 },
    };
    for (path) |p| {
        try testing.expectEqual(Shake.Event.none, s.feed(t, p));
        t += SHAKE_TICK_MS;
    }
}

test "Shake : sélectionner du texte en allant et venant lentement : rien" {
    var s = Shake.init(32);
    // trois allers-retours de 300 px, chacun en 1,2 s
    try testing.expectEqual(@as(?u32, null), shakeAt(&s, 0, 3600, 300, 1.0 / 1.2, false));
}

test "Shake : reste agrandi tant qu'on secoue, revient ensuite" {
    var s = Shake.init(32);
    const t_start = shakeAt(&s, 0, 2000, 400, 4, false) orelse return error.PasDeclenche;
    // on continue à secouer pendant 2 s : aucun retour
    var t: u32 = t_start + SHAKE_TICK_MS;
    var stopped_at: ?u32 = null;
    const end = t + 2000;
    while (t < end) : (t += SHAKE_TICK_MS) {
        const phase = @as(f32, @floatFromInt(t)) / 1000 * 4 * 2 * std.math.pi;
        const x: i32 = 800 + @as(i32, @intFromFloat(200 * @sin(phase)));
        if (s.feed(t, .{ .x = x, .y = 500 }) == .stop) stopped_at = t;
    }
    try testing.expectEqual(@as(?u32, null), stopped_at);
    // souris arrêtée : retour au bout d'environ SHAKE_HOLD_MS
    while (t < end + 2000) : (t += SHAKE_TICK_MS) {
        if (s.feed(t, .{ .x = 800, .y = 500 }) == .stop) {
            stopped_at = t;
            break;
        }
    }
    const d = (stopped_at orelse return error.PasRevenu) - end;
    try testing.expect(d <= SHAKE_HOLD_MS + 2 * SHAKE_TICK_MS);
    try testing.expect(!s.big);
}

test "Shake : après un retour, il faut secouer à nouveau pour redéclencher" {
    var s = Shake.init(32);
    _ = shakeAt(&s, 0, 2000, 400, 4, false) orelse return error.PasDeclenche;
    var t: u32 = 2000;
    while (s.big) : (t += SHAKE_TICK_MS) _ = s.feed(t, .{ .x = 0, .y = 0 });
    try testing.expectEqual(Shake.Event.none, s.feed(t + 30, .{ .x = 400, .y = 0 }));
    try testing.expect(shakeAt(&s, t + 60, 2000, 400, 4, false) != null);
}

test "Shake : le passage par zéro du compteur de millisecondes ne gêne pas" {
    var s = Shake.init(32);
    const t0: u32 = std.math.maxInt(u32) - 500; // déborde en cours de route
    _ = shakeAt(&s, t0, 2000, 400, 4, false) orelse return error.PasDeclenche;
}

test "Shake : stop() dit si le curseur était agrandi et remet tout à zéro" {
    var s = Shake.init(32);
    try testing.expect(!s.stop());
    _ = shakeAt(&s, 0, 2000, 400, 4, false) orelse return error.PasDeclenche;
    try testing.expect(s.stop());
    try testing.expect(!s.big and !s.started);
    try testing.expectEqual(@as(i32, 64), s.min_seg);
}

// =====================================================================
// Chaînes et icône
// =====================================================================

/// Concatène des chaînes UTF-16 dans `buf` (tronque si besoin) et termine par 0.
pub fn join(buf: []u16, parts: []const []const u16) [:0]const u16 {
    std.debug.assert(buf.len > 0);
    var n: usize = 0;
    for (parts) |p| {
        const k = @min(p.len, buf.len - 1 - n);
        @memcpy(buf[n..][0..k], p[0..k]);
        n += k;
    }
    buf[n] = 0;
    return buf[0..n :0];
}

/// Dessine l'icône de notification dans `buf` (s × s pixels BGRA) : un rond mi-noir
/// mi-blanc cerclé de gris, en gris atténué quand l'outil est en pause.
pub fn renderTrayIcon(buf: []u32, s: usize, on: bool) void {
    std.debug.assert(buf.len >= s * s);
    const c = @as(f32, @floatFromInt(s - 1)) / 2;
    const r = @as(f32, @floatFromInt(s)) / 2 - 0.5;
    const left: u32 = if (on) 0x101010 else 0x505050;
    const right: u32 = if (on) 0xF5F5F5 else 0xB0B0B0;
    for (0..s) |y| {
        for (0..s) |x| {
            const fx: f32 = @floatFromInt(x);
            const dx = fx - c;
            const dy = @as(f32, @floatFromInt(y)) - c;
            const d = @sqrt(dx * dx + dy * dy);
            const a = std.math.clamp(r - d + 0.5, 0, 1);
            const rgb: u32 = if (d > r - 1.2) 0x808080 else if (fx <= c) left else right;
            buf[y * s + x] = (@as(u32, @intFromFloat(a * 255)) << 24) | rgb;
        }
    }
}

const L = std.unicode.utf8ToUtf16LeStringLiteral;

test "join : concatène et termine par 0" {
    var buf: [32]u16 = undefined;
    const s = join(&buf, &.{ L("C:\\Windows"), L("\\Cursors\\"), L("arrow_r.cur") });
    try testing.expectEqualSlices(u16, L("C:\\Windows\\Cursors\\arrow_r.cur"), s);
    try testing.expectEqual(@as(u16, 0), buf[s.len]);
}

test "join : tronque proprement si le tampon est trop petit" {
    var buf: [6]u16 = undefined;
    const s = join(&buf, &.{ L("abc"), L("defgh") });
    try testing.expectEqualSlices(u16, L("abcde"), s);
    try testing.expectEqual(@as(u16, 0), buf[5]);
}

test "renderTrayIcon : coins transparents, moitié gauche sombre, moitié droite claire" {
    var buf: [32 * 32]u32 = undefined;
    renderTrayIcon(&buf, 32, true);
    try testing.expectEqual(@as(u32, 0), buf[0] >> 24); // coin
    try testing.expectEqual(@as(u32, 0), buf[31] >> 24);
    const mid = 16 * 32;
    try testing.expectEqual(@as(u32, 255), buf[mid + 8] >> 24); // opaque
    try testing.expect(luma(buf[mid + 8]) < 40); // gauche sombre
    try testing.expect(luma(buf[mid + 24]) > 220); // droite claire
}

test "renderTrayIcon : en pause, contraste atténué" {
    var on: [32 * 32]u32 = undefined;
    var off: [32 * 32]u32 = undefined;
    renderTrayIcon(&on, 32, true);
    renderTrayIcon(&off, 32, false);
    const mid = 16 * 32;
    const contrast_on = luma(on[mid + 24]) - luma(on[mid + 8]);
    const contrast_off = luma(off[mid + 24]) - luma(off[mid + 8]);
    try testing.expect(contrast_off < contrast_on);
}
