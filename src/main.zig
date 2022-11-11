const std = @import("std");
const Writer = std.fs.File.Writer;
const Jix = @import("jix.zig").Jix;
const String = @import("string.zig").String;
const JixError = @import("error.zig").JixError;
const natives = @import("natives.zig").natives;
const ArenaAllocator = std.heap.ArenaAllocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

usingnamespace @import("inst.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const stdin = std.io.getStdIn().reader();

const Global = @This();

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
        \\  compile [-r [-l <limit>] [-s]] <input.jix> [-o <output.jout>]  compile a Jix program
        \\  run [-s] <input.jout>                                          run a Jix's compiled program
        \\  disasm <input.jout>                                            disassemble a Jix's compiled program
        \\
    , .{program}) catch unreachable;
}

pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var aa = ArenaAllocator.init(gpa.allocator());
    defer aa.deinit();

    const allocator = aa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    const program = args.next().?;

    if (args.next()) |subcommand| {
        if (std.mem.eql(u8, subcommand, "compile")) {
            var input_file = String.init(allocator);
            var run = false;
            var output_file = String.init(allocator);
            var limit: isize = -1;
            var step = false;

            while (args.next()) |flag| {
                if (std.mem.eql(u8, flag, "-r")) {
                    run = true;
                } else if (std.mem.eql(u8, flag, "-o")) {
                    if (args.next()) |file_path| {
                        output_file.clear();
                        try output_file.concat(file_path);
                    } else {
                        usage(stderr, program);
                        stderr.print("error: output file is not provided\n", .{}) catch unreachable;
                        std.process.exit(1);
                    }
                } else if (std.mem.eql(u8, flag, "-l")) {
                    if (args.next()) |limit_str| {
                        limit = std.fmt.parseInt(isize, limit_str, 10) catch {
                            usage(stderr, program);
                            stderr.print("error: the limit should be a number\n", .{}) catch unreachable;
                            std.process.exit(1);
                        };
                    } else {
                        usage(stderr, program);
                        stderr.print("error: limit is not provided\n", .{}) catch unreachable;
                        std.process.exit(1);
                    }
                } else if (std.mem.eql(u8, flag, "-s")) {
                    step = true;
                } else {
                    if (flag[0] == '-') {
                        usage(stderr, program);
                        stderr.print("error: unknown flag `{s}`\n", .{flag}) catch unreachable;
                        std.process.exit(1);
                    }

                    input_file.clear();
                    try input_file.concat(flag);
                }
            }

            if (input_file.len() < 1) {
                usage(stderr, program);
                stderr.print("error: input file is not provided\n", .{}) catch unreachable;
                std.process.exit(1);
            }

            var jix = Jix.init(allocator);
            defer jix.deinit();

            jix.translateSource(input_file, 0) catch |e| {
                switch (e) {
                    JixError.IllegalInst => {
                        stderr.print("{s}:{}: error: illegal instruction `{s}`\n", .{
                            jix.error_context.illegal_inst.file_path.str(),
                            jix.error_context.illegal_inst.line_number,
                            jix.error_context.illegal_inst.inst.str(),
                        }) catch unreachable;
                        std.process.exit(1);
                    },
                    JixError.IllegalOperand => {
                        stderr.print("{s}:{}: error: illegal operand `{s}`\n", .{
                            jix.error_context.illegal_operand.file_path.str(),
                            jix.error_context.illegal_operand.line_number,
                            jix.error_context.illegal_operand.operand.string.str(),
                        }) catch unreachable;
                        std.process.exit(1);
                    },
                    JixError.MissingOperand => {
                        stdout.print("{s}:{}: error: missing operand\n", .{
                            jix.error_context.missing_operand.file_path.str(),
                            jix.error_context.missing_operand.line_number,
                        }) catch unreachable;
                        std.process.exit(1);
                    },
                    JixError.UndefinedLabel => {
                        stderr.print("{s}:{}: error: undefined label `{s}`\n", .{
                            jix.error_context.undefined_label.file_path.str(),
                            jix.error_context.undefined_label.line_number,
                            jix.error_context.undefined_label.label.str(),
                        }) catch unreachable;
                        std.process.exit(1);
                    },
                    JixError.UnknownDirective => {
                        stderr.print("{s}:{}: error: unknown pre-processor directive `{s}`\n", .{
                            jix.error_context.unknown_directive.file_path.str(),
                            jix.error_context.unknown_directive.line_number,
                            jix.error_context.unknown_directive.directive.str(),
                        }) catch unreachable;
                        std.process.exit(1);
                    },
                    JixError.RedefinedLabel => {
                        stderr.print("{s}:{}: error: label `{s}` is already defined\n", .{
                            jix.error_context.redefined_label.file_path.str(),
                            jix.error_context.redefined_label.line_number,
                            jix.error_context.redefined_label.label.str(),
                        }) catch unreachable;
                        std.process.exit(1);
                    },
                    JixError.ExceededMaxIncludeLevel => {
                        stderr.print("{s}:{}: error: exceeded maximum include level\n", .{
                            jix.error_context.exceeded_max_include_level.file_path.str(),
                            jix.error_context.exceeded_max_include_level.line_number,
                        }) catch unreachable;
                        std.process.exit(1);
                    },
                    JixError.IntegerOverflow => {
                        stderr.print("{s}:{}: error: integer overflow\n", .{
                            jix.error_context.integer_overflow.file_path.str(),
                            jix.error_context.integer_overflow.line_number,
                        }) catch unreachable;
                        std.process.exit(1);
                    },
                    JixError.UnknownNative => {
                        stderr.print("{s}:{}: error: unknown native `{}`\n", .{
                            jix.error_context.unknown_native.file_path.str(),
                            jix.error_context.unknown_native.line_number,
                            jix.error_context.unknown_native.native,
                        }) catch unreachable;
                        std.process.exit(1);
                    },
                    else => return e,
                }
            };

            if (output_file.len() < 1) {
                try output_file.concat(input_file.str()[0 .. input_file.len() - 4]);
                try output_file.concat(".jout");

                try jix.saveProgramToFile(output_file);
            } else {
                try jix.saveProgramToFile(output_file);
            }

            if (run) {
                try loadNatives(&jix);
                if (step)
                    try stepDebug(&jix, limit)
                else
                    try executeProgram(&jix, limit);
            }
        } else if (std.mem.eql(u8, subcommand, "run")) {
            var input_file = String.init(allocator);
            var limit: isize = -1;
            var step = false;

            while (args.next()) |flag| {
                if (std.mem.eql(u8, flag, "-l")) {
                    if (args.next()) |limit_str| {
                        limit = std.fmt.parseInt(isize, limit_str, 10) catch {
                            usage(stderr, program);
                            stderr.print("error: the limit should be a number\n", .{}) catch unreachable;
                            std.process.exit(1);
                        };
                    } else {
                        usage(stderr, program);
                        stderr.print("error: limit is not provided\n", .{}) catch unreachable;
                        std.process.exit(1);
                    }
                } else if (std.mem.eql(u8, flag, "-s")) {
                    step = true;
                } else {
                    if (flag[0] == '-') {
                        usage(stderr, program);
                        stderr.print("error: unknown flag `{s}`\n", .{flag}) catch unreachable;
                        std.process.exit(1);
                    }

                    input_file.clear();
                    try input_file.concat(flag);
                }
            }

            if (input_file.len() < 1) {
                usage(stderr, program);
                stderr.print("error: input file is not provided\n", .{}) catch unreachable;
                std.process.exit(1);
            }

            var jix = Jix.init(allocator);
            defer jix.deinit();

            try jix.loadProgramFromFile(input_file);

            try loadNatives(&jix);
            if (step)
                try stepDebug(&jix, limit)
            else
                try executeProgram(&jix, limit);
        } else if (std.mem.eql(u8, subcommand, "disasm")) {
            var input_file = String.init(allocator);

            while (args.next()) |flag| {
                input_file.clear();
                try input_file.concat(flag);
            }

            if (input_file.len() < 1) {
                usage(stderr, program);
                stderr.print("error: input file is not provided\n", .{}) catch unreachable;
                std.process.exit(1);
            }

            var jix = Jix.init(allocator);
            defer jix.deinit();

            try jix.loadProgramFromFile(input_file);

            for (jix.program.items()) |inst| {
                var inst_str = try inst.toString(allocator);
                stdout.print("{s}\n", .{inst_str.str()}) catch unreachable;
            }
        } else if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
            usage(stdout, program);
        } else {
            usage(stderr, program);
            stderr.print("error: unknown subcommand `{s}`\n", .{subcommand}) catch unreachable;
            std.process.exit(1);
        }
    } else {
        usage(stderr, program);
        stderr.print("error: no subcommand provided\n", .{}) catch unreachable;
        std.process.exit(1);
    }
}

fn loadNatives(jix: *Jix) !void {
    for (&natives) |native, i| {
        try jix.natives.put(i, native);
    }
}

fn stepDebug(jix: *Jix, limit: isize) !void {
    var m_limit = limit;
    while (m_limit != 0 and !jix.halt) {
        jix.dumpStack(stdout);

        var inst = try jix.program.get(jix.ip).toString(jix.aa.allocator());
        stdout.print("Instruction: {s}\n", .{inst.str()}) catch unreachable;

        _ = try stdin.readByte();

        try jix.executeInst();

        if (m_limit > 0)
            m_limit -= 1;
    }
}

fn executeProgram(jix: *Jix, limit: isize) !void {
    jix.executeProgram(limit) catch |e| {
        switch (e) {
            JixError.StackUnderflow => {
                stderr.print("{s}:{}: error: stack underflow\n", .{
                    jix.error_context.stack_underflow.file_path.str(),
                    jix.error_context.stack_underflow.line_number,
                }) catch unreachable;
            },
            JixError.StackOverflow => {
                stderr.print("{s}:{}: error: stack overflow\n", .{
                    jix.error_context.stack_overflow.file_path.str(),
                    jix.error_context.stack_overflow.line_number,
                }) catch unreachable;
            },
            JixError.IllegalOperand => {
                switch (jix.error_context.illegal_operand.operand.word) {
                    .as_i64 => |operand| {
                        stderr.print("{s}:{}: error: illegal operand `{}` (i64)\n", .{
                            jix.error_context.illegal_operand.file_path.str(),
                            jix.error_context.illegal_operand.line_number,
                            operand,
                        }) catch unreachable;
                    },
                    .as_u64 => |operand| {
                        stderr.print("{s}:{}: error: illegal operand `{}` (u64)\n", .{
                            jix.error_context.illegal_operand.file_path.str(),
                            jix.error_context.illegal_operand.line_number,
                            operand,
                        }) catch unreachable;
                    },
                    .as_f64 => |operand| {
                        stderr.print("{s}:{}: error: illegal operand `{d}` (f64)\n", .{
                            jix.error_context.illegal_operand.file_path.str(),
                            jix.error_context.illegal_operand.line_number,
                            operand,
                        }) catch unreachable;
                    },
                    .as_ptr => |operand| {
                        stderr.print("{s}:{}: error: illegal operand `{*}` (ptr)\n", .{
                            jix.error_context.illegal_operand.file_path.str(),
                            jix.error_context.illegal_operand.line_number,
                            operand,
                        }) catch unreachable;
                    },
                }
                std.process.exit(1);
            },
            else => return e,
        }
    };
}
