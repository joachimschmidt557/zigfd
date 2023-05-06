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

/// Parameter identification for clap.Param(Id)
pub const Id = enum {
    // flags
    help,
    version,
    hidden,
    full_path,
    print0,
    show_errors,

    // options
    max_depth,
    type,
    extension,
    color,
    exec,
    exec_batch,

    // positionals
    positional,

    pub fn description(id: Id) []const u8 {
        return switch (id) {
            .help => "Display this help and exit.",
            .version => "Display version info and exit.",
            .hidden => "Include hidden files and directories",
            .full_path => "Match the pattern against the full path instead of the file name",
            .print0 => "Separate search results with a null character",
            .show_errors => "Show errors which were encountered during searching",

            .max_depth => "Set a limit for the depth",
            .type => "Filter by entry type",
            .extension => "Additionally filter by a file extension",
            .color => "Declare when to use colored output",
            .exec => "Execute a command for each search result",
            .exec_batch => "Execute a command with all search results at once",

            .positional => "Pattern or search paths",
        };
    }

    pub fn value(id: Id) []const u8 {
        return switch (id) {
            .max_depth => "num",
            .type => "type",
            .extension => "ext",
            .color => "auto|always|never",

            .positional => "pattern/path",

            else => unreachable,
        };
    }
};

/// The command-line flags and options
pub const params = [_]clap.Param(Id){
    // flags
    clap.Param(Id){
        .id = .help,
        .names = clap.Names{ .short = 'h', .long = "help" },
    },
    clap.Param(Id){
        .id = .version,
        .names = clap.Names{ .short = 'v', .long = "version" },
    },
    clap.Param(Id){
        .id = .hidden,
        .names = clap.Names{ .short = 'H', .long = "hidden" },
    },
    clap.Param(Id){
        .id = .full_path,
        .names = clap.Names{ .short = 'p', .long = "full-path" },
    },
    clap.Param(Id){
        .id = .print0,
        .names = clap.Names{ .short = '0', .long = "print0" },
    },
    clap.Param(Id){
        .id = .show_errors,
        .names = clap.Names{ .long = "show-errors" },
    },

    // Options
    clap.Param(Id){
        .id = .max_depth,
        .names = clap.Names{ .short = 'd', .long = "max-depth" },
        .takes_value = clap.Values.one,
    },
    clap.Param(Id){
        .id = .type,
        .names = clap.Names{ .short = 't', .long = "type" },
        .takes_value = clap.Values.many,
    },
    clap.Param(Id){
        .id = .extension,
        .names = clap.Names{ .short = 'e', .long = "extension" },
        .takes_value = clap.Values.many,
    },
    clap.Param(Id){
        .id = .color,
        .names = clap.Names{ .short = 'c', .long = "color" },
        .takes_value = clap.Values.one,
    },
    clap.Param(Id){
        .id = .exec,
        .names = clap.Names{ .short = 'x', .long = "exec" },
    },
    clap.Param(Id){
        .id = .exec_batch,
        .names = clap.Names{ .short = 'X', .long = "exec-batch" },
    },

    // Positionals
    clap.Param(Id){
        .id = .positional,
        .takes_value = clap.Values.many,
    },
};

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
    var parser = clap.streaming.Clap(Id, std.process.ArgIterator){
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
                    .help => {
                        try clap.help(std.io.getStdErr().writer(), Id, &params, .{});
                        return error.Help;
                    },
                    .version => {
                        try std.io.getStdErr().writer().print("zigfd version {s}\n", .{"0.0.1"});
                        return error.Help;
                    },
                    .hidden => walk_options.include_hidden = true,
                    .full_path => filter.full_path = true,
                    .print0 => print_options.null_sep = true,
                    .show_errors => print_options.errors = true,

                    .max_depth => walk_options.max_depth = try std.fmt.parseInt(usize, arg.value.?, 10),
                    .type => {
                        if (filter.types == null) filter.types = TypeFilter{};
                        if (std.mem.eql(u8, "f", arg.value.?) or std.mem.eql(u8, "file", arg.value.?)) {
                            filter.types.?.file = true;
                        } else if (std.mem.eql(u8, "d", arg.value.?) or std.mem.eql(u8, "directory", arg.value.?)) {
                            filter.types.?.directory = true;
                        } else if (std.mem.eql(u8, "l", arg.value.?) or std.mem.eql(u8, "link", arg.value.?)) {
                            filter.types.?.symlink = true;
                        } else if (std.mem.eql(u8, "s", arg.value.?) or std.mem.eql(u8, "socket", arg.value.?)) {
                            filter.types.?.socket = true;
                        } else if (std.mem.eql(u8, "p", arg.value.?) or std.mem.eql(u8, "pipe", arg.value.?)) {
                            filter.types.?.pipe = true;
                        } else {
                            std.log.err("'{s}' is not a valid type.", .{arg.value.?});
                            return error.ParseCliError;
                        }
                    },
                    .extension => {
                        if (filter.extensions == null) filter.extensions = ArrayList([]const u8).init(allocator);
                        try filter.extensions.?.append(try allocator.dupe(u8, arg.value.?));
                    },
                    .color => {
                        if (std.mem.eql(u8, "auto", arg.value.?)) {
                            color_option = .auto;
                        } else if (std.mem.eql(u8, "always", arg.value.?)) {
                            color_option = .always;
                        } else if (std.mem.eql(u8, "never", arg.value.?)) {
                            color_option = .never;
                        } else {
                            std.log.err("'{s}' is not a valid color argument.", .{arg.value.?});
                            return error.ParseCliError;
                        }
                    },
                    .exec => {
                        action.deinit();
                        action = Action{
                            .execute = actions.ExecuteTarget.init(allocator),
                        };
                        state = .Command;
                    },
                    .exec_batch => {
                        action.deinit();
                        action = Action{
                            .execute_batch = actions.ExecuteBatchTarget.init(allocator),
                        };
                        state = .Command;
                    },

                    .positional => {
                        // If a regex is already compiled, we are looking at paths
                        if (filter.pattern) |_| {
                            try paths.append(arg.value.?);
                        } else {
                            filter.pattern = try regex.Regex.compile(allocator, arg.value.?);
                        }
                    },
                }
            } else break,
            .Command => if (iter.next()) |arg| {
                if (std.mem.eql(u8, ";", arg)) {
                    state = .Normal;
                } else {
                    switch (action) {
                        .execute => |*x| try x.cmd.append(arg),
                        .execute_batch => |*x| try x.cmd.append(arg),
                        else => unreachable, // We can only get to this state by -x or -X
                    }
                }
            } else break,
        }
    }

    // Providing an empty command is an error
    const no_command = switch (action) {
        .execute => |x| x.cmd.items.len == 0,
        .execute_batch => |x| x.cmd.items.len == 0,
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
