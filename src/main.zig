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
    if (!(f.matches(e) catch return)) return;

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
            .takes_value = true,
        },
        clap.Param(u8){
            .id = 'X',
            .names = clap.Names{ .short = 'X', .long = "exec-batch" },
            .takes_value = true,
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

    // Print options
    var lsc: ?LsColors = null;
    defer if (lsc) |*x| x.deinit();

    var print_options = PrintOptions.default;

    var paths = ArrayList([]const u8).init(allocator);
    defer paths.deinit();

    // var group = Group(void).init(allocator);
    // var batch = Batch(void, 8, .auto_async).init();

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (try parser.next()) |arg| {
        // arg.param will point to the parameter which matched the argument.
        switch (arg.param.id) {
            'h' => return std.debug.warn("Help!\n", .{}),
            'v' => return try buffered_stdout.writer().print("zigfd version {}\n", .{"0.0.1"}),
            'H' => walk_options.include_hidden = true,
            'p' => filter.full_path = true,
            '0' => print_options.null_sep = true,
            's' => print_options.errors = true,
            'd' => walk_options.max_depth = try std.fmt.parseInt(usize, arg.value.?, 10),
            't' => {
                const t = arg.value.?;
                filter.types = TypeFilter.none;
                if (std.mem.eql(u8, "f", t) or std.mem.eql(u8, "file", t)) {
                    filter.types.?.file = true;
                } else if (std.mem.eql(u8, "d", t) or std.mem.eql(u8, "directory", t)) {
                    filter.types.?.directory = true;
                } else if (std.mem.eql(u8, "l", t) or std.mem.eql(u8, "link", t)) {
                    filter.types.?.symlink = true;
                } else {
                    std.debug.warn("zigfd: '{}' is not a valid type.\n", .{t});
                    std.process.exit(1);
                }
            },
            'e' => filter.extension = arg.value.?,
            'c' => {},
            'x' => action = Action{
                .Execute = actions.ExecuteTarget.init(allocator, arg.value.?),
            },
            'X' => action = Action{
                .ExecuteBatch = actions.ExecuteBatchTarget.init(allocator, arg.value.?),
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

                    switch (action) {
                        .ExecuteBatch => {},
                        else => e.deinit(),
                    }
                } else {
                    continue :outer;
                }
            } else |err| {
                // const held = buffered_stdout_locked.acquire();
                // defer held.release();

                // const out = held.value.writer();
                try actions.printError(err, buffered_stdout.writer(), print_options);
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
