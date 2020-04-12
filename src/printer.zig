const std = @import("std");

const lscolors = @import("lscolors");
const LsColors = lscolors.LsColors;

const walkdir = @import("walkdir");
const Entry = walkdir.Entry;

pub const PrintOptions = struct {
    color: ?LsColors,
    null_sep: bool,

    const Self = @This();

    pub const default = Self{
        .color = null,
        .null_sep = false,
    };

    pub fn deinit(self: *Self) void {
        if (self.color) |*lsc| lsc.deinit();
    }
};

pub fn printEntry(entry: Entry, out: var, opt: PrintOptions) !void {
    if (opt.color) |lsc| {
        try out.print("{}", .{ lsc.styled(entry.relative_path) });
    } else {
        try out.writeAll(entry.relative_path);
    }

    if (opt.null_sep) {
        try out.writeAll(&[_]u8{ 0 });
    } else {
        try out.writeAll("\n");
    }
}

pub fn printError(err: anyerror, out: var, opt: PrintOptions) !void {
    try out.print("Error encountered: {}", .{err});

    if (opt.null_sep) {
        try out.writeAll(&[_]u8{ 0 });
    } else {
        try out.writeAll("\n");
    }
}
