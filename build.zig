const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addStaticLibrary(.{
        .name = "renderer",
        .root_source_file = .{ .path = "caml.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.bundle_compiler_rt = true;
    const exe = b.addSystemCommand(&.{"ocamlopt"});
    exe.addArg("-o");
    const output = exe.addOutputFileArg("main");
    exe.addArgs(&.{ "-I", "+unix", "unix.cmxa", "cell.ml", "rope.ml" });
    exe.addArtifactArg(lib);
    exe.addArgs(&.{ "terminal.ml", "editor.ml", "commands.ml", "render.ml", "main.ml" });
    exe.extra_file_dependencies = &.{ "cell.ml", "rope.ml", "terminal.ml", "editor.ml", "commands.ml", "render.ml", "main.ml" };
    b.installArtifact(lib);
    const install = b.addInstallFile(output, "main");
    b.default_step.dependOn(&exe.step);
    b.default_step.dependOn(&install.step);
    const run = std.Build.Step.Run.create(b, "main");
    run.addFileArg(output);
    run.has_side_effects = true;
    run.stdio = .inherit;
    const run_step = b.step("run", "Run the editor");
    run_step.dependOn(&run.step);
}
