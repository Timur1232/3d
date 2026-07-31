package main

Vertex :: struct {
    position: Vector3,
    normal: Vector3,
    color: Vector3,
}

Draw_Mode :: enum {
    Line,
    Triangle,
    Quad,
}
Gl_Draw_Modes := [Draw_Mode]u32 {
    .Line = gl.LINES,
    .Triangle = gl.TRIANGLES,
    .Quad = gl.TRIANGLE_STRIP, // draw two triangles instead of GL_QUADS
}

Draw_Request :: struct {
    mode: Draw_Mode,
    vertex_count: i32,
    transform: Mat4,
}

Render_Batch :: struct {
    vertices: []Vertex,
    draws: []Draw_Request,

    vertices_count: int,
    draws_count: int,

    program: Shader_Program,
    transform_uniform: i32,

    current_transform: Mat4,

    vao: u32,
    vbo: u32,
}

// TODO: parametrize this
PRIMITIVE_VERTEX_SHADER_PATH   :: SHADERS_DIR+"primitive_vs.glsl"
PRIMITIVE_FRAGMENT_SHADER_PATH :: SHADERS_DIR+"primitive_fs.glsl"

@(private="file")
batch_vs_source := string(#load(PRIMITIVE_VERTEX_SHADER_PATH))
@(private="file")
batch_fs_source := string(#load(PRIMITIVE_FRAGMENT_SHADER_PATH))

// NOTE: Must be called after making window context and loading OpenGL functions
render_batch_init :: proc(batch: ^Render_Batch, vertex_count, draw_count: int) -> (ok: bool){
    assert_current_context()
    assert_opengl()

    alloc_err: runtime.Allocator_Error
    batch.vertices, alloc_err = make([]Vertex, vertex_count)
    assert(alloc_err == .None, "Buy more RAM")
    batch.draws, alloc_err = make([]Draw_Request, draw_count)
    assert(alloc_err == .None, "Buy more RAM")

    defer if !ok {
        delete(batch.vertices)
        delete(batch.draws)
    }

    gl.GenVertexArrays(1, &batch.vao)
    if batch.vao == 0 {
        ok = false
        return
    }
    defer if !ok {
        gl.DeleteBuffers(1, &batch.vao)
    }

    gl.GenBuffers(1, &batch.vbo)
    if batch.vbo == 0 {
        ok = false
        return
    }
    defer if !ok {
        gl.DeleteBuffers(1, &batch.vbo)
    }

    gl.BindVertexArray(batch.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, batch.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(Vertex)*vertex_count, nil, gl.DYNAMIC_DRAW)

    set_vertex_vao()

    program := shader_program_create_from_source(batch_vs_source, batch_fs_source) or_return

    batch.program = program
    batch.transform_uniform = gl.GetUniformLocation(program.id, "u_transform")

    ok = true

    return
}

render_batch_destroy :: proc(batch: ^Render_Batch) {
    delete(batch.vertices)
    delete(batch.draws)
    gl.DeleteBuffers(1, &batch.vbo)
    gl.DeleteVertexArrays(1, &batch.vao)
}

// Target VAO must be binded before calling this
set_vertex_vao :: proc() {
    offset: uintptr = 0

    // Position
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset)
    gl.EnableVertexAttribArray(0)

    offset += 3*size_of(f32)

    // Normal
    gl.VertexAttribPointer(1, 3, gl.FLOAT, false, size_of(Vertex), offset)
    gl.EnableVertexAttribArray(1)

    offset += 3*size_of(f32)

    // Color (tint)
    gl.VertexAttribPointer(2, 3, gl.FLOAT, false, size_of(Vertex), offset)
    gl.EnableVertexAttribArray(2)
}

begin_drawing :: proc(batch: ^Render_Batch, window: ^Window) {
    when ODIN_DEBUG do assert_current_context()
    batch.current_transform = window_ortho(window)
    gl.Disable(gl.DEPTH_TEST)
}
end_drawing :: #force_inline proc(batch: ^Render_Batch) {
    render_batch(batch)
    gl.Enable(gl.DEPTH_TEST)
}

begin_camera_3d :: proc(batch: ^Render_Batch, window: ^Window, camera: Camera) {
    when ODIN_DEBUG do assert_current_context()
    view := camera_view(camera)
    perspective := camera_perspective(camera, window_aspect(window))
    batch.current_transform = perspective * view
    gl.Enable(gl.DEPTH_TEST)
}

end_camera_3d :: proc(batch: ^Render_Batch, window: ^Window) {
    batch.current_transform = window_ortho(window)
    gl.Disable(gl.DEPTH_TEST)
}

draw_line_3d :: proc(batch: ^Render_Batch, p1, p2: Vector3, color: Vector3) {
    when ODIN_DEBUG do assert_current_context()
    append_draw_request(batch, .Line)
    append_vertices(batch, color, p1, p2)
}

draw_line_2d :: proc(batch: ^Render_Batch, p1, p2: Vector2, color: Vector3) {
    when ODIN_DEBUG do assert_current_context()
    append_draw_request(batch, .Line)
    append_vertices(batch, color, add_one_component(p1), add_one_component(p2))
}

draw_triangle_2d :: proc(batch: ^Render_Batch, p1, p2, p3: Vector2, color: Vector3) {
    when ODIN_DEBUG do assert_current_context()
    append_draw_request(batch, .Triangle)
    append_vertices(batch, color, add_one_component(p1), add_one_component(p2), add_one_component(p3))
}

draw_triangle_3d :: proc(batch: ^Render_Batch, p1, p2, p3: Vector3, color: Vector3) {
    when ODIN_DEBUG do assert_current_context()
    append_draw_request(batch, .Triangle)
    append_vertices(batch, color, p1, p2, p3)
}

draw_rectangle_2d :: proc(batch: ^Render_Batch, pos, size: Vector2, color: Vector3) {
    when ODIN_DEBUG do assert_current_context()

    append_draw_request(batch, .Quad)
    lt := add_one_component(pos)              // left top
    rt := Vector3{ pos.x + size.x, pos.y, 1 } // right top
    lb := Vector3{ pos.x, pos.y + size.y, 1 } // left bottom
    rb := add_one_component(pos + size)       // right bottom
    append_vertices(batch, color, lb, lt, rb, rt)
}

draw_rectangle_3d :: proc(batch: ^Render_Batch, pos: Vector3, size: Vector2, yaw, pitch: f32, color: Vector3) {
    when ODIN_DEBUG do assert_current_context()

    rot_yaw := linalg.matrix4_rotate(math.to_radians(yaw), Vector3{0, 1, 0})
    rot_pitch := linalg.matrix4_rotate(math.to_radians(pitch), Vector3{1, 0, 0})
    translate := linalg.matrix4_translate(pos)

    lt4 := Vector4{ 0, 0, 0, 1}
    rt4 := Vector4{ size.x, 0, 0, 1 }
    lb4 := Vector4{ 0, -size.y, 0, 1 }
    rb4 := Vector4{ size.x, -size.y, 0, 1 }

    transform := rot_pitch * rot_yaw * translate

    lt := (transform * lt4).xyz
    rt := (transform * rt4).xyz
    lb := (transform * lb4).xyz
    rb := (transform * rb4).xyz

    append_draw_request(batch, .Quad)
    append_vertices(batch, color, lb, lt, rb, rt)
}

// Renders batch to current attached window
render_batch :: proc(batch: ^Render_Batch) {
    when ODIN_DEBUG {
        assert_current_context()
        assert_opengl()
    }

    gl.BindVertexArray(batch.vao)

    // fmt.println("==============================")

    gl.BindBuffer(gl.ARRAY_BUFFER, batch.vbo)
    gl.BufferSubData(gl.ARRAY_BUFFER, 0, size_of(Vertex)*batch.vertices_count, raw_data(batch.vertices[:batch.vertices_count]))

    // fmt.printfln("batch.vertices = %v", batch.vertices[:batch.vertices_count])

    shader_program_use(batch.program)

    current_vertex_index: i32 = 0
    // fmt.println("------------------------------")
    for draw in batch.draws[:batch.draws_count] {
        transform_flat := linalg.matrix_flatten(draw.transform)
        // fmt.printfln("draw = %v", draw)
        gl.UniformMatrix4fv(batch.transform_uniform, 1, false, raw_data(transform_flat[:]))
        gl.DrawArrays(Gl_Draw_Modes[draw.mode], current_vertex_index, draw.vertex_count)
        current_vertex_index += draw.vertex_count
    }

    batch.draws_count = 0
    batch.vertices_count = 0
}

append_draw_request :: #force_inline proc(batch: ^Render_Batch, mode: Draw_Mode) {
    draw_req := Draw_Request {
        mode = mode,
        transform = batch.current_transform,
    }
    switch mode {
    case .Line:     draw_req.vertex_count = 2
    case .Triangle: draw_req.vertex_count = 3
    case .Quad:     draw_req.vertex_count = 4
    }
    if batch.draws_count >= len(batch.draws) {
        render_batch(batch)
    }
    batch.draws[batch.draws_count] = draw_req
    batch.draws_count += 1
}

append_vertices :: #force_inline proc(batch: ^Render_Batch, color: Vector3, points: ..Vector3) {
    for p in points {
        v := Vertex {
            position = p,
            color = color,
        }
        if batch.vertices_count >= len(batch.vertices) {
            render_batch(batch)
        }
        batch.vertices[batch.vertices_count] = v
        batch.vertices_count += 1
    }
}

import gl "vendor:OpenGL"
import "base:runtime"
import "core:math"
import "core:math/linalg"
import "core:fmt"
