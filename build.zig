const std = @import("std");

pub fn build(b: *std.Build) void {
    const build_unit_tests = b.option(bool, "build-unit-tests", "Build the Calyx unit tests") orelse true;
    const build_integration_tests = b.option(bool, "build-integration-tests", "Build the Calyx integration tests") orelse true;
    const build_sample = b.option(bool, "build-sample", "Build the Calyx sample") orelse true;
    const build_docs = b.option(bool, "build-docs", "Build the Calyx docs") orelse true;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Calyx Module
    const calyx_mod = b.addModule("calyx", .{
        .root_source_file = b.path("src/calyx.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Calyx Lib
    const calyx_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "calyx",
        .root_module = calyx_mod,
    });

    b.installArtifact(calyx_lib);

    // Calyx Unit Tests
    if (build_unit_tests) {
        const calyx_unit_tests = b.addTest(.{
            .name = "calyx_unit_tests",
            .root_module = calyx_mod,
        });

        const calyx_run_unit_tests = b.addRunArtifact(calyx_unit_tests);

        const calyx_unit_test_step = b.step("test", "Run unit tests");
        calyx_unit_test_step.dependOn(&calyx_run_unit_tests.step);

        b.installArtifact(calyx_unit_tests);
    }

    // Calyx Integration Tests
    if (build_integration_tests) {
        const calyx_integration_tests_mod = b.createModule(.{
            .root_source_file = b.path("test/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "calyx",
                    .module = calyx_mod,
                },
            },
        });

        const calyx_integration_tests = b.addTest(.{
            .name = "calyx_integration_tests",
            .root_module = calyx_integration_tests_mod,
        });

        const calyx_run_integration_tests = b.addRunArtifact(calyx_integration_tests);

        const calyx_integration_test_step = b.step("integrationTest", "Run integration tests");
        calyx_integration_test_step.dependOn(&calyx_run_integration_tests.step);

        b.installArtifact(calyx_integration_tests);
    }

    // Calyx Docs
    if (build_docs) {
        const calyx_docs = b.addInstallDirectory(.{
            .source_dir = calyx_lib.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });

        const calyx_docs_step = b.step("docs", "Install docs");
        calyx_docs_step.dependOn(&calyx_docs.step);
    }

    // Calyx Sample
    if (build_sample) {
        const calyx_sample_exe_mod = b.createModule(.{
            .root_source_file = b.path("sample/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "calyx",
                    .module = calyx_mod,
                },
            },
        });

        const calyx_sample_exe = b.addExecutable(.{
            .name = "calyx_sample",
            .root_module = calyx_sample_exe_mod,
        });

        const calyx_sample_run_cmd = b.addRunArtifact(calyx_sample_exe);

        calyx_sample_run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            calyx_sample_run_cmd.addArgs(args);
        }

        const calyx_run_step = b.step("sample", "Run the Calyx sample app");
        calyx_run_step.dependOn(&calyx_sample_run_cmd.step);

        b.installArtifact(calyx_sample_exe);
    }
}
