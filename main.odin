package main

gl_version_major :: 4
gl_version_minor :: 6

assets_dir :: "assets/"
models_dir :: assets_dir+"models/"
shaders_dir :: assets_dir+"shaders/"

model_path :: models_dir+"monkey.obj"
model_data := #load(model_path)

vertex_shader_source := string(#load(shaders_dir+"vs.glsl"))
fragment_shader_source := string(#load(shaders_dir+"fs.glsl"))

wireframe := false
fov  : f32 : 60
near :: 0.1
far  :: 100

Vertex :: struct {
    position: Vector3,
    normal: Vector3,
}

main :: proc() {

    // For repeate key event would work on wayland
    glfw.InitHint(glfw.PLATFORM, glfw.PLATFORM_X11);

    if !glfw.Init() {
        log.fatal("Unable to initialize glfw")
        return
    }
    defer glfw.Terminate()

    window: Window
    if create_window_err := init_window(&window, 800, 600, "Hello from OpenGL"); create_window_err != nil {
        log.fatal("Unable to create window: %v", create_window_err)
    }
    defer destroy_window(&window)

    glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)

    gl.Enable(gl.DEBUG_OUTPUT)
    gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
    gl.DebugMessageCallback(proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, userParam: rawptr) {
        libc.printf("OpenGL message: %s\n", message)
    }, nil)

    gl.Enable(gl.DEPTH_TEST);

    ok: bool
    vertex_shader: u32
    if vertex_shader, ok = shader_create_from_source(gl.VERTEX_SHADER, vertex_shader_source); !ok {
        log.fatal("Problem with vertex shader")
        return
    }

    fragment_shader: u32
    if fragment_shader, ok = shader_create_from_source(gl.FRAGMENT_SHADER, fragment_shader_source); !ok {
        log.fatal("Problem with fragment shader")
        return
    }

    program: u32
    if program, ok = create_shader_program(vertex_shader, fragment_shader); !ok {
        log.fatal("Problem with shader program")
        return
    }
    defer gl.DeleteProgram(program)

    gl.DeleteShader(vertex_shader)
    gl.DeleteShader(fragment_shader)

    time_uniform := gl.GetUniformLocation(program, "u_time")
    transform_uniform := gl.GetUniformLocation(program, "u_transform")
    perspective_uniform := gl.GetUniformLocation(program, "u_perspective")
    view_uniform := gl.GetUniformLocation(program, "u_view")

    scene: tinyobj.Scene
    cfg := tinyobj.default_config()
    res := tinyobj.load_obj_from_memory(&scene, raw_data(model_data), len(model_data), &cfg, nil)
    if res != .Ok {
        log.error("Unable to load obj file %s: %s", model_path, tinyobj.result_string(res))
    }
    defer tinyobj.scene_free(&scene)

    vertices: []Vertex
    indices: []u32

    if scene.num_shapes > 0 {
        vertices = make([]Vertex, scene.attrib.vertices.count/3)
        for i in 0..<scene.attrib.vertices.count/3 {
            vertices[i].position = {
                scene.attrib.vertices.ptr[i*3 + 0],
                scene.attrib.vertices.ptr[i*3 + 1],
                scene.attrib.vertices.ptr[i*3 + 2],
            }
        }

        scene_indices := scene.shapes[0].mesh.indices[:scene.shapes[0].mesh.num_indices]
        indices = make([]u32, len(scene_indices))
        for idx, i in scene_indices {
            indices[i] = u32(idx.vertex_index)
            vertices[idx.vertex_index].normal = {
                scene.attrib.normals.ptr[idx.normal_index*3 + 0],
                scene.attrib.normals.ptr[idx.normal_index*3 + 1],
                scene.attrib.normals.ptr[idx.normal_index*3 + 2],
            }
        }
    } else {
        log.warn("No model was loaded")
    }

    defer if scene.num_shapes > 0 {
        delete(vertices)
        delete(indices)
    }

    vao: u32
    vbo: u32
    ebo: u32
    gl.GenVertexArrays(1, &vao)
    gl.GenBuffers(1, &vbo)
    gl.GenBuffers(1, &ebo)

    gl.BindVertexArray(vao)

    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices)*size_of(indices[0]), raw_data(indices), gl.STATIC_DRAW)

    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices)*size_of(vertices[0]), raw_data(vertices), gl.STATIC_DRAW)

    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), 0)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, false, 6*size_of(f32), 3*size_of(f32))
    gl.EnableVertexAttribArray(1)

    time_elapsed: f32 = 0
    start_time: time.Time

    scale := linalg.matrix4_scale_f32({1, 1, 1})
    translate := linalg.matrix4_translate_f32({ 0, 0, -5 })

    camera_speed :: 0.2
    camera_spin_speed :: 1

    camera_pos := Vector3(0)
    camera_dir := Vector3{ 0, 0, -1 }

    up :: Vector3{ 0, 1, 0 }
    camera_right := linalg.normalize(linalg.cross(up, camera_dir))
    camera_up := linalg.cross(camera_dir, camera_right)

    yaw: f32 = -90
    pitch: f32

    for !glfw.WindowShouldClose(window.handle) {
        defer free_all(context.temp_allocator)

        start_frame(&window)
        defer end_frame(&window)

        if is_key_pressed(&window, glfw.KEY_ESCAPE) {
            glfw.SetWindowShouldClose(window.handle, true)
        }
        if is_key_pressed(&window, glfw.KEY_SPACE) {
            wireframe = !wireframe
            gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE if wireframe else gl.FILL)
        }

        forward_move_dir := i32(is_key_down(&window, glfw.KEY_W)) - i32(is_key_down(&window, glfw.KEY_S))
        if forward_move_dir != 0 {
            camera_pos += f32(forward_move_dir)*camera_dir*camera_speed
        }
        sideways_move_dir := i32(is_key_down(&window, glfw.KEY_A)) - i32(is_key_down(&window, glfw.KEY_D))
        if sideways_move_dir != 0 {
            camera_right := linalg.normalize(linalg.cross(up, camera_dir))
            camera_pos += f32(sideways_move_dir)*camera_right*camera_speed
        }

        sensitivity :: 0.1
        yaw += f32(window.mouse_delta.x)*sensitivity
        pitch = clamp(pitch - f32(window.mouse_delta.y)*sensitivity, -89, 89)

        camera_dir.x = math.cos(math.to_radians(yaw)) * math.cos(math.to_radians(pitch))
        camera_dir.y = math.sin(math.to_radians(pitch))
        camera_dir.z = math.sin(math.to_radians(yaw)) * math.cos(math.to_radians(pitch))

        start_time = time.now()

        gl.ClearColor(f32(0x18)/255, f32(0x18)/255, f32(0x18)/255, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.UseProgram(program)

        perspective := linalg.matrix4_perspective(math.to_radians(fov), f32(window.width)/f32(window.height), near, far)
        perspective_flat := linalg.matrix_flatten(perspective)
        gl.UniformMatrix4fv(perspective_uniform, 1, false, raw_data(perspective_flat[:]))

        view := linalg.matrix4_look_at(camera_pos, camera_pos + camera_dir, camera_up)
        view_flat := linalg.matrix_flatten(view)
        gl.UniformMatrix4fv(view_uniform, 1, false, raw_data(view_flat[:]))

        rotate := linalg.matrix4_rotate_f32(0, { 0, 1, 0 })
        transform := linalg.matrix_flatten(translate*rotate*scale)
        gl.UniformMatrix4fv(transform_uniform, 1, false, raw_data(transform[:]))

        gl.Uniform1f(time_uniform, time_elapsed)

        gl.BindVertexArray(vao)
        gl.DrawElements(gl.TRIANGLES, i32(len(indices)*3), gl.UNSIGNED_INT, nil)

        time_elapsed += f32(time.diff(start_time, time.now()))/f32(time.Second)
    }
}

shader_create_from_source :: proc(type: u32, source_code: string, loc := #caller_location) -> (shader: u32, ok: bool) {
    shader = gl.CreateShader(type)
    if shader == 0 {
        log.error("Unable to create shader", location = loc)
        return
    }

    gl.ShaderSource(shader, 1, raw_data([]cstring{ fmt.ctprint(source_code) }), nil)
    gl.CompileShader(shader)

    success: i32
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)

    if success == 0 {
        @(static) info_log: [512]u8
        gl.GetShaderInfoLog(shader, 512, nil, raw_data(info_log[:]))
        log.error("Unable to compile shader: %s", string(info_log[:]), location = loc)
        gl.DeleteShader(shader)
        return 0, false
    }

    return shader, true
}

create_shader_program :: proc(vertex_shader, fragment_shader: u32, loc := #caller_location) -> (program: u32, ok: bool) {
    program = gl.CreateProgram()
    if program == 0 {
        log.error("Unable to create shader program", location = loc)
        return 0, false
    }

    gl.AttachShader(program, vertex_shader)
    gl.AttachShader(program, fragment_shader)
    gl.LinkProgram(program)

    success: i32
    gl.GetProgramiv(program, gl.LINK_STATUS, &success)
    if success == 0 {
        @(static) info_log: [512]u8
        gl.GetProgramInfoLog(program, 512, nil, raw_data(info_log[:]))
        log.error("Unable to link shader program: %s", string(info_log[:]), location = loc)
        gl.DeleteProgram(program)
        return 0, false
    }

    return program, true
}

import gl "vendor:OpenGL"
import "vendor:glfw"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:c/libc"
import "core:time"
import "core:log"
import "tinyobj"
