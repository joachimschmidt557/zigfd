const std = @import("std");

const Entry = @import("entry.zig").Entry;

pub const BreadthFirstWalker = struct {
    startPath    : []u8,
    pathsToScan  : std.atomic.Queue([]u8),
    allocator    : *std.mem.Allocator,
    maxDepth     : u32,

    currentDir   : std.fs.Dir,
    currentPath  : []u8,
    currentDepth : u32,

    pub const Self = @This();

    pub fn init(alloc: *std.mem.Allocator, path: []u8) !Self {
        return Self{
            .startPath    = path,
            .pathsToScan  = std.atomic.Queue([]u8).init(),
            .allocator    = alloc,
            .maxDepth     = 0,

            .currentDir   = try std.fs.Dir.open(alloc, path),
            .currentPath  = path,
            .currentDepth = 0,
        };
    }

    pub fn next(self: *Self) !?Entry {
        outer: while (true) {
            if (try self.currentDir.next()) |entry| {
                //var full_entry_buf = std.ArrayList(u8).init(self.allocator);
                //try full_entry_buf.resize(self.currentPath.len + entry.name.len + 1);
                
                //var full_entry_buf = [_]u8{0} ** std.fs.MAX_PATH_BYTES;

                //var full_entry_buf = try self.allocator.create([std.fs.MAX_PATH_BYTES]u8);

                //const full_entry_path = full_entry_buf[0 .. self.currentPath.len + entry.name.len + 1];

                const full_entry_path = try self.allocator.alloc(u8, self.currentPath.len + entry.name.len + 1);
                std.mem.copy(u8, full_entry_path, self.currentPath);
                full_entry_path[self.currentPath.len] = std.fs.path.sep;
                std.mem.copy(u8, full_entry_path[self.currentPath.len + 1 ..], entry.name);
    
                if (entry.kind == std.fs.Dir.Entry.Kind.Directory) {
                    const new_dir = try self.allocator.create(std.atomic.Queue([]u8).Node);
                    new_dir.* = std.atomic.Queue([]u8).Node {
                        .next = undefined,
                        .prev = undefined,
                        .data = full_entry_path,
                    };
    
                    self.pathsToScan.put(new_dir);
                }
    
                return Entry{
                    .name = entry.name,
                    .absolutePath = full_entry_path,
                    .relativePath = full_entry_path[self.startPath.len + 1..],
                    .kind = entry.kind,
                };
            } else {
                // No entries left in the current dir
                self.currentDir.close();
                if (self.pathsToScan.get()) |node| {
                    self.currentPath = node.data;
                    self.currentDir = try std.fs.Dir.open(self.allocator, self.currentPath);
                    self.allocator.destroy(node);

                    continue :outer;
                }
                return null;
            }
        }
    }
};
