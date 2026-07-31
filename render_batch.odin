package main

Vertex :: struct {
    position: Vector3,
    normal: Vector3,
    color: Vector4,
}

Draw_Mode :: enum {
    Line,
    Triangle,
    Quad,
}
GL_Draw_Modes := [Draw_Mode]u32 {
    .Line = gl.LINES,
    .Triangle = gl.TRIANGLES,
    .Quad = gl.TRIANGLE_STRIP,
}
Draw_Opt :: enum {
    Depth_Test,
    Backface_Culling,
}
Draw_Opts :: bit_set[Draw_Opt]
GL_Draw_Opt := [Draw_Opt]u32 {
    .Depth_Test = gl.DEPTH_TEST,
    .Backface_Culling = gl.CULL_FACE,
}

Draw_Request :: struct {
    mode: Draw_Mode,
    vertex_count: i32,
    transform: Mat4,
    opts: Draw_Opts,
}

Render_Batch :: struct {
    vertices: []Vertex,
    draws: []Draw_Request,

    vertices_count: int,
    draws_count: int,

    shader_primitives: Shader,
    transform_uniform: i32,

    current_transform: Mat4,
    draw_opts: Draw_Opts,

    vao: u32,
    vbo: u32,
}

// TODO: parametrize this
PRIMITIVE_VERTEX_SHADER_PATH   :: SHADERS_DIR+"primitive_vs.glsl"
PRIMITIVE_FRAGMENT_SHADER_PATH :: SHADERS_DIR+"primitive_fs.glsl"

@(private="file")
batch_vs_source := #load(PRIMITIVE_VERTEX_SHADER_PATH)
@(private="file")
batch_fs_source := #load(PRIMITIVE_FRAGMENT_SHADER_PATH)

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

    set_vertex_attributes(Vertex)

    batch.shader_primitives = shader_create_from_source(batch_vs_source, batch_fs_source) or_return
    batch.transform_uniform = shader_uniform_location(batch.shader_primitives, "u_transform")

    ok = true
    return
}

render_batch_destroy :: proc(batch: ^Render_Batch) {
    delete(batch.vertices)
    delete(batch.draws)
    gl.DeleteBuffers(1, &batch.vbo)
    gl.DeleteVertexArrays(1, &batch.vao)
}

// Gets needed information from type for vertex attributes
get_gl_type :: proc(info: ^reflect.Type_Info) -> (gl_type: u32, gl_size: i32, size_in_bytes: int) {
    #partial switch t in info.variant {
    case runtime.Type_Info_Integer:
        if t.signed {
            return gl.INT, 1, info.size
        }
        else {
            return gl.UNSIGNED_INT, 1, info.size
        }
    case runtime.Type_Info_Float:
        return gl.FLOAT, 1, info.size
    case runtime.Type_Info_Array:
        gl_size = i32(t.count)
        elem := runtime.type_info_base(t.elem)
        elem_type, elem_size, _ := get_gl_type(elem)
        gl_size *= elem_size
        return elem_type, gl_size, info.size
    case:
        assert(false, fmt.tprintf("Type %v not supported for now"))
        unreachable()
    }
}

// Target VAO must be binded before calling this
//
// WARNING: This is generelized solution for easy use
// Prefer manual attributes setting for more control of more complex structures
set_vertex_attributes :: proc($T: typeid) where intrinsics.type_is_struct(T) {
    struct_fields := reflect.struct_field_types(T)

    attrib_loc: u32 = 0
    offset: uintptr = 0

    for f in struct_fields {
        gl_type, gl_size, size_in_bytes := get_gl_type(reflect.type_info_base(f))
        gl.VertexAttribPointer(attrib_loc, gl_size, gl_type, false, size_of(T), offset)
        gl.EnableVertexAttribArray(attrib_loc)

        offset += auto_cast size_in_bytes
        attrib_loc += 1
    }
}

// Renders batch to current attached window
render_batch :: proc(batch: ^Render_Batch) {
    when ODIN_DEBUG {
        assert_current_context()
        assert_opengl()
    }

    gl.BindVertexArray(batch.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, batch.vbo)
    gl.BufferSubData(gl.ARRAY_BUFFER, 0, size_of(Vertex)*batch.vertices_count, raw_data(batch.vertices[:batch.vertices_count]))

    shader_use(batch.shader_primitives)

    current_vertex_index: i32 = 0
    for draw in batch.draws[:batch.draws_count] {
        apply_draw_options(draw.opts)
        transform_flat := linalg.matrix_flatten(draw.transform)
        gl.UniformMatrix4fv(batch.transform_uniform, 1, false, raw_data(transform_flat[:]))
        gl.DrawArrays(GL_Draw_Modes[draw.mode], current_vertex_index, draw.vertex_count)
        current_vertex_index += draw.vertex_count
    }

    batch.draws_count = 0
    batch.vertices_count = 0

    // Enable some setting back
    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)
}

apply_draw_options :: proc(opts: Draw_Opts) {
    for opt in Draw_Opt {
        if opt in opts {
            gl.Enable(GL_Draw_Opt[opt])
        } else {
            gl.Disable(GL_Draw_Opt[opt])
        }
    }
}

append_draw_request :: #force_inline proc(batch: ^Render_Batch, mode: Draw_Mode) {
    draw_req := Draw_Request {
        mode = mode,
        transform = batch.current_transform,
        opts = batch.draw_opts,
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

append_vertices :: #force_inline proc(batch: ^Render_Batch, color: Color, points: ..Vector3) {
    for p in points {
        v := Vertex {
            position = p,
            color = normalize_color(color),
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
import "base:intrinsics"
import "core:reflect"
import "core:fmt"
import "core:math/linalg"
