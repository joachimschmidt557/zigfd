const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const regex = @import("regex");
const clap = @import("clap");
const walkdir = @import("walkdir");
const filters = @import("filter.zig");
const Filter = filters.Filter;
const TypeFilter = filters.TypeFilter;
const actions = @import("actions.zig");
const Action = actions.Action;
const ColorOption = actions.ColorOption;
const PrintOptions = actions.PrintOptions;

pub const CliOptions = struct {
    arena: *std.heap.ArenaAllocator,
    paths: []const []const u8,
    walkdir: walkdir.Options,
    filter: Filter,
    action: Action,
    color: ColorOption,
    print: PrintOptions,

    pub fn deinit(self: *CliOptions) void {
        const base_allocator = self.arena.child_allocator;
        self.arena.deinit();
        base_allocator.destroy(self.arena);
    }
};

/// The command-line flags and options
pub const params = [_]clap.Param(u8){
    // flags
    clap.Param(u8){
        .id = 'h',
        .names = clap.Names{ .short = 'h', .long = "help" },
    },
    clap.Param(u8){
        .id = 'v',
        .names = clap.Names{ .short = 'v', .long = "version" },
    },
    clap.Param(u8){
        .id = 'H',
        .names = clap.Names{ .short = 'H', .long = "hidden" },
    },
    clap.Param(u8){
        .id = 'p',
        .names = clap.Names{ .short = 'p', .long = "full-path" },
    },
    clap.Param(u8){
        .id = '0',
        .names = clap.Names{ .short = '0', .long = "print0" },
    },
    clap.Param(u8){
        .id = 's',
        .names = clap.Names{ .long = "show-errors" },
    },

    // Options
    clap.Param(u8){
        .id = 'd',
        .names = clap.Names{ .short = 'd', .long = "max-depth" },
        .takes_value = clap.Values.one,
    },
    clap.Param(u8){
        .id = 't',
        .names = clap.Names{ .short = 't', .long = "type" },
        .takes_value = clap.Values.many,
    },
    clap.Param(u8){
        .id = 'e',
        .names = clap.Names{ .short = 'e', .long = "extension" },
        .takes_value = clap.Values.many,
    },
    clap.Param(u8){
        .id = 'c',
        .names = clap.Names{ .short = 'c', .long = "color" },
        .takes_value = clap.Values.one,
    },
    clap.Param(u8){
        .id = 'x',
        .names = clap.Names{ .short = 'x', .long = "exec" },
    },
    clap.Param(u8){
        .id = 'X',
        .names = clap.Names{ .short = 'X', .long = "exec-batch" },
    },

    // Positionals
    clap.Param(u8){
        .id = '*',
        .takes_value = clap.Values.many,
    },
};

pub fn helpText(param: clap.Param(u8)) []const u8 {
    return switch (param.id) {
        'h' => "Display this help and exit.",
        'v' => "Display version info and exit.",
        'H' => "Include hidden files and directories",
        'p' => "Match the pattern against the full path instead of the file name",
        '0' => "Separate search results with a null character",
        's' => "Show errors which were encountered during searching",
        'd' => "Set a limit for the depth",
        't' => "Filter by entry type",
        'e' => "Additionally filter by a file extension",
        'c' => "Declare when to use colored output",
        'x' => "Execute a command for each search result",
        'X' => "Execute a command with all search results at once",
        '*' => "Pattern or search paths",
        else => unreachable,
    };
}

pub fn valueText(param: clap.Param(u8)) []const u8 {
    return switch (param.id) {
        'd' => "NUM",
        't' => "type",
        'e' => "ext",
        'c' => "when",
        '*' => "pattern/path",
        else => unreachable,
    };
}

pub fn parseCliOptions(base_allocator: Allocator) !CliOptions {
    const arena = try base_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(base_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    // Skip exe argument
    _ = iter.next();

    var diag = clap.Diagnostic{};
    var parser = clap.StreamingClap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    // Walk options
    var walk_options = walkdir.Options{};

    // Filter
    var filter = Filter{};

    // Action
    var action = Action.default;

    // Print options
    var color_option = ColorOption.default;
    var print_options = PrintOptions.default;

    // Search paths
    var paths = ArrayList([]const u8).init(allocator);

    const ParseState = enum {
        Normal,
        Command,
    };
    var state: ParseState = .Normal;

    while (true) {
        switch (state) {
            .Normal => if (parser.next() catch |err| {
                // Report useful error and exit
                diag.report(std.io.getStdErr().writer(), err) catch {};
                return err;
            }) |arg| {
                // arg.param will point to the parameter which matched the argument.
                switch (arg.param.id) {
                    'h' => {
                        try clap.helpEx(
                            std.io.getStdErr().writer(),
                            u8,
                            &params,
                            helpText,
                            valueText,
                        );
                        return error.Help;
                    },
                    'v' => {
                        try std.io.getStdErr().writer().print("zigfd version {s}\n", .{"0.0.1"});
                        return error.Help;
                    },
                    'H' => walk_options.include_hidden = true,
                    'p' => filter.full_path = true,
                    '0' => print_options.null_sep = true,
                    's' => print_options.errors = true,
                    'd' => walk_options.max_depth = try std.fmt.parseInt(usize, arg.value.?, 10),
                    't' => {
                        if (filter.types == null) filter.types = TypeFilter{};
                        if (std.mem.eql(u8, "f", arg.value.?) or std.mem.eql(u8, "file", arg.value.?)) {
                            filter.types.?.file = true;
                        } else if (std.mem.eql(u8, "d", arg.value.?) or std.mem.eql(u8, "directory", arg.value.?)) {
                            filter.types.?.directory = true;
                        } else if (std.mem.eql(u8, "l", arg.value.?) or std.mem.eql(u8, "link", arg.value.?)) {
                            filter.types.?.symlink = true;
                        } else {
                            std.log.err("'{s}' is not a valid type.", .{arg.value.?});
                            return error.ParseCliError;
                        }
                    },
                    'e' => {
                        if (filter.extensions == null) filter.extensions = ArrayList([]const u8).init(allocator);
                        try filter.extensions.?.append(try allocator.dupe(u8, arg.value.?));
                    },
                    'c' => {
                        if (std.mem.eql(u8, "auto", arg.value.?)) {
                            color_option = .Auto;
                        } else if (std.mem.eql(u8, "always", arg.value.?)) {
                            color_option = .Always;
                        } else if (std.mem.eql(u8, "never", arg.value.?)) {
                            color_option = .Never;
                        } else {
                            std.log.err("'{s}' is not a valid color argument.", .{arg.value.?});
                            return error.ParseCliError;
                        }
                    },
                    'x' => {
                        action.deinit();
                        action = Action{
                            .Execute = actions.ExecuteTarget.init(allocator),
                        };
                        state = .Command;
                    },
                    'X' => {
                        action.deinit();
                        action = Action{
                            .ExecuteBatch = actions.ExecuteBatchTarget.init(allocator),
                        };
                        state = .Command;
                    },
                    '*' => {
                        // Positionals
                        // If a regex is already compiled, we are looking at paths
                        if (filter.pattern) |_| {
                            try paths.append(arg.value.?);
                        } else {
                            filter.pattern = try regex.Regex.compile(allocator, arg.value.?);
                        }
                    },
                    else => unreachable,
                }
            } else break,
            .Command => if (iter.next()) |arg| {
                if (std.mem.eql(u8, ";", arg)) {
                    state = .Normal;
                } else {
                    switch (action) {
                        .Execute => |*x| try x.cmd.append(arg),
                        .ExecuteBatch => |*x| try x.cmd.append(arg),
                        else => unreachable, // We can only get to this state by -x or -X
                    }
                }
            } else break,
        }
    }

    // Providing an empty command is an error
    const no_command = switch (action) {
        .Execute => |x| x.cmd.items.len == 0,
        .ExecuteBatch => |x| x.cmd.items.len == 0,
        else => false,
    };
    if (no_command) {
        std.log.err("Expected a command after -x or -X", .{});
        return error.ParseCliError;
    }

    return CliOptions{
        .arena = arena,
        .paths = paths.items,
        .walkdir = walk_options,
        .filter = filter,
        .action = action,
        .color = color_option,
        .print = print_options,
    };
}
