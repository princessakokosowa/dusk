const gpu = @import("gpu");

const Context = @import("Context.zig");

const Application = @This();

context: Context,
render_pipeline: gpu.RenderPipeline,

pub fn init() !Application {
    var context = try Context.init();

    const wgsl = @embedFile("triangle.wgsl");

    const vs_module = context.device.createShaderModule(&.{
        .label = "vertex shader",
        .code = .{
            .wgsl = wgsl,
        },
    });

    const fs_module = context.device.createShaderModule(&.{
        .label = "fragment shader",
        .code = .{
            .wgsl = wgsl,
        },
    });

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
            color_target
        },
        .constants = null,
    };

    const vertex = gpu.VertexState{
        .module = vs_module,
        .entry_point = "vsMain",
        .buffers = null,
    };

    const render_pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .layout = null,
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

    var render_pipeline: gpu.RenderPipeline = context.device.createRenderPipeline(&render_pipeline_descriptor);

    fs_module.release();
    vs_module.release();

    return Application{
        .context = context,
        .render_pipeline = render_pipeline,
    };
}

pub fn update(application: *Application) void {
    const back_buffer_view = application.context.swap_chain.getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .resolve_target = null,
        .clear_value = gpu.Color{
            .r = 0.2,
            .g = 0.3,
            .b = 0.3,
            .a = 1.0
        },
        .load_op = .clear,
        .store_op = .store,
    };

    const command_encoder = application.context.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassEncoder.Descriptor{
        .color_attachments = &.{
            color_attachment,
        },
        .depth_stencil_attachment = null,
    };

    const render_pass = command_encoder.beginRenderPass(&render_pass_info);

    render_pass.setPipeline(application.render_pipeline);
    render_pass.draw(3, 1, 0, 0);
    render_pass.end();
    render_pass.release();

    var command = command_encoder.finish(null);
    command_encoder.release();

    application.context.queue.submit(&.{
        command
    });

    command.release();
    application.context.swap_chain.present();
    back_buffer_view.release();
}

pub fn deinit(application: *Application) void {
    application.context.deinit();
}