const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mustache = b.createModule(.{
        .source_file = .{ .path = "dependencies/mustache-zig/src/mustache.zig" },
    });

    const zttp = b.createModule(.{
        .source_file = .{ .path = "src/zttp.zig" },
        .dependencies = &.{
            .{ .name = "mustache", .module = mustache },
        },
    });

    const Example = struct { name: []const u8, path: []const u8 };
    const examples = [_]Example{
        .{ .name = "todo-app", .path = "examples/todo-app/src/main.zig" },
    };

    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = .{ .path = example.path },
            .target = target,
            .optimize = optimize,
        });

        exe.addModule("zttp", zttp);

        const build_exe = b.addInstallArtifact(exe, .{});
        const build_step = b.step(example.name, "Build the example " ++ example.name);
        build_step.dependOn(&build_exe.step);

        const run_exe = b.addRunArtifact(exe);
        const run_step = b.step("run-" ++ example.name, "Run the example " ++ example.name);
        run_step.dependOn(&run_exe.step);
    }
}
