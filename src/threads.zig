const std = @import("std");

pub const Thread = *anyopaque;
const winapi = std.os.windows;
    
pub fn spawn(stack_size: usize, comptime f: anytype, arg: ?*anyopaque) !Thread {
    var thread_id: winapi.DWORD = undefined;
    const Instance = struct {
        fn entryFn(raw_arg: ?*anyopaque) callconv(.C) winapi.DWORD {
            f(@ptrCast(@alignCast(raw_arg)));
            return 0;
        }
    };
    var handle = winapi.kernel32.CreateThread(null, stack_size, &Instance.entryFn, arg, 0, &thread_id);
    if (handle) |h| return h;
    
    const errno = winapi.kernel32.GetLastError();
    return winapi.unexpectedError(errno);
}

pub fn join(thread: Thread) void {
    _ = winapi.CloseHandle(thread);
}

pub fn setName(thread: Thread, name: []const u8) !void {
    var buf: [31]u16 = undefined;
    const len = try std.unicode.utf8ToUtf16Le(&buf, name);
    const byte_len = std.math.cast(c_ushort, len * 2) orelse return error.NameTooLong;

    // Note: NT allocates its own copy, no use-after-free here.
    const unicode_string = std.os.windows.UNICODE_STRING{
        .Length = byte_len,
        .MaximumLength = byte_len,
        .Buffer = &buf,
    };

    switch (std.os.windows.ntdll.NtSetInformationThread(
        thread,
        .ThreadNameInformation,
        &unicode_string,
        @sizeOf(std.os.windows.UNICODE_STRING),
    )) {
        .SUCCESS => return,
        .NOT_IMPLEMENTED => return error.Unsupported,
        else => |err| return std.os.windows.unexpectedStatus(err),
    }
}
