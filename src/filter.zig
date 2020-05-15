const std = @import("std");

const walkdir = @import("walkdir");
const Entry = walkdir.Entry;

const regex = @import("regex");
const Regex = regex.Regex;

pub const TypeFilter = struct {
    file: bool,
    directory: bool,
    symlink: bool,
    executable: bool,
    empty: bool,

    const Self = @This();

    pub const none = Self{
        .file = false,
        .directory = false,
        .symlink = false,
        .executable = false,
        .empty = false,
    };

    pub fn matches(self: Self, entry: Entry) bool {
        return switch (entry.kind) {
            .BlockDevice => false,
            .CharacterDevice => false,
            .Directory => self.directory,
            .NamedPipe => false,
            .SymLink => self.symlink,
            .File => self.file,
            .UnixDomainSocket => false,
            .Whiteout => false,
            .Unknown => false,
        };
    }
};

pub const Filter = struct {
    pattern: ?Regex,
    full_path: bool,
    extensions: []const []const u8,
    types: ?TypeFilter,

    const Self = @This();

    pub const all = Self{
        .pattern = null,
        .full_path = false,
        .extensions = &[_][]const u8{},
        .types = null,
    };

    pub fn deinit(self: *Self) void {
        if (self.pattern) |*r| r.deinit();
    }

    pub fn matches(self: Self, entry: Entry) !bool {
        const text = if (self.full_path) entry.relative_path else entry.name;

        if (self.pattern) |re| {
            var r = re;

            if (!(try r.partialMatch(text))) {
                return false;
            }
        }

        for (self.extensions) |ext| {
            if (!std.mem.endsWith(u8, text, ext)) {
                return false;
            }
        }

        if (self.types) |types| {
            if (!types.matches(entry)) return false;
        }

        return true;
    }
};
