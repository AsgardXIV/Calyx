const std = @import("std");

pub fn build(b: *std.Build) void {
    // Build Config
    const build_sample = b.option(bool, "build-sample", "Build the Calyx sample") orelse true;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "calyx",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    // Tests
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Sample executable
    if (build_sample) {
        const sample_exe_mod = b.createModule(.{
            .root_source_file = b.path("sample/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        sample_exe_mod.addImport("calyx", lib_mod);

        const sample_exe = b.addExecutable(.{
            .name = "calyx_sample",
            .root_module = sample_exe_mod,
        });

        b.installArtifact(sample_exe);

        const run_cmd = b.addRunArtifact(sample_exe);

        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
}
