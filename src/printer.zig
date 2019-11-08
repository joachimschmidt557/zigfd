const std = @import("std");

const Entry = @import("zig-walkdir/src/entry.zig").Entry;

pub fn printEntryFile(entry: Entry, out: std.fs.File) !void {
    try out.write(entry.relative_path);
    try out.write("\n");
}

pub fn printEntryStream(entry: Entry, out: var) !void {
    try out.print("{}\n", entry.relative_path);
}
