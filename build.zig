const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    exe_mod.addImport("agrama_v2_lib", lib_mod);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "agrama_v2",
        .root_module = lib_mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "agrama_v2",
        .root_module = exe_mod,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    // Comprehensive test runner
    const comprehensive_tests = b.addExecutable(.{
        .name = "comprehensive_test_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add source dependencies to test runner
    comprehensive_tests.root_module.addImport("agrama_lib", lib_mod);

    const run_comprehensive_tests = b.addRunArtifact(comprehensive_tests);

    const test_all_step = b.step("test-all", "Run comprehensive test suite");
    test_all_step.dependOn(&run_comprehensive_tests.step);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add all source dependencies to integration tests
    integration_tests.root_module.addImport("agrama_lib", lib_mod);

    const run_integration_tests = b.addRunArtifact(integration_tests);

    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&run_integration_tests.step);

    // Benchmark infrastructure (module for potential future use)
    _ = b.createModule(.{
        .root_source_file = b.path("benchmarks/benchmark_runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Comprehensive benchmark suite
    const benchmark_suite = b.addExecutable(.{
        .name = "benchmark_suite",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/benchmark_suite.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    benchmark_suite.root_module.addImport("agrama_lib", lib_mod);

    // Individual benchmark executables
    const hnsw_bench = b.addExecutable(.{
        .name = "hnsw_benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/hnsw_benchmarks.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hnsw_bench.root_module.addImport("agrama_lib", lib_mod);

    const fre_bench = b.addExecutable(.{
        .name = "fre_benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/fre_benchmarks.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    fre_bench.root_module.addImport("agrama_lib", lib_mod);

    const db_bench = b.addExecutable(.{
        .name = "database_benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/database_benchmarks.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    db_bench.root_module.addImport("agrama_lib", lib_mod);

    const mcp_bench = b.addExecutable(.{
        .name = "mcp_benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/mcp_benchmarks.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    mcp_bench.root_module.addImport("agrama_lib", lib_mod);

    // Install benchmark executables
    b.installArtifact(benchmark_suite);
    b.installArtifact(hnsw_bench);
    b.installArtifact(fre_bench);
    b.installArtifact(db_bench);
    b.installArtifact(mcp_bench);

    // Benchmark run commands
    const run_benchmark_suite = b.addRunArtifact(benchmark_suite);
    const run_hnsw_bench = b.addRunArtifact(hnsw_bench);
    const run_fre_bench = b.addRunArtifact(fre_bench);
    const run_db_bench = b.addRunArtifact(db_bench);
    const run_mcp_bench = b.addRunArtifact(mcp_bench);

    // Pass arguments to benchmarks
    if (b.args) |args| {
        run_benchmark_suite.addArgs(args);
        run_hnsw_bench.addArgs(args);
        run_fre_bench.addArgs(args);
        run_db_bench.addArgs(args);
        run_mcp_bench.addArgs(args);
    }

    // Benchmark build steps
    const bench_step = b.step("bench", "Run comprehensive benchmark suite");
    bench_step.dependOn(&run_benchmark_suite.step);

    const bench_hnsw_step = b.step("bench-hnsw", "Run HNSW benchmarks only");
    bench_hnsw_step.dependOn(&run_hnsw_bench.step);

    const bench_fre_step = b.step("bench-fre", "Run FRE benchmarks only");
    bench_fre_step.dependOn(&run_fre_bench.step);

    const bench_db_step = b.step("bench-database", "Run database benchmarks only");
    bench_db_step.dependOn(&run_db_bench.step);

    const bench_mcp_step = b.step("bench-mcp", "Run MCP benchmarks only");
    bench_mcp_step.dependOn(&run_mcp_bench.step);

    // Quick benchmark for development
    const quick_bench_cmd = b.addRunArtifact(benchmark_suite);
    quick_bench_cmd.addArg("--quick");
    const bench_quick_step = b.step("bench-quick", "Run benchmarks in quick mode (reduced dataset sizes)");
    bench_quick_step.dependOn(&quick_bench_cmd.step);

    // Benchmark validation (optimized build for accurate performance measurement)
    const validate_benchmark_suite = b.addExecutable(.{
        .name = "validate_suite",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/benchmark_suite.zig"),
            .target = target,
            .optimize = .ReleaseFast, // Force optimized build for validation
        }),
    });
    validate_benchmark_suite.root_module.addImport("agrama_lib", lib_mod);
    b.installArtifact(validate_benchmark_suite);

    const run_validate_suite = b.addRunArtifact(validate_benchmark_suite);
    if (b.args) |args| {
        run_validate_suite.addArgs(args);
    }

    const validate_step = b.step("validate", "Run performance validation with optimized build");
    validate_step.dependOn(&run_validate_suite.step);

    // Regression testing
    const regression_cmd = b.addRunArtifact(benchmark_suite);
    regression_cmd.addArg("--compare");
    regression_cmd.addArg("benchmarks/baseline.json");
    const regression_step = b.step("bench-regression", "Check for performance regressions against baseline");
    regression_step.dependOn(&regression_cmd.step);

    // Security summary report
    const security_summary = b.addExecutable(.{
        .name = "websocket_security_summary",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/websocket_security_summary.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(security_summary);

    const run_security_summary = b.addRunArtifact(security_summary);
    const security_summary_step = b.step("security-report", "Display WebSocket security fix summary");
    security_summary_step.dependOn(&run_security_summary.step);
}
