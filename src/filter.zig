const std = @import("std");

const walkdir = @import("walkdir");
const Entry = walkdir.Entry;

const regex = @import("regex");
const Regex = regex.Regex;

pub const Filter = struct {
    pattern: ?Regex,
    full_path: bool,

    const Self = @This();

    pub const all = Self{
        .pattern = null,
        .full_path = false,
    };

    pub fn deinit(self: *Self) void {
        if (self.pattern) |*r| r.deinit();
    }

    pub fn matches(self: Self, entry: Entry) !bool {
        if (self.pattern) |re| {
            var r = re;

            const text = if (self.full_path) entry.relative_path else entry.name;
            if (!(try r.partialMatch(text))) {
                return false;
            }
        }

        return true;
    }
};
