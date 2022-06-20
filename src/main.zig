const glfw = @import("glfw");

const Application = @import("Application.zig");

pub fn main() !void {
    var application = try Application.init();
    defer application.deinit();

    while (!application.context.window.shouldClose()) {
        try glfw.pollEvents();

        application.update();
    }
}
