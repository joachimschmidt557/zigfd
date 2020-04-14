const std = @import("std");

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

    var action = actions.Action.default;
    defer action.deinit();

    // Flags
    if (args.flag("--help")) {
        return try clap.help(out, &params);
    }
    if (args.flag("--version")) {
        return try out.print("zigfd version {}\n", .{"0.0.1"});
    }

    // Options
    // if (args.option("--color")) |when| {
    //     if (std.mem.eql(u8, "always", when) or stdout_file.isTty()) {
    //         print_options.color = try LsColors.fromEnv(allocator);
    //     }
    // }

    // Walk options
    const walk_options = walkdir.Options{
        .include_hidden = args.flag("--hidden"),
        .max_depth = if (args.option("--max-depth")) |d|
            std.fmt.parseUnsigned(usize, d, 10) catch null
            else null,
     };

    // Action
    if (args.option("--exec")) |cmd| {
        action = actions.Action{
            .Execute = actions.ExecuteOptions{
                .cmd = cmd,
            }
        };
    } else {
        action = actions.Action{
            .Print = actions.PrintOptions{
                .color = null,
                .null_sep = args.flag("--print0"),
                .errors = args.flag("--show-errors"),
            }
        };
    }

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
                        switch (action) {
                            .Print => |x| try actions.printEntry(e, out, x),
                            else => {},
                        }
                    } else {
                        switch (action) {
                            .Print => |x| try actions.printEntry(e, out, x),
                            else => {},
                        }
                    }
                } else {
                    continue :outer;
                }
            } else |err| {
                try actions.printError(err, out, actions.PrintOptions.default);
            }
        }
    }
}
