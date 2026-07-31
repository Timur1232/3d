package main

Shader_Type :: enum u32 {
    None     = 0,
    Vertex   = gl.VERTEX_SHADER,
    Fragment = gl.FRAGMENT_SHADER,
    Compute  = gl.COMPUTE_SHADER, // Not supported for now
}

Shader :: struct {
    id: u32,
    type: Shader_Type,
}

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

Shader_Program :: struct {
    id: u32,
    locs: Default_Uniform_Indices,
}

// NOTE: Deleting shader doesn't make it invalid
shader_valid :: #force_inline proc(shader: Shader) -> bool {
    return shader.id != 0
}

shader_create_from_source :: proc(type: Shader_Type, source_code: string, loc := #caller_location) -> (shader: Shader, ok: bool) {
    assert(type != .None)

    if type == .Compute {
        log.warn("Compute shaders are not supported through current API for now. Use native gl function to create program.")
    }

    shader.id = gl.CreateShader(u32(type))
    if !shader_valid(shader) {
        log.errorf("Unable to create %v shader", type, location = loc)
        ok = false
        return
    }
    shader.type = type

    defer if !ok {
        shader_delete(shader)
        shader.id = 0
    }

    cstr := to_csrt_temp(source_code)
    gl.ShaderSource(shader.id, 1, &cstr, nil)
    gl.CompileShader(shader.id)

    success: i32
    gl.GetShaderiv(shader.id, gl.COMPILE_STATUS, &success)

    if success == 0 {
        @(static) info_log: [512]u8
        gl.GetShaderInfoLog(shader.id, 512, nil, raw_data(info_log[:]))
        log.errorf("Unable to compile shader: %s", string(info_log[:]), location = loc)
        ok = false
        return
    }

    ok = true
    return
}

// NOTE: Deleting shader doesn't make it invalid
shader_delete :: #force_inline proc(shader: Shader) {
    gl.DeleteShader(shader.id)
}

// NOTE: Deleting shader program doesn't make it invalid
shader_program_valid :: #force_inline proc(program: Shader_Program) -> bool {
    return program.id != 0
}

shader_program_create :: proc(vertex_shader, fragment_shader: Shader, loc := #caller_location) -> (program: Shader_Program, ok: bool) {
    assert(shader_valid(vertex_shader) && shader_valid(fragment_shader))

    if vertex_shader.type == .Compute || fragment_shader.type == .Compute {
        log.warn("Compute shaders are not supported through current API for now. Use native gl function to create program.")
    }

    program.id = gl.CreateProgram()
    if !shader_program_valid(program) {
        log.error("Unable to create shader program", location = loc)
        ok = false
        return
    }

    defer if !ok {
        shader_program_delete(program)
        program.id = 0
    }

    gl.AttachShader(program.id, vertex_shader.id)
    gl.AttachShader(program.id, fragment_shader.id)

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

// NOTE: Deleting shader program doesn't make it invalid
shader_program_delete :: #force_inline proc(program: Shader_Program) {
    gl.DeleteProgram(program.id)
}

shader_program_use :: #force_inline proc(program: Shader_Program) {
    gl.UseProgram(program.id)
}

shader_program_default_uniform :: proc(program: Shader_Program, $type: Default_Uniform_Type, data: Default_Uniform_Types[type]) {
    if program.locs[type] < 0 do return
    when type == .Time {
        gl.ProgramUniform1f(program.id, program.locs[type], data)
    } else when type == .Light_Pos {
        data := data
        gl.ProgramUniform3fv(program.id, program.locs[type], 1, raw_data(&data))
    } else {
        mat_flat := linalg.matrix_flatten(data)
        gl.ProgramUniformMatrix4fv(program.id, program.locs[type], 1, false, raw_data(&mat_flat))
    }
}

shader_program_create_from_source :: proc(vs_source, fs_source: string) -> (program: Shader_Program, ok: bool) {
    vertex_shader := shader_create_from_source(.Vertex, vs_source) or_return
    fragment_shader := shader_create_from_source(.Fragment, fs_source) or_return
    program = shader_program_create(vertex_shader, fragment_shader) or_return
    shader_delete(vertex_shader)
    shader_delete(fragment_shader)
    return program, true
}

shader_program_create_from_path :: proc(vs_path, fs_path: string, allocator := context.temp_allocator) -> (program: Shader_Program, ok: bool) {
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
    return shader_program_create_from_source(string(vs_source), string(fs_source))
}

import gl "vendor:OpenGL"
import "core:log"
import "core:os"
import "core:fmt"
import "core:math/linalg"
