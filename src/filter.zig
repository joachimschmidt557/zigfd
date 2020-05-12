const std = @import("std");

const walkdir = @import("walkdir");
const Entry = walkdir.Entry;

const regex = @import("regex");
const Regex = regex.Regex;

pub const Filter = struct {
    pattern: ?Regex,
    full_path: bool,
    extensions: []const []const u8,

    const Self = @This();

    pub const all = Self{
        .pattern = null,
        .full_path = false,
        .extensions = &[_][]const u8{},
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

        return true;
    }
};
