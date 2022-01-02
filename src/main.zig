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
const cli = @import("cli.zig");

const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

// pub const io_mode = .evented;

inline fn handleEntry(
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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

    var lsc: ?LsColors = null;
    defer if (lsc) |*x| x.deinit();

    var cli_options = cli.parseCliOptions(allocator) catch |err| switch (err) {
        error.Help, error.ParseCliError => std.process.exit(1),
        else => return err,
    };
    defer cli_options.deinit();

    // Set up colored output
    if (cli_options.color == .Always or cli_options.color == .Auto and stdout_file.isTty()) {
        lsc = try LsColors.fromEnv(allocator);
        cli_options.print.color = &lsc.?;
    }

    // If no search paths were given, default to the current
    // working directory.
    const search_paths = if (cli_options.paths.len == 0) &[_][]const u8{"."} else cli_options.paths;

    outer: for (search_paths) |search_path| {
        var walker = try DepthFirstWalker.init(allocator, search_path, cli_options.walkdir);
        // var walker = try BreadthFirstWalker.init(allocator, search_path, cli_options.walkdir);
        defer walker.deinit();

        while (true) {
            if (walker.next()) |entry| {
                if (entry) |e| {
                    handleEntry(
                        e,
                        cli_options.filter,
                        &cli_options.action,
                        cli_options.print,
                        &buffered_stdout,
                    );
                } else {
                    continue :outer;
                }
            } else |err| {
                std.log.err("Error encountered: {}", .{err});
            }
        }
    }

    // Complete async group
    // batch.wait();

    // If the action ExecuteBatch is chosen, we have to execute the action after
    // all entries have been found
    switch (cli_options.action) {
        .ExecuteBatch => |*a| try a.finalize(),
        else => {},
    }
}
