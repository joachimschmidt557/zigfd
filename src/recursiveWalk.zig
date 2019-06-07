const std = @import("std");

const printer = @import("printer.zig");

pub fn walkDir(allocator: *std.mem.Allocator, path: []u8) anyerror!void {
    var dir = try std.fs.Dir.open(allocator, path);
    defer dir.close();

    var full_entry_buf = std.ArrayList(u8).init(allocator);
    defer full_entry_buf.deinit();

    while (try dir.next()) |entry| {
        try printer.printEntry(entry);

        if (entry.kind == std.fs.Dir.Entry.Kind.Directory) {
            try full_entry_buf.resize(path.len + entry.name.len + 1);
     
            const full_entry_path = full_entry_buf.toSlice();
            std.mem.copy(u8, full_entry_path, path);
            full_entry_path[path.len] = std.fs.path.sep;
            std.mem.copy(u8, full_entry_path[path.len + 1 ..], entry.name);
     
            try walkDir(allocator, full_entry_path);
        }
    }

}
