const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
// const Batch = std.event.Batch;
// const Group = std.event.Group;
// const Locked = std.event.Locked;

const regex = @import("regex");
const clap = @import("clap");
const lscolors = @import("lscolors");
const LsColors = lscolors.LsColors;

const walkdir = @import("walkdir");
const Entry = walkdir.Entry;
const DepthFirstWalker = walkdir.DepthFirstWalker;
const BreadthFirstWalker = walkdir.BreadthFirstWalker;

const actions = @import("actions.zig");
const Action = actions.Action;
const ColorOption = actions.ColorOption;
const PrintOptions = actions.PrintOptions;
const filters = @import("filter.zig");
const Filter = filters.Filter;
const TypeFilter = filters.TypeFilter;

const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

// pub const io_mode = .evented;

fn handleEntry(
    e: Entry,
    f: Filter,
    action: *Action,
    print_options: actions.PrintOptions,
    writer: *BufferedWriter,
) void {
    const matches = f.matches(e) catch false;

    defer switch (action.*) {
        .ExecuteBatch => if (!matches) e.deinit(),
        else => e.deinit(),
    };

    if (!matches) return;

    // const held_action = locked_action.acquire();
    // defer held_action.release();

    switch (action.*) {
        .Print => {
            // const held = locked_writer.acquire();
            // defer held.release();

            // const out = held.value.writer();
            actions.printEntry(e, writer.writer(), print_options) catch return;
        },
        .Execute => |*a| a.do(e) catch return,
        .ExecuteBatch => |*a| a.do(e) catch return,
    }
}

pub fn main() !void {
    // Set up allocators
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = &arena.allocator;
    const allocator = std.heap.c_allocator;

    // Set up stdout
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    var buffered_stdout = std.io.bufferedWriter(stdout);
    defer buffered_stdout.flush() catch {};

    // var buffered_stdout_locked = Locked(BufferedOut).init(buffered_stdout);
    // defer buffered_stdout_locked.deinit();
    // defer {
    //     const held = buffered_stdout_locked.acquire();
    //     defer held.release();

    //     held.value.flush() catch {};
    // }

    // These are the command-line args
    const params = [_]clap.Param(u8){
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

    var filter = Filter.all;
    defer filter.deinit();

    // var locked_action = Locked(Action).init(action);

    // Action
    var action = Action.default;
    defer action.deinit();

    // Print options
    var lsc: ?LsColors = null;
    defer if (lsc) |*x| x.deinit();

    var color_option = ColorOption.default;
    var print_options = PrintOptions.default;

    var paths = ArrayList([]const u8).init(allocator);
    defer paths.deinit();

    // var group = Group(void).init(allocator);
    // var batch = Batch(void, 8, .auto_async).init();

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
                        try std.io.getStdErr().writer().print("Help!\n", .{});
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
                            std.log.emerg(.Args, "zigfd: '{}' is not a valid type.\n", .{arg.value.?});
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
                            std.log.emerg(.Args, "zigfd: '{}' is not a valid color argument.", .{arg.value.?});
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
        std.log.emerg(.Args, "zigfd: Expected a command after -x oder -X", .{});
        std.process.exit(1);
    }

    // Set up colored output
    if (color_option == .Always or color_option == .Auto and std.io.getStdErr().isTty()) {
        lsc = try LsColors.fromEnv(allocator);
        print_options.color = &lsc.?;
    }

    // If no search paths were given, default to the current
    // working directory.
    if (paths.items.len == 0) {
        // Add current working directory to search paths
        try paths.append(".");
    }

    outer: for (paths.items) |search_path| {
        var walker = try DepthFirstWalker.init(allocator, search_path, walk_options);
        // var walker = try BreadthFirstWalker.init(allocator, search_path, walk_options);

        inner: while (true) {
            if (walker.next()) |entry| {
                if (entry) |e| {
                    handleEntry(e, filter, &action, print_options, &buffered_stdout);
                } else {
                    continue :outer;
                }
            } else |err| {
                std.log.err(.Walkdir, "Error encountered: {}\n", .{err});
            }
        }
    }

    // Complete async group
    // batch.wait();

    // If the action ExecuteBatch is chosen, we have to execute the action after
    // all entries have been found
    switch (action) {
        .ExecuteBatch => |*a| try a.finalize(),
        else => {},
    }
}
