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
}

Draw_Batch :: struct {
    vertices: [dynamic]Vertex,
    draws: [dynamic]Draw_Request,

    program: Shader_Program,
    view_uniform: i32,
    perspective_uniform: i32,

    vao: u32,
    vbo: u32,
}

draw_batch_init :: proc(batch: ^Draw_Batch, vertex_count, draw_count: int, program: Shader_Program) {
    batch.vertices = make([dynamic]Vertex, 0, vertex_count)
    batch.draws = make([dynamic]Draw_Request, 0, draw_count)

    gl.GenVertexArrays(1, &batch.vao)
    gl.GenBuffers(1, &batch.vbo)

    gl.BindVertexArray(batch.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, batch.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(Vertex)*vertex_count, nil, gl.DYNAMIC_DRAW)

    batch.program = program
    batch.view_uniform = gl.GetUniformLocation(program.id, "u_view")
    batch.perspective_uniform = gl.GetUniformLocation(program.id, "u_perspective")

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

draw_line :: proc(batch: ^Draw_Batch, p1, p2: Vector3, color: Vector3) {
    draw_req := Draw_Request {
        mode = .Line,
        vertex_count = 2,
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

render_batch :: proc(batch: ^Draw_Batch, window: ^Window, camera: Camera) {
    gl.BindVertexArray(batch.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, batch.vbo)
    gl.BufferSubData(gl.ARRAY_BUFFER, 0, slice.size(batch.vertices[:]), raw_data(batch.vertices[:]))

    shader_program_use(batch.program)

    // TODO: make something either with prespective calculation, or near and far constants
    perspective := linalg.matrix4_perspective(math.to_radians(camera.fov), window_aspect(window), near, far)
    view := camera_view(camera)

    perspective_flat := linalg.matrix_flatten(perspective)
    view_flat := linalg.matrix_flatten(view)

    gl.UniformMatrix4fv(batch.perspective_uniform, 1, false, raw_data(perspective_flat[:]))
    gl.UniformMatrix4fv(batch.view_uniform, 1, false, raw_data(view_flat[:]))

    current_vertex_index: i32 = 0
    for draw in batch.draws {
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
