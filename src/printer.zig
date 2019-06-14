const std = @import("std");

const iterative = @import("iterativeWalk.zig");

pub fn printEntry(entry: iterative.Entry, out:std.fs.File) !void {
    try out.write(entry.relativePath);
    try out.write("\n");
}
