const std = @import("std");
const glfw = @import("glfw");
const gpu = @import("gpu");

const c = @import("c.zig").c;

const objc = @cImport({
    @cInclude("objc/message.h");
});

const Context = @This();

window: glfw.Window,
surface: gpu.Surface,

native_instance: gpu.NativeInstance,
adapter_type: gpu.Adapter.Type,
backend_type: gpu.Adapter.BackendType,
device: gpu.Device,
queue: gpu.Queue,
swap_chain: gpu.SwapChain,
swap_chain_descriptor: gpu.SwapChain.Descriptor,

pub const texture_format: gpu.Texture.Format = gpu.Texture.Format.bgra8_unorm;

// @NOTE
// For the time being, so far, all I care about is using this WebGPU implementation in the context
// of a wrapper on the native APIs for portability.
//
// Most likely, I won't be particularly interested in its Web-related capabilities itself in the
// near future.
//     - princessakokosowa, 20 June 2022

pub fn init() !Context {
    // glfw.setErrorCallback(/* to be defined */);
    try glfw.init(.{});

    const hints = getHints();

    // @TODO
    // Decide whether `window` should be created inside of `Context` or outside of it. For the
    // time being, let it be this way unless I change my mind.
    //     - princessakokosowa, 20 June 2022
    const window = try glfw.Window.create(800, 600, "dusk", null, null, hints);
    // const window_size = try window.getSize();
    const framebuffer_size = try window.getFramebufferSize();

    const backend_procs = c.machDawnNativeGetProcs();
    c.dawnProcSetProcs(backend_procs);

    const dummy_native_instance = c.machDawnNativeInstance_init();

    // @NOTE
    // If this program were ever to target OpenGL, this has to be wrapped somehow.
    //     - princessakokosowa, 20 June 2022
    c.machDawnNativeInstance_discoverDefaultAdapters(dummy_native_instance);
    var native_instance = gpu.NativeInstance.wrap(c.machDawnNativeInstance_get(dummy_native_instance).?);

    const interface = native_instance.interface();
    const adapter = switch (interface.waitForAdapter(&.{
        .power_preference = .high_performance,
    })) {
        .adapter => |v| v,
        .err => |err| {
            std.debug.print("Oops, failed to get adapter, details:\n", .{});
            std.debug.print("    code    : {}\n", .{ err.code });
            std.debug.print("    message : {s}\n", .{ err.message });

            return error.GraphicsAdapterNotFound;
        },
    };

    const properties = adapter.properties;

    std.debug.print("High-performance device has been found, details:\n", .{});
    std.debug.print("    name         : {s}\n", .{ properties.name });
    std.debug.print("    driver       : {s}\n", .{ properties.driver_description });
    std.debug.print("    adapter type : {s}\n", .{ gpu.Adapter.typeName(properties.adapter_type) });
    std.debug.print("    backend type : {s}\n", .{ gpu.Adapter.backendTypeName(properties.backend_type) });

    const device = switch (adapter.waitForDevice(&.{})) {
        .device => |v| v,
        .err => |err| {
            std.debug.print("Oops, failed to get device, details:\n", .{});
            std.debug.print("    code    : {}\n", .{ err.code });
            std.debug.print("    message : {s}\n", .{ err.message });

            return error.DeviceNotFound;
        },
    };

    const surface = createSurfaceForWindow(&native_instance, window, comptime detectGlfwOptions());
    const swap_chain_descriptor: gpu.SwapChain.Descriptor = .{
        .label = "main window swap chain",
        .usage = .{
            .render_attachment = true
        },
        .format = texture_format,
        .width = framebuffer_size.width,
        .height = framebuffer_size.height,
        .present_mode = .fifo,
        .implementation = 0,
    };

    const swap_chain = device.nativeCreateSwapChain(
        surface,
        &swap_chain_descriptor,
    );

    return Context{
        .window = window,
        .surface = surface,

        .native_instance = native_instance,
        .adapter_type = properties.adapter_type,
        .backend_type = properties.backend_type,
        .device = device,
        .queue = device.getQueue(),
        .swap_chain = swap_chain,
        .swap_chain_descriptor = swap_chain_descriptor,
    };
}

pub fn deinit(context: *Context) void {
    context.swap_chain.release();
    context.queue.release();
    context.device.release();

    // @TODO
    // How do I release this?
    //     - princessakokosowa, 15 June 2022
    //
    // context.native_instance.release();

    context.surface.release();
    glfw.terminate();
}
fn getHints() glfw.Window.Hints {
    return .{
        .client_api = .no_api,
        .cocoa_retina_framebuffer = true,
    };
}

fn detectGlfwOptions() glfw.BackendOptions {
    const target = @import("builtin").target;
    if (target.isDarwin()) return .{ .cocoa = true };
    return switch (target.os.tag) {
        .windows => .{ .win32 = true },
        .linux => .{ .x11 = true },
        else => .{},
    };
}

fn createSurfaceForWindow(
    native_instance: *const gpu.NativeInstance,
    window: glfw.Window,
    comptime glfw_options: glfw.BackendOptions,
) gpu.Surface {
    const glfw_native = glfw.Native(glfw_options);
    const descriptor = if (glfw_options.win32) gpu.Surface.Descriptor{
        .windows_hwnd = .{
            .label = "basic surface",
            .hinstance = std.os.windows.kernel32.GetModuleHandleW(null).?,
            .hwnd = glfw_native.getWin32Window(window),
        },
    } else if (glfw_options.x11) gpu.Surface.Descriptor{
        .xlib = .{
            .label = "basic surface",
            .display = glfw_native.getX11Display(),
            .window = glfw_native.getX11Window(window),
        },
    } else if (glfw_options.cocoa) blk: {
        const ns_window = glfw_native.getCocoaWindow(window);
        const ns_view = msgSend(ns_window, "contentView", .{}, *anyopaque); // [nsWindow contentView]

        // Create a CAMetalLayer that covers the whole window that will be passed to CreateSurface.
        msgSend(ns_view, "setWantsLayer:", .{true}, void); // [view setWantsLayer:YES]
        const layer = msgSend(objc.objc_getClass("CAMetalLayer"), "layer", .{}, ?*anyopaque); // [CAMetalLayer layer]
        if (layer == null) @panic("failed to create Metal layer");
        msgSend(ns_view, "setLayer:", .{layer.?}, void); // [view setLayer:layer]

        // Use retina if the window was created with retina support.
        const scale_factor = msgSend(ns_window, "backingScaleFactor", .{}, f64); // [ns_window backingScaleFactor]
        msgSend(layer.?, "setContentsScale:", .{scale_factor}, void); // [layer setContentsScale:scale_factor]

        break :blk gpu.Surface.Descriptor{
            .metal_layer = .{
                .label = "basic surface",
                .layer = layer.?,
            },
        };
    } else if (glfw_options.wayland) {
        @panic("Dawn does not yet have Wayland support, see https://bugs.chromium.org/p/dawn/issues/detail?id=1246&q=surface&can=2");
    } else unreachable;

    return native_instance.createSurface(&descriptor);
}

// Borrowed from https://github.com/hazeycode/zig-objcrt
fn msgSend(obj: anytype, sel_name: [:0]const u8, args: anytype, comptime ReturnType: type) ReturnType {
    const args_meta = @typeInfo(@TypeOf(args)).Struct.fields;

    const FnType = switch (args_meta.len) {
        0 => fn (@TypeOf(obj), objc.SEL) callconv(.C) ReturnType,
        1 => fn (@TypeOf(obj), objc.SEL, args_meta[0].field_type) callconv(.C) ReturnType,
        2 => fn (@TypeOf(obj), objc.SEL, args_meta[0].field_type, args_meta[1].field_type) callconv(.C) ReturnType,
        3 => fn (@TypeOf(obj), objc.SEL, args_meta[0].field_type, args_meta[1].field_type, args_meta[2].field_type) callconv(.C) ReturnType,
        4 => fn (@TypeOf(obj), objc.SEL, args_meta[0].field_type, args_meta[1].field_type, args_meta[2].field_type, args_meta[3].field_type) callconv(.C) ReturnType,
        else => @compileError("Unsupported number of args"),
    };

    // NOTE: func is a var because making it const causes a compile error which I believe is a compiler bug
    var func = @ptrCast(FnType, objc.objc_msgSend);
    const sel = objc.sel_getUid(sel_name);

    return @call(.{}, func, .{ obj, sel } ++ args);
}
