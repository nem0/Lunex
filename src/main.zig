const std = @import("std");
const c = @import("c.zig");
const jobs = @import("jobs.zig");

var main_job_finished_event: std.Thread.ResetEvent = .{};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

fn mainFn(_: ?*anyopaque) callconv(.C) void {
    if (c.glfwInit() == 0) @panic("Failed to init glfw");
    defer c.glfwTerminate();
    
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    const window = c.glfwCreateWindow(640, 480, "Lunex Zig Studio Enterprise", null, null);
    if (window == null) @panic("Failed to create window");
    defer c.glfwDestroyWindow(window);
    
    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    var desc: c.sg_desc = .{ };
    c.sg_setup(&desc);
    defer c.sg_shutdown();

    var sg_imgui: c.sg_imgui_t = .{};
    c.sg_imgui_init(&sg_imgui, &.{});

    c.simgui_setup(&.{
        .max_vertices = 65536,
        .image_pool_size = 256
    });

    const vertices = [_]f32{
        // positions            // colors
         0.0,  0.5, 0.5,     1.0, 0.0, 0.0, 1.0,
         0.5, -0.5, 0.5,     0.0, 1.0, 0.0, 1.0,
        -0.5, -0.5, 0.5,     0.0, 0.0, 1.0, 1.0
    };
    const vbuf: c.sg_buffer = c.sg_make_buffer(&.{
        .data = .{ .ptr = &vertices, .size = vertices.len * @sizeOf(f32) }
    });

    // a shader
    const shd: c.sg_shader = c.sg_make_shader(&.{
        .vs = .{ .source =
            \\ #version 330
            \\ layout(location=0) in vec4 position;
            \\ layout(location=1) in vec4 color0;
            \\ out vec4 color;
            \\ void main() {
            \\   gl_Position = position;
            \\  color = color0;
            \\ }
        },
        .fs = .{ .source =
            \\ #version 330
            \\ in vec4 color;
            \\ out vec4 frag_color;
            \\ void main() {
            \\   frag_color = color;
            \\ }
        }
    });

    // a pipeline state object (default render states are fine for triangle)
    var pipeline_desc: c.sg_pipeline_desc = .{
        .shader = shd,
        .layout = .{}
    };
    pipeline_desc.layout.attrs[0] = .{ .format = c.SG_VERTEXFORMAT_FLOAT3 };
    pipeline_desc.layout.attrs[1] = .{ .format = c.SG_VERTEXFORMAT_FLOAT4 };

    const pip: c.sg_pipeline = c.sg_make_pipeline(&pipeline_desc);

    // resource bindings
    var bind: c.sg_bindings = .{};
    bind.vertex_buffers[0] = vbuf;

    // default pass action (clear to grey)
    const pass_action: c.sg_pass_action = .{};

    // draw loop
    while (c.glfwWindowShouldClose(window) == 0) {
        c.simgui_new_frame(&.{
            .width = 640,
            .height = 480,
            .delta_time = 1.0 / 60.0,
            .dpi_scale = 1
        });

        var cur_width: i32 = undefined;
        var cur_height: i32 = undefined;
        c.sg_imgui_draw(&sg_imgui);
        c.glfwGetFramebufferSize(window, &cur_width, &cur_height);
        c.sg_begin_default_pass(&pass_action, cur_width, cur_height);
        c.sg_apply_pipeline(pip);
        c.sg_apply_bindings(&bind);
        c.sg_draw(0, 3, 1);

        c.igSetNextWindowSize(.{.x = 200, .y = 200}, 0);
        if (c.igBegin("Lunex Studio Trial Version", null, 0)) {
        }
        c.igEnd();

        c.simgui_render();

        c.sg_end_pass();
        c.sg_commit();
        c.glfwSwapBuffers(window);
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
