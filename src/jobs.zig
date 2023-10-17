const fibers = @import("fibers.zig");
const std = @import("std");
const threads = @import("threads.zig");

var g_queue: std.ArrayList(Job) = undefined;
var g_mutex: std.Thread.Mutex = .{};
var g_workers: std.ArrayList(*Worker) = undefined;
var g_ready_fibers: std.ArrayList(fibers.Handle) = undefined;
var g_allocator: std.mem.Allocator = undefined;

const JobFunction = fn (arg: ?*anyopaque) callconv(.C) void;

const Job = struct {
    task: *const JobFunction,
    data: ?*anyopaque,
	//Signal* dec_on_finish;
	//u8 worker_index;
};

const Worker = struct {
    thread: threads.Thread,
    finish_requested: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),
    current_fiber: fibers.Handle
};

threadlocal var g_worker: std.atomic.Atomic(*Worker) = undefined;

fn getWorker() *Worker {
    return g_worker.load(std.atomic.Ordering.Acquire);
}

const Waitor = struct {
    //next: ?*Waitor = null
    // ?*anyopaque instead of ?*Waitor because of https://github.com/ziglang/zig/issues/12325
    next: std.atomic.Atomic(?*anyopaque) = std.atomic.Atomic(?*anyopaque).init(null),
    fiber: fibers.Handle
};

pub const Signal = struct {
    is_green: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(true),
    waitor: std.atomic.Atomic(?*Waitor) = std.atomic.Atomic(?*Waitor).init(null)
};

fn workerLoop(arg: ?*anyopaque) callconv(.C) void {
    g_mutex.unlock();    
    _ = arg;
    while (true) {
        if (getWorker().finish_requested.load(std.atomic.Ordering.Acquire)) break;        

        g_mutex.lock();
        var job_ptr = g_queue.popOrNull();
        g_mutex.unlock();
        if (job_ptr) |job| {
            job.task(job.data);
        }
    }    
}

fn workerMain(worker: *Worker) void {
    threads.setName(worker.*.thread, "Worker") catch {};
    g_worker.store(worker, std.atomic.Ordering.Release);
    g_mutex.lock();
    fibers.initThread(&workerLoop, &worker.current_fiber);
}

pub fn init(num_workers: usize, allocator: std.mem.Allocator) !void {
    g_allocator = allocator;    
    g_queue = std.ArrayList(Job).init(allocator); 
    g_workers = std.ArrayList(*Worker).init(allocator);
    g_ready_fibers = std.ArrayList(fibers.Handle).init(allocator);
    for (0..num_workers) |_| {
        var worker: *Worker = try allocator.create(Worker);
        worker.*.thread = try threads.spawn(64*1024, workerMain, worker);
        try g_workers.append(worker);
    }
}

pub fn shutdown() void {
    for (g_workers.items) |w| {
        w.finish_requested.store(true, std.atomic.Ordering.Release);
    }
    
    for (g_workers.items) |w| {
        threads.join(w.*.thread);
    }

    for (g_workers.items) |w| {
        g_allocator.destroy(w);
    }

    g_queue.deinit();
    g_workers.deinit();
    g_ready_fibers.deinit();
}

pub fn run(func: *const JobFunction, arg: ?*anyopaque) !void {
    g_mutex.lock();
    try g_queue.append(.{
        .task = func,
        .data = arg
    });
    g_mutex.unlock();
}

fn getCurrentFiber() fibers.Handle {
    return getWorker().*.current_fiber;
}

fn getFreeFiber() fibers.Handle {
    return fibers.create(64*1024, &workerLoop, null);
}

fn switchTo(to: fibers.Handle) void {
    var from = getCurrentFiber();
    getWorker().current_fiber = to;
    fibers.switchTo(null, to);
    getWorker().current_fiber = from;
}

pub fn wait(signal: *Signal) !void {
    if (signal.*.is_green.load(std.atomic.Ordering.Acquire)) return;
    g_mutex.lock();
    if (signal.*.is_green.load(std.atomic.Ordering.Acquire)) {
        g_mutex.unlock();
        return;
    }

    var waitor: Waitor = .{
        .fiber = getCurrentFiber()
    };

    waitor.next.store(signal.*.waitor.load(std.atomic.Ordering.Acquire), std.atomic.Ordering.Release);
    signal.*.waitor.store(&waitor, std.atomic.Ordering.Release);

    switchTo(getFreeFiber());

    g_mutex.unlock();
}

pub fn setGreen(signal: *Signal) !void {
    g_mutex.lock();
    signal.*.is_green.store(true, std.atomic.Ordering.Release);
    var waitor = signal.*.waitor.swap(null, std.atomic.Ordering.AcqRel);
    if (waitor) |w| {
        try g_ready_fibers.append(w.fiber);
    }
    g_mutex.unlock();
}

pub fn setRed(signal: *Signal) void {
    g_mutex.lock();
    signal.is_green.store(false, std.atomic.Ordering.Release);
    g_mutex.unlock();
}

// test

var val: std.atomic.Atomic(u32) = std.atomic.Atomic(u32).init(0);
var test_signal: Signal = .{};

fn jobTestFn(arg: ?*anyopaque) callconv(.C) void {
    _ = arg;
    _ = val.fetchAdd(1, std.atomic.Ordering.AcqRel);
    try wait(&test_signal);
}

test "jobs" {
    try init(1, std.testing.allocator);
    setRed(&test_signal);
    for (0..1024) |_| {
        try run(&jobTestFn, null);
    }
    try setGreen(&test_signal);
    std.time.sleep(1_000_000_000);
    shutdown();
    try std.testing.expectEqual(@as(u32, 1024), val.load(std.atomic.Ordering.Acquire));
}