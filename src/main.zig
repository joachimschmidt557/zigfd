const std = @import("std");
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
const Filter = @import("filter.zig").Filter;

const BufferedOut = std.io.BufferedOutStream(4096, std.fs.File.OutStream);

// pub const io_mode = .evented;

fn handleEntry(e: Entry, filter: Filter, action: *Action, print_options: actions.PrintOptions, out_stream: *BufferedOut) void {
    if (!(filter.matches(e) catch return)) return;
    
    // const held_action = locked_action.acquire();
    // defer held_action.release();

    switch (action.*) {
        .Print => {
            // const held = locked_out_stream.acquire();
            // defer held.release();

            // const out = held.value.outStream();
            actions.printEntry(e, out_stream.outStream(), print_options) catch return;
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
    const stdout = stdout_file.outStream();

    var buffered_stdout = std.io.bufferedOutStream(stdout);
    defer buffered_stdout.flush() catch {};

    // var buffered_stdout_locked = Locked(BufferedOut).init(buffered_stdout);
    // defer buffered_stdout_locked.deinit();
    // defer {
    //     const held = buffered_stdout_locked.acquire();
    //     defer held.release();

    //     held.value.flush() catch {};
    // }

    // These are the command-line args
    @setEvalBranchQuota(10000);
    const params = comptime [_]clap.Param(clap.Help){
        // Flags
        clap.parseParam("-h, --help Display this help and exit.") catch unreachable,
        clap.parseParam("-v, --version Display version info and exit.") catch unreachable,
        clap.parseParam("-H, --hidden Include hidden files and directories") catch unreachable,
        clap.parseParam("-p, --full-path Match the pattern against the full path instead of the file name") catch unreachable,
        clap.parseParam("-0, --print0 Separate search results with a null character") catch unreachable,
        clap.parseParam("--show-errors Show errors which were encountered during searching") catch unreachable,

        // Options
        clap.parseParam("-d, --max-depth <NUM> Set a limit for the depth") catch unreachable,
        clap.parseParam("-c, --color <when> Declare when to use colored output") catch unreachable,
        clap.parseParam("-x, --exec <cmd> Execute a command for each search result") catch unreachable,
        clap.parseParam("-X, --exec-batch <cmd> Execute a command with all search results at once") catch unreachable,

        // Positionals
        clap.Param(clap.Help){
            .takes_value = true,
        },
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = try clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    // Finally we can parse the arguments
    var args = try clap.ComptimeClap(clap.Help, &params).parse(allocator, clap.args.OsIterator, &iter);
    defer args.deinit();

    // Flags
    if (args.flag("--help")) {
        return try clap.help(buffered_stdout.outStream(), &params);
    }
    if (args.flag("--version")) {
        return try buffered_stdout.outStream().print("zigfd version {}\n", .{"0.0.1"});
    }

    // Walk options
    const walk_options = walkdir.Options{
        .include_hidden = args.flag("--hidden"),
        .max_depth = blk: {
            if (args.option("--max-depth")) |d| {
                break :blk std.fmt.parseUnsigned(usize, d, 10) catch null;
            } else {
                break :blk null;
            }
        },
    };

    var filter = Filter{
        .pattern = null,
        .full_path = args.flag("--full-path"),
    };
    defer filter.deinit();
    // var locked_action = Locked(Action).init(action);
    var action: Action = Action.Print;

    // Action
    if (args.option("--exec")) |cmd| {
        action = Action{
            .Execute = actions.ExecuteTarget.init(allocator, cmd),
        };
    } else if (args.option("--exec-batch")) |cmd| {
        action = Action{
            .ExecuteBatch = actions.ExecuteBatchTarget.init(allocator, cmd),
        };
    }

    // Print options
    var lsc: ?LsColors = null;
    defer if (lsc) |*x| x.deinit();

    const print_options = actions.PrintOptions{
        .color = blk: {
            if (args.option("--color")) |when| {
                if (std.mem.eql(u8, "always", when) or stdout_file.isTty()) {
                    lsc = try LsColors.fromEnv(allocator);
                    break :blk &lsc.?;
                }
            }

            break :blk null;
        },
        .null_sep = args.flag("--print0"),
        .errors = args.flag("--show-errors"),
    };

    var paths = ArrayList([]const u8).init(allocator);
    defer paths.deinit();

    // var group = Group(void).init(allocator);
    // var batch = Batch(void, 8, .auto_async).init();

    // Positionals
    for (args.positionals()) |pos| {
        // If a regex is already compiled, we are looking at paths
        if (filter.pattern) |_| {
            try paths.append(pos);
        }
        else {
            filter.pattern = try regex.Regex.compile(allocator, pos);
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

                // const out = held.value.outStream();
                try actions.printError(err, buffered_stdout.outStream(), print_options);
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
