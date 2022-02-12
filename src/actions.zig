const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ChildProcess = std.ChildProcess;

const LsColors = @import("lscolors").LsColors;

const Entry = @import("walkdir").Entry;

pub const ActionType = enum {
    print,
    execute,
    execute_batch,
};

pub const Action = union(ActionType) {
    print,
    execute: ExecuteTarget,
    execute_batch: ExecuteBatchTarget,

    const Self = @This();

    pub const default: Self = .print;

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .execute => |*x| x.deinit(),
            .execute_batch => |*x| x.deinit(),
            else => {},
        }
    }
};

pub const ExecuteTarget = struct {
    allocator: Allocator,
    cmd: ArrayList([]const u8),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .cmd = ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.cmd.deinit();
    }

    pub fn do(self: *Self, entry: Entry) !void {
        try self.cmd.append(entry.relative_path);
        defer _ = self.cmd.pop();

        var child_process = try ChildProcess.init(self.cmd.items, self.allocator);
        defer child_process.deinit();

        _ = try child_process.spawnAndWait();
    }
};

pub const ExecuteBatchTarget = struct {
    cmd: ArrayList([]const u8),
    allocator: Allocator,
    args: ArrayList(Entry),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .cmd = ArrayList([]const u8).init(allocator),
            .allocator = allocator,
            .args = ArrayList(Entry).init(allocator),
        };
    }

    pub fn do(self: *Self, entry: Entry) !void {
        try self.args.append(entry);
    }

    pub fn deinit(self: *Self) void {
        self.cmd.deinit();
    }

    pub fn finalize(self: *Self) !void {
        defer self.args.deinit();
        defer for (self.args.items) |x| x.deinit();

        for (self.args.items) |e| {
            try self.cmd.append(e.relative_path);
        }

        var child_process = try ChildProcess.init(self.cmd.items, self.allocator);
        defer child_process.deinit();

        _ = try child_process.spawnAndWait();
    }
};

pub const ColorOption = enum {
    auto,
    always,
    never,

    const Self = @This();

    pub const default = Self.auto;
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

pub fn printEntry(entry: Entry, writer: anytype, opt: PrintOptions) !void {
    if (opt.color) |lsc| {
        try writer.print("{}", .{lsc.styledComponents(entry.relative_path)});
    } else {
        try writer.writeAll(entry.relative_path);
    }

    if (opt.null_sep) {
        try writer.writeByte(0);
    } else {
        try writer.writeByte('\n');
    }
}
