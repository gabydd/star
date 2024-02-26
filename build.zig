const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "star",
        .root_source_file = .{ .path = "src/Rope.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const run_step = b.step("run", "Run the editor");
    run_step.dependOn(&b.addRunArtifact(exe).step);
}
