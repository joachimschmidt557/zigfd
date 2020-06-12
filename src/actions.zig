const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ChildProcess = std.ChildProcess;

const LsColors = @import("lscolors").LsColors;

const Entry = @import("walkdir").Entry;

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
    alloc: *Allocator,
    cmd: []const u8,

    const Self = @This();

    pub fn init(alloc: *Allocator, cmd: []const u8) Self {
        return Self{
            .alloc = alloc,
            .cmd = cmd,
        };
    }

    pub fn do(self: *Self, entry: Entry) !void {
        var cmd = ArrayList([]const u8).init(self.alloc);
        defer cmd.deinit();

        try cmd.append(self.cmd);
        try cmd.append(entry.relative_path);

        var child_process = try ChildProcess.init(cmd.items, self.alloc);
        const term = try child_process.spawnAndWait();
    }
};

pub const ExecuteBatchTarget = struct {
    cmd: []const u8,
    alloc: *Allocator,
    args: ArrayList(Entry),

    const Self = @This();

    pub fn init(alloc: *Allocator, cmd: []const u8) Self {
        return Self{
            .cmd = cmd,
            .alloc = alloc,
            .args = ArrayList(Entry).init(alloc),
        };
    }

    pub fn do(self: *Self, entry: Entry) !void {
        try self.args.append(entry);
    }

    pub fn finalize(self: *Self) !void {
        defer self.args.deinit();
        defer for (self.args.items) |x| x.deinit();

        var cmd = ArrayList([]const u8).init(self.alloc);
        defer cmd.deinit();

        try cmd.append(self.cmd);
        for (self.args.items) |e| {
            try cmd.append(e.relative_path);
        }

        var child_process = try ChildProcess.init(cmd.items, self.alloc);
        const term = try child_process.spawnAndWait();
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

pub fn printEntry(entry: Entry, writer: var, opt: PrintOptions) !void {
    if (opt.color) |lsc| {
        try writer.print("{}", .{lsc.styledComponents(entry.relative_path)});
    } else {
        try writer.writeAll(entry.relative_path);
    }

    if (opt.null_sep) {
        try writer.writeAll(&[_]u8{0});
    } else {
        try writer.writeAll("\n");
    }
}

pub fn printError(err: anyerror, writer: var, opt: PrintOptions) !void {
    if (!opt.errors) return;

    try writer.print("Error encountered: {}", .{err});

    if (opt.null_sep) {
        try writer.writeAll(&[_]u8{0});
    } else {
        try writer.writeAll("\n");
    }
}
