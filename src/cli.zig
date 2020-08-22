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
    paths: []const []const u8,
    walkdir: walkdir.Options,
    filter: Filter,
    action: Action,
    color: ColorOption,
    print: PrintOptions,
};

/// The command-line arguments
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
        .takes_value = true,
    },
    clap.Param(u8){
        .id = 't',
        .names = clap.Names{ .short = 't', .long = "type" },
        .takes_value = true,
    },
    clap.Param(u8){
        .id = 'e',
        .names = clap.Names{ .short = 'e', .long = "extension" },
        .takes_value = true,
    },
    clap.Param(u8){
        .id = 'c',
        .names = clap.Names{ .short = 'c', .long = "color" },
        .takes_value = true,
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
        .takes_value = true,
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

pub fn parseCliOptions(allocator: *Allocator) !CliOptions {
    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = try clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    // Finally we can parse the arguments
    var parser = clap.StreamingClap(u8, clap.args.OsIterator){
        .params = &params,
        .iter = &iter,
    };

    // Walk options
    var walk_options = walkdir.Options.default;

    // Filter
    var filter = Filter.all;

    // Action
    var action = Action.default;

    // Print options
    var color_option = ColorOption.default;
    var print_options = PrintOptions.default;

    var paths = ArrayList([]const u8).init(allocator);

    const ParseState = enum {
        Normal,
        Command,
    };
    var state: ParseState = .Normal;

    while (true) {
        switch (state) {
            .Normal => if (try parser.next()) |arg| {
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
                        std.process.exit(1);
                    },
                    'v' => {
                        try std.io.getStdErr().writer().print("zigfd version {}\n", .{"0.0.1"});
                        std.process.exit(1);
                    },
                    'H' => walk_options.include_hidden = true,
                    'p' => filter.full_path = true,
                    '0' => print_options.null_sep = true,
                    's' => print_options.errors = true,
                    'd' => walk_options.max_depth = try std.fmt.parseInt(usize, arg.value.?, 10),
                    't' => {
                        if (filter.types == null) filter.types = TypeFilter.none;
                        if (std.mem.eql(u8, "f", arg.value.?) or std.mem.eql(u8, "file", arg.value.?)) {
                            filter.types.?.file = true;
                        } else if (std.mem.eql(u8, "d", arg.value.?) or std.mem.eql(u8, "directory", arg.value.?)) {
                            filter.types.?.directory = true;
                        } else if (std.mem.eql(u8, "l", arg.value.?) or std.mem.eql(u8, "link", arg.value.?)) {
                            filter.types.?.symlink = true;
                        } else {
                            std.log.emerg("zigfd: '{}' is not a valid type.\n", .{arg.value.?});
                            std.process.exit(1);
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
                            std.log.emerg("zigfd: '{}' is not a valid color argument.", .{arg.value.?});
                            std.process.exit(1);
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
            .Command => if (try iter.next()) |arg| {
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
        std.log.emerg("zigfd: Expected a command after -x oder -X", .{});
        std.process.exit(1);
    }

    return CliOptions{
        .paths = paths.items,
        .walkdir = walk_options,
        .filter = filter,
        .action = action,
        .color = color_option,
        .print = print_options,
    };
}
