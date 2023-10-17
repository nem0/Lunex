pub usingnamespace @cImport({
    //@cDefine("SOKOL_GLCORE33", {});   
    //@cDefine("SOKOL_IMGUI_NO_SOKOL_APP", {});   
    //@cDefine("SOKOL_TRACE_HOOKS", {});   
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", {});   
    @cInclude("cimgui.h");
    @cInclude("sokol_gfx.h");
    @cInclude("util/sokol_imgui.h");    
    @cInclude("util/sokol_gfx_imgui.h");
    @cInclude("GLFW/glfw3.h");
});

