const std = @import("std");
const ArrayList = std.ArrayList;

const regex = @import("regex");
const clap = @import("clap");
const lscolors = @import("lscolors");
const LsColors = lscolors.LsColors;

const walkdir = @import("walkdir");
const DepthFirstWalker = walkdir.DepthFirstWalker;
const BreadthFirstWalker = walkdir.BreadthFirstWalker;

const actions = @import("actions.zig");

const PathQueue = std.atomic.Queue([]const u8);

pub fn main() !void {
    // Set up allocators
    // var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    // defer arena.deinit();
    // const allocator = &arena.allocator;
    const allocator = std.heap.c_allocator;

    // Set up stdout
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.outStream();
    var buffered_stdout = std.io.bufferedOutStream(stdout);
    const out = buffered_stdout.outStream();
    defer buffered_stdout.flush() catch {};

    // These are the command-line args
    @setEvalBranchQuota(10000);
    const params = comptime [_]clap.Param(clap.Help){
        // Flags
        clap.parseParam("-h, --help Display this help and exit.") catch unreachable,
        clap.parseParam("-v, --version Display version info and exit.") catch unreachable,
        clap.parseParam("-H, --hidden Include hidden files and directories") catch unreachable,
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
        return try clap.help(out, &params);
    }
    if (args.flag("--version")) {
        return try out.print("zigfd version {}\n", .{"0.0.1"});
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

    var action: actions.Action = actions.Action.Print;

    // Action
    if (args.option("--exec")) |cmd| {
        action = actions.Action{
            .Execute = actions.ExecuteTarget{
                .cmd = cmd,
            }
        };
    } else if (args.option("--exec-batch")) |cmd| {
        action = actions.Action{
            .ExecuteBatch = actions.ExecuteBatchTarget{
                .cmd = cmd,
                .args = ArrayList([]const u8).init(allocator),
            }
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

    var re: ?regex.Regex = null;
    var paths = PathQueue.init();

    // Positionals
    for (args.positionals()) |pos| {
        // If a regex is already compiled, we are looking at paths
        if (re) |_| {
            const new_node = try allocator.create(PathQueue.Node);
            new_node.* = PathQueue.Node {
                .next = undefined,
                .prev = undefined,
                .data = pos,
            };

            paths.put(new_node);
        }
        else {
            re = try regex.Regex.compile(allocator, pos);
        }
    }

    // If no search paths were given, default to the current
    // working directory.
    if (paths.isEmpty()) {
        // Add current working directory to search paths
        const new_node = try allocator.create(PathQueue.Node);
        new_node.* = PathQueue.Node{
            .next = undefined,
            .prev = undefined,
            .data = ".",
        };

        paths.put(new_node);
    }

    outer: while (paths.get()) |search_path| {
        var walker = try DepthFirstWalker.init(allocator, search_path.data, walk_options);
        // var walker = try BreadthFirstWalker.init(allocator, search_path.data, walk_options);
        defer allocator.destroy(search_path);

        inner: while (true) {
            if (walker.next()) |entry| {
                if (entry) |e| {
                    defer e.deinit();

                    if (re) |*pattern| {
                        if (try pattern.partialMatch(e.name)) {
                            switch (action) {
                                .Print => try actions.printEntry(e, out, print_options),
                                .Execute => |*a| try a.do(e),
                                .ExecuteBatch => |*a| try a.do(e),
                            }
                        }
                    } else {
                        switch (action) {
                            .Print => try actions.printEntry(e, out, print_options),
                            .Execute => |*a| try a.do(e),
                            .ExecuteBatch => |*a| try a.do(e),
                        }
                    }
                } else {
                    continue :outer;
                }
            } else |err| {
                try actions.printError(err, out, print_options);
            }
        }
    }

    // If the action ExecuteBatch is chosen, we have to execute the action after
    // all entries have been found
    switch (action) {
        .ExecuteBatch => |*a| try a.finalize(),
        else => {},
    }
}
