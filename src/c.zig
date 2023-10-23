pub usingnamespace @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", {});   
    @cDefine("GLFW_EXPOSE_NATIVE_WIN32",{});
    @cInclude("cimgui.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
    @cInclude("d3d11_1.h");
    @cInclude("d3dcompiler.h");
});

