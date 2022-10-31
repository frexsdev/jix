const std = @import("std");
const io = std.io;
const mem = std.mem;
const process = std.process;
const Writer = std.fs.File.Writer;
const Jix = @import("jix.zig").Jix;
const Inst = @import("inst.zig").Inst;
const JixError = @import("error.zig").JixError;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const InstHasOperand = @import("inst.zig").InstHasOperand;

const stdout = io.getStdOut().writer();
const stderr = io.getStdErr().writer();

fn usage(writer: Writer, program: []const u8) void {
    writer.print(
        \\Usage: {s} [options] [command]
        \\
        \\CLI for the Jix virtual machine.
        \\
        \\Options:
        \\  -h, --help                                                display this help message
        \\
        \\Commands:
        \\  compile [-r [-l <limit>]] <input.jix> [-o <output.jout>]  compile a Jix program
        \\  run <input.jout>                                          run a Jix's compiled program
        \\  disasm <input.jout>                                       disassemble a Jix's compiled program
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
            var output_file: ?[]const u8 = null;
            var limit: isize = -1;

            while (args.next()) |flag| {
                if (mem.eql(u8, flag, "-r")) {
                    run = true;
                } else if (mem.eql(u8, flag, "-o")) {
                    if (args.next()) |file_path| {
                        output_file = file_path;
                    } else {
                        usage(stderr, program);
                        stderr.print("error: output file is not provided\n", .{}) catch unreachable;
                        process.exit(1);
                    }
                } else if (mem.eql(u8, flag, "-l")) {
                    if (args.next()) |limit_str| {
                        limit = std.fmt.parseInt(isize, limit_str, 10) catch {
                            usage(stderr, program);
                            stderr.print("error: the limit should be a number\n", .{}) catch unreachable;
                            process.exit(1);
                        };
                    } else {
                        usage(stderr, program);
                        stderr.print("error: limit is not provided\n", .{}) catch unreachable;
                        process.exit(1);
                    }
                } else {
                    if (flag[0] == '-') {
                        usage(stderr, program);
                        stderr.print("error: unknown flag `{s}`\n", .{flag}) catch unreachable;
                        process.exit(1);
                    }

                    input_file = flag;
                }
            }

            if (input_file) |file_path| {
                var jix = Jix.init(allocator);
                defer jix.deinit();

                jix.translateAsm(file_path) catch |e| {
                    switch (e) {
                        JixError.IllegalInst => {
                            stderr.print("{s}:{}: error: illegal instruction\n", .{
                                file_path,
                                jix.error_context.illegal_inst.line_number,
                            }) catch unreachable;
                            process.exit(1);
                        },
                        JixError.IllegalOperand => {
                            stderr.print("{s}:{}: error: illegal operand\n", .{
                                file_path,
                                jix.error_context.illegal_operand.line_number,
                            }) catch unreachable;
                            process.exit(1);
                        },
                        JixError.MissingOperand => {
                            stderr.print("{s}:{}: error: missing operand\n", .{
                                file_path,
                                jix.error_context.missing_operand.line_number,
                            }) catch unreachable;
                            process.exit(1);
                        },
                        else => return e,
                    }
                };

                if (output_file) |output_file_path| {
                    try jix.saveProgramToFile(output_file_path);
                } else {
                    const output_file_path = try mem.concat(allocator, u8, ([_][]const u8{ file_path[0 .. file_path.len - 4], ".jout" })[0..]);
                    defer allocator.free(output_file_path);

                    try jix.saveProgramToFile(output_file_path);
                }

                if (run) try jix.executeProgram(limit);
            } else {
                usage(stderr, program);
                stderr.print("error: input file is not provided\n", .{}) catch unreachable;
                process.exit(1);
            }
        } else if (mem.eql(u8, subcommand, "run")) {
            var input_file: ?[]const u8 = null;
            var limit: isize = -1;

            while (args.next()) |flag| {
                if (mem.eql(u8, flag, "-l")) {
                    if (args.next()) |limit_str| {
                        limit = std.fmt.parseInt(isize, limit_str, 10) catch {
                            usage(stderr, program);
                            stderr.print("error: the limit should be a number\n", .{}) catch unreachable;
                            process.exit(1);
                        };
                    } else {
                        usage(stderr, program);
                        stderr.print("error: limit is not provided\n", .{}) catch unreachable;
                        process.exit(1);
                    }
                } else {
                    if (flag[0] == '-') {
                        usage(stderr, program);
                        stderr.print("error: unknown flag `{s}`\n", .{flag}) catch unreachable;
                        process.exit(1);
                    }

                    input_file = flag;
                }
            }

            if (input_file) |file_path| {
                var jix = Jix.init(allocator);
                defer jix.deinit();

                try jix.loadProgramFromFile(file_path);
                try jix.executeProgram(limit);
            } else {
                usage(stderr, program);
                stderr.print("error: input file is not provided\n", .{}) catch unreachable;
                process.exit(1);
            }
        } else if (mem.eql(u8, subcommand, "disasm")) {
            var input_file: ?[]const u8 = null;

            while (args.next()) |flag| {
                input_file = flag;
            }

            if (input_file) |file_path| {
                var jix = Jix.init(allocator);
                defer jix.deinit();

                try jix.loadProgramFromFile(file_path);

                for (jix.program.items()) |inst| {
                    const inst_name = @tagName(inst.@"type");
                    if (InstHasOperand.get(inst_name).?)
                        switch (inst.operand) {
                            .as_u64 => |w| stdout.print("{s} {}\n", .{ inst_name, w }) catch unreachable,
                            .as_i64 => |w| stdout.print("{s} {}\n", .{ inst_name, w }) catch unreachable,
                            .as_f64 => |w| stdout.print("{s} {d}\n", .{ inst_name, w }) catch unreachable,
                            .as_ptr => |w| stdout.print("{s} {}\n", .{ inst_name, w }) catch unreachable,
                        }
                    else
                        stdout.print("{s}\n", .{inst_name}) catch unreachable;
                }
            } else {
                usage(stderr, program);
                stderr.print("error: input file is not provided\n", .{}) catch unreachable;
                process.exit(1);
            }
        } else if (mem.eql(u8, subcommand, "--help") or mem.eql(u8, subcommand, "-h")) {
            usage(stdout, program);
        } else {
            usage(stderr, program);
            stderr.print("error: unknown subcommand `{s}`\n", .{subcommand}) catch unreachable;
            process.exit(1);
        }
    } else {
        usage(stderr, program);
        stderr.print("error: no subcommand provided\n", .{}) catch unreachable;
        process.exit(1);
    }
}
