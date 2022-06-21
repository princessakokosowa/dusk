const std = @import("std");
const gpu = @import("gpu");

const Context = @import("Context.zig");

const Application = @This();

context: Context,
render_pipeline: gpu.RenderPipeline,
uniform_buffer: gpu.Buffer,
bind_group: gpu.BindGroup,

const UniformBufferObject = struct {
    colour: @Vector(4, f32),
};

pub fn init() !Application {
    var context = try Context.init();

    errorScopeBegin(context);

    const wgsl = @embedFile("triangle.wgsl");

    const vs_module = context.device.createShaderModule(&.{
        .label = "vertex shader",
        .code = .{
            .wgsl = wgsl,
        },
    });
    defer vs_module.release();

    const fs_module = context.device.createShaderModule(&.{
        .label = "fragment shader",
        .code = .{
            .wgsl = wgsl,
        },
    });
    defer fs_module.release();

    const blend = gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
    };

    const color_target = gpu.ColorTargetState{
        .format = Context.texture_format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMask.all,
    };

    const fragment = gpu.FragmentState{
        .module = fs_module,
        .entry_point = "fsMain",
        .targets = &.{
            color_target,
        },
        .constants = null,
    };

    const vertex = gpu.VertexState{
        .module = vs_module,
        .entry_point = "vsMain",
        .buffers = null,
    };

    const bind_group_layout_entry = gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0);
    const bind_group_layout = context.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor{
            .entries = &.{
                bind_group_layout_entry,
            },
        },
    );
    defer bind_group_layout.release();

    const bind_group_layouts = [_]gpu.BindGroupLayout{
        bind_group_layout
    };

    const pipeline_layout = context.device.createPipelineLayout(&.{
        .bind_group_layouts = &bind_group_layouts,
    });

    const render_pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .layout = pipeline_layout,
        .depth_stencil = null,
        .vertex = vertex,
        .multisample = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
            .alpha_to_coverage_enabled = false,
        },
        .primitive = .{
            .front_face = .ccw,
            .cull_mode = .none,
            .topology = .triangle_list,
            .strip_index_format = .none,
        },
    };

    const uniform_buffer = context.device.createBuffer(&.{
        .usage = .{
            .copy_dst = true,
            .uniform = true
        },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = false,
    });

    const bind_group = context.device.createBindGroup(
        &gpu.BindGroup.Descriptor{
            .layout = bind_group_layout,
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
            },
        },
    );

    var render_pipeline: gpu.RenderPipeline = context.device.createRenderPipeline(&render_pipeline_descriptor);

    try errorScopeEnd(context);

    return Application{
        .context = context,
        .render_pipeline = render_pipeline,
        .uniform_buffer = uniform_buffer,
        .bind_group = bind_group,
    };
}

pub fn deinit(application: *Application) void {
    application.bind_group.release();
    application.uniform_buffer.release();

    application.context.deinit();
}

pub fn update(application: *Application) void {
    const back_buffer_view = application.context.swap_chain.getCurrentTextureView();
    defer back_buffer_view.release();

    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .resolve_target = null,
        .clear_value = gpu.Color{
            .r = 0.2,
            .g = 0.3,
            .b = 0.3,
            .a = 1.0,
        },
        .load_op = .clear,
        .store_op = .store,
    };

    const command_encoder = application.context.device.createCommandEncoder(null);
    defer command_encoder.release();

    const render_pass_info = gpu.RenderPassEncoder.Descriptor{
        .color_attachments = &.{
            color_attachment,
        },
        .depth_stencil_attachment = null,
    };

    const ubo = UniformBufferObject{
        .colour = .{ 1.0, 0.5, 0.2, 1.0 },
    };

    command_encoder.writeBuffer(application.uniform_buffer, 0, UniformBufferObject, &.{ ubo });

    const render_pass = command_encoder.beginRenderPass(&render_pass_info);
    defer render_pass.release();

    render_pass.setPipeline(application.render_pipeline);
    render_pass.setBindGroup(0, application.bind_group, &.{ 0 });

    render_pass.draw(3, 1, 0, 0);
    render_pass.end();

    var command = command_encoder.finish(null);
    defer command.release();

    application.context.queue.submit(&.{
        command,
    });

    application.context.swap_chain.present();
}

fn errorScopeBegin(context: Context) void {
    context.device.pushErrorScope(.validation);
}

fn errorScopeEnd(context: Context) !void {
    var has_error_occured = false;

    // @NOTE
    // `popErrorScope` seems to always return `true`. Verify?
    //     - princessakokosowa, 21 June 2022
    _ = context.device.popErrorScope(&gpu.ErrorCallback.init(*bool, &has_error_occured, struct {
        fn callback(ctx: *bool, typ: gpu.ErrorType, message: [*:0]const u8) void {
            if (typ != .noError) {
                std.debug.print("{s}\n", .{ message });
                ctx.* = true;
            }
        }
    }.callback));

    if (has_error_occured) {
        return error.FuckYou;
    }
}
