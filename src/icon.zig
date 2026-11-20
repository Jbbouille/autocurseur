//! Icône de la zone de notification, dessinée dans des tampons statiques.

const core = @import("core.zig");
const w = @import("win32.zig");

pub var px: [core.ICON_MAX * core.ICON_MAX]u32 = undefined;
pub var mask: [core.ICON_MAX / 8 * core.ICON_MAX]u8 = @splat(0); // tout opaque : l'alpha décide

/// Icône active (`on`) ou en pause, à la taille des petites icônes du système.
pub fn create(on: bool) w.HICON {
    const s: usize = @intCast(@min(@max(w.GetSystemMetrics(w.SM_CXSMICON), 16), core.ICON_MAX));
    core.renderTrayIcon(&px, s, on);
    const color = w.CreateBitmap(@intCast(s), @intCast(s), 1, 32, &px);
    const m = w.CreateBitmap(@intCast(s), @intCast(s), 1, 1, &mask);
    defer {
        _ = w.DeleteObject(color);
        _ = w.DeleteObject(m);
    }
    var ii: w.ICONINFO = .{ .fIcon = 1, .xHotspot = 0, .yHotspot = 0, .hbmMask = m, .hbmColor = color };
    return w.CreateIconIndirect(&ii);
}
