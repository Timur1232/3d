package main

Vertex :: struct {
    position: Vector3,
    normal: Vector3,
    color: Vector3,
}

Draw_Mode :: enum {
    None,
    Line,
    Triangle,
    Quad,
}
Gl_Draw_Modes := [Draw_Mode]u32 {
    .None = 0,
    .Line = gl.LINES,
    .Triangle = gl.TRIANGLES,
    .Quad = gl.QUADS
}

Draw_Request :: struct {
    mode: Draw_Mode,
    vertex_count: i32,
    transform: Mat4,
}

Draw_Batch :: struct {
    vertices: [dynamic]Vertex,
    draws: [dynamic]Draw_Request,

    program: Shader_Program,
    transform_uniform: i32,

    current_transform: Mat4,
    current_window: ^Window,

    vao: u32,
    vbo: u32,
}

draw_batch_init :: proc(batch: ^Draw_Batch, vertex_count, draw_count: int, program: Shader_Program, window: ^Window) {
    batch.vertices = make([dynamic]Vertex, 0, vertex_count)
    batch.draws = make([dynamic]Draw_Request, 0, draw_count)
    batch.current_window = window

    gl.GenVertexArrays(1, &batch.vao)
    gl.GenBuffers(1, &batch.vbo)

    gl.BindVertexArray(batch.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, batch.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(Vertex)*vertex_count, nil, gl.DYNAMIC_DRAW)

    batch.program = program
    batch.transform_uniform = gl.GetUniformLocation(program.id, "u_transform")

    set_vertex_vao()
}

draw_batch_destroy :: proc(batch: ^Draw_Batch) {
    delete(batch.vertices)
    delete(batch.draws)
    gl.DeleteBuffers(1, &batch.vbo)
    gl.DeleteVertexArrays(1, &batch.vao)
}

// Target VAO must be binded before calling this
set_vertex_vao :: proc() {
    offset: uintptr = 0

    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset)
    gl.EnableVertexAttribArray(0)

    offset += 3*size_of(f32)

    gl.VertexAttribPointer(1, 3, gl.FLOAT, false, size_of(Vertex), offset)
    gl.EnableVertexAttribArray(1)

    offset += 3*size_of(f32)

    gl.VertexAttribPointer(2, 3, gl.FLOAT, false, size_of(Vertex), offset)
    gl.EnableVertexAttribArray(2)
}

window_ortho :: #force_inline proc(window: ^Window) -> Mat4 {
    return linalg.matrix_ortho3d_f32(0, f32(window.width), f32(window.height), 0, 0, math.F32_MAX)
}

begin_drawing :: proc(batch: ^Draw_Batch, window: ^Window) {
    batch.current_transform = window_ortho(window)
    batch.current_window = window
}
end_drawing :: proc(batch:^ Draw_Batch) {
    render_batch(batch)
    batch.current_transform = window_ortho(batch.current_window)
}

begin_camera_3d :: proc(batch: ^Draw_Batch, camera: Camera) {
    view := camera_view(camera)
    perspective := camera_perspective(camera, window_aspect(batch.current_window))
    batch.current_transform = perspective * view
}

end_camera_3d :: proc(batch: ^Draw_Batch) {
    batch.current_transform = window_ortho(batch.current_window)
}

draw_line_3d :: proc(batch: ^Draw_Batch, p1, p2: Vector3, color: Vector3) {
    draw_req := Draw_Request {
        mode = .Line,
        vertex_count = 2,
        transform = batch.current_transform,
    }
    append(&batch.draws, draw_req)

    v1 := Vertex {
        position = p1,
        color = color,
    }
    v2 := Vertex {
        position = p2,
        color = color,
    }

    append(&batch.vertices, v1, v2)
}

draw_line_2d :: proc(batch: ^Draw_Batch, p1, p2: Vector2, color: Vector3) {
    draw_req := Draw_Request {
        mode = .Line,
        vertex_count = 2,
        transform = batch.current_transform,
    }
    append(&batch.draws, draw_req)

    v1 := Vertex {
        position = { p1.x, p1.y, 1.0 },
        color = color,
    }
    v2 := Vertex {
        position = { p2.x, p2.y, 1.0 },
        color = color,
    }
    append(&batch.vertices, v1, v2)
}

// Renders batch to current attached window
render_batch :: proc(batch: ^Draw_Batch) {
    gl.BindVertexArray(batch.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, batch.vbo)
    gl.BufferSubData(gl.ARRAY_BUFFER, 0, slice.size(batch.vertices[:]), raw_data(batch.vertices[:]))

    shader_program_use(batch.program)

    current_vertex_index: i32 = 0
    for draw in batch.draws {
        transform_flat := linalg.matrix_flatten(draw.transform)
        gl.UniformMatrix4fv(batch.transform_uniform, 1, false, raw_data(transform_flat[:]))
        gl.DrawArrays(Gl_Draw_Modes[draw.mode], current_vertex_index, draw.vertex_count)
        current_vertex_index += draw.vertex_count
    }

    clear(&batch.vertices)
    clear(&batch.draws)
}

import gl "vendor:OpenGL"
import "core:slice"
import "core:math"
import "core:math/linalg"
