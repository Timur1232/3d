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

Shader_Program :: struct {
    program_id: u32,
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
        log.error("Unable to create %v shader", type, location = loc)
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
        log.error("Unable to compile shader: %s", string(info_log[:]), location = loc)
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
    return program.program_id != 0
}

shader_program_create :: proc(vertex_shader, fragment_shader: Shader, loc := #caller_location) -> (program: Shader_Program, ok: bool) {
    assert(shader_valid(vertex_shader) && shader_valid(fragment_shader))

    if vertex_shader.type == .Compute || fragment_shader.type == .Compute {
        log.warn("Compute shaders are not supported through current API for now. Use native gl function to create program.")
    }

    program.program_id = gl.CreateProgram()
    if !shader_program_valid(program) {
        log.error("Unable to create shader program", location = loc)
        ok = false
        return
    }

    defer if !ok {
        shader_program_delete(program)
        program.program_id = 0
    }

    gl.AttachShader(program.program_id, vertex_shader.id)
    gl.AttachShader(program.program_id, fragment_shader.id)

    gl.LinkProgram(program.program_id)

    success: i32
    gl.GetProgramiv(program.program_id, gl.LINK_STATUS, &success)

    if success == 0 {
        @(static) info_log: [512]u8
        gl.GetProgramInfoLog(program.program_id, 512, nil, raw_data(info_log[:]))
        log.error("Unable to link shader program: %s", string(info_log[:]), location = loc)
        ok = false
        return
    }

    ok = true
    return
}

// NOTE: Deleting shader program doesn't make it invalid
shader_program_delete :: #force_inline proc(program: Shader_Program) {
    gl.DeleteProgram(program.program_id)
}

shader_program_use :: #force_inline proc(program: Shader_Program) {
    gl.UseProgram(program.program_id)
}

import gl "vendor:OpenGL"
import "core:log"
