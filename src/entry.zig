const std = @import("std");

pub const Entry = struct {
    name: []const u8,
    absolutePath: []u8,
    relativePath: []u8,
    kind: std.fs.Dir.Entry.Kind,
};

