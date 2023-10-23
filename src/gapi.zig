const dx = @import("c.zig");
const std = @import("std");

const DXError = error.DXError;

var g_device: [*c]dx.ID3D11Device = undefined;
var g_device_context: [*c]dx.ID3D11DeviceContext = undefined;
const D3DCompileType = *const fn (data: ?*const anyopaque, data_size: dx.SIZE_T, filename: [*c]const u8, defines: [*c]const dx.D3D_SHADER_MACRO, include: [*c]dx.ID3DInclude, entrypoint: [*c]const u8, target: [*c]const u8, sflags: dx.UINT, eflags: dx.UINT, shader: [*c][*c]dx.ID3DBlob, error_messages: [*c][*c]dx.ID3DBlob) callconv(.C) dx.HRESULT;
var g_d3dcompile: D3DCompileType = undefined;

pub const WindowHandle = dx.HWND;
pub const Swapchain = struct {
	const Self = @This();

	swapchain: [*c]dx.IDXGISwapChain = undefined,
	rtv: [*c]dx.ID3D11RenderTargetView = undefined,
	dsv: [*c]dx.ID3D11DepthStencilView = undefined,
	w: u32,
	h: u32,

	pub fn present(self: Self) !void {
		const hr = self.swapchain.*.lpVtbl.*.Present.?(self.swapchain, 1, 0);
		if (hr != 0) return DXError;
	}
};

pub const TextureFlags = packed struct(u32) {
	point_filter: bool =  false,
	anisotropic_filter: bool =  false,
	clamp_u: bool = false,
	clamp_v: bool = false,
	clamp_w: bool = false,
	no_mips: bool = false,
	srgb: bool = false,
	readback: bool = false,
	is_3d: bool = false,
	is_cube: bool = false,
	compute_write: bool = false,
	render_target: bool = false,
	_ : u20 = undefined
};

pub const Texture = struct {
	desc: TextureDesc,
    texture2D: [*c]dx.ID3D11Texture2D = null,
    texture3D: [*c]dx.ID3D11Texture3D = null,
	srv: [*c]dx.ID3D11ShaderResourceView = null,	
	sampler: [*c]dx.ID3D11SamplerState = null,
	dxgi_format: dx.DXGI_FORMAT
};

pub const TextureFormat = enum {
	R8,
	RG8,
	D32,
	D24S8,
	RGBA8,
	RGBA16,
	RGBA16F,
	RGBA32F,
	BGRA8,
	R16F,
	R16,
	R32F,
	RG32F,
	SRGB,
	SRGBA,
	BC1,
	BC2,
	BC3,
	BC4,
	BC5,
	R11G11B10F,
	RGB32F,
	RG16,
	RG16F,

	const Self = @This();
	
	pub fn toDXGI(self: Self) dx.DXGI_FORMAT {
		_ = self;
		return 0;
	}

	pub fn canGenMips(self: Self) bool {
		_ = self;
		return false;
	}
};

pub const TextureDesc = struct {
	w: u32,
	h: u32,
	depth: u32,
	format: TextureFormat,
	flags: TextureFlags,

	pub inline fn computeMipCount(self: @This()) usize {
		return if (self.flags.no_mips) 1 else 1 + std.math.log2(@max(self.w, self.h, if (self.flags.is_3d) self.depth else 1));
	}

	pub inline fn isDepthFormat(self: @This()) bool {
		return switch(self.format) {
			.D24S8 => true,
			.D32 => true,
			else => false
		};
	}

	pub inline fn getDXGIFormat(self: @This()) dx.DXGI_FORMAT {
		return switch (self.format) {
			.BC1 => dx.DXGI_FORMAT_BC1_UNORM,
			.BC2 => dx.DXGI_FORMAT_BC2_UNORM,
			.BC3 => dx.DXGI_FORMAT_BC3_UNORM,
			.BC4 => dx.DXGI_FORMAT_BC4_UNORM,
			.BC5 => dx.DXGI_FORMAT_BC5_UNORM,
			.R16 => dx.DXGI_FORMAT_R16_UNORM,
			.RG16 => dx.DXGI_FORMAT_R16G16_UNORM,
			.R8 => dx.DXGI_FORMAT_R8_UNORM,
			.RG8 => dx.DXGI_FORMAT_R8G8_UNORM,
			.BGRA8 => dx.DXGI_FORMAT_B8G8R8A8_UNORM,
			.SRGBA => dx.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
			.RGBA8 => dx.DXGI_FORMAT_R8G8B8A8_UNORM,
			.RGBA16 => dx.DXGI_FORMAT_R16G16B16A16_UNORM,
			.R11G11B10F => dx.DXGI_FORMAT_R11G11B10_FLOAT,
			.RGBA16F => dx.DXGI_FORMAT_R16G16B16A16_FLOAT,
			.RGBA32F => dx.DXGI_FORMAT_R32G32B32A32_FLOAT,
			.RG32F => dx.DXGI_FORMAT_R32G32_FLOAT,
			.RGB32F => dx.DXGI_FORMAT_R32G32B32_FLOAT,
			.R32F => dx.DXGI_FORMAT_R32_FLOAT,
			.RG16F => dx.DXGI_FORMAT_R16G16_FLOAT,
			.R16F => dx.DXGI_FORMAT_R16_FLOAT,
			
			.D32 => dx.DXGI_FORMAT_R32_TYPELESS,
			.D24S8 => dx.DXGI_FORMAT_R24G8_TYPELESS,
			
			.SRGB => @panic("Format not supported")
		};
	}
};

pub fn bindTexture(idx: u32, texture: Texture) void {
	g_device_context.*.lpVtbl.*.VSSetShaderResources.?(g_device_context, idx, 1, &texture.srv);
	g_device_context.*.lpVtbl.*.PSSetShaderResources.?(g_device_context, idx, 1, &texture.srv);
	g_device_context.*.lpVtbl.*.PSSetSamplers.?(g_device_context, idx, 1, &texture.sampler);
	g_device_context.*.lpVtbl.*.VSSetSamplers.?(g_device_context, idx, 1, &texture.sampler);
}

fn getSampler(flags: TextureFlags) [*c]dx.ID3D11SamplerState {
	// TODO reuse
	var sampler_desc: dx.D3D11_SAMPLER_DESC = .{};
	sampler_desc.Filter = if(flags.anisotropic_filter) dx.D3D11_FILTER_ANISOTROPIC else if (flags.point_filter) dx.D3D11_FILTER_MIN_MAG_MIP_POINT else dx.D3D11_FILTER_MIN_MAG_MIP_LINEAR;
	sampler_desc.AddressU = if (flags.clamp_u) dx.D3D11_TEXTURE_ADDRESS_CLAMP else dx.D3D11_TEXTURE_ADDRESS_WRAP;
	sampler_desc.AddressV = if(flags.clamp_v) dx.D3D11_TEXTURE_ADDRESS_CLAMP else dx.D3D11_TEXTURE_ADDRESS_WRAP;
	sampler_desc.AddressW = if(flags.clamp_w) dx.D3D11_TEXTURE_ADDRESS_CLAMP else dx.D3D11_TEXTURE_ADDRESS_WRAP;
	sampler_desc.MipLODBias = 0;
	sampler_desc.ComparisonFunc = dx.D3D11_COMPARISON_ALWAYS;
	sampler_desc.MinLOD = 0;
	sampler_desc.MaxLOD = dx.D3D11_FLOAT32_MAX;
	sampler_desc.MaxAnisotropy = if (flags.anisotropic_filter) 8 else 1;
	var sampler: [*c]dx.ID3D11SamplerState = undefined;
	var hr = g_device.*.lpVtbl.*.CreateSamplerState.?(g_device, &sampler_desc, &sampler);
	if (hr != 0) @panic("Failed to craete sampler");
	return sampler;
}

fn fillTextureDesc(in_desc: TextureDesc, out_desc: anytype) void {
	out_desc.Width = in_desc.w;
	out_desc.Height = in_desc.h;
	out_desc.MipLevels = @intCast(in_desc.computeMipCount());
	out_desc.Usage = dx.D3D11_USAGE_DEFAULT;
	out_desc.CPUAccessFlags = 0;
	out_desc.Format = in_desc.getDXGIFormat();
	out_desc.BindFlags = dx.D3D11_BIND_SHADER_RESOURCE;

	const gen_mip = !in_desc.flags.readback and !in_desc.flags.no_mips and !in_desc.isDepthFormat() and in_desc.format.canGenMips();
	if (gen_mip or in_desc.flags.render_target) {
		out_desc.BindFlags |= if (in_desc.isDepthFormat()) dx.D3D11_BIND_DEPTH_STENCIL else dx.D3D11_BIND_RENDER_TARGET;
	}
	if (in_desc.flags.compute_write) {
		out_desc.BindFlags |= dx.D3D11_BIND_UNORDERED_ACCESS;
	}
	if (in_desc.flags.readback) {
		out_desc.Usage = dx.D3D11_USAGE_STAGING;
		out_desc.CPUAccessFlags = dx.D3D11_CPU_ACCESS_READ;
		out_desc.BindFlags = 0;
	}
	out_desc.MiscFlags = if (gen_mip) dx.D3D11_RESOURCE_MISC_GENERATE_MIPS else 0;
}

fn toViewFormat(format: dx.DXGI_FORMAT) dx.DXGI_FORMAT {
	return switch(format) {
		dx.DXGI_FORMAT_R24G8_TYPELESS => dx.DXGI_FORMAT_R24_UNORM_X8_TYPELESS,
		dx.DXGI_FORMAT_R32_TYPELESS => dx.DXGI_FORMAT_R32_FLOAT,
		else => format
	};
}

pub fn createTexture(desc: TextureDesc) Texture {
	var texture: Texture = .{
		.desc = desc,
		.sampler = getSampler(desc.flags),
		.dxgi_format = desc.getDXGIFormat()
	};

	var desc_3d: dx.D3D11_TEXTURE3D_DESC = .{};
	var desc_2d: dx.D3D11_TEXTURE2D_DESC = .{};
	
	
	if (desc.flags.is_3d) {
		fillTextureDesc(desc, &desc_3d);
		desc_3d.Depth = desc.depth;
	}
	else {
		fillTextureDesc(desc, &desc_2d);
		desc_2d.SampleDesc.Count = 1;
		desc_2d.ArraySize = if (desc.flags.is_cube) 6 * desc.depth else desc.depth;
		desc_2d.MiscFlags |= if (desc.flags.is_cube) dx.D3D11_RESOURCE_MISC_TEXTURECUBE else 0;
	}

	if (desc.flags.is_3d) {
		var hr = g_device.*.lpVtbl.*.CreateTexture3D.?(g_device, &desc_3d, null, &texture.texture3D);
		if (hr != 0) @panic("Failed to create texture");
	}
	else {
		var hr = g_device.*.lpVtbl.*.CreateTexture2D.?(g_device, &desc_2d, null, &texture.texture2D);
		if (hr != 0) @panic("Failed to create texture");
	}
//
	//if (compute_write) {
	//	D3D11_UNORDERED_ACCESS_VIEW_DESC uav_desc = {};
	//	if (is_3d) {
	//		uav_desc.Format = texture.dxgi_format;
	//		uav_desc.ViewDimension = D3D11_UAV_DIMENSION_TEXTURE3D;
	//		uav_desc.Texture3D.MipSlice = 0;
	//		uav_desc.Texture3D.WSize = -1;
	//		uav_desc.Texture3D.FirstWSlice = 0;
	//		d3d->device->CreateUnorderedAccessView(texture.texture3D, &uav_desc, &texture.uav);
	//	}
	//	else {
	//		uav_desc.Format = texture.dxgi_format;
	//		uav_desc.ViewDimension = D3D11_UAV_DIMENSION_TEXTURE2D;
	//		uav_desc.Texture2D.MipSlice = 0;
	//		d3d->device->CreateUnorderedAccessView(texture.texture2D, &uav_desc, &texture.uav);
	//	}
	//}
//
	if (!desc.flags.readback) {
		var srv_desc: dx.D3D11_SHADER_RESOURCE_VIEW_DESC = .{};
		if (desc.flags.is_3d) {
			srv_desc.Format = toViewFormat(desc_3d.Format);
			srv_desc.ViewDimension = dx.D3D11_SRV_DIMENSION_TEXTURE3D;
			srv_desc.unnamed_0.Texture3D.MipLevels = desc_3d.MipLevels;
			var hr = g_device.*.lpVtbl.*.CreateShaderResourceView.?(g_device, @ptrCast(texture.texture3D), &srv_desc, &texture.srv);
			if (hr != 0) @panic("Failed to create SRV");
		}
		else if (desc.flags.is_cube) {
			srv_desc.Format = toViewFormat(desc_2d.Format);
			if (desc.depth > 1) {
				srv_desc.ViewDimension = dx.D3D11_SRV_DIMENSION_TEXTURECUBEARRAY;
				srv_desc.unnamed_0.TextureCubeArray.MipLevels = desc_2d.MipLevels;
				srv_desc.unnamed_0.TextureCubeArray.NumCubes = desc.depth;
				var hr = g_device.*.lpVtbl.*.CreateShaderResourceView.?(g_device, @ptrCast(texture.texture2D), &srv_desc, &texture.srv);
				if (hr != 0) @panic("Failed to create SRV");
			}
			else {
				srv_desc.ViewDimension = dx.D3D11_SRV_DIMENSION_TEXTURECUBE;
				srv_desc.unnamed_0.TextureCube.MipLevels = desc_2d.MipLevels;
				var hr = g_device.*.lpVtbl.*.CreateShaderResourceView.?(g_device, @ptrCast(texture.texture2D), &srv_desc, &texture.srv);
				if (hr != 0) @panic("Failed to create SRV");
			}
		}
		else if (desc.depth > 1) {
			srv_desc.Format = toViewFormat(desc_2d.Format);
			srv_desc.ViewDimension = dx.D3D11_SRV_DIMENSION_TEXTURE2DARRAY;
			srv_desc.unnamed_0.Texture2DArray.MipLevels = desc_2d.MipLevels;
			srv_desc.unnamed_0.Texture2DArray.ArraySize = desc.depth;
			var hr = g_device.*.lpVtbl.*.CreateShaderResourceView.?(g_device, @ptrCast(texture.texture2D), &srv_desc, &texture.srv);
			if (hr != 0) @panic("Failed to create SRV");
		}
		else {
			srv_desc.Format = toViewFormat(desc_2d.Format);
			srv_desc.ViewDimension = dx.D3D11_SRV_DIMENSION_TEXTURE2D;
			srv_desc.unnamed_0.Texture2D.MipLevels = desc_2d.MipLevels;
			var hr = g_device.*.lpVtbl.*.CreateShaderResourceView.?(g_device, @ptrCast(texture.texture2D), &srv_desc, &texture.srv);
			if (hr != 0) @panic("Failed to create SRV");
		}
	}

	return texture;
}

inline fn getSize(format: dx.DXGI_FORMAT) u32 {
	return switch(format) {
		dx.DXGI_FORMAT_R8_UNORM => 1,
		dx.DXGI_FORMAT_R8G8_UNORM => 2,
		dx.DXGI_FORMAT_R32_TYPELESS => 4,
		dx.DXGI_FORMAT_R24G8_TYPELESS => 4,
		dx.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB => 4,
		dx.DXGI_FORMAT_R8G8B8A8_UNORM => 4,
		dx.DXGI_FORMAT_B8G8R8A8_UNORM_SRGB => 4,
		dx.DXGI_FORMAT_B8G8R8A8_UNORM => 4,
		dx.DXGI_FORMAT_R16G16B16A16_UNORM => 8,
		dx.DXGI_FORMAT_R16G16B16A16_FLOAT => 8,
		dx.DXGI_FORMAT_R32G32_FLOAT => 8,
		dx.DXGI_FORMAT_R32G32B32_FLOAT => 12,
		dx.DXGI_FORMAT_R32G32B32A32_FLOAT => 16,
		dx.DXGI_FORMAT_R16_UNORM => 2,
		dx.DXGI_FORMAT_R16_FLOAT => 2,
		dx.DXGI_FORMAT_R32_FLOAT => 4,
		else => @panic("Unknown format")
	};
}

fn calcSubresource(mip_slice: u32, array_slice: u32, mip_levels: u32) u32 {
    return mip_slice + array_slice * mip_levels;
}


pub fn updateBuffer(buffer: Buffer, src: []const u8) void {
	//if (buffer->uav) {
	//	const D3D11_BOX box = { 0, 0, 0, (UINT)size, 1, 1};
	//	d3d->device_ctx->UpdateSubresource1(buffer->buffer, 0, &box, data, 0, 0, D3D11_COPY_DISCARD);
	//}
	//else {
		var msr: dx.D3D11_MAPPED_SUBRESOURCE = undefined;
		var hr = g_device_context.*.lpVtbl.*.Map.?(g_device_context, @ptrCast(buffer.buffer), 0, dx.D3D11_MAP_WRITE_DISCARD, 0, &msr);
		if (hr != 0) @panic("Failed to map buffer");
		var dst: []u8 = undefined;	
		dst.ptr = @ptrCast(msr.pData);
		dst.len = src.len;
		std.mem.copy(u8, dst, src);
		g_device_context.*.lpVtbl.*.Unmap.?(g_device_context, @ptrCast(buffer.buffer), 0);
	//}
}

pub fn updateTexture(texture: Texture, mip: u32, x: u32, y: u32, z: u32, w: u32, h: u32, format: TextureFormat, data: []const u8) void {
	_ = format;	
	//const bool is_srgb = u32(texture->flags & TextureFlags::SRGB);
	//ASSERT(texture->dxgi_format == getDXGIFormat(format, is_srgb));
	//const bool no_mips = u32(texture->flags & TextureFlags::NO_MIPS);
	const mip_count = 
		//no_mips ? 1 : 
		1 + std.math.log2(@max(texture.desc.w, texture.desc.h));
	const subres = calcSubresource(mip, z, mip_count);
	//const bool is_compressed = FormatDesc::get(format).compressed;
	const row_pitch = w * getSize(texture.dxgi_format);
	const depth_pitch = row_pitch * h;
	const box: dx.D3D11_BOX = .{
		.left = x,
		.top = y,
		.right = x + w,
		.bottom = y + h,
		.front = 0,
		.back = 1
	};
	g_device_context.*.lpVtbl.*.UpdateSubresource.?(g_device_context, @ptrCast(texture.texture2D), subres, &box, data.ptr, row_pitch, depth_pitch);
}

pub const Buffer = struct {
	buffer: [*c]dx.ID3D11Buffer = null,
	srv: [*c]dx.ID3D11ShaderResourceView = null,
	uav: [*c]dx.ID3D11UnorderedAccessView = null,
	mapped_ptr: ?*u8 = null,
	is_constant_buffer: bool = false,
	bound_to_output: u32 = 0xffFFffFF
};

pub const BufferFlags = packed struct(u32) {
	immutable: bool = false,
	uniform_buffer: bool = false,
	shader_buffer: bool = false,
	compute_write: bool = false,
	mappable: bool = false,
	_: u27 = undefined
};

pub fn createBuffer(size_in: u32, data: ?*const u8, flags: BufferFlags) Buffer {
	var res: Buffer = .{};
	var desc: dx.D3D11_BUFFER_DESC = .{};
	var size = size_in;
	if (flags.shader_buffer) {
		size = ((size + 15) / 16) * 16;
	}

	desc.ByteWidth = size;
	
	res.is_constant_buffer = flags.uniform_buffer;
	if (flags.uniform_buffer) {
		desc.BindFlags = dx.D3D11_BIND_CONSTANT_BUFFER; 
	}
	else {
		desc.BindFlags = dx.D3D11_BIND_VERTEX_BUFFER | dx.D3D11_BIND_INDEX_BUFFER; 
		if (flags.shader_buffer) {
			desc.BindFlags |= dx.D3D11_BIND_SHADER_RESOURCE;
			desc.MiscFlags = dx.D3D11_RESOURCE_MISC_BUFFER_ALLOW_RAW_VIEWS;
			if (flags.compute_write) {
				desc.BindFlags |= dx.D3D11_BIND_UNORDERED_ACCESS;
				desc.MiscFlags |= dx.D3D11_RESOURCE_MISC_DRAWINDIRECT_ARGS;
			}
		}
	}

	if (flags.immutable) {
		desc.Usage = dx.D3D11_USAGE_IMMUTABLE;
	}
	else if (flags.compute_write) {
		desc.Usage = dx.D3D11_USAGE_DEFAULT;
	}
	else {
		desc.CPUAccessFlags = dx.D3D11_CPU_ACCESS_WRITE;
		desc.Usage = dx.D3D11_USAGE_DYNAMIC;
	}
	var initial_data: dx.D3D11_SUBRESOURCE_DATA = .{};
	initial_data.pSysMem = data;
	const hr = g_device.*.lpVtbl.*.CreateBuffer.?(g_device, &desc, if (data != null) &initial_data else null, &res.buffer);
	if (hr != 0) @panic("Failed to create DX buffer");

	if (flags.shader_buffer) {
		const srv_desc: dx.D3D11_SHADER_RESOURCE_VIEW_DESC = .{
			.Format = dx.DXGI_FORMAT_R32_TYPELESS,
			.ViewDimension = dx.D3D11_SRV_DIMENSION_BUFFEREX,
			.unnamed_0 = . {.BufferEx = .{
				.Flags = dx.D3D11_BUFFEREX_SRV_FLAG_RAW,
				.FirstElement = 0,
				.NumElements = size / 4
			}}
		};

		const hr2 = g_device.*.lpVtbl.*.CreateShaderResourceView.?(g_device, @ptrCast(res.buffer), &srv_desc, &res.srv);
		if (hr2 != 0) @panic("Failed to create DX buffer");

		if (flags.compute_write) {
			const uav_desc: dx.D3D11_UNORDERED_ACCESS_VIEW_DESC = .{
				.Format = dx.DXGI_FORMAT_R32_TYPELESS,
				.ViewDimension = dx.D3D11_UAV_DIMENSION_BUFFER,
				.unnamed_0 = . {.Buffer = .{
					.FirstElement = 0,
					.NumElements = size / @sizeOf(f32),
					.Flags = dx.D3D11_BUFFER_UAV_FLAG_RAW
				}}
			};
			const hr3 = g_device.*.lpVtbl.*.CreateUnorderedAccessView.?(g_device, @ptrCast(res.buffer), &uav_desc, &res.uav);
			if (hr3 != 0) @panic("Failed to crate DX buffer");
		}
	}
	return res;
}

var g_index_type: IndexType = .U32;

pub fn usePipeline(pipeline: Pipeline) void {
	g_index_type = pipeline.index_type;
	g_device_context.*.lpVtbl.*.VSSetShader.?(g_device_context, pipeline.vertex_shader, null, 0);
	g_device_context.*.lpVtbl.*.PSSetShader.?(g_device_context, pipeline.fragment_shader, null, 0);
	g_device_context.*.lpVtbl.*.IASetPrimitiveTopology.?(g_device_context, pipeline.topology);
	
	const stencil_ref: u32 = 0;
	const blend_factor: [4]f32 = .{0, 0, 0, 0};
	g_device_context.*.lpVtbl.*.OMSetDepthStencilState.?(g_device_context, pipeline.depth_stencil_state, stencil_ref);
	g_device_context.*.lpVtbl.*.RSSetState.?(g_device_context, pipeline.rasterizer_state);
	g_device_context.*.lpVtbl.*.OMSetBlendState.?(g_device_context, pipeline.blend_state, &blend_factor, 0xffFFffFF);
	g_device_context.*.lpVtbl.*.IASetInputLayout.?(g_device_context, pipeline.input_layout);
}

pub fn bindVertexBuffer(binding_idx: u32, buffer: ?Buffer, buffer_offset: u32, stride: u32) void {
	if (buffer) |b| {
		g_device_context.*.lpVtbl.*.IASetVertexBuffers.?(g_device_context, binding_idx, 1, &b.buffer, &stride, &buffer_offset);
	}
	else {
		const tmp: [*c]dx.ID3D11Buffer = null;
		const tmp2: dx.UINT = 0;
		g_device_context.*.lpVtbl.*.IASetVertexBuffers.?(g_device_context, binding_idx, 1, &tmp, &tmp2, &tmp2);
	}
}

var g_rtvs: std.BoundedArray([*c]dx.ID3D11RenderTargetView, 16) = .{};
var g_ds: [*c]dx.ID3D11DepthStencilView = null;

pub const ClearDesc = struct {
	color: ?@Vector(4, f32),
	depth: ?f32,
	stencil: ?u8
};

pub fn clear(desc: ClearDesc) void {
	if (desc.color) |color| {
		const color_array: [4]f32 = color;
		for (g_rtvs.slice()) |rtv| {
			g_device_context.*.lpVtbl.*.ClearRenderTargetView.?(g_device_context, rtv, &color_array);
		}
	}
	var ds_flags: u32 = 0;
	var depth: f32 = 0;
	var stencil: u8 = 0;
	if (desc.depth) |d| {
		depth = d;
		ds_flags |= dx.D3D11_CLEAR_DEPTH;
	}
	if (desc.stencil) |s| {
		stencil = s;
		ds_flags |= dx.D3D11_CLEAR_STENCIL;
	}
	if (ds_flags != 0 and g_ds != null) {
		g_device_context.*.lpVtbl.*.ClearDepthStencilView.?(g_device_context, g_ds, ds_flags, depth, stencil);
	}
}

pub fn bindFramebuffer(swapchain: Swapchain) !void {
	g_device_context.*.lpVtbl.*.OMSetRenderTargets.?(g_device_context, 1, &swapchain.rtv, swapchain.dsv);
	g_rtvs = try std.BoundedArray([*c]dx.ID3D11RenderTargetView, 16).init(0);
	g_ds = swapchain.dsv;
	try g_rtvs.append(swapchain.rtv);
	setViewport(0, 0, swapchain.w, swapchain.h);
}

pub fn draw(index_buffer: ?Buffer, num_vertices: u32, num_instances: u32, index_buffer_offset: u32) void {
	if (index_buffer) |ib| {
		g_device_context.*.lpVtbl.*.IASetIndexBuffer.?(g_device_context, ib.buffer, g_index_type.toDXGI(), 0);
	}
	else {
		g_device_context.*.lpVtbl.*.IASetIndexBuffer.?(g_device_context, null, dx.DXGI_FORMAT_UNKNOWN, 0);
	}
	g_device_context.*.lpVtbl.*.DrawIndexedInstanced.?(g_device_context, num_vertices, num_instances, index_buffer_offset, 0, 0);
}

const AttributeType = enum(u8) {
	U8,
	FLOAT,
	I16,
	I8
};

pub const AttributeFlags = packed struct (u8) {
	int: bool = false,
	instanced: bool = false,

	_ : u6 = undefined
};

pub const Attribute = struct {
	byte_offset: u8,
	num_components: u3,
	type: AttributeType,
	flags: AttributeFlags,

	pub fn byteSize(self: @This()) u32 {
		const s: u32 = switch (self.type) {
			.FLOAT => @sizeOf(f32),
			.I16 => @sizeOf(i16),
			.I8 => @sizeOf(i8),
			.U8 => @sizeOf(u8),
		};
		return self.num_components * s;
	}
};

pub const VertexLayout = struct {
	const Self = @This();

	attributes: [8]Attribute = undefined,
	count: u8 = 0,

	pub fn computeStride(self: Self) u32 {
		var res: u32 = 0;
		for (0..self.count) |i| {
			res = @max(res, self.attributes[i].byte_offset + self.attributes[i].byteSize());
		}
		return res;
	}

	pub fn addAttribute(self: *Self, attr: Attribute) void {
		if (self.count == self.attributes.len) @panic("No space for another attribute");
		self.attributes[self.count] = attr;
		self.count += 1;
	}
};

pub const IndexType = enum(u8) {
	U16,
	U32,

	pub fn toDXGI(self: @This()) dx.DXGI_FORMAT {
		switch (self) {
			.U16 => return dx.DXGI_FORMAT_R16_UINT,
			.U32 => return dx.DXGI_FORMAT_R32_UINT,
		}
	} 

	pub fn fromType(comptime t: type) IndexType {
		switch (t) {
			u16 => return IndexType.U16,
			u32 => return IndexType.U32,
			else => @panic("Unknown")
		}
	}
};

pub const Pipeline = struct {
	topology: dx.D3D11_PRIMITIVE_TOPOLOGY,
	index_type: IndexType,
	input_layout: [*c]dx.ID3D11InputLayout,
	vertex_shader: [*c]dx.ID3D11VertexShader,
	fragment_shader: [*c]dx.ID3D11PixelShader = null,
	depth_stencil_state: [*c]dx.ID3D11DepthStencilState = null,
	rasterizer_state: [*c]dx.ID3D11RasterizerState = null,
	blend_state: [*c]dx.ID3D11BlendState = null,
};

pub const CullMode = enum {
	BACK,
	FRONT,
	NONE
};

pub const DepthTestFunction = enum {
	ALWAYS,
	GREATER,
	EQUAL,
};

pub const Blend = enum {
	ZERO,
	ONE,
	SRC_COLOR,
	INV_SRC_COLOR,
	SRC_ALPHA,
	INV_SRC_ALPHA,
	DEST_ALPHA,
	INV_DEST_ALPHA,
	DEST_COLOR,
	INV_DEST_COLOR,
	SRC_ALPHA_SAT,
	BLEND_FACTOR,
	INV_BLEND_FACTOR,
	SRC1_COLOR,
	INV_SRC1_COLOR,
	SRC1_ALPHA,
	INV_SRC1_ALPHA,

	pub fn toDX(self: @This()) dx.D3D11_BLEND {
		return switch(self) {
			.ZERO => dx.D3D11_BLEND_ZERO,
			.ONE => dx.D3D11_BLEND_ONE,
			.SRC_COLOR => dx.D3D11_BLEND_SRC_COLOR,
			.INV_SRC_COLOR => dx.D3D11_BLEND_INV_SRC_COLOR,
			.SRC_ALPHA => dx.D3D11_BLEND_SRC_ALPHA,
			.INV_SRC_ALPHA => dx.D3D11_BLEND_INV_SRC_ALPHA,
			.DEST_ALPHA => dx.D3D11_BLEND_DEST_ALPHA,
			.INV_DEST_ALPHA => dx.D3D11_BLEND_INV_DEST_ALPHA,
			.DEST_COLOR => dx.D3D11_BLEND_DEST_COLOR,
			.INV_DEST_COLOR => dx.D3D11_BLEND_INV_DEST_COLOR,
			.SRC_ALPHA_SAT => dx.D3D11_BLEND_SRC_ALPHA_SAT,
			.BLEND_FACTOR => dx.D3D11_BLEND_BLEND_FACTOR,
			.INV_BLEND_FACTOR => dx.D3D11_BLEND_INV_BLEND_FACTOR,
			.SRC1_COLOR => dx.D3D11_BLEND_SRC1_COLOR,
			.INV_SRC1_COLOR => dx.D3D11_BLEND_INV_SRC1_COLOR,
			.SRC1_ALPHA => dx.D3D11_BLEND_SRC1_ALPHA,
			.INV_SRC1_ALPHA => dx.D3D11_BLEND_INV_SRC1_ALPHA
		};
	}
};

pub const PipelineDesc = struct {
	vertex_shader: [:0]const u8,
	fragment_shader: [:0]const u8,
	index_type: IndexType,
	layout: VertexLayout,
	topology: PrimiteTopology,
	cull: CullMode = .BACK,
	wireframe: bool = false,
	scissor_enable: bool = false,
	depth_write: bool = true,
	depth_test_function: DepthTestFunction = .GREATER,
	blend_enabled: bool = false,
	src_blend: Blend = undefined,
	dst_blend: Blend = undefined,
	src_alpha_blend: Blend = undefined,
	dst_alpha_blend: Blend = undefined,
};

pub const PrimiteTopology = enum(u8) {
	TRIANGLES,
	TRIANGLE_STRIP,
	LINES,
	POINTS,

	pub fn toDXGI(self: @This()) dx.D3D11_PRIMITIVE_TOPOLOGY {
		switch(self) {
			.TRIANGLES => return dx.D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST,
			.TRIANGLE_STRIP => return dx.D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP,
			.LINES => return dx.D3D_PRIMITIVE_TOPOLOGY_LINELIST,
			.POINTS => return dx.D3D_PRIMITIVE_TOPOLOGY_POINTLIST,
		}
	}
};

fn u16len(val: [*c]const u16) usize {
	var res: usize = 0;
	var c = val;	
	while (c.* != 0) {
		res += 1;
		c += 1;
	}
	return res;
}

fn compile(src: [:0]const u8, target: [:0]const u8) [*c]dx.ID3DBlob {
	var output: [*c]dx.ID3DBlob = undefined;
	var errors: [*c]dx.ID3DBlob = undefined;
	const hr = g_d3dcompile(src.ptr,
		src.len,
		"shader name",
		null,
		null,
		"main",
		target,
		dx.D3DCOMPILE_PACK_MATRIX_COLUMN_MAJOR | dx.D3DCOMPILE_DEBUG,
		0,
		&output,
		&errors);
	if (errors != null) {
		const msg = errors.*.lpVtbl.*.GetBufferPointer.?(errors);
		// TODO msg
		
		var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
		var alloc = arena.allocator();
		var slice: []const u16 = undefined;
		slice.ptr = @alignCast(@ptrCast(msg));
		slice.len = u16len(slice.ptr);
		const utf8string = std.unicode.utf16leToUtf8Alloc(alloc, slice) catch @panic("Failed to get error msg");
		if (hr != 0) @panic(utf8string);
		_ = errors.*.lpVtbl.*.Release.?(errors);
		if (hr != 0) return null;
	}

	return output;
}

fn createVS(src: [:0]const u8, layout: VertexLayout) struct {
	shader: [*c]dx.ID3D11VertexShader,
	layout: [*c]dx.ID3D11InputLayout
} {
	const blob = compile(src, "vs_5_0");
	const ptr = blob.*.lpVtbl.*.GetBufferPointer.?(blob);
	const len = blob.*.lpVtbl.*.GetBufferSize.?(blob);
	var vs: [*c]dx.ID3D11VertexShader = undefined;
	const hr = g_device.*.lpVtbl.*.CreateVertexShader.?(g_device, ptr, len, null, &vs);
	if (hr != 0) @panic("Failed to create vertex shader");

	var descs: [16]dx.D3D11_INPUT_ELEMENT_DESC = undefined;
	for (0..layout.count) |i| {
		const attr = layout.attributes[i];
		descs[i].AlignedByteOffset = attr.byte_offset;
		descs[i].Format = getDXGIFormat(attr);
		descs[i].SemanticIndex = @intCast(i);
		descs[i].SemanticName = "TEXCOORD";
		descs[i].InputSlot = if (attr.flags.instanced) 1 else 0;
		descs[i].InputSlotClass = if (attr.flags.instanced) dx.D3D11_INPUT_PER_INSTANCE_DATA else dx.D3D11_INPUT_PER_VERTEX_DATA; 
		descs[i].InstanceDataStepRate = if (attr.flags.instanced) 1 else 0;
	}

	var input_layout: [*c]dx.ID3D11InputLayout = null;
	if (ptr != null and layout.count > 0) {
		const hr4 = g_device.*.lpVtbl.*.CreateInputLayout.?(g_device, &descs, layout.count, ptr, len, &input_layout);
		if (hr4 != 0) @panic("Failed to create input layout");
	}

	const hr5 = blob.*.lpVtbl.*.Release.?(blob);
	if (hr5 != 0) @panic("Failed to release bytecode");
	return .{
		.shader = vs,
		.layout = input_layout
	};
}

fn createFS(src: [:0]const u8) [*c]dx.ID3D11PixelShader {
	var blob = compile(src, "ps_5_0");
	const ptr = blob.*.lpVtbl.*.GetBufferPointer.?(blob);
	const len = blob.*.lpVtbl.*.GetBufferSize.?(blob);
	var ps: [*c]dx.ID3D11PixelShader = undefined;
	const hr = g_device.*.lpVtbl.*.CreatePixelShader.?(g_device, ptr, len, null, &ps);
	if (hr != 0) @panic("Failed to create pixel shader");	
	const hr2 = blob.*.lpVtbl.*.Release.?(blob);
	if (hr2 != 0) @panic("Failed to release bytecode");	
	return ps;
}

fn getDXGIFormat(attr: Attribute) dx.DXGI_FORMAT {
	const as_int = attr.flags.int;
	switch (attr.type) {
		.FLOAT => return switch (attr.num_components) {
				1 => dx.DXGI_FORMAT_R32_FLOAT,
				2 => dx.DXGI_FORMAT_R32G32_FLOAT,
				3 => dx.DXGI_FORMAT_R32G32B32_FLOAT,
				4 => dx.DXGI_FORMAT_R32G32B32A32_FLOAT,
				else => @panic("Unexpected value")
			},
		.I8 => return switch(attr.num_components) {
				1 => if (as_int) dx.DXGI_FORMAT_R8_SINT else dx.DXGI_FORMAT_R8_SNORM,
				2 => if (as_int) dx.DXGI_FORMAT_R8G8_SINT else dx.DXGI_FORMAT_R8G8_SNORM,
				4 => if (as_int) dx.DXGI_FORMAT_R8G8B8A8_SINT else dx.DXGI_FORMAT_R8G8B8A8_SNORM,
				else => @panic("Unexpected value")
			},
		.U8 => return switch(attr.num_components) {
				1 => if (as_int) dx.DXGI_FORMAT_R8_UINT else dx.DXGI_FORMAT_R8_UNORM,
				2 => if (as_int) dx.DXGI_FORMAT_R8G8_UINT else dx.DXGI_FORMAT_R8G8_UNORM,
				4 => if (as_int) dx.DXGI_FORMAT_R8G8B8A8_UINT else dx.DXGI_FORMAT_R8G8B8A8_UNORM,
				else => @panic("Unexpected value")
			},
		.I16 => return switch(attr.num_components) {
				4 => if (as_int) dx.DXGI_FORMAT_R16G16B16A16_SINT else dx.DXGI_FORMAT_R16G16B16A16_SNORM,
				else => @panic("Unexpected value")
			}
	}
	@panic("Unknown format");
}

pub fn setViewport(x: u32, y: u32, w: u32, h: u32) void {
	var vp: dx.D3D11_VIEWPORT = std.mem.zeroes(dx.D3D11_VIEWPORT);
	vp.Width =  @floatFromInt(w);
	vp.Height = @floatFromInt(h);
	vp.MinDepth = 0.0;
	vp.MaxDepth = 1.0;
	vp.TopLeftX = @floatFromInt(x);
	vp.TopLeftY = @floatFromInt(y);
	g_device_context.*.lpVtbl.*.RSSetViewports.?(g_device_context, 1, &vp);
}

pub fn createPipeline(desc: PipelineDesc) Pipeline {
	var blend_desc:dx.D3D11_BLEND_DESC = .{};
	var rasterizer_desc:dx.D3D11_RASTERIZER_DESC = .{};
	var depth_stencil_desc: dx.D3D11_DEPTH_STENCIL_DESC = .{};
		
	rasterizer_desc.CullMode = switch(desc.cull) {
		.BACK => dx.D3D11_CULL_BACK,
		.FRONT => dx.D3D11_CULL_FRONT,
		.NONE => dx.D3D11_CULL_NONE
	};

	rasterizer_desc.FrontCounterClockwise = dx.TRUE;
	rasterizer_desc.FillMode = if (desc.wireframe) dx.D3D11_FILL_WIREFRAME else dx.D3D11_FILL_SOLID;
	rasterizer_desc.ScissorEnable = if (desc.scissor_enable) dx.TRUE else dx.FALSE;
	rasterizer_desc.DepthClipEnable = dx.FALSE;

	depth_stencil_desc.DepthEnable = if (desc.depth_test_function != .ALWAYS) dx.TRUE else dx.FALSE;
	depth_stencil_desc.DepthWriteMask = if (desc.depth_write) dx.D3D11_DEPTH_WRITE_MASK_ALL else dx.D3D11_DEPTH_WRITE_MASK_ZERO;
	
	depth_stencil_desc.DepthFunc = switch (desc.depth_test_function) {
		.GREATER => dx.D3D11_COMPARISON_GREATER,
		.EQUAL => dx.D3D11_COMPARISON_EQUAL,
		.ALWAYS => dx.D3D11_COMPARISON_ALWAYS,
	};

	//const StencilFuncs func = (StencilFuncs)((u64(state) >> 31) & 0xf);
	//depth_stencil_desc.StencilEnable = func != StencilFuncs::DISABLE; 
	//if(depth_stencil_desc.StencilEnable) {
//
	//	depth_stencil_desc.StencilReadMask = u8(u64(state) >> 43);
	//	depth_stencil_desc.StencilWriteMask = u8(u64(state) >> 23);
	//	D3D11_COMPARISON_FUNC dx_func;
	//	switch(func) {
	//		case StencilFuncs::ALWAYS: dx_func = D3D11_COMPARISON_ALWAYS; break;
	//		case StencilFuncs::EQUAL: dx_func = D3D11_COMPARISON_EQUAL; break;
	//		case StencilFuncs::NOT_EQUAL: dx_func = D3D11_COMPARISON_NOT_EQUAL; break;
	//		case StencilFuncs::DISABLE: ASSERT(false); break;
	//	}
	//	auto toDXOp = [](StencilOps op) {
	//		constexpr D3D11_STENCIL_OP table[] = {
	//			D3D11_STENCIL_OP_KEEP,
	//			D3D11_STENCIL_OP_ZERO,
	//			D3D11_STENCIL_OP_REPLACE,
	//			D3D11_STENCIL_OP_INCR_SAT,
	//			D3D11_STENCIL_OP_DECR_SAT,
	//			D3D11_STENCIL_OP_INVERT,
	//			D3D11_STENCIL_OP_INCR,
	//			D3D11_STENCIL_OP_DECR
	//		};
	//		return table[(int)op];
	//	};
	//	const D3D11_STENCIL_OP sfail = toDXOp(StencilOps((u64(state) >> 51) & 0xf));
	//	const D3D11_STENCIL_OP zfail = toDXOp(StencilOps((u64(state) >> 55) & 0xf));
	//	const D3D11_STENCIL_OP zpass = toDXOp(StencilOps((u64(state) >> 59) & 0xf));
//
	//	depth_stencil_desc.FrontFace.StencilFailOp = sfail;
	//	depth_stencil_desc.FrontFace.StencilDepthFailOp = zfail;
	//	depth_stencil_desc.FrontFace.StencilPassOp = zpass;
	//	depth_stencil_desc.FrontFace.StencilFunc = dx_func;
//
	//	depth_stencil_desc.BackFace.StencilFailOp = sfail;
	//	depth_stencil_desc.BackFace.StencilDepthFailOp = zfail;
	//	depth_stencil_desc.BackFace.StencilPassOp = zpass;
	//	depth_stencil_desc.BackFace.StencilFunc = dx_func;
	//}

	//u16 blend_bits = u16(u64(state) >> 7);
//
	//auto to_dx = [&](BlendFactors factor) -> D3D11_BLEND {
	//	static const D3D11_BLEND table[] = {
	//		D3D11_BLEND_ZERO,
	//		D3D11_BLEND_ONE,
	//		D3D11_BLEND_SRC_COLOR,
	//		D3D11_BLEND_INV_SRC_COLOR,
	//		D3D11_BLEND_SRC_ALPHA,
	//		D3D11_BLEND_INV_SRC_ALPHA,
	//		D3D11_BLEND_DEST_COLOR,
	//		D3D11_BLEND_INV_DEST_COLOR,
	//		D3D11_BLEND_DEST_ALPHA,
	//		D3D11_BLEND_INV_DEST_ALPHA,
	//		D3D11_BLEND_SRC1_COLOR,
	//		D3D11_BLEND_INV_SRC1_COLOR,
	//		D3D11_BLEND_SRC1_ALPHA,
	//		D3D11_BLEND_INV_SRC1_ALPHA,
	//	};
	//	ASSERT((u32)factor < lengthOf(table));
	//	return table[(int)factor];
	//};
//
	for(&blend_desc.RenderTarget) |*x| {
		if (desc.blend_enabled) {
			x.BlendEnable = dx.TRUE;
			blend_desc.AlphaToCoverageEnable = dx.FALSE;
			x.SrcBlend = desc.src_blend.toDX();
			x.DestBlend = desc.dst_blend.toDX();
			x.BlendOp = dx.D3D11_BLEND_OP_ADD;
			x.SrcBlendAlpha = desc.src_alpha_blend.toDX();
			x.DestBlendAlpha = desc.dst_alpha_blend.toDX();
			x.BlendOpAlpha = dx.D3D11_BLEND_OP_ADD;
			x.RenderTargetWriteMask = dx.D3D11_COLOR_WRITE_ENABLE_ALL;
		}
		else {
			x.BlendEnable = dx.FALSE;
			x.SrcBlend = dx.D3D11_BLEND_SRC_ALPHA;
			x.DestBlend = dx.D3D11_BLEND_INV_SRC_ALPHA;
			x.BlendOp = dx.D3D11_BLEND_OP_ADD;
			x.SrcBlendAlpha = dx.D3D11_BLEND_SRC_ALPHA;
			x.DestBlendAlpha = dx.D3D11_BLEND_INV_SRC_ALPHA;
			x.BlendOpAlpha = dx.D3D11_BLEND_OP_ADD;
			x.RenderTargetWriteMask = dx.D3D11_COLOR_WRITE_ENABLE_ALL;
		}
	}
	
	var depth_stencil_state: [*c]dx.ID3D11DepthStencilState = undefined;
	var rasterizer_state: [*c]dx.ID3D11RasterizerState = undefined;
	var blend_state: [*c]dx.ID3D11BlendState = undefined;

	const hr = g_device.*.lpVtbl.*.CreateDepthStencilState.?(g_device, &depth_stencil_desc, &depth_stencil_state);
	if (hr != 0) @panic("Failed to create depth stencil state");
	const hr2 = g_device.*.lpVtbl.*.CreateRasterizerState.?(g_device, &rasterizer_desc, &rasterizer_state);
	if (hr2 != 0) @panic("Failed to create rasterizer state");
	const hr3 = g_device.*.lpVtbl.*.CreateBlendState.?(g_device, &blend_desc, &blend_state);
	if (hr3 != 0) @panic("Failed to create blend state");

	var vs = createVS(desc.vertex_shader, desc.layout);

	const pipeline: Pipeline = .{
		.vertex_shader = vs.shader,
		.fragment_shader = createFS(desc.fragment_shader),
		.index_type = desc.index_type,
		.topology = desc.topology.toDXGI(),
		.depth_stencil_state = depth_stencil_state,
		.rasterizer_state = rasterizer_state,
		.blend_state = blend_state,
		.input_layout = vs.layout
	};
	return pipeline;
}

pub fn init() !void {
	var create_flags: c_uint = dx.D3D11_CREATE_DEVICE_DEBUG;

	var res = dx.D3D11CreateDevice(null, dx.D3D_DRIVER_TYPE_HARDWARE, null, create_flags, null, 0, dx.D3D11_SDK_VERSION, &g_device, null, &g_device_context);
	
	if (res != 0) {
		// debug layer might not be installed on system, try without it
		create_flags = create_flags & ~@as(c_uint, dx.D3D11_CREATE_DEVICE_DEBUG);
		res = dx.D3D11CreateDevice(null, dx.D3D_DRIVER_TYPE_HARDWARE, null, create_flags, null, 0, dx.D3D11_SDK_VERSION, &g_device, null, &g_device_context);
		if (res != 0) return DXError;
	}

	var dlls: [5][*c]const u8 = .{
		"D3DCompiler_47.dll", "D3DCompiler_46.dll", "D3DCompiler_45.dll", "D3DCompiler_44.dll", "D3DCompiler_43.dll"
	};

	for (dlls) |dll_name| {
		var dll = dx.LoadLibraryA(dll_name);
		if (dll != null) {
			g_d3dcompile = @ptrCast(dx.GetProcAddress(dll, "D3DCompile"));
			break;
		}
	}

}

pub fn createSwapchain(window_handle: WindowHandle) !Swapchain {
	var factory: [*c]dx.IDXGIFactory1 = null;
	const hr = dx.CreateDXGIFactory1(&dx.IID_IDXGIFactory, @ptrCast(&factory));
	if (hr != 0) return DXError;

	var desc: dx.DXGI_SWAP_CHAIN_DESC = .{
		.BufferDesc = .{ 
			.Width = 640,
			.Height = 480,
			.Format = dx.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
			.RefreshRate = .{
				.Numerator = 60,
				.Denominator = 1
			}
		},
		.OutputWindow = window_handle,
		.Windowed = 1,
		.SwapEffect = dx.DXGI_SWAP_EFFECT_DISCARD,
		.BufferCount = 1,
		.SampleDesc = .{
			.Count = 1,
			.Quality = 0,
		},
		.Flags = dx.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH,
		.BufferUsage = dx.DXGI_USAGE_RENDER_TARGET_OUTPUT
	};
	var res: Swapchain = .{
		.w = 640,
		.h = 480
	};
	const hr2 = factory.*.lpVtbl.*.CreateSwapChain.?(factory, @ptrCast(g_device), &desc, &res.swapchain);
	if (hr2 != 0) return DXError;

	var rt: [*c]dx.ID3D11Texture2D = undefined;
	const hr3 = res.swapchain.*.lpVtbl.*.GetBuffer.?(res.swapchain, 0, &dx.IID_ID3D11Texture2D, @ptrCast(&rt));
	if (hr3 != 0) return DXError;

	const rt_desc: dx.D3D11_RENDER_TARGET_VIEW_DESC = .{
		.Format = dx.DXGI_FORMAT_R8G8B8A8_UNORM,
		.ViewDimension = dx.D3D11_RTV_DIMENSION_TEXTURE2D,
		.unnamed_0 = .{
			.Texture2D = .{
				.MipSlice = 0
			}
		}
	};
	const hr4 = g_device.*.lpVtbl.*.CreateRenderTargetView.?(g_device, @ptrCast(rt), &rt_desc, &res.rtv);
	if (hr4 != 0) return DXError;
	
	var ds_desc: dx.D3D11_TEXTURE2D_DESC = std.mem.zeroes(dx.D3D11_TEXTURE2D_DESC);
	ds_desc.Width = 640;
	ds_desc.Height = 480;
	ds_desc.MipLevels = 1;
	ds_desc.ArraySize = 1;
	ds_desc.Format = dx.DXGI_FORMAT_D24_UNORM_S8_UINT;
	ds_desc.SampleDesc = .{ .Count = 1, .Quality = 0 };
	ds_desc.Usage = dx.D3D11_USAGE_DEFAULT;
	ds_desc.BindFlags = dx.D3D11_BIND_DEPTH_STENCIL;

	var ds: [*c]dx.ID3D11Texture2D = undefined;
	var hr5 = g_device.*.lpVtbl.*.CreateTexture2D.?(g_device, &ds_desc, null, &ds);
	if (hr5 != 0) return DXError;

	var dsv_desc: dx.D3D11_DEPTH_STENCIL_VIEW_DESC = std.mem.zeroes(dx.D3D11_DEPTH_STENCIL_VIEW_DESC);
	dsv_desc.Format = ds_desc.Format;
	dsv_desc.ViewDimension = dx.D3D11_DSV_DIMENSION_TEXTURE2D;

	var hr6 = g_device.*.lpVtbl.*.CreateDepthStencilView.?(g_device, @ptrCast(ds), &dsv_desc, &res.dsv);
	if (hr6 != 0) return DXError;

	return res;
}

pub fn shutdown() void {
	_ = g_device_context.*.lpVtbl.*.Release.?(g_device_context);
	_ = g_device.*.lpVtbl.*.Release.?(g_device);
}

test {
	var it = IndexType.fromType(u8);
	_ = it;

	try init();
	_ = try createSwapchain(null);
	shutdown();
}