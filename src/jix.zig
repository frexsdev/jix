const std = @import("std");
const io = std.io;
const fs = std.fs;
const fmt = std.fmt;
const mem = std.mem;
const log = std.log;
const math = std.math;
const ascii = std.ascii;
const Writer = std.fs.File.Writer;
const Allocator = std.mem.Allocator;
const Inst = @import("inst.zig").Inst;
const Array = @import("array.zig").Array;
const InstType = @import("inst.zig").InstType;
const JixError = @import("error.zig").JixError;
const AsmContext = @import("context.zig").AsmContext;
const InstFromString = @import("inst.zig").InstFromString;
const InstHasOperand = @import("inst.zig").InstHasOperand;

const stdout = io.getStdOut().writer();
const stderr = io.getStdErr().writer();

pub const Word = i64;

pub const Jix = struct {
    allocator: Allocator,

    stack: Array(Word),

    program: Array(Inst),
    ip: Word = 0,
    context: AsmContext,

    halt: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .stack = Array(Word).init(allocator),
            .program = Array(Inst).init(allocator),
            .context = AsmContext.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
        self.program.deinit();
        self.context.deinit();
        self.* = undefined;
    }

    pub fn translateAsm(self: *Self, file_path: []const u8) !void {
        self.program.reset();

        var absolute_path = try fs.realpathAlloc(self.allocator, file_path);
        defer self.allocator.free(absolute_path);

        const f = try fs.openFileAbsolute(absolute_path, .{ .mode = .read_only });
        defer f.close();

        var source = try f.readToEndAlloc(self.allocator, math.maxInt(usize));
        defer self.allocator.free(source);

        var lines = mem.split(u8, source, "\n");
        while (lines.next()) |o_line| {
            if (o_line.len < 1) continue;

            var line_c = mem.split(u8, mem.trim(u8, o_line, &ascii.spaces), ";");
            const line = line_c.next().?;

            if (line.len < 1) continue;

            var parts = mem.split(u8, line, " ");
            const inst_name = mem.trim(u8, parts.next().?, &ascii.spaces);

            if (inst_name[inst_name.len - 1] == ':') {
                try self.context.labels.push(.{
                    .name = mem.trim(u8, inst_name[0 .. inst_name.len - 1], &ascii.spaces),
                    .addr = self.program.size(),
                });
            } else {
                if (InstFromString.get(inst_name)) |inst_type| {
                    if (inst_type == .jmp or inst_type == .jmp_if) {
                        if (parts.next()) |operand| {
                            const t_operand = mem.trim(u8, operand, &ascii.spaces);

                            if (ascii.isDigit(t_operand[0])) {
                                const n_operand = fmt.parseInt(Word, t_operand, 10) catch return JixError.IllegalOperand;
                                try self.program.push(.{ .@"type" = inst_type, .operand = n_operand });
                            } else {
                                try self.context.deferred_operands.push(.{
                                    .addr = self.program.size(),
                                    .label = t_operand,
                                });

                                try self.program.push(.{ .@"type" = inst_type });
                            }
                        } else return JixError.MissingOperand;
                    } else {
                        if (InstHasOperand.get(inst_name).?) {
                            if (parts.next()) |operand| {
                                const t_operand = mem.trim(u8, operand, &ascii.spaces);
                                const n_operand = fmt.parseInt(Word, t_operand, 10) catch return JixError.IllegalOperand;
                                try self.program.push(.{ .@"type" = inst_type, .operand = n_operand });
                            } else return JixError.MissingOperand;
                        } else {
                            try self.program.push(.{ .@"type" = inst_type });
                        }
                    }
                } else return JixError.IllegalInst;
            }
        }

        for (self.context.deferred_operands.items()) |deferred_operand| {
            if (self.context.find(deferred_operand.label)) |addr|
                self.program.items()[deferred_operand.addr].operand = @intCast(Word, addr)
            else
                return JixError.UnknownLabel;
        }
    }

    pub fn executeProgram(self: *Self, limit: isize) JixError!void {
        var m_limit = limit;
        while (m_limit != 0 and !self.halt) {
            try self.executeInst();

            if (m_limit > 0) {
                m_limit -= 1;
            }
        }

        self.dump(stdout);
    }

    pub fn executeInst(self: *Self) JixError!void {
        if (self.ip < 0 or self.ip >= self.program.size())
            return JixError.IllegalInstAccess;

        const inst = self.program.get(@intCast(usize, self.ip));

        switch (inst.@"type") {
            // stack
            .push => {
                try self.stack.push(inst.operand);

                self.ip += 1;
            },
            .dup => {
                if (@intCast(i64, self.stack.size()) - inst.operand <= 0)
                    return JixError.StackUnderflow;

                if (inst.operand < 0)
                    return JixError.IllegalOperand;

                try self.stack.push(self.stack.get(self.stack.size() - 1 - @intCast(usize, inst.operand)));

                self.ip += 1;
            },

            // arithmetics
            .plus => {
                const a = try self.stack.pop();
                const b = try self.stack.pop();

                var result: Word = undefined;
                if (@addWithOverflow(Word, b, a, &result))
                    return JixError.IntegerOverflow
                else
                    try self.stack.push(result);

                self.ip += 1;
            },
            .minus => {
                const a = try self.stack.pop();
                const b = try self.stack.pop();
                var result: Word = undefined;
                if (@subWithOverflow(Word, b, a, &result))
                    return JixError.IntegerOverflow
                else
                    try self.stack.push(result);

                self.ip += 1;
            },
            .mult => {
                const a = try self.stack.pop();
                const b = try self.stack.pop();
                var result: Word = undefined;
                if (@mulWithOverflow(Word, b, a, &result))
                    return JixError.IntegerOverflow
                else
                    try self.stack.push(result);

                self.ip += 1;
            },
            .div => {
                const a = try self.stack.pop();
                const b = try self.stack.pop();
                try self.stack.push(math.divExact(Word, b, a) catch return JixError.DivByZero);

                self.ip += 1;
            },
            .eq => {
                const a = try self.stack.pop();
                const b = try self.stack.pop();
                try self.stack.push(@boolToInt(a == b));

                self.ip += 1;
            },

            // misc
            .jmp => self.ip = inst.operand,
            .jmp_if => {
                const a = try self.stack.pop();
                if (a != 0)
                    self.ip = inst.operand
                else
                    self.ip += 1;
            },
            .halt => self.halt = true,
        }
    }

    pub fn dump(self: *const Self, writer: Writer) void {
        writer.print("Stack:\n", .{}) catch unreachable;

        if (self.stack.size() > 0) {
            var i: usize = 0;
            while (i < self.stack.size()) : (i += 1) {
                writer.print("  {}\n", .{self.stack.get(i)}) catch unreachable;
            }
        } else writer.print("  [empty]\n", .{}) catch unreachable;
    }

    pub fn loadProgramFromMemory(self: *Self, program_slice: []const Inst) Allocator.Error!void {
        for (program_slice) |inst|
            try self.program.push(inst);
    }

    pub fn loadProgramFromFile(self: *Self, file_path: []const u8) !void {
        var absolute_path = try fs.realpathAlloc(self.allocator, file_path);
        defer self.allocator.free(absolute_path);

        const f = try fs.openFileAbsolute(absolute_path, .{ .mode = .read_only });
        defer f.close();

        while (true) {
            const inst = f.reader().readStruct(Inst) catch |e| {
                if (e == error.EndOfStream)
                    break
                else
                    return e;
            };

            try self.program.push(inst);
        }
    }

    pub fn saveProgramToFile(self: *const Self, file_path: []const u8) !void {
        const cwd = fs.cwd();

        const f = try cwd.createFile(file_path, .{});
        defer f.close();

        for (self.program.items()) |inst|
            try f.writer().writeStruct(inst);
    }
};
