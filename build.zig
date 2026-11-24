const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .os_tag = .windows } });
    // Mode de compilation de l'exe publié et des tests de performance (qui mesurent donc
    // exactement ce qui est livré). `fast` (ReleaseFast) par défaut ; `-Doptimize=small` pour un exe plus petit.
    const optimize: std.builtin.Optimize = b.option(std.builtin.Optimize, "optimize", "Mode de compilation de l'exe : fast (défaut), small, safe, debug") orelse .fast;

    // ----- application -----
    const exe = b.addExecutable(.{
        .name = "AutoCurseur",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
        }),
    });
    exe.subsystem = .windows; // pas de fenêtre console
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Lancer AutoCurseur").dependOn(&run.step);

    // ----- tests -----
    const lib_debug = b.createModule(.{ .root_source_file = b.path("src/lib.zig"), .target = target, .optimize = .debug });
    const lib_release = b.createModule(.{ .root_source_file = b.path("src/lib.zig"), .target = target, .optimize = optimize });

    // unitaires : logique pure + vérifications statiques, en Debug (contrôles de sécurité actifs)
    const unit = b.addRunArtifact(b.addTest(.{ .name = "unit", .root_module = lib_debug }));

    // intégration : vrais fichiers curseurs, images dessinées en mémoire
    const integration = b.addRunArtifact(b.addTest(.{ .name = "integration", .root_module = b.createModule(.{
        .root_source_file = b.path("tests/integration.zig"),
        .target = target,
        .optimize = .debug,
        .imports = &.{.{ .name = "autocurseur", .module = lib_debug }},
    }) }));

    // performance : dans le même mode que l'exe publié, après les autres pour ne pas être perturbés
    const perf = b.addRunArtifact(b.addTest(.{ .name = "perf", .root_module = b.createModule(.{
        .root_source_file = b.path("tests/perf.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "autocurseur", .module = lib_release }},
    }) }));
    perf.step.dependOn(&unit.step);
    perf.step.dependOn(&integration.step);
    perf.has_side_effects = true; // toujours relancer les mesures

    const test_step = b.step("test", "Tests unitaires, d'intégration et de performance");
    test_step.dependOn(&unit.step);
    test_step.dependOn(&integration.step);
    test_step.dependOn(&perf.step);

    // système : change le vrai curseur et lance l'exe ; à part, sur demande
    // outil en C des tests système : forme du pointeur réellement affichée (duplication d'écran)
    const ptrcap = b.addExecutable(.{ .name = "ptrcap", .root_module = b.createModule(.{
        .target = target,
        .optimize = .fast,
        .link_libc = true,
    }) });
    ptrcap.root_module.addCSourceFile(.{ .file = b.path("tests/tools/ptrcap.c") });
    for ([_][]const u8{ "d3d11", "dxgi", "user32", "gdi32" }) |lib| ptrcap.root_module.linkSystemLibrary(lib, .{});

    const opts = b.addOptions();
    opts.addOptionPath("exe_path", exe.getEmittedBin());
    opts.addOptionPath("ptrcap_path", ptrcap.getEmittedBin());
    const system_tests = b.addTest(.{ .name = "system", .root_module = b.createModule(.{
        .root_source_file = b.path("tests/system.zig"),
        .target = target,
        .optimize = .debug,
        .imports = &.{
            .{ .name = "autocurseur", .module = lib_debug },
            .{ .name = "build_options", .module = opts.createModule() },
        },
    }) });
    const system = b.addRunArtifact(system_tests);
    system.has_side_effects = true;
    b.step("test-system", "Tests système : change le curseur et lance l'exe (quittez AutoCurseur avant)").dependOn(&system.step);
    // compiler les tests système sans les lancer (sans toucher au curseur)
    b.step("check-system", "Compiler les tests système sans les lancer").dependOn(&system_tests.step);
}
