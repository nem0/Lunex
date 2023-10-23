const c = @import("c.zig");
const g = @import("gapi.zig");
const std = @import("std");

const ImGuiError = error.ImGuiError;

var g_imgui_pipeline: g.Pipeline = undefined;
var g_imgui_index_buffer: g.Buffer = undefined;
var g_imgui_vertex_buffer: g.Buffer = undefined;
var g_font_texture: g.Texture = undefined;

pub fn init() !void {
    _ = c.igCreateContext(null);
    var io = c.igGetIO();
    _ = c.ImFontAtlas_AddFontDefault(io.*.Fonts, null);
    if (!c.ImFontAtlas_Build(io.*.Fonts)) return ImGuiError;

    var layout: g.VertexLayout = .{};
    layout.addAttribute(.{ .byte_offset = 0, .flags = .{}, .num_components = 2, .type = .FLOAT }); // pos
    layout.addAttribute(.{ .byte_offset = 8, .flags = .{}, .num_components = 2, .type = .FLOAT }); // uv
    layout.addAttribute(.{ .byte_offset = 16, .flags = .{}, .num_components = 4, .type = .U8 }); // color

    g_imgui_pipeline = g.createPipeline(.{
        .vertex_shader = 
            \\cbuffer vertexBuffer : register(b0) {
            \\  float4x4 ProjectionMatrix;
            \\};
            \\struct VS_INPUT {
            \\  float2 pos : TEXCOORD0;
            \\  float2 uv  : TEXCOORD1;
            \\  float4 col : TEXCOORD2;
            \\};
            \\
            \\struct PS_INPUT {
            \\  float4 pos : SV_POSITION;
            \\  float4 col : COLOR0;
            \\  float2 uv  : TEXCOORD0;
            \\};
            \\
            \\PS_INPUT main(VS_INPUT input) {
            \\  PS_INPUT output;
            \\  output.pos = /*mul( ProjectionMatrix, */float4(input.pos.xy / float2(640.0, 480.0) * float2(2.0, -2.0) - float2(1.0, -1.0), 0.f, 1.f)/*)*/;
            \\  output.col = input.col;
            \\  output.uv  = input.uv;
            \\  return output;
            \\}
        ,
        .fragment_shader = 
            \\struct PS_INPUT {
            \\     float4 pos : SV_POSITION;
            \\     float4 col : COLOR0;
            \\     float2 uv  : TEXCOORD0;
            \\};
            \\
            \\sampler sampler0;
            \\Texture2D texture0;
            \\
            \\float4 main(PS_INPUT input) : SV_Target {
            \\     float4 out_col = input.col * texture0.Sample(sampler0, input.uv); 
            \\     return out_col; 
            \\}
        ,
        .index_type = .U32,
        .layout = layout,
        .topology = .TRIANGLES,
        .cull = .NONE,
        .depth_write = false,
        .depth_test_function = .ALWAYS,
        .blend_enabled = true,
        .src_blend = .SRC_ALPHA,
        .dst_blend = .INV_SRC_ALPHA,
        .src_alpha_blend = .SRC_ALPHA,
        .dst_alpha_blend = .INV_SRC_ALPHA
    });

    g_imgui_index_buffer = g.createBuffer(512 * 1024, null, .{});
    g_imgui_vertex_buffer = g.createBuffer(4 * 1024 * 1024, null, .{});

    var fonts = io.*.Fonts;
    var pixels: [*c]u8 = null;
    var font_h: c_int = undefined;
    var font_w: c_int = undefined;
    var bpp: c_int = undefined;
    c.ImFontAtlas_GetTexDataAsRGBA32(fonts, &pixels, &font_w, &font_h, &bpp);

    g_font_texture = g.createTexture(.{
        .w = @intCast(font_w),
        .h = @intCast(font_h),
        .depth = 1,
        .format = .RGBA8,
        .flags = .{}
    });

    var slice: []const u8 = undefined;
    slice.ptr = pixels;
    slice.len = @intCast(4 * font_w * font_h);

    g.updateTexture(g_font_texture, 0, 0, 0, 0, @intCast(font_w), @intCast(font_h), .RGBA8, slice);
}

pub fn newFrame() void {
    var io = c.igGetIO();
    io.*.DisplaySize.x = 640;
    io.*.DisplaySize.y = 480;
    c.igNewFrame();
}

inline fn asSlice(comptime T: type, val: [*]T, size: usize) []T {
    var slice: []T = undefined;
    slice.ptr = val;
    slice.len = size;
    return slice;
}

pub fn render() void {
    c.igRender();

    var dd = c.igGetDrawData();
    
    for (0..@intCast(dd.*.CmdLists.Size)) |cmd_list_idx| {
        var cmd_list = dd.*.CmdLists.Data[cmd_list_idx];
        
        g.updateBuffer(g_imgui_vertex_buffer, asSlice(u8, @ptrCast(cmd_list.*.VtxBuffer.Data), @intCast(cmd_list.*.VtxBuffer.Size * @sizeOf(c.ImDrawVert))));
        g.updateBuffer(g_imgui_index_buffer, asSlice(u8, @ptrCast(cmd_list.*.IdxBuffer.Data), @intCast(cmd_list.*.IdxBuffer.Size * @sizeOf(c.ImDrawIdx))));

        g.usePipeline(g_imgui_pipeline);
        g.bindTexture(0, g_font_texture);
        g.bindVertexBuffer(0, g_imgui_vertex_buffer, 0, 20);
        
        for (0..@intCast(cmd_list.*.CmdBuffer.Size)) |cmd_idx| {
		    var cmd = cmd_list.*.CmdBuffer.Data[cmd_idx];
            if (cmd.UserCallback != null) @panic("Unsupported imgui command");
            if (cmd.ElemCount == 0) continue;

            const h = std.math.clamp((cmd.ClipRect.w - cmd.ClipRect.y), 0.0, 65535.0);
            _ = h;
            g.draw(g_imgui_index_buffer, cmd.ElemCount, 1, cmd.IdxOffset * @sizeOf(u32));
        }
    }
}