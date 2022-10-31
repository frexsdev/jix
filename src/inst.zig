const std = @import("std");
const Word = @import("jix.zig").Word;
const ComptimeStringMap = std.ComptimeStringMap;
const AutoHashMap = std.AutoHashMap;

pub const InstType = enum {
    // stack
    push,
    dup,
    swap,
    drop,

    // arithmetics
    plusi,
    plusf,

    minusi,
    minusf,

    multi,
    multf,

    divi,
    divf,

    eqi,
    eqf,

    gei,
    gef,

    // misc
    jmp,
    jmp_if,
    call,
    ret,
    halt,
};

pub const Inst = struct {
    @"type": InstType,
    operand: Word = undefined,
};

pub const InstFromString = ComptimeStringMap(InstType, .{
    // stack
    .{ "push", .push },
    .{ "dup", .dup },
    .{ "swap", .swap },
    .{ "drop", .drop },

    // arithmetics
    .{ "plusi", .plusi },
    .{ "plusf", .plusf },

    .{ "minusi", .minusi },
    .{ "minusf", .minusf },

    .{ "multi", .multi },
    .{ "multf", .multf },

    .{ "divi", .divi },
    .{ "divf", .divf },

    .{ "eqi", .eqi },
    .{ "eqf", .eqf },

    .{ "gei", .gei },
    .{ "gef", .gef },

    // misc
    .{ "jmp", .jmp },
    .{ "jmp_if", .jmp_if },
    .{ "call", .call },
    .{ "ret", .ret },
    .{ "halt", .halt },
});

pub const InstHasOperand = ComptimeStringMap(bool, .{
    // stack
    .{ "push", true },
    .{ "dup", true },
    .{ "swap", true },
    .{ "drop", false },

    // arithmetics
    .{ "plusi", false },
    .{ "plusf", false },

    .{ "minusi", false },
    .{ "minusf", false },

    .{ "multi", false },
    .{ "multf", false },

    .{ "divi", false },
    .{ "divf", false },

    .{ "eqi", false },
    .{ "eqf", false },

    .{ "gei", false },
    .{ "gef", false },

    // misc
    .{ "jmp", true },
    .{ "jmp_if", true },
    .{ "call", true },
    .{ "ret", false },
    .{ "halt", false },
});
