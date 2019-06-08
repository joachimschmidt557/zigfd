const std = @import("std");

const regex = @import("zig-regex/regex.zig");
const clap = @import("zig-clap");

const recursive = @import("recursiveWalk.zig");
//const iterative = @import("iterativeWalk.zig");

pub fn main() anyerror!void {
    var cwd_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const search_path = try std.os.getcwd(&cwd_buf);

    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var arena = std.heap.ArenaAllocator.init(&direct_allocator.allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    try recursive.walkDir(allocator, search_path);
}
