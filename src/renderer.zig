const std = @import("std");
const c = @import("c.zig");
const g = @import("gapi.zig");
pub usingnamespace c;

pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);
pub const DVec3 = @Vector(3, f64);
pub const Quat = @Vector(4, f32);
pub const Matrix = struct {
    columns: [4]Vec4 = undefined,

    pub fn makeIdentity() Matrix {
        var res: Matrix = .{};
        res.columns[0] = Vec4{1, 0, 0, 0};
        res.columns[1] = Vec4{0, 1, 0, 0};
        res.columns[2] = Vec4{0, 0, 1, 0};
        res.columns[3] = Vec4{0, 0, 0, 1};
        return res;
    }

    pub fn makePerspective(fov: f32, ratio: f32, near_plane: f32, reversed_z: bool) Matrix {
        var res = Matrix.makeIdentity();
        const f = 1 / std.math.tan(fov * 0.5);
        res.columns[0][0] = f / ratio;
        res.columns[1][1] = f;
        res.columns[3][3]= 0;
        res.columns[2][3] = -1.0;

        if (reversed_z) {
            res.columns[2][2] = 0;
            res.columns[3][2] = near_plane;
        } else {
            res.columns[2][2] = -1;
            res.columns[3][2] = -near_plane;
        }
        return res;
    }
};

const EntityData = struct {
    position: DVec3,
    rotattion: Quat,
    scale: Vec3,
    valid: bool
};

pub const Entity = struct {
    world: *World,
    index: u32,

    fn destroy(self: *@This()) void {
        self.world.entities.items[self.index].valid = false;
    }

    fn getPosition(self: @This()) DVec3 { return self.world.entities.items[self.index].position; }
    fn setPosition(self: @This(), position: DVec3) void { self.world.entities.items[self.index].position = position; }

    fn getRotation(self: @This()) Quat { return self.world.entities.items[self.index].rotation; }
    fn setRotation(self: @This(), rotation: Quat) void { self.world.entities.items[self.index].rotation = rotation; }

    fn getScale(self: @This()) Vec3 { return self.world.entities.items[self.index].scale; }
    fn setScale(self: @This(), scale: Vec3) void { self.world.entities.items[self.index].scale = scale; }
};

pub const World = struct {
    entities: std.ArrayList(EntityData),
    first_free_entity: i32 = -1,

    fn new(allocator: std.mem.Allocator) World {
        var world: World = .{
            .entities = std.ArrayList(EntityData).init(allocator)
        };
        return world;
    }

    fn destroy(self: *@This()) void {
        self.entities.deinit();
    }

    fn createEntity(self: *@This()) Entity {
        var entity: Entity = .{
            .world = self,
            .index = @intCast(self.entities.items.len)
        };
        self.entities.append(.{
            .position = DVec3{0, 0, 0},
            .rotattion = Quat{0, 0, 0, 1},
            .scale = Vec3{1, 1, 1},
            .valid = true
        }) catch @panic("Could not create entity");
        return entity;
    }
};

pub const Shader = struct {
    vertex_source: [:0]const u8,
    fragment_source: [:0]const u8,
};

pub const Material = struct {
    shader: *const Shader,
    textures: std.BoundedArray(g.Texture, 16) = std.BoundedArray(g.Texture, 16).init(0) catch @panic("Fatal error")
};

pub const Mesh = struct {
    vertex_buffer: g.Buffer,
    index_buffer: g.Buffer,
    num_triangles: u32,
    vertex_layout: g.VertexLayout,
    index_type: g.IndexType,
    material: *const Material
};

pub const MeshDrawcall = struct {
    vertex_buffer: g.Buffer,
    index_buffer: g.Buffer,
    pipeline: g.Pipeline,
    num_triangles: u32,
    vertex_stride: u32,
    material: Material,
};

pub fn createMeshDrawcall(mesh: Mesh, defines: []const u8) MeshDrawcall {
    _ = defines;

    const pipeline: g.Pipeline = g.createPipeline(.{
        .vertex_shader = mesh.material.shader.vertex_source,
        .fragment_shader = mesh.material.shader.fragment_source,
        .layout = mesh.vertex_layout,
        .index_type = mesh.index_type,
        .topology = .TRIANGLES,
        .depth_test_function = .GREATER,
        .cull = .NONE
    });

    var drawcall:MeshDrawcall = .{
        .vertex_buffer = mesh.vertex_buffer,
        .index_buffer = mesh.index_buffer,
        .num_triangles = mesh.num_triangles,
        .pipeline = pipeline,
        .vertex_stride = mesh.vertex_layout.computeStride(),
        .material = mesh.material.*
    };
    return drawcall;
}

pub fn bindFramebuffer(swapchain: g.Swapchain) !void {
    try g.bindFramebuffer(swapchain);
}

pub fn clear(desc: g.ClearDesc) void {
    g.clear(desc);
}

pub fn render(drawcall: MeshDrawcall) void {
    for (drawcall.material.textures.slice(), 0..) |t, i| {
        g.bindTexture(@intCast(i), t);
    }

    g.usePipeline(drawcall.pipeline);
    g.bindVertexBuffer(0, drawcall.vertex_buffer, 0, drawcall.vertex_stride);
    g.draw(drawcall.index_buffer, drawcall.num_triangles * 3, 1, 0);
}

pub fn makeCubeMesh(material: *const Material) Mesh {
    const indices = [_]u16{
        //side
        0, 1, 2,
        3, 2, 1,

        4, 6, 5,
        7, 5, 6,

        //front
        1, 3, 7,
        1, 7, 5,

        0, 6, 2,
        0, 4, 6,

        //top
        1, 5, 0,
        0, 5, 6,

        3, 2, 7,
        2, 6, 7
    };
    const vertices = [_]f32{
         -1, -1, -1,
         -1, -1, 1,
         -1, 1, -1,
         -1, 1, 1,
         
         1, -1, -1,
         1, -1, 1,
         1, 1, -1,
         1, 1, 1,
    };

    const vbuf: g.Buffer = g.createBuffer(vertices.len * @sizeOf(f32), @ptrCast(&vertices), .{});
    const ibuf: g.Buffer = g.createBuffer(indices.len * @sizeOf(u16), @ptrCast(&indices), .{});

    var layout: g.VertexLayout = .{};
    layout.addAttribute(.{
        .type = .FLOAT,
        .byte_offset = 0,
        .num_components = 3,
        .flags = .{}
    });

    return .{
        .vertex_buffer = vbuf,
        .index_buffer = ibuf,
        .index_type = g.IndexType.fromType(@TypeOf(indices[0])),
        .material = material,
        .num_triangles = indices.len / 3,
        .vertex_layout = layout
    };
}


test "world" {
    var world = World.new(std.testing.allocator);
    defer world.destroy();

    var entity: Entity = world.createEntity();
    defer entity.destroy();

    entity.setPosition(DVec3{1, 2, 3});
    const p = entity.getPosition();
    try std.testing.expectApproxEqAbs(@as(f64, 1), p[0], 0.00001);
    try std.testing.expectApproxEqAbs(@as(f64, 2), p[1], 0.00001);
    try std.testing.expectApproxEqAbs(@as(f64, 3), p[2], 0.00001);

    const shader: Shader = .{
        .vertex_source =
            \\ #version 330
            \\ layout (std140) uniform Matrices {
            \\     mat4 projection;
            \\ };
            \\ layout(location=0) in vec4 position;
            \\ out vec3 v_col;
            \\ void main() {
            \\   v_col = position;
            \\   gl_Position = projection * position;
            \\ }
        ,
        .fragment_source =
            \\ #version 330
            \\ out vec4 frag_color;
            \\ in vec3 v_col;
            \\ void main() {
            \\   frag_color = vec4(vcol * 0.5 + 0.5, 1);
            \\ }
    };

    const material: Material = .{
        .shader = &shader,
        .textures = undefined
    };

    var cube = makeCubeMesh(&material);
    var dc = createMeshDrawcall(cube, "");
    render(dc);
}