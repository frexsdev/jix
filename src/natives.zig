const std = @import("std");
const Jix = @import("jix.zig").Jix;
const JixError = @import("error.zig").JixError;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub const JixNative = *const fn (*Jix) JixError!void;

pub const natives = [_]JixNative{
    jixAlloc,
    jixFree,
    jixPrintI64,
    jixPrintU64,
    jixPrintF64,
    jixPrintPtr,
};

fn jixAlloc(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_u64;
    try jix.stack.push(.{ .as_ptr = std.c.malloc(a) });
}

fn jixFree(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_ptr;
    std.c.free(a);
}

fn jixPrintI64(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_i64;
    stderr.print("{}\n", .{a}) catch unreachable;
}

fn jixPrintU64(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_u64;
    stderr.print("{}\n", .{a}) catch unreachable;
}

fn jixPrintF64(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_f64;
    stderr.print("{d}\n", .{a}) catch unreachable;
}

fn jixPrintPtr(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_ptr;
    stderr.print("{*}\n", .{a}) catch unreachable;
}
