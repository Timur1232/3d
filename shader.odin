package main

Shader_Type :: enum u32 {
    Vertex   = gl.VERTEX_SHADER,
    Fragment = gl.FRAGMENT_SHADER,
    Compute  = gl.COMPUTE_SHADER,
}

// Uniforms found by default
Default_Uniform_Type :: enum int {
    Time = 0,
    Light_Pos,
    Model,
    View,
    Perspective,
}
Default_Uniform_Indices :: [Default_Uniform_Type]i32
Default_Uniform_Names := [Default_Uniform_Type]cstring {
    .Time        = "u_time",
    .Light_Pos   = "u_light_pos",
    .Model       = "u_model",
    .View        = "u_view",
    .Perspective = "u_perspective",
}
Default_Uniform_Types :: [Default_Uniform_Type]typeid {
    .Time        = f32,
    .Light_Pos   = Vector3,
    .Model       = Mat4,
    .View        = Mat4,
    .Perspective = Mat4,
}

// Abstraction over shader program
Shader :: struct {
    id: u32,
    locs: Default_Uniform_Indices,
}

// NOTE: Deleting shader doesn't make it invalid
shader_valid :: #force_inline proc(shader: Shader) -> bool {
    return shader.id != 0
}

shader_compile_from_source :: proc(type: Shader_Type, source_code: []u8, loc := #caller_location) -> (shader_id: u32, ok: bool) {
    shader_id = gl.CreateShader(u32(type))
    if shader_id == 0 {
        log.errorf("Unable to create %v shader", type, location = loc)
        ok = false
        return
    }

    defer if !ok {
        gl.DeleteShader(shader_id)
        shader_id = 0
    }

    source_code := source_code
    cstr := cstring(raw_data(source_code))
    length := []i32{ i32(len(source_code)) }
    gl.ShaderSource(shader_id, 1, &cstr, raw_data(length))
    gl.CompileShader(shader_id)

    success: i32
    gl.GetShaderiv(shader_id, gl.COMPILE_STATUS, &success)

    if success == 0 {
        @(static) info_log: [512]u8
        gl.GetShaderInfoLog(shader_id, 512, nil, raw_data(info_log[:]))
        log.errorf("Unable to compile shader: %s", string(info_log[:]), location = loc)
        ok = false
        return
    }

    ok = true
    return
}

// NOTE: Deleting shader program doesn't make it invalid
shader_delete :: #force_inline proc(shader: Shader) {
    gl.DeleteProgram(shader.id)
}

shader_link :: proc(shader_ids: ..u32, loc := #caller_location) -> (program: Shader, ok: bool) {
    program.id = gl.CreateProgram()
    if !shader_valid(program) {
        log.error("Unable to create shader program", location = loc)
        ok = false
        return
    }

    defer if !ok {
        shader_delete(program)
        program.id = 0
    }

    for id in shader_ids {
        assert(id != 0, "Shader must be valid", loc = loc)
        gl.AttachShader(program.id, id)
    }

    gl.LinkProgram(program.id)

    success: i32
    gl.GetProgramiv(program.id, gl.LINK_STATUS, &success)

    if success == 0 {
        @(static) info_log: [512]u8
        gl.GetProgramInfoLog(program.id, 512, nil, raw_data(info_log[:]))
        log.errorf("Unable to link shader program: %s", string(info_log[:]), location = loc)
        ok = false
        return
    }

    for type in Default_Uniform_Type {
        program.locs[type] = gl.GetUniformLocation(program.id, Default_Uniform_Names[type])
    }

    ok = true
    return
}

shader_use :: #force_inline proc(program: Shader) {
    gl.UseProgram(program.id)
}

shader_uniform_location :: #force_inline proc(program: Shader, name: cstring) -> i32 {
    return gl.GetUniformLocation(program.id, name)
}

shader_default_uniform :: proc(program: Shader, $type: Default_Uniform_Type, data: Default_Uniform_Types[type]) {
    if program.locs[type] < 0 do return
    when type == .Time {
        gl.ProgramUniform1f(program.id, program.locs[type], data)
    } else when type == .Light_Pos {
        data := data
        gl.ProgramUniform3fv(program.id, program.locs[type], 1, raw_data(&data))
    } else {
        mat_flat := la.matrix_flatten(data)
        gl.ProgramUniformMatrix4fv(program.id, program.locs[type], 1, false, raw_data(&mat_flat))
    }
}

shader_create_from_source :: proc(vs_source, fs_source: []u8) -> (program: Shader, ok: bool) {
    vertex_shader := shader_compile_from_source(.Vertex, vs_source) or_return
    fragment_shader := shader_compile_from_source(.Fragment, fs_source) or_return
    program = shader_link(vertex_shader, fragment_shader) or_return
    gl.DeleteShader(vertex_shader)
    gl.DeleteShader(fragment_shader)
    return program, true
}

shader_create_from_path :: proc(vs_path, fs_path: string, allocator := context.temp_allocator) -> (program: Shader, ok: bool) {
    vs_source, file_err := os.read_entire_file(vs_path, allocator)
    if file_err != nil {
        log.errorf("Unable to read %s: %v", vs_path, file_err)
        ok = false
        return
    }
    fs_source: []u8
    fs_source, file_err = os.read_entire_file(fs_path, allocator)
    if file_err != nil {
        log.errorf("Unable to read %s: %v", fs_path, file_err)
        ok = false
        return
    }
    return shader_create_from_source(vs_source, fs_source)
}

import gl "vendor:OpenGL"
import "core:log"
import "core:os"
import la "core:math/linalg"
