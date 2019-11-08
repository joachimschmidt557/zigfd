const std = @import("std");

const regex      = @import("zig-regex/src/regex.zig");
const clap       = @import("zig-clap/clap.zig");

const depth_first = @import("zig-walkdir/src/depth_first.zig");
const breadth_first = @import("zig-walkdir/src/breadth_first.zig");
const walkdir    = @import("zig-walkdir/src/main.zig");
const printer    = @import("printer.zig");

pub fn main() !void {
    // Set up allocators
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    // Set up stdout
    const stdout_file = try std.io.getStdOut();
    var stdout_out_stream = stdout_file.outStream();
    const stdout = &stdout_out_stream.stream;

    // Set up walking options
    var walk_options = walkdir.WalkDirOptions.default();

    // These are the command-line args
    const params = comptime [_]clap.Param(clap.Help){
        // Flags
        clap.parseParam("-h, --help Display this help and exit.") catch unreachable,
        clap.parseParam("-v, --version Display version info and exit.") catch unreachable,
        clap.parseParam("-H, --hidden Include hidden files and directories") catch unreachable,

        // Options
        clap.parseParam("-d, --max-depth <NUM> Set a limit for the depth") catch unreachable,

        // Positionals
        clap.Param(clap.Help){
            .takes_value = true,
        },
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = clap.args.OsIterator.init(std.heap.direct_allocator);
    defer iter.deinit();

    // Consume the exe arg.
    const exe = try iter.next();

    // Finally we can parse the arguments
    var args = try clap.ComptimeClap(clap.Help, params).parse(std.heap.direct_allocator, clap.args.OsIterator, &iter);
    defer args.deinit();

    // Flags
    if (args.flag("--help")) {
        return try clap.help(stdout, params);
    }
    if (args.flag("--version")) {
        return try stdout.print("zigfd\n");
    }
    if (args.flag("--hidden")) {
        walk_options.include_hidden = true;
    }

    // Options
    if (args.option("--max-depth")) |d| {
        const depth = try std.fmt.parseUnsigned(u32, d, 10);
        walk_options.max_depth = depth;
    }

    var re: ?regex.Regex = null;
    var paths: std.atomic.Queue([]u8) = std.atomic.Queue([]u8).init();

    // Positionals
    for (args.positionals()) |pos| {
        // If a regex is already compiled, we are looking at paths
        if (re) |_| {
            const new_path = try allocator.alloc(u8, pos.len);
            std.mem.copy(u8, new_path, pos);

            const new_node = try allocator.create(std.atomic.Queue([]u8).Node);
            new_node.* = std.atomic.Queue([]u8).Node {
                .next = undefined,
                .prev = undefined,
                .data = new_path,
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
        var cwd_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const cwd = try std.os.getcwd(&cwd_buf);

        const new_node = try allocator.create(std.atomic.Queue([]u8).Node);
        new_node.* = std.atomic.Queue([]u8).Node {
            .next = undefined,
            .prev = undefined,
            .data = cwd,
        };

        paths.put(new_node);
    }

    outer: while (paths.get()) |search_path| {
        //var walker = try walkdir.Walker.init(allocator, search_path.data, walk_options);
        var walker = try depth_first.DepthFirstWalker.init(allocator, search_path.data, walk_options.max_depth, walk_options.include_hidden);
        //var walker = try breadth_first.BreadthFirstWalker.init(allocator, search_path.data, walk_options.max_depth, walk_options.include_hidden);
        defer allocator.destroy(search_path);

        inner: while (walker.next()) |entry| {
            if (entry) |e| {
                if (re) |*pattern| {
                    if (try pattern.match(e.name)) {
                        try printer.printEntryStream(e, stdout);
                    }
                } else {
                    try printer.printEntryStream(e, stdout);
                }
            } else {
                continue :outer;
            }
        } else |err| {
            return err;
        }
    }
}
