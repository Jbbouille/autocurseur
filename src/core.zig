//! Logique pure d'AutoCurseur : aucune dépendance à Windows, entièrement testée.
//!
//! - `decide`      : choix noir / blanc avec hystérésis
//! - `luma`        : luminance perçue d'un pixel, `averageLuma` d'une zone
//! - `invertColorPixels` / `invertMono` : fabrication de la version inversée d'un curseur
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

/// Inverse une image monochrome de curseur : `xor_bits` (couleur) et `and_bits` (masque de
/// transparence) ont la même disposition. Pixel opaque (ET = 0) : la couleur bascule.
/// Pixels transparents (ET = 1, OUX = 0) et « inverse l'écran » (ET = 1, OUX = 1) : inchangés.
pub fn invertMono(xor_bits: []u8, and_bits: []const u8) void {
    std.debug.assert(xor_bits.len == and_bits.len);
    for (xor_bits, and_bits) |*x, a| x.* ^= ~a;
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

test "invertMono : opaques inversés, transparents et « inverse l'écran » gardés" {
    // une ligne de 8 pixels
    //   pixel : 0 noir, 1 blanc, 2 transparent, 3 inverse-écran, 4-7 noir
    //   ET    : 0 0 1 1 0 0 0 0  = 0b0011_0000
    //   OUX   : 0 1 0 1 0 0 0 0  = 0b0101_0000
    const and_bits = [_]u8{0b0011_0000};
    var xor_bits = [_]u8{0b0101_0000};
    invertMono(&xor_bits, &and_bits);
    //   OUX attendu : 1 0 0 1 1 1 1 1
    try testing.expectEqual(@as(u8, 0b1001_1111), xor_bits[0]);
}

test "invertMono : deux inversions redonnent l'image d'origine" {
    var prng = std.Random.DefaultPrng.init(7);
    var xor_bits: [256]u8 = undefined;
    var and_bits: [256]u8 = undefined;
    prng.random().bytes(&xor_bits);
    prng.random().bytes(&and_bits);
    const orig = xor_bits;
    invertMono(&xor_bits, &and_bits);
    invertMono(&xor_bits, &and_bits);
    try testing.expectEqualSlices(u8, &orig, &xor_bits);
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

/// Taille des curseurs à demander à Windows, en pixels.
/// - `measured` : largeur de la flèche que Windows utilise en ce moment. C'est la référence :
///   Windows arrondit par paliers (à 250 % d'affichage, il prend 64 px et non 32 × 2,5 = 80).
/// - repli si elle est illisible : `metric` (SM_CXCURSOR, taille standard à l'échelle actuelle).
/// Le réglage « taille du pointeur » de l'accessibilité n'entre pas en compte : Windows
/// l'applique lui-même à l'affichage, à ses curseurs comme aux nôtres (voir displayedSize).
pub fn cursorSize(measured: i32, metric: i32) i32 {
    if (measured >= 16 and measured <= MAX_CUR) return measured;
    return if (metric < 16 or metric > MAX_CUR) 32 else metric;
}

/// Réglage « taille du pointeur » (CursorBaseSize : 32 pour la taille 1, puis par pas de 16),
/// ramené à des valeurs possibles.
pub fn pointerBase(base: u32) u32 {
    return if (base < 32 or base > 256) 32 else base;
}

/// Taille à laquelle Windows affiche un curseur de `cursor_px` sur l'écran principal, une fois
/// appliqué le réglage « taille du pointeur » `base` (48 px et taille 80 -> 120 px).
pub fn displayedSize(cursor_px: i32, base: u32) i32 {
    return @divTrunc(cursor_px * @as(i32, @intCast(pointerBase(base))), 32);
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
    try testing.expectEqual(@as(i32, 64), cursorSize(64, 64));
    try testing.expectEqual(@as(i32, 64), cursorSize(64, 0)); // même si la métrique est absurde
    try testing.expectEqual(@as(i32, 48), cursorSize(48, 64));
}

test "cursorSize : repli sur la taille standard, sans le réglage d'accessibilité" {
    try testing.expectEqual(@as(i32, 64), cursorSize(0, 64)); // 250 % : palier de 64 px
    try testing.expectEqual(@as(i32, 32), cursorSize(0, 32)); // 100 %
    try testing.expectEqual(@as(i32, 48), cursorSize(-1, 48)); // 150 %
}

test "cursorSize : valeurs absurdes ramenées au défaut" {
    try testing.expectEqual(@as(i32, 32), cursorSize(0, 0)); // métrique illisible -> 32
    try testing.expectEqual(@as(i32, 32), cursorSize(0, 100_000));
    try testing.expectEqual(@as(i32, 64), cursorSize(MAX_CUR + 1, 64)); // mesure hors bornes ignorée
}

test "displayedSize : le réglage « taille du pointeur » agrandit à l'affichage" {
    try testing.expectEqual(@as(i32, 48), displayedSize(48, 32)); // taille 1
    try testing.expectEqual(@as(i32, 120), displayedSize(48, 80)); // taille 4 : mesuré sur Windows 11
    try testing.expectEqual(@as(i32, 160), displayedSize(64, 80));
    try testing.expectEqual(@as(i32, 48 * 8), displayedSize(48, 256)); // taille maximale
    try testing.expectEqual(@as(i32, 48), displayedSize(48, 0)); // réglage illisible -> taille 1
    try testing.expectEqual(@as(i32, 48), displayedSize(48, 100_000));
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

/// Après un changement de réglages de Windows (taille du pointeur, écran…), instants (ms
/// depuis la dernière notification) où AutoCurseur remet ses curseurs. Windows recharge
/// parfois les siens après sa notification, sans en envoyer d'autre : on attend qu'il ait
/// fini, puis on repasse deux fois pour être sûr.
pub const SETTLE_MS = [_]u32{ 500, 1500, 3000 };

test "SETTLE_MS : croissants, le premier laisse à Windows le temps de finir" {
    try testing.expect(SETTLE_MS[0] >= 300);
    for (SETTLE_MS[1..], SETTLE_MS[0 .. SETTLE_MS.len - 1]) |b, a| try testing.expect(b > a);
}

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
/// Nombre de demi-tours amples et consécutifs qui déclenchent l'agrandissement
/// (5 demi-tours = deux allers-retours et demi)...
pub const SHAKE_TURNS = 5;
/// ...s'ils tiennent dans cette durée (ms) : il faut secouer à deux allers-retours par
/// seconde au moins.
pub const SHAKE_WINDOW_MS = 1000;
/// Amplitude minimale d'un aller, en tailles de curseur (144 px pour un curseur de 48).
pub const SHAKE_SEG_FACTOR = 3;
/// Durée pendant laquelle le curseur reste agrandi après le dernier demi-tour (ms).
pub const SHAKE_HOLD_MS = 600;

/// Taille du curseur agrandi pour un curseur normal de `px`.
pub fn bigSize(px: i32) i32 {
    return @min(px * SHAKE_SCALE, MAX_CUR);
}

/// Taille du curseur rouge à demander quand le pointeur est agrandi par le réglage `base` de
/// l'accessibilité : le double du curseur normal, sans que Windows l'affiche à plus de 255 px
/// sur l'écran principal. Au-delà, il le dessine lui-même et le charger coûte cher (0,7 s pour
/// le jeu rouge à la taille maximale du pointeur, mesuré). Un pointeur déjà énorme ne grossit
/// donc plus : il devient seulement rouge.
pub fn bigSizeFor(px: i32, base: u32) i32 {
    const max_loaded: i32 = @intCast(255 * 32 / pointerBase(base));
    return @max(px, @min(bigSize(px), max_loaded));
}

test "bigSizeFor : double tant que l'affichage reste sous 255 px, jamais plus petit que le normal" {
    try testing.expectEqual(@as(i32, 96), bigSizeFor(48, 32)); // taille 1 : inchangé
    try testing.expectEqual(@as(i32, 96), bigSizeFor(48, 80)); // affiché 240 px
    try testing.expectEqual(@as(i32, 63), bigSizeFor(48, 128)); // affiché 252 px au lieu de 384
    try testing.expectEqual(@as(i32, 48), bigSizeFor(48, 256)); // déjà énorme : seulement rouge
    for ([_]u32{ 32, 48, 80, 128, 176, 256 }) |b| {
        const r = bigSizeFor(48, b);
        try testing.expect(r >= 48 and r <= 96);
        try testing.expect(r == 48 or displayedSize(r, b) <= 255);
    }
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

/// Version rouge 32 bits d'une image monochrome de curseur de la version noire :
/// `and_bits` (transparence) et `xor_bits` (couleur), lignes de `stride` octets.
/// `one_is_white` : le bit de couleur 1 désigne le blanc (cas habituel de la palette).
/// Opaque noir -> rouge, opaque blanc -> blanc ; les pixels transparents et « inverse
/// l'écran » deviennent transparents.
pub fn monoToRed(and_bits: []const u8, xor_bits: []const u8, stride: usize, w: usize, h: usize, one_is_white: bool, out: []u32) void {
    std.debug.assert(out.len >= w * h and and_bits.len >= stride * h and xor_bits.len >= stride * h);
    const white_bit: u1 = if (one_is_white) 1 else 0;
    for (0..h) |y| {
        for (0..w) |x| {
            out[y * w + x] = if (maskBit(and_bits, stride, x, y) == 1)
                0
            else if (maskBit(xor_bits, stride, x, y) == white_bit)
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

    /// Vrai si un demi-tour d'au moins `min_seg` px vient d'avoir lieu. Un aller plus
    /// court interrompt la série : seuls des allers-retours amples et consécutifs comptent.
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
        if (amp < min_seg) {
            a.n = 0;
            a.next = 0;
            return false;
        }
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

    /// L'amplitude minimale d'un aller est SHAKE_SEG_FACTOR fois la taille du curseur :
    /// elle suit l'agrandissement de l'écran, et les gestes vifs du quotidien ne comptent pas.
    pub fn init(cursor_px: i32) Shake {
        const seg = @max(64, cursor_px * SHAKE_SEG_FACTOR);
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
    // 4 pixels sur une ligne, stride 2 octets
    const and_bits = [_]u8{ 0b0011_0000, 0 };
    const xor_bits = [_]u8{ 0b0101_0000, 0 };
    var out: [4]u32 = undefined;
    monoToRed(&and_bits, &xor_bits, 2, 4, 1, true, &out);
    try testing.expectEqual(@as(u32, 0xFF000000 | RED), out[0]); // ET 0, OUX 0 : noir
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), out[1]); // ET 0, OUX 1 : blanc
    try testing.expectEqual(@as(u32, 0), out[2]); // ET 1, OUX 0 : transparent
    try testing.expectEqual(@as(u32, 0), out[3]); // ET 1, OUX 1 : inverse l'écran
}

test "monoToRed : palette inversée (bit 1 = noir)" {
    const and_bits = [_]u8{ 0, 0 };
    const xor_bits = [_]u8{ 0b1000_0000, 0 };
    var out: [2]u32 = undefined;
    monoToRed(&and_bits, &xor_bits, 2, 2, 1, false, &out);
    try testing.expectEqual(@as(u32, 0xFF000000 | RED), out[0]);
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), out[1]);
}

/// Donne à `s` les positions x successives `xs`, une toutes les SHAKE_TICK_MS.
/// Renvoie l'indice de la position qui déclenche, ou null.
fn feedXs(s: *Shake, xs: []const i32) ?usize {
    for (xs, 0..) |x, i| {
        if (s.feed(@intCast(i * SHAKE_TICK_MS), .{ .x = x, .y = 500 }) == .start) return i;
    }
    return null;
}

/// Allers-retours en dents de scie entre `lo` et `hi`, `steps` lectures par aller.
fn zigzag(buf: []i32, lo: i32, hi: i32, steps: usize, swings: usize) []const i32 {
    var n: usize = 0;
    buf[n] = lo;
    n += 1;
    for (0..swings) |k| {
        const from = if (k % 2 == 0) lo else hi;
        const to = if (k % 2 == 0) hi else lo;
        for (1..steps + 1) |j| {
            buf[n] = from + @divTrunc((to - from) * @as(i32, @intCast(j)), @as(i32, @intCast(steps)));
            n += 1;
        }
    }
    return buf[0..n];
}

test "Shake : seuils proportionnels à la taille du curseur" {
    const s32 = Shake.init(32);
    const s64 = Shake.init(64);
    try testing.expectEqual(@as(i32, 96), s32.min_seg);
    try testing.expectEqual(@as(i32, 192), s64.min_seg);
    try testing.expect(s64.jitter > s32.jitter);
    try testing.expectEqual(@as(i32, 64), Shake.init(0).min_seg);
}

test "Shake : secouer franchement déclenche, à l'horizontale comme à la verticale" {
    for ([_]bool{ false, true }) |vertical| {
        for ([_]f32{ 3, 4, 6 }) |hz| {
            var s = Shake.init(32);
            const t = shakeAt(&s, 0, 3000, 400, hz, vertical) orelse return error.PasDeclenche;
            try testing.expect(t < 1500);
            try testing.expect(s.big);
        }
    }
}

test "Shake : il faut au moins deux allers-retours et demi" {
    var buf: [64]i32 = undefined;
    // 5 allers rapides et amples (4 demi-tours) : pas assez
    var a = Shake.init(64);
    try testing.expectEqual(@as(?usize, null), feedXs(&a, zigzag(&buf, 500, 1000, 4, 5)));
    // 6 allers (5 demi-tours) : déclenche
    var b = Shake.init(64);
    try testing.expect(feedXs(&b, zigzag(&buf, 500, 1000, 4, 6)) != null);
}

test "Shake : va-et-vient trop petit ou trop lent : rien" {
    // deux fois la taille du curseur, vite : sous le seuil de trois fois
    var small = Shake.init(64);
    try testing.expectEqual(@as(?u32, null), shakeAt(&small, 0, 3000, 2 * 64, 4, false));
    var small100 = Shake.init(32);
    try testing.expectEqual(@as(?u32, null), shakeAt(&small100, 0, 3000, 2 * 32, 5, false));
    // ample mais à un aller-retour et demi par seconde seulement
    var slow = Shake.init(32);
    try testing.expectEqual(@as(?u32, null), shakeAt(&slow, 0, 5000, 600, 1.5, false));
}

test "Shake : un aller trop court interrompt la série" {
    var buf: [128]i32 = undefined;
    var n: usize = 0;
    // 3 allers amples, un petit retour de 100 px, puis 3 allers amples : jamais 6 demi-tours
    // amples d'affilée, même si tout tient dans la fenêtre
    for (zigzag(buf[0..], 500, 1000, 3, 3)) |x| {
        buf[n] = x;
        n += 1;
    }
    const tail = [_]i32{ 950, 900, 950, 1000 }; // petit aller-retour à droite
    for (tail) |x| {
        buf[n] = x;
        n += 1;
    }
    var more: [32]i32 = undefined;
    for (zigzag(&more, 1000, 500, 3, 4)[1..]) |x| {
        buf[n] = x;
        n += 1;
    }
    var s = Shake.init(64);
    try testing.expectEqual(@as(?usize, null), feedXs(&s, buf[0..n]));
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
    try testing.expectEqual(@as(i32, 96), s.min_seg);
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
