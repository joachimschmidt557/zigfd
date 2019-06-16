const std = @import("std");

const regex = @import("zig-regex/src/regex.zig");
const clap = @import("zig-clap/clap.zig");

const recursive = @import("recursiveWalk.zig");
const iterative = @import("iterativeWalk.zig");
const printer   = @import("printer.zig");

pub fn main() anyerror!void {
    // Set up allocators
    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();
    const dir_allocator = &direct_allocator.allocator;

    var arena = std.heap.ArenaAllocator.init(&direct_allocator.allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    // Set up stdout
    const stdout_file = try std.io.getStdOut();
    var stdout_out_stream = stdout_file.outStream();
    const stdout = &stdout_out_stream.stream;

    // These are the command-line args
    const params = comptime [_]clap.Param([]const u8){
        // Flags
        clap.Param([]const u8){
            .id = "Display this help and exit.",
            .names = clap.Names{ .short = 'h', .long = "help" },
        },
        clap.Param([]const u8){
            .id = "Display version info and exit.",
            .names = clap.Names{ .short = 'v', .long = "version" },
        },
        clap.Param([]const u8){
            .id = "Include hidden files and directories",
            .names = clap.Names{
                .short = 'H',
                .long = "hidden",
            },
        },

        // Options
        clap.Param([]const u8){
            .id = "Set a limit for the depth",
            .names = clap.Names{
                .short = 'd',
                .long = "max-depth",
            },
            .takes_value = true,
        },

        // Positionals
        clap.Param([]const u8){
            .id = "PATTERN",
            .takes_value = true,
        },
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = clap.args.OsIterator.init(dir_allocator);
    defer iter.deinit();

    // Consume the exe arg.
    const exe = try iter.next();

    // Finally we can parse the arguments
    var args = try clap.ComptimeClap([]const u8, params).parse(dir_allocator, clap.args.OsIterator, &iter);
    defer args.deinit();

    // Flags
    if (args.flag("--help")) {
        return try clap.help(stdout, params);
    }
    if (args.flag("--version")) {
        return try stdout_file.write("zigfd\n");
    }

    // Options
    if (args.option("--max-depth")) |d| {
    }

    var re : ?regex.Regex = null;
    var paths : std.atomic.Queue([]u8) = std.atomic.Queue([]u8).init();
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

    while (paths.get()) |search_path| {
        var walker = try iterative.IterativeWalker.init(allocator, search_path.data);
        defer allocator.destroy(search_path);
        while (try walker.next()) |entry| {
            if (re) |pattern| {
                if (try re.?.match(entry.name)) {
                    try printer.printEntry(entry, stdout_file);
                }
            } else {
                try printer.printEntry(entry, stdout_file);
            }
        }
    }
}
