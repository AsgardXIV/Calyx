const std = @import("std");

pub fn build(b: *std.Build) void {
    // Build Config
    const build_sample = b.option(bool, "build-sample", "Build the Calyx sample") orelse true;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const lib_mod = b.addModule("calyx", .{
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

    // Unit Tests
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Integration tests
    const integration_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    integration_tests_mod.addImport("calxy", lib_mod);

    const integration_tests = b.addTest(.{
        .root_module = integration_tests_mod,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);

    const integration_test_step = b.step("integrationTest", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // Docs
    const lib_install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&lib_install_docs.step);

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
