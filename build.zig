const std = @import("std");
const glfw = @import("libs/mach/glfw/build.zig");
const gpu_dawn = @import("libs/mach/gpu-dawn/build.zig");
const gpu = @import("libs/mach/gpu/build.zig");
const Pkg = std.build.Pkg;

pub const Options = struct {
    glfw_options: glfw.Options = .{},
    gpu_dawn_options: gpu_dawn.Options = .{},
    gpu_options: gpu.Options = .{},
};

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("dusk", "src/main.zig");

    const gpu_dawn_options = gpu_dawn.Options{
        .from_source = b.option(bool, "dawn-from-source", "Build Dawn from source") orelse false,
    };

    const options = Options{
        .gpu_dawn_options = gpu_dawn_options,
    };

    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.addPackage(glfw.pkg);

    // This `gpu-dawn` package has no such thing as `std.build.Pkg`,
    // presumably because `gpu-dawn` just builds Dawn (Google Chrome's WebGPU implementation).
    //
    // Even so, I'll leave it here just for the sake of understanding what's going on here.
    //     - princessakokosowa, 15 June 2022
    //
    // exe.addPackage(gpu_dawn.pkg);

    exe.addPackage(gpu.pkg);

    glfw.link(exe.builder, exe, options.glfw_options);
    gpu_dawn.link(exe.builder, exe, options.gpu_dawn_options);
    gpu.link(exe.builder, exe, options.gpu_options);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
