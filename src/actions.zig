const std = @import("std");

const lscolors = @import("lscolors");
const LsColors = lscolors.LsColors;

const walkdir = @import("walkdir");
const Entry = walkdir.Entry;

pub const ActionType = enum {
    Print,
    Execute,
};

pub const Action = union(ActionType) {
    Print: PrintOptions,
    Execute: ExecuteOptions,

    const Self = @This();

    pub const default = Self{
        .Print = PrintOptions.default,
    };

    pub fn deinit(self: Self) void {
        switch (self) {
            .Print => |x| x.deinit(),
            else => {},
        }
    }

    pub fn do(self: *Self, entry: Entry) void {
        switch (self) {
            .Print => {},
            else => {},
        }
    }

    pub fn finalize(self: *Self, entry: Entry) void {
        switch (self) {
            else => {},
        }
    }
};

pub const ExecuteOptions = struct {
    cmd: []const u8,
};

pub const PrintOptions = struct {
    color: ?*LsColors,
    null_sep: bool,
    errors: bool,

    const Self = @This();

    pub const default = Self{
        .color = null,
        .null_sep = false,
        .errors = false,
    };

    pub fn deinit(self: Self) void {
        if (self.color) |lsc| lsc.deinit();
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
    if (!opt.errors) return;

    try out.print("Error encountered: {}", .{err});

    if (opt.null_sep) {
        try out.writeAll(&[_]u8{ 0 });
    } else {
        try out.writeAll("\n");
    }
}
