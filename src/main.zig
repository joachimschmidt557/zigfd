const std = @import("std");

const regex = @import("zig-regex/regex.zig");
const clap = @import("zig-clap/index.zig");

const recursive = @import("recursiveWalk.zig");
//const iterative = @import("iterativeWalk.zig");

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
    const params = comptime []clap.Param([]const u8){
        // Flags
        clap.Param([]const u8).flag(
            "Display this help and exit.",
            clap.Names.both("help"),
        ),
        clap.Param([]const u8).flag(
            "Include hidden files and directories",
            clap.Names{
                .short = 'H',
                .long = "hidden",
            }
        ),

        // Options
        clap.Param([]const u8).option(
            "Set a limit for the depth",
            clap.Names{
                .short = 'd',
                .long = "max-depth",
            }
        ),

        // Positionals
        clap.Param([]const u8).positional("PATTERN"),
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

    // clap.help is a function that can print a simple help message, given a
    // slice of Param([]const u8). There is also a helpEx, which can print a
    // help message for any Param, but it is more verbose to call.
    if (args.flag("--help"))
        return try clap.help(stdout, params);
    for (args.positionals()) |pos|
        std.debug.warn("{}\n", pos);


    // Get current working directory
    var cwd_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const search_path = try std.os.getcwd(&cwd_buf);

    try recursive.walkDir(allocator, search_path);
}
