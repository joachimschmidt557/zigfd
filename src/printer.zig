const std = @import("std");

pub fn printEntry(entry: std.fs.Dir.Entry) !void {
    const stdout_file = try std.io.getStdOut();
    try stdout_file.write(entry.name);
    try stdout_file.write("\n");
}
