const std = @import("std");

pub fn printEntry(entry: std.fs.Dir.Entry, out:std.fs.File) !void {
    try out.write(entry.name);
    try out.write("\n");
}
