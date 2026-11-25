//! Expose les modules d'AutoCurseur aux tests (`zig build test`).

const std = @import("std");

pub const core = @import("core.zig");
pub const win32 = @import("win32.zig");
pub const cursors = @import("cursors.zig");
pub const curfile = @import("curfile.zig");
pub const svgcur = @import("svgcur.zig");
pub const sampler = @import("sampler.zig");
pub const icon = @import("icon.zig");
pub const settings = @import("settings.zig");
pub const i18n = @import("i18n.zig");
pub const colorpick = @import("colorpick.zig");

test {
    // inclut les tests unitaires de chaque fichier
    _ = core;
    _ = win32;
    _ = cursors;
    _ = curfile;
    _ = svgcur;
    _ = sampler;
    _ = icon;
    _ = settings;
    _ = i18n;
    _ = colorpick;
}

test "aucune allocation dynamique dans le code de l'application" {
    const sources = [_][]const u8{
        @embedFile("main.zig"),     @embedFile("core.zig"),      @embedFile("cursors.zig"),
        @embedFile("sampler.zig"),  @embedFile("icon.zig"),      @embedFile("win32.zig"),
        @embedFile("settings.zig"), @embedFile("i18n.zig"),      @embedFile("curfile.zig"),
        @embedFile("svgcur.zig"),   @embedFile("colorpick.zig"),
    };
    // motifs assemblés à la compilation pour ne pas apparaître tels quels dans ce fichier
    const banned = [_][]const u8{
        "std." ++ "heap",   "Alloc" ++ "ator",   "Heap" ++ "Alloc", "Virtual" ++ "Alloc",
        "Local" ++ "Alloc", "Global" ++ "Alloc", "mal" ++ "loc(",   "CoTask" ++ "MemAlloc",
    };
    for (sources) |src| {
        for (banned) |b| {
            if (std.mem.indexOf(u8, src, b)) |_| {
                std.debug.print("motif interdit trouvé : {s}\n", .{b});
                return error.AllocationDynamique;
            }
        }
    }
}

test "budget mémoire statique : moins de 480 Ko de tampons" {
    const total = @sizeOf(@TypeOf(cursors.src_buf)) + @sizeOf(@TypeOf(cursors.out_buf)) + 8 * 1024 + 2 * 32 * 240 +
        @sizeOf(@TypeOf(sampler.buf)) + @sizeOf(@TypeOf(icon.px)) + @sizeOf(@TypeOf(icon.mask));
    try std.testing.expect(total < 480 * 1024);
}
