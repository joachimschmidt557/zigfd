const std = @import("std");
const ArrayList = std.ArrayList;

const lscolors = @import("lscolors");
const LsColors = lscolors.LsColors;

const walkdir = @import("walkdir");
const Entry = walkdir.Entry;

pub const ActionType = enum {
    Print,
    Execute,
    ExecuteBatch,
};

pub const Action = union(ActionType) {
    Print,
    Execute: ExecuteTarget,
    ExecuteBatch: ExecuteBatchTarget,
};

pub const ExecuteTarget = struct {
    cmd: []const u8,

    const Self = @This();

    pub fn do(self: *Self, entry: Entry) !void {

    }
};

pub const ExecuteBatchTarget = struct {
    cmd: []const u8,
    args: ArrayList([]const u8),

    const Self = @This();

    pub fn do(self: *Self, entry: Entry) !void {
        try self.args.append(entry.relative_path);
    }

    pub fn finalize(self: *Self) !void {
        defer self.args.deinit();
    }
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
