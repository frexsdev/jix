const std = @import("std");
const io = std.io;
const mem = std.mem;
const process = std.process;
const Writer = std.fs.File.Writer;
const Jix = @import("jix.zig").Jix;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const stdout = io.getStdOut().writer();
const stderr = io.getStdErr().writer();

fn usage(writer: Writer, program: []const u8) void {
    writer.print(
        \\Usage: {s} [options] [command]
        \\
        \\CLI for the Jix virtual machine.
        \\
        \\Options:
        \\  -h, --help                          display this help message
        \\
        \\Commands:
        \\  compile [-r] <input> [-o <output>]  compile a Jix program
        \\  run <input>                         run a Jix compiled program
        \\
    , .{program}) catch unreachable;
}

pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();

    const program = args.next().?;

    if (args.next()) |subcommand| {
        if (mem.eql(u8, subcommand, "compile")) {
            var input_file: ?[]const u8 = null;
            var run = false;
            var output_file: []const u8 = "";

            while (args.next()) |flag| {
                if (mem.eql(u8, flag, "-r")) {
                    run = true;
                } else if (mem.eql(u8, flag, "-o")) {
                    if (args.next()) |file_path| {
                        output_file = file_path;
                    } else {
                        usage(stderr, program);
                        stderr.print("error: output file is not provided", .{}) catch unreachable;
                        process.exit(1);
                    }
                } else {
                    input_file = flag;
                }
            }

            var should_free = false;
            if (input_file) |file_path| {
                if (output_file.len < 1) {
                    output_file = try mem.concat(allocator, u8, ([_][]const u8{ file_path[0 .. file_path.len - 4], ".jout" })[0..]);
                    should_free = true;
                }

                var jix = Jix.init(allocator);
                defer jix.deinit();

                try jix.translateAsm(file_path);
                try jix.saveProgramToFile(output_file);

                if (run) try jix.executeProgram();
            } else {
                usage(stderr, program);
                stderr.print("error: input file is not provided", .{}) catch unreachable;
                process.exit(1);
            }

            if (should_free) allocator.free(output_file);
        } else if (mem.eql(u8, subcommand, "run")) {
            var input_file: ?[]const u8 = null;

            while (args.next()) |flag| {
                input_file = flag;
            }

            if (input_file) |file_path| {
                var jix = Jix.init(allocator);
                defer jix.deinit();

                try jix.loadProgramFromFile(file_path);
                try jix.executeProgram();
            } else {
                usage(stderr, program);
                stderr.print("error: input file is not provided", .{}) catch unreachable;
                process.exit(1);
            }
        } else if (mem.eql(u8, subcommand, "--help") or mem.eql(u8, subcommand, "-h")) {
            usage(stdout, program);
        } else {
            usage(stderr, program);
            stderr.print("error: unknown subcommand `{s}`", .{subcommand}) catch unreachable;
            process.exit(1);
        }
    } else {
        usage(stderr, program);
        stderr.print("error: no subcommand provided", .{}) catch unreachable;
        process.exit(1);
    }
}
