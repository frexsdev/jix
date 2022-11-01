const std = @import("std");
const Jix = @import("jix.zig").Jix;
const JixError = @import("error.zig").JixError;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub const JixNative = *const fn (*Jix) JixError!void;

pub const natives = [_]JixNative{
    jixAlloc,
    jixFree,
    jixPrint,
};

fn jixAlloc(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_u64;
    try jix.stack.push(.{ .as_ptr = std.c.malloc(a) });
}

fn jixFree(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_ptr;
    std.c.free(a);
}

fn jixPrint(jix: *Jix) JixError!void {
    const a_w = try jix.stack.pop();
    switch (a_w) {
        .as_i64 => |a| stderr.print("{}\n", .{a}) catch unreachable,
        .as_u64 => |a| stderr.print("{}\n", .{a}) catch unreachable,
        .as_f64 => |a| stderr.print("{d}\n", .{a}) catch unreachable,
        .as_ptr => |a| stderr.print("{*}\n", .{a}) catch unreachable,
    }
}
