const std = @import("std");

pub const IterativeWalker = struct {
    pathsToScan : std.atomic.Queue([]u8),
    currentDir  : std.fs.Dir,
    currentPath : []u8,
    allocator   : *std.mem.Allocator,

    pub const Self = @This();

    pub fn init(alloc: *std.mem.Allocator, path: []u8) !Self {
        return Self{
            .pathsToScan = std.atomic.Queue([]u8).init(),
            .currentDir  = try std.fs.Dir.open(alloc, path),
            .currentPath = path,
            .allocator   = alloc,
        };
    }

    pub fn next(self: *Self) anyerror!?std.fs.Dir.Entry {
        if (try self.currentDir.next()) |entry| {
            if (entry.kind == std.fs.Dir.Entry.Kind.Directory) {
                var full_entry_buf = std.ArrayList(u8).init(self.allocator);
                try full_entry_buf.resize(self.currentPath.len + entry.name.len + 1);
     
                const full_entry_path = full_entry_buf.toSlice();
                std.mem.copy(u8, full_entry_path, self.currentPath);
                full_entry_path[self.currentPath.len] = std.fs.path.sep;
                std.mem.copy(u8, full_entry_path[self.currentPath.len + 1 ..], entry.name);

                const new_dir = try self.allocator.create(std.atomic.Queue([]u8).Node);
                new_dir.* = std.atomic.Queue([]u8).Node {
                    .next = undefined,
                    .prev = undefined,
                    .data = full_entry_path,
                };

                self.pathsToScan.put(new_dir);
            }
            return entry;
        } else {
            // No entries left in the current dir
            self.currentDir.close();
            while (self.pathsToScan.get()) |node| {
                self.currentPath = node.data;
                self.currentDir = try std.fs.Dir.open(self.allocator, self.currentPath);

                self.allocator.destroy(node);

                if (try self.next()) |entry| {
                    return entry;
                } else {
                    continue;
                }
            }
            return null;
        }
    }
};
