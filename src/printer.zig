const std = @import("std");

const iterative = @import("iterativeWalk.zig");

pub fn printEntryFile(entry: iterative.Entry, out: std.fs.File) !void {
    try out.write(entry.relativePath);
    try out.write("\n");
}

pub fn printEntryStream(entry: iterative.Entry, out: var) !void {
    try out.print("{}\n", entry.relativePath);
}
