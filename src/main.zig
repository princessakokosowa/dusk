const std = @import("std");
const gpu = @import("gpu");

pub const c = @cImport({
    @cInclude("dawn/webgpu.h");
    @cInclude("dawn/dawn_proc.h");
    @cInclude("dawn_native_mach.h");
});

pub fn main() !void {
    c.dawnProcSetProcs(c.machDawnNativeGetProcs());
    var instance = c.machDawnNativeInstance_init();
    c.machDawnNativeInstance_discoverDefaultAdapters(instance);

    var native_instance = gpu.NativeInstance.wrap(c.machDawnNativeInstance_get(instance).?);
    const interface = native_instance.interface();
    const adapter = switch (interface.waitForAdapter(&.{
        .power_preference = .high_performance,
    })) {
        .adapter => |v| v,
        .err => |err| {
            std.debug.print("Oops, failed to get adapter, details:\n", .{});
            std.debug.print("    code    : {}\n", .{ err.code });
            std.debug.print("    message : {s}\n", .{ err.message });

            return error.NoGraphicsAdapter;
        },
    };

    const properties = adapter.properties;

    std.debug.print("High-performance device has been found, details:\n", .{});
    std.debug.print("    name         : {s}\n", .{ properties.name });
    std.debug.print("    driver       : {s}\n", .{ properties.driver_description });
    std.debug.print("    adapter type : {s}\n", .{ gpu.Adapter.typeName(properties.adapter_type) });
    std.debug.print("    backend type : {s}\n", .{ gpu.Adapter.backendTypeName(properties.backend_type) });
}
