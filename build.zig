const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lscolors = b.dependency("lscolors", .{}).module("lscolors");
    const walkdir = b.dependency("walkdir", .{}).module("walkdir");
    const clap = b.dependency("clap", .{}).module("clap");
    const regex = b.dependency("regex", .{}).module("regex");

    const exe = b.addExecutable(.{
        .name = "zigfd",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    exe.addModule("clap", clap);
    exe.addModule("regex", regex);
    exe.addModule("walkdir", walkdir);
    exe.addModule("lscolors", lscolors);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
