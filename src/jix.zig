const std = @import("std");
const Writer = std.fs.File.Writer;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const Array = @import("array.zig").Array;
const String = @import("string.zig").String;
const JixError = @import("error.zig").JixError;
const JixNative = @import("natives.zig").JixNative;
const AsmContext = @import("context.zig").AsmContext;

usingnamespace @import("inst.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const Global = @This();

const JIX_MAX_INCLUDE_LEVEL = 69;

pub const InstAddr = usize;

pub const Word = union(enum) {
    as_u64: u64,
    as_i64: i64,
    as_f64: f64,
    as_ptr: ?*anyopaque,
};

pub const Jix = struct {
    allocator: Allocator,

    stack: Array(Word),

    program: Array(Global.Inst),
    ip: InstAddr = 0,
    context: AsmContext,

    halt: bool = false,

    natives: AutoHashMap(usize, JixNative),

    error_context: union {
        // zig fmt: off
        illegal_inst: struct {
            file_path: String,
            line_number: usize,
            inst: String,
        },
        illegal_operand: struct {
            file_path: String,
            line_number: usize,
            operand: String,
        },
        missing_operand: struct {
            file_path: String,
            line_number: usize,
        },
        undefined_label: struct {
            file_path: String,
            line_number: usize,
            label: String,
        },
        unknown_directive: struct {
            file_path: String,
            line_number: usize,
            directive: String,
        },
        redefined_label: struct {
            file_path: String,
            line_number: usize,
            label: String,
        }, 
        exceeded_max_include_level: struct {
            file_path: String,
            line_number: usize,
        },
        // zig fmt: on
    } = undefined,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .stack = Array(Word).init(allocator),
            .program = Array(Global.Inst).init(allocator),
            .context = AsmContext.init(allocator),
            .natives = AutoHashMap(usize, JixNative).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
        self.program.deinit();
        self.context.deinit();
        self.natives.deinit();
        self.* = undefined;
    }

    pub fn translateSource(self: *Self, file_path: String, level: usize) !void {
        var absolute_path = try std.fs.realpathAlloc(self.allocator, file_path.str());
        const f = try std.fs.openFileAbsolute(absolute_path, .{ .mode = .read_only });

        var source_str = try f.readToEndAlloc(self.allocator, std.math.maxInt(usize));

        var source = String.init(self.allocator);
        try source.concat(source_str);

        self.program.reset();

        var line_number: usize = 0;
        while (try source.splitToString("\n", line_number)) |c_line| {
            line_number += 1;

            var line = try c_line.clone();
            line.trim(&std.ascii.spaces);

            if (line.isEmpty()) continue;

            var comment = try line.splitToString(";", 0);
            if (comment) |n_line| {
                line = n_line;
                line.trim(&std.ascii.spaces);
            } else continue;

            var inst_name = (try line.splitToString(" ", 0)).?;
            inst_name.trim(&std.ascii.spaces);

            if (std.mem.eql(u8, inst_name.charAt(0).?, "%")) {
                var directive = try inst_name.substr(1, inst_name.len());
                directive.trim(&std.ascii.spaces);

                if (directive.cmp("label")) {
                    if (try line.splitToString(" ", 1)) |c_label| {
                        var label = try c_label.clone();
                        label.trim(&std.ascii.spaces);

                        if (try line.splitToString(" ", 2)) |c_value| {
                            var value = try c_value.clone();
                            value.trim(&std.ascii.spaces);

                            if (self.context.resolve(label)) |_| {
                                self.error_context = .{ .redefined_label = .{
                                    .file_path = file_path,
                                    .line_number = line_number,
                                    .label = label,
                                } };
                                return JixError.RedefinedLabel;
                            }

                            if (std.fmt.parseInt(u64, value.str(), 10)) |i_value| {
                                try self.context.bindLabel(label, .{ .as_u64 = i_value });
                            } else |_| {
                                if (std.fmt.parseFloat(f64, value.str())) |f_value| {
                                    try self.context.bindLabel(label, .{ .as_f64 = f_value });
                                } else |_| {
                                    self.error_context = .{ .illegal_operand = .{
                                        .file_path = file_path,
                                        .line_number = line_number,
                                        .operand = value,
                                    } };
                                    return JixError.IllegalOperand;
                                }
                            }
                        } else {
                            self.error_context = .{ .missing_operand = .{
                                .file_path = file_path,
                                .line_number = line_number,
                            } };
                            return JixError.MissingOperand;
                        }
                    } else {
                        self.error_context = .{ .missing_operand = .{
                            .file_path = file_path,
                            .line_number = line_number,
                        } };
                        return JixError.MissingOperand;
                    }
                } else if (directive.cmp("include")) {
                    if (try line.splitToString(" ", 1)) |c_path| {
                        var path = try c_path.clone();
                        path.trim(&std.ascii.spaces);

                        if (std.mem.eql(u8, path.charAt(0).?, "\"") and std.mem.eql(u8, path.charAt(path.len() - 1).?, "\"")) {
                            var n_path = try path.substr(1, path.len() - 1);

                            if (level + 1 >= JIX_MAX_INCLUDE_LEVEL) {
                                self.error_context = .{ .exceeded_max_include_level = .{
                                    .file_path = file_path,
                                    .line_number = line_number,
                                } };
                                return JixError.ExceededMaxIncludeLevel;
                            }

                            try self.translateSource(n_path, level + 1);
                        } else {
                            self.error_context = .{ .illegal_operand = .{
                                .file_path = file_path,
                                .line_number = line_number,
                                .operand = path,
                            } };
                            return JixError.IllegalOperand;
                        }
                    } else {
                        self.error_context = .{ .missing_operand = .{
                            .file_path = file_path,
                            .line_number = line_number,
                        } };
                        return JixError.MissingOperand;
                    }
                } else {
                    self.error_context = .{ .unknown_directive = .{
                        .file_path = file_path,
                        .line_number = line_number,
                        .directive = directive,
                    } };
                    return JixError.UnknownDirective;
                }

                continue;
            }

            if (std.mem.eql(u8, inst_name.charAt(inst_name.len() - 1).?, ":")) {
                var label = try inst_name.substr(0, inst_name.len() - 1);
                label.trim(&std.ascii.spaces);

                if (self.context.resolve(label)) |_| {
                    self.error_context = .{ .redefined_label = .{
                        .file_path = file_path,
                        .line_number = line_number,
                        .label = label,
                    } };
                    return JixError.RedefinedLabel;
                }

                try self.context.bindLabel(label, .{ .as_u64 = self.program.size() });

                if (try line.splitToString(" ", 1)) |c_after_label| {
                    var after_label = try c_after_label.clone();
                    after_label.trim(&std.ascii.spaces);
                    inst_name = after_label;
                } else continue;
            }

            if (Global.InstType.fromString(inst_name)) |inst_type| {
                if (inst_type.hasOperand()) {
                    if (try line.splitToString(" ", 1)) |c_operand| {
                        var operand = try c_operand.clone();
                        operand.trim(&std.ascii.spaces);

                        if (std.ascii.isDigit(operand.charAt(0).?[0])) {
                            if (std.fmt.parseInt(u64, operand.str(), 10)) |i_operand| {
                                try self.program.push(.{ .@"type" = inst_type, .operand = .{ .as_u64 = i_operand } });
                            } else |_| {
                                if (std.fmt.parseFloat(f64, operand.str())) |f_operand| {
                                    try self.program.push(.{ .@"type" = inst_type, .operand = .{ .as_f64 = f_operand } });
                                } else |_| {
                                    self.error_context = .{ .illegal_operand = .{
                                        .file_path = file_path,
                                        .line_number = line_number,
                                        .operand = operand,
                                    } };
                                    return JixError.IllegalOperand;
                                }
                            }
                        } else {
                            try self.context.deferred_operands.push(.{
                                .addr = self.program.size(),
                                .label = operand,
                                .line_number = line_number,
                            });

                            try self.program.push(.{ .@"type" = inst_type });
                        }
                    } else {
                        self.error_context = .{ .missing_operand = .{
                            .file_path = file_path,
                            .line_number = line_number,
                        } };
                        return JixError.MissingOperand;
                    }
                } else {
                    try self.program.push(.{ .@"type" = inst_type });
                }
            } else {
                self.error_context = .{ .illegal_inst = .{
                    .file_path = file_path,
                    .line_number = line_number,
                    .inst = inst_name,
                } };
                return JixError.IllegalInst;
            }
        }

        for (self.context.deferred_operands.items()) |deferred_operand| {
            if (self.context.resolve(deferred_operand.label)) |word|
                self.program.items()[deferred_operand.addr].operand = word
            else {
                self.error_context = .{ .undefined_label = .{
                    .file_path = file_path,
                    .line_number = deferred_operand.line_number,
                    .label = deferred_operand.label,
                } };
                return JixError.UndefinedLabel;
            }
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
                switch (inst.operand) {
                    .as_u64 => |operand| {
                        if (self.stack.size() - @intCast(InstAddr, operand) <= 0)
                            return JixError.StackUnderflow;

                        try self.stack.push(self.stack.get(self.stack.size() - 1 - @intCast(InstAddr, operand)));

                        self.ip += 1;
                    },
                    else => return JixError.IllegalOperand,
                }
            },
            .swap => {
                switch (inst.operand) {
                    .as_u64 => |operand| {
                        const a = self.stack.size() - 1;
                        const b = self.stack.size() - 1 - @intCast(usize, operand);

                        const t = self.stack.get(a);
                        self.stack.items()[a] = self.stack.get(b);
                        self.stack.items()[b] = t;

                        self.ip += 1;
                    },
                    else => return JixError.IllegalOperand,
                }
            },
            .drop => {
                _ = try self.stack.pop();

                self.ip += 1;
            },

            // arithmetics
            .add => {
                const a_w = try self.stack.pop();
                const b_w = try self.stack.pop();

                switch (a_w) {
                    .as_i64 => |a| {
                        switch (b_w) {
                            .as_i64 => |b| {
                                var result: i64 = undefined;
                                if (@addWithOverflow(i64, b, a, &result))
                                    return JixError.IntegerOverflow
                                else
                                    try self.stack.push(.{ .as_i64 = result });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_u64 => |a| {
                        switch (b_w) {
                            .as_u64 => |b| {
                                var result: u64 = undefined;
                                if (@addWithOverflow(u64, b, a, &result))
                                    return JixError.IntegerOverflow
                                else
                                    try self.stack.push(.{ .as_u64 = result });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_f64 => |a| {
                        switch (b_w) {
                            .as_f64 => |b| {
                                try self.stack.push(.{ .as_f64 = b + a });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    else => return JixError.IllegalOperand,
                }

                self.ip += 1;
            },
            .sub => {
                const a_w = try self.stack.pop();
                const b_w = try self.stack.pop();

                switch (a_w) {
                    .as_i64 => |a| {
                        switch (b_w) {
                            .as_i64 => |b| {
                                var result: i64 = undefined;
                                if (@subWithOverflow(i64, b, a, &result))
                                    return JixError.IntegerOverflow
                                else
                                    try self.stack.push(.{ .as_i64 = result });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_u64 => |a| {
                        switch (b_w) {
                            .as_u64 => |b| {
                                var result: u64 = undefined;
                                if (@subWithOverflow(u64, b, a, &result))
                                    return JixError.IntegerOverflow
                                else
                                    try self.stack.push(.{ .as_u64 = result });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_f64 => |a| {
                        switch (b_w) {
                            .as_f64 => |b| {
                                try self.stack.push(.{ .as_f64 = b - a });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    else => return JixError.IllegalOperand,
                }

                self.ip += 1;
            },
            .mult => {
                const a_w = try self.stack.pop();
                const b_w = try self.stack.pop();

                switch (a_w) {
                    .as_i64 => |a| {
                        switch (b_w) {
                            .as_i64 => |b| {
                                var result: i64 = undefined;
                                if (@mulWithOverflow(i64, b, a, &result))
                                    return JixError.IntegerOverflow
                                else
                                    try self.stack.push(.{ .as_i64 = result });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_u64 => |a| {
                        switch (b_w) {
                            .as_u64 => |b| {
                                var result: u64 = undefined;
                                if (@mulWithOverflow(u64, b, a, &result))
                                    return JixError.IntegerOverflow
                                else
                                    try self.stack.push(.{ .as_u64 = result });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_f64 => |a| {
                        switch (b_w) {
                            .as_f64 => |b| {
                                try self.stack.push(.{ .as_f64 = b * a });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    else => return JixError.IllegalOperand,
                }

                self.ip += 1;
            },
            .div => {
                const a_w = try self.stack.pop();
                const b_w = try self.stack.pop();

                switch (a_w) {
                    .as_i64 => |a| {
                        switch (b_w) {
                            .as_i64 => |b| {
                                try self.stack.push(.{ .as_i64 = @divExact(b, a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_u64 => |a| {
                        switch (b_w) {
                            .as_u64 => |b| {
                                try self.stack.push(.{ .as_u64 = @divExact(b, a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_f64 => |a| {
                        switch (b_w) {
                            .as_f64 => |b| {
                                try self.stack.push(.{ .as_f64 = b / a });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    else => return JixError.IllegalOperand,
                }

                self.ip += 1;
            },
            .not => {
                const a_w = try self.stack.pop();
                switch (a_w) {
                    .as_i64 => |a| {
                        try self.stack.push(.{ .as_u64 = @boolToInt(!(a != 0)) });
                    },
                    .as_u64 => |a| {
                        try self.stack.push(.{ .as_u64 = @boolToInt(!(a != 0)) });
                    },
                    .as_f64 => |a| {
                        try self.stack.push(.{ .as_u64 = @boolToInt(!(a != 0)) });
                    },
                    else => return JixError.IllegalOperand,
                }

                self.ip += 1;
            },

            // comparison
            .eq => {
                const a = try self.stack.pop();
                const b = try self.stack.pop();
                try self.stack.push(.{ .as_u64 = @boolToInt(std.meta.eql(a, b)) });

                self.ip += 1;
            },
            .gt => {
                const a_w = try self.stack.pop();
                const b_w = try self.stack.pop();
                switch (a_w) {
                    .as_i64 => |a| {
                        switch (b_w) {
                            .as_i64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b > a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_u64 => |a| {
                        switch (b_w) {
                            .as_u64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b > a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_f64 => |a| {
                        switch (b_w) {
                            .as_f64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b > a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    else => return JixError.IllegalOperand,
                }

                self.ip += 1;
            },
            .get => {
                const a_w = try self.stack.pop();
                const b_w = try self.stack.pop();
                switch (a_w) {
                    .as_i64 => |a| {
                        switch (b_w) {
                            .as_i64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b >= a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_u64 => |a| {
                        switch (b_w) {
                            .as_u64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b >= a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_f64 => |a| {
                        switch (b_w) {
                            .as_f64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b >= a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    else => return JixError.IllegalOperand,
                }

                self.ip += 1;
            },
            .lt => {
                const a_w = try self.stack.pop();
                const b_w = try self.stack.pop();
                switch (a_w) {
                    .as_i64 => |a| {
                        switch (b_w) {
                            .as_i64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b < a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_u64 => |a| {
                        switch (b_w) {
                            .as_u64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b < a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_f64 => |a| {
                        switch (b_w) {
                            .as_f64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b < a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    else => return JixError.IllegalOperand,
                }

                self.ip += 1;
            },
            .let => {
                const a_w = try self.stack.pop();
                const b_w = try self.stack.pop();
                switch (a_w) {
                    .as_i64 => |a| {
                        switch (b_w) {
                            .as_i64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b <= a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_u64 => |a| {
                        switch (b_w) {
                            .as_u64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b <= a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    .as_f64 => |a| {
                        switch (b_w) {
                            .as_f64 => |b| {
                                try self.stack.push(.{ .as_u64 = @boolToInt(b <= a) });
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    else => return JixError.IllegalOperand,
                }

                self.ip += 1;
            },

            // misc
            .jmp => {
                switch (inst.operand) {
                    .as_u64 => |operand| {
                        self.ip = operand;
                    },
                    else => return JixError.IllegalOperand,
                }
            },
            .jmp_if => {
                const a_w = try self.stack.pop();
                switch (a_w) {
                    .as_u64 => |a| {
                        switch (inst.operand) {
                            .as_u64 => |operand| {
                                if (a != 0)
                                    self.ip = operand
                                else
                                    self.ip += 1;
                            },
                            else => return JixError.IllegalOperand,
                        }
                    },
                    else => return JixError.IllegalOperand,
                }
            },
            .call => {
                switch (inst.operand) {
                    .as_u64 => |operand| {
                        try self.stack.push(.{ .as_u64 = self.ip + 1 });
                        self.ip = operand;
                    },
                    else => return JixError.IllegalOperand,
                }
            },
            .ret => {
                const a_w = try self.stack.pop();
                switch (a_w) {
                    .as_u64 => |a| {
                        self.ip = a;
                    },
                    else => return JixError.IllegalOperand,
                }
            },
            .native => {
                switch (inst.operand) {
                    .as_u64 => |operand| {
                        if (self.natives.get(operand)) |native|
                            try native(self)
                        else
                            return JixError.UnknownNative;

                        self.ip += 1;
                    },
                    else => return JixError.IllegalOperand,
                }
            },
            .halt => self.halt = true,
        }
    }

    pub fn dumpStack(self: Self, writer: Writer) void {
        writer.print("Stack:\n", .{}) catch unreachable;

        if (self.stack.size() > 0) {
            var i: InstAddr = 0;
            while (i < self.stack.size()) : (i += 1) {
                switch (self.stack.get(i)) {
                    .as_u64 => |w| writer.print("  {}\n", .{w}) catch unreachable,
                    .as_i64 => |w| writer.print("  {}\n", .{w}) catch unreachable,
                    .as_f64 => |w| writer.print("  {d}\n", .{w}) catch unreachable,
                    .as_ptr => |w| writer.print("  {*}\n", .{w}) catch unreachable,
                }
            }
        } else writer.print("  [empty]\n", .{}) catch unreachable;
    }

    pub fn loadProgramFromMemory(self: *Self, program_slice: []const Global.Inst) !void {
        for (program_slice) |inst|
            try self.program.push(inst);
    }

    pub fn loadProgramFromFile(self: *Self, file_path: String) !void {
        var absolute_path = try std.fs.realpathAlloc(self.allocator, file_path.str());
        const f = try std.fs.openFileAbsolute(absolute_path, .{ .mode = .read_only });

        var bytes = try f.readToEndAlloc(self.allocator, std.math.maxInt(usize));

        const program = std.mem.bytesAsSlice(Global.Inst, bytes);
        for (program) |inst|
            try self.program.push(inst);
    }

    pub fn saveProgramToFile(self: Self, file_path: String) !void {
        const cwd = std.fs.cwd();
        const f = try cwd.createFile(file_path.str(), .{});

        try f.writeAll(std.mem.sliceAsBytes(self.program.items()));
    }
};
