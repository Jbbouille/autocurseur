//! Expose les modules d'AutoCurseur aux tests (`zig build test`).

const std = @import("std");

pub const core = @import("core.zig");
pub const win32 = @import("win32.zig");
pub const cursors = @import("cursors.zig");
pub const sampler = @import("sampler.zig");
pub const icon = @import("icon.zig");
pub const settings = @import("settings.zig");
pub const i18n = @import("i18n.zig");

test {
    // inclut les tests unitaires de chaque fichier
    _ = core;
    _ = win32;
    _ = cursors;
    _ = sampler;
    _ = icon;
    _ = settings;
    _ = i18n;
}

test "aucune allocation dynamique dans le code de l'application" {
    const sources = [_][]const u8{
        @embedFile("main.zig"),     @embedFile("core.zig"), @embedFile("cursors.zig"),
        @embedFile("sampler.zig"),  @embedFile("icon.zig"), @embedFile("win32.zig"),
        @embedFile("settings.zig"), @embedFile("i18n.zig"),
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

test "budget mémoire statique : moins de 400 Ko de tampons" {
    const total = @sizeOf(@TypeOf(cursors.px_buf)) + @sizeOf(@TypeOf(cursors.mask_buf)) +
        @sizeOf(@TypeOf(sampler.buf)) + @sizeOf(@TypeOf(icon.px)) + @sizeOf(@TypeOf(icon.mask));
    try std.testing.expect(total < 400 * 1024);
}
