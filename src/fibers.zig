const c = @cImport({
    @cInclude("windows.h");
});
const std = @import("std");

pub const Handle = c.LPVOID;
pub const INVALID_FIBER: Handle = null;
const FiberProc = fn(?*anyopaque) callconv(.C) void;

// call on a thread before calling any other fiber functions on that thread
pub fn initThread(proc: *const FiberProc, out: *Handle) void {
	out.* = c.ConvertThreadToFiber(null);
	proc(null);
}

pub fn create(stack_size: usize, proc: *const FiberProc, parameter: ?*anyopaque) Handle {
	return c.CreateFiber(stack_size, proc, parameter);
}

pub fn destroy(fiber: Handle) void {
	c.DeleteFiber(fiber);
}

pub fn switchTo(from: ?*Handle, to: Handle) void {
    _ = from;
	c.SwitchToFiber(to);
}

// test
var val: std.atomic.Atomic(u32) = std.atomic.Atomic(u32).init(0);
var primary_fiber: Handle = undefined;

fn fiberFn(arg: ?*anyopaque) callconv(.C) void {
    _ = arg;
    val.store(42, std.atomic.Ordering.Release);
    switchTo(null, primary_fiber);
}

fn fiberMain(arg: ?*anyopaque) callconv(.C) void {
    _ = arg;
    var fiber = create(1024 * 4, fiberFn, null);
    switchTo(null, fiber);
}

test "fibers" {
    initThread(fiberMain, &primary_fiber);
    try std.testing.expectEqual(@as(u32, 42), val.load(std.atomic.Ordering.Acquire));
}