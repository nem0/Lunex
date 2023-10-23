const std = @import("std");
const c = @import("c.zig");
const jobs = @import("jobs.zig");
const r = @import("renderer.zig");
const g = @import("gapi.zig");
const ig = @import("imgui.zig");

var main_job_finished_event: std.Thread.ResetEvent = .{};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

fn mainFn(_: ?*anyopaque) callconv(.C) void {
    if (c.glfwInit() == 0) @panic("Failed to init glfw");
    defer c.glfwTerminate();
    
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    const window = c.glfwCreateWindow(640, 480, "Lunex Zig Studio Enterprise", null, null);
    if (window == null) @panic("Failed to create window");
    defer c.glfwDestroyWindow(window);
    
    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    var hwnd = c.glfwGetWin32Window(window);
    g.init() catch @panic("Failed to init gapi");
    var swapchain = g.createSwapchain(hwnd) catch @panic("Failed to create swapchain");

    ig.init() catch @panic("Failed to init imgui");

    const shader: r.Shader = .{
        .vertex_source =
            \\ struct VS_INPUT {
            \\   float3 pos : TEXCOORD0;
            \\ };
            \\ 
            \\ struct PS_INPUT {
            \\   float4 pos : SV_POSITION;
            \\ };
            \\ 
            \\ PS_INPUT main(VS_INPUT input) {
            \\   PS_INPUT output;
            \\   output.pos = float4(input.pos.xy * 0.2, 0.5, 1.f);
            \\   return output;
            \\ }
        ,
        .fragment_source =
            \\ struct PS_INPUT {
            \\     float4 pos : SV_POSITION;
            \\ };
            \\
            \\ sampler sampler0;
            \\ Texture2D texture0;
            \\
            \\ float4 main(PS_INPUT input) : SV_Target {
            \\     float4 out_col = texture0.Sample(sampler0, float2(0.5, 0.5));
            \\     return out_col;
            \\ }
    };

    var material: r.Material = .{
        .shader = &shader,
    };
    var tex = g.createTexture(.{
        .w = 1,
        .h = 1,
        .depth = 1,
        .flags = .{},
        .format = .RGBA8
    });
    const tex_data = [_]u8{0, 255, 0, 255};
    g.updateTexture(tex, 0, 0, 0, 0, 1, 1, .RGBA8, tex_data[0..]);
    material.textures.append(tex) catch @panic("Failed to create material");

    var cube = r.makeCubeMesh(&material);
    var dc = r.createMeshDrawcall(cube, "");

    var mtx = r.Matrix.makePerspective(std.math.degreesToRadians(f32, 90), 640.0 / 480.0, 0.1, true);
    _ = mtx;

    // draw loop
    while (c.glfwWindowShouldClose(window) == 0) {
        ig.newFrame();
        var cur_width: i32 = undefined;
        var cur_height: i32 = undefined;
        c.glfwGetFramebufferSize(window, &cur_width, &cur_height);

        r.bindFramebuffer(swapchain) catch @panic("Failed to bind framebuffer");
        r.clear(.{ 
            .color = r.Vec4{0, 0, 1, 1},
            .depth = 0,
            .stencil = null
        });
        r.render(dc);

        c.igSetNextWindowSize(.{.x = 200, .y = 200}, 0);
        if (c.igBegin("Lunex Studio Trial Version", null, 0)) {
            c.igTextUnformatted("Hello World!", null);
        }
        c.igEnd();

        ig.render();
        swapchain.present() catch @panic("Failed to present swapchain");
        c.glfwPollEvents();
    }    
    main_job_finished_event.set();
}

pub fn main() !void {
    try jobs.init(4, allocator);
    main_job_finished_event.reset();
    try jobs.run(&mainFn, null);
    main_job_finished_event.wait();
    jobs.shutdown();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
