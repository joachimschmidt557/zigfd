const std = @import("std");

pub fn walkDir(allocator: *std.mem.Allocator, path: []u8) !void {
    var stack = std.atomic.Stack([]u8).init();
    const node = try allocator.create(std.atomic.Stack([]u8).Node);
    node.* = std.atomic.Stack([]u8).Node {
        .next = undefined,
        .data = path,
    };
    stack.push(node);
    while (stack.pop()) |item| {
        const data = item.data;
        var dir = try std.fs.Dir.open(allocator, data);
        defer dir.close();
        while (try dir.next()) |entry| {
            try printEntry(entry);
            if (entry.kind == std.fs.Dir.Entry.Kind.Directory) {
                const new_node = try allocator.create(std.atomic.Stack([]u8).Node);
                var new_dir_path = entry.name;
                new_node.* = std.atomic.Stack([]u8).Node {
                    .next = undefined,
                    .data = new_dir_path,
                };
                stack.push(new_node);
            }
        }
    }
}

pub fn printEntry(entry: std.fs.Dir.Entry) !void {
    const stdout_file = try std.io.getStdOut();
    try stdout_file.write(entry.name);
    try stdout_file.write("\n");
}
