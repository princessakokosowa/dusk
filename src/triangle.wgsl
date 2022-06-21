struct UniformBufferObject {
    colour: vec4<f32>,
}

@group(0) @binding(0) var<uniform> ubo : UniformBufferObject;

@stage(vertex) fn vsMain(
    @builtin(vertex_index) VertexIndex : u32
) -> @builtin(position) vec4<f32> {
    var pos = array<vec2<f32>, 3>(
        vec2<f32>( 0.0,  0.5),
        vec2<f32>(-0.5, -0.5),
        vec2<f32>( 0.5, -0.5)
    );

    return vec4<f32>(pos[VertexIndex], 0.0, 1.0);
}

@stage(fragment) fn fsMain() -> @location(0) vec4<f32> {
    return vec4<f32>(ubo.colour.r, ubo.colour.g, ubo.colour.b, ubo.colour.a);
}
