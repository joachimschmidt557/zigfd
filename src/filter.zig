const std = @import("std");
const ArrayList = std.ArrayList;

const walkdir = @import("walkdir");
const Entry = walkdir.Entry;

const regex = @import("regex");
const Regex = regex.Regex;

pub const TypeFilter = struct {
    file: bool = false,
    directory: bool = false,
    symlink: bool = false,
    socket: bool = false,
    pipe: bool = false,

    // only_executable: bool = false,
    // only_empty: bool = false,

    const Self = @This();

    pub fn matches(self: Self, entry: Entry) bool {
        return switch (entry.kind) {
            .Directory => self.directory,
            .SymLink => self.symlink,
            .File => self.file,
            .UnixDomainSocket => self.socket,
            .NamedPipe => self.pipe,

            .BlockDevice => false,
            .CharacterDevice => false,
            .Whiteout => false,
            .Door => false,
            .EventPort => false,
            .Unknown => false,
        };
    }
};

fn hasExtension(name: []const u8, ext: []const u8) bool {
    return std.mem.endsWith(u8, name, ext) and name.len > ext.len and name[name.len - ext.len - 1] == '.';
}

pub const Filter = struct {
    pattern: ?Regex = null,
    full_path: bool = false,
    extensions: ?ArrayList([]const u8) = null,
    types: ?TypeFilter = null,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        if (self.pattern) |*r| r.deinit();
        if (self.extensions) |ext| {
            for (ext.items) |x| ext.allocator.free(x);
            ext.deinit();
        }
    }

    pub fn matches(self: Self, entry: Entry) !bool {
        const text = if (self.full_path) entry.relative_path else entry.name;

        if (self.pattern) |re| {
            var r = re;

            if (!(try r.partialMatch(text))) {
                return false;
            }
        }

        if (self.extensions) |ext| {
            for (ext.items) |x| {
                if (hasExtension(text, x)) {
                    break;
                }
            } else return false;
        }

        if (self.types) |types| {
            if (!types.matches(entry)) return false;
        }

        return true;
    }
};
