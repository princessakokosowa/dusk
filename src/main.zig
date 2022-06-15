const std = @import("std");
const glfw = @import("glfw");
const gpu = @import("gpu");

pub const c = @cImport({
    @cInclude("dawn/webgpu.h");
    @cInclude("dawn/dawn_proc.h");
    @cInclude("dawn_native_mach.h");
});

const Context = struct {
    window: glfw.Window,
    native_instance: gpu.NativeInstance,
    adapter_type: gpu.Adapter.Type,
    backend_type: gpu.Adapter.BackendType,
    device: gpu.Device,

    const Self = @This();

    pub fn init(window: glfw.Window) !Self {
        const backend_procs = c.machDawnNativeGetProcs();
        c.dawnProcSetProcs(backend_procs);

        const dummy_native_instance = c.machDawnNativeInstance_init();
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

        return Self{
        //     ^^^^
        // That's very unfortunate.
        //     - princessakokosowa, 15 June 2022
            .window = window,
            .native_instance = native_instance,
            .adapter_type = properties.adapter_type,
            .backend_type = properties.backend_type,
            .device = device,
        };
    }

    pub fn deinit(self: Self) void {
        // @TODO
        // How do I release this?
        //     - princessakokosowa, 15 June 2022
        //
        // self.native_instance.release();

        self.device.release();
    }
};

pub fn main() !void {
    try glfw.init(.{});
    defer glfw.terminate();
    //         ^^^^^^^^^^^
    // That's also very unfortunate.
    //     - princessakokosowa, 15 June 2022

    const window = try glfw.Window.create(1280, 720, "dusk", null, null, .{
        .client_api = .no_api,
        .cocoa_retina_framebuffer = true,
    });

    var context = try Context.init(window);
    defer context.deinit();

    while (!window.shouldClose()) {
        try glfw.pollEvents();
    }
}
