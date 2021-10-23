const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zigfd", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("clap", "zig-clap/clap.zig");
    exe.addPackagePath("regex", "zig-regex/src/regex.zig");
    exe.addPackagePath("walkdir", "zig-walkdir/src/main.zig");
    exe.addPackagePath("lscolors", "zig-lscolors/src/main.zig");
    exe.linkSystemLibrary("c");

    const run_cmd = exe.run();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
