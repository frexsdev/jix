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

pub const InstAddr = usize;

pub const Word = union(enum) {
    as_u64: u64,
    as_i64: i64,
    as_f64: f64,
    as_ptr: *anyopaque,
};

pub const Jix = struct {
    allocator: Allocator,

    stack: Array(Word),

    program: Array(Inst),
    ip: InstAddr = 0,
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
            var inst_name = mem.trim(u8, parts.next().?, &ascii.spaces);

            if (inst_name[inst_name.len - 1] == ':') {
                try self.context.labels.push(.{
                    .name = mem.trim(u8, inst_name[0 .. inst_name.len - 1], &ascii.spaces),
                    .addr = self.program.size(),
                });

                if (parts.next()) |after_label|
                    inst_name = mem.trim(u8, after_label, &ascii.spaces)
                else
                    continue;
            }

            if (InstFromString.get(inst_name)) |inst_type| {
                if (inst_type == .jmp or inst_type == .jmp_if) {
                    if (parts.next()) |operand| {
                        const t_operand = mem.trim(u8, operand, &ascii.spaces);

                        if (ascii.isDigit(t_operand[0])) {
                            const n_operand = fmt.parseInt(u64, t_operand, 10) catch return JixError.IllegalOperand;
                            try self.program.push(.{ .@"type" = inst_type, .operand = .{ .as_u64 = n_operand } });
                        } else {
                            try self.context.deferred_operands.push(.{
                                .addr = self.program.size(),
                                .label = t_operand,
                            });

                            try self.program.push(.{ .@"type" = inst_type });
                        }
                    } else return JixError.MissingOperand;
                } else if (inst_type == .push) {
                    if (parts.next()) |operand| {
                        const t_operand = mem.trim(u8, operand, &ascii.spaces);
                        if (fmt.parseInt(u64, t_operand, 10)) |i_operand| {
                            try self.program.push(.{ .@"type" = inst_type, .operand = .{ .as_u64 = i_operand } });
                        } else |_| {
                            if (fmt.parseFloat(f64, t_operand)) |f_operand| {
                                try self.program.push(.{ .@"type" = inst_type, .operand = .{ .as_f64 = f_operand } });
                            } else |_| {
                                return JixError.IllegalOperand;
                            }
                        }
                    } else return JixError.MissingOperand;
                } else {
                    if (InstHasOperand.get(inst_name).?) {
                        if (parts.next()) |operand| {
                            const t_operand = mem.trim(u8, operand, &ascii.spaces);
                            const n_operand = fmt.parseInt(u64, t_operand, 10) catch return JixError.IllegalOperand;
                            try self.program.push(.{ .@"type" = inst_type, .operand = .{ .as_u64 = n_operand } });
                        } else return JixError.MissingOperand;
                    } else {
                        try self.program.push(.{ .@"type" = inst_type });
                    }
                }
            } else return JixError.IllegalInst;
        }

        for (self.context.deferred_operands.items()) |deferred_operand| {
            if (self.context.find(deferred_operand.label)) |addr|
                self.program.items()[deferred_operand.addr].operand = .{ .as_u64 = addr }
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

        self.dumpStack(stdout);
    }

    pub fn executeInst(self: *Self) JixError!void {
        if (self.ip >= self.program.size())
            return JixError.IllegalInstAccess;

        const inst = self.program.get(self.ip);

        switch (inst.@"type") {
            // stack
            .push => {
                try self.stack.push(inst.operand);

                self.ip += 1;
            },
            .dup => {
                if (self.stack.size() - @intCast(InstAddr, inst.operand.as_u64) <= 0)
                    return JixError.StackUnderflow;

                try self.stack.push(self.stack.get(self.stack.size() - 1 - @intCast(InstAddr, inst.operand.as_u64)));

                self.ip += 1;
            },
            .swap => {
                const a = self.stack.size() - 1;
                const b = self.stack.size() - 1 - @intCast(usize, inst.operand.as_u64);

                const t = self.stack.get(a);
                self.stack.items()[a] = self.stack.get(b);
                self.stack.items()[b] = t;

                self.ip += 1;
            },
            .drop => {
                _ = try self.stack.pop();

                self.ip += 1;
            },

            // arithmetics
            .plusi => {
                const a = (try self.stack.pop()).as_u64;
                const b = (try self.stack.pop()).as_u64;

                var result: u64 = undefined;
                if (@addWithOverflow(u64, b, a, &result))
                    return JixError.IntegerOverflow
                else
                    try self.stack.push(.{ .as_u64 = result });

                self.ip += 1;
            },
            .plusf => {
                const a = (try self.stack.pop()).as_f64;
                const b = (try self.stack.pop()).as_f64;
                try self.stack.push(.{ .as_f64 = b + a });

                self.ip += 1;
            },

            .minusi => {
                const a = (try self.stack.pop()).as_u64;
                const b = (try self.stack.pop()).as_u64;
                var result: u64 = undefined;
                if (@subWithOverflow(u64, b, a, &result))
                    return JixError.IntegerOverflow
                else
                    try self.stack.push(.{ .as_u64 = result });

                self.ip += 1;
            },
            .minusf => {
                const a = (try self.stack.pop()).as_f64;
                const b = (try self.stack.pop()).as_f64;
                try self.stack.push(.{ .as_f64 = b - a });

                self.ip += 1;
            },

            .multi => {
                const a = (try self.stack.pop()).as_u64;
                const b = (try self.stack.pop()).as_u64;
                var result: u64 = undefined;
                if (@mulWithOverflow(u64, b, a, &result))
                    return JixError.IntegerOverflow
                else
                    try self.stack.push(.{ .as_u64 = result });

                self.ip += 1;
            },
            .multf => {
                const a = (try self.stack.pop()).as_f64;
                const b = (try self.stack.pop()).as_f64;
                try self.stack.push(.{ .as_f64 = b * a });

                self.ip += 1;
            },

            .divi => {
                const a = (try self.stack.pop()).as_u64;
                const b = (try self.stack.pop()).as_u64;

                if (a == 0 or b == 0)
                    return JixError.DivByZero;

                try self.stack.push(.{ .as_u64 = b / a });

                self.ip += 1;
            },
            .divf => {
                const a = (try self.stack.pop()).as_f64;
                const b = (try self.stack.pop()).as_f64;

                if (a == 0 or b == 0)
                    return JixError.DivByZero;

                try self.stack.push(.{ .as_f64 = b / a });

                self.ip += 1;
            },

            .eqi => {
                const a = (try self.stack.pop()).as_u64;
                const b = (try self.stack.pop()).as_u64;
                try self.stack.push(.{ .as_u64 = @boolToInt(a == b) });

                self.ip += 1;
            },
            .eqf => {
                const a = (try self.stack.pop()).as_f64;
                const b = (try self.stack.pop()).as_f64;
                try self.stack.push(.{ .as_u64 = @boolToInt(a == b) });

                self.ip += 1;
            },

            .gei => {
                const a = (try self.stack.pop()).as_u64;
                const b = (try self.stack.pop()).as_u64;
                try self.stack.push(.{ .as_u64 = @boolToInt(a >= b) });

                self.ip += 1;
            },
            .gef => {
                const a = (try self.stack.pop()).as_f64;
                const b = (try self.stack.pop()).as_f64;
                try self.stack.push(.{ .as_u64 = @boolToInt(a >= b) });

                self.ip += 1;
            },

            // misc
            .jmp => self.ip = inst.operand.as_u64,
            .jmp_if => {
                const a = (try self.stack.pop()).as_u64;
                if (a != 0)
                    self.ip = inst.operand.as_u64
                else
                    self.ip += 1;
            },
            .halt => self.halt = true,
        }
    }

    pub fn dumpStack(self: *const Self, writer: Writer) void {
        writer.print("Stack:\n", .{}) catch unreachable;

        if (self.stack.size() > 0) {
            var i: InstAddr = 0;
            while (i < self.stack.size()) : (i += 1) {
                switch (self.stack.get(i)) {
                    .as_u64 => |w| writer.print("  {}\n", .{w}) catch unreachable,
                    .as_i64 => |w| writer.print("  {}\n", .{w}) catch unreachable,
                    .as_f64 => |w| writer.print("  {}\n", .{w}) catch unreachable,
                    .as_ptr => |w| writer.print("  {}\n", .{w}) catch unreachable,
                }
            }
        } else writer.print("  [empty]\n", .{}) catch unreachable;
    }

    pub fn loadProgramFromMemory(self: *Self, program_slice: []const Inst) !void {
        for (program_slice) |inst|
            try self.program.push(inst);
    }

    pub fn loadProgramFromFile(self: *Self, file_path: []const u8) !void {
        var absolute_path = try fs.realpathAlloc(self.allocator, file_path);
        defer self.allocator.free(absolute_path);

        const f = try fs.openFileAbsolute(absolute_path, .{ .mode = .read_only });
        defer f.close();

        var bytes = try f.readToEndAlloc(self.allocator, math.maxInt(usize));
        defer self.allocator.free(bytes);

        const program = mem.bytesAsSlice(Inst, bytes);
        for (program) |inst|
            try self.program.push(inst);
    }

    pub fn saveProgramToFile(self: *const Self, file_path: []const u8) !void {
        const cwd = fs.cwd();

        const f = try cwd.createFile(file_path, .{});
        defer f.close();

        try f.writeAll(mem.sliceAsBytes(self.program.items()));
    }
};
