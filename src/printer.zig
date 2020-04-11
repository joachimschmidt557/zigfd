const std = @import("std");

const Entry = @import("../zig-walkdir/src/entry.zig").Entry;

pub fn printEntry(entry: Entry, out: var) !void {
    try out.print("{}\n", .{entry.relative_path});
}

pub fn printError(err: anyerror, out: var) !void {
    try out.print("Error encountered: {}\n", .{err});
}
