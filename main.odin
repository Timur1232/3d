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

LOWEST_LOG_LEVEL : log.Level : .Debug when ODIN_DEBUG else .Info

main :: proc() {
    logger := log.create_console_logger(lowest = LOWEST_LOG_LEVEL, opt = {
        .Level,
        .Terminal_Color,
        .Short_File_Path,
        .Line,
        .Procedure,
    })
    context.logger = logger
    defer log.destroy_console_logger(logger)

    when ODIN_DEBUG {
        log_alloc: log.Log_Allocator
        log.log_allocator_init(&log_alloc, .Debug)
        context.allocator = log.log_allocator(&log_alloc)
    }

    // For repeate key event would work on wayland
    glfw.InitHint(glfw.PLATFORM, glfw.PLATFORM_X11);

    if !glfw.Init() {
        log.fatal("Unable to initialize glfw")
        return
    }
    log.info("GLFW initialized")
    defer {
        glfw.Terminate()
        log.info("GLFW terminated")
    }

    window: Window
    if err := init_window(&window, 800, 600, "Hello from OpenGL", debug = ODIN_DEBUG); err != nil {
        log.fatal("Unable to create window: %v", err)
        return
    }
    defer destroy_window(&window)

    glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)

    ok: bool
    vertex_shader: Shader
    if vertex_shader, ok = shader_create_from_source(.Vertex, vertex_shader_source); !ok {
        log.fatal("Problem with vertex shader")
        return
    }

    fragment_shader: Shader
    if fragment_shader, ok = shader_create_from_source(.Fragment, fragment_shader_source); !ok {
        log.fatal("Problem with fragment shader")
        return
    }

    program: Shader_Program
    if program, ok = shader_program_create(vertex_shader, fragment_shader); !ok {
        log.fatal("Problem with shader program")
        return
    }
    defer shader_program_delete(program)

    shader_delete(vertex_shader)
    shader_delete(fragment_shader)

    model_uniform := gl.GetUniformLocation(program.program_id, "u_model")
    view_uniform := gl.GetUniformLocation(program.program_id, "u_view")
    perspective_uniform := gl.GetUniformLocation(program.program_id, "u_perspective")

    time_uniform := gl.GetUniformLocation(program.program_id, "u_time")
    light_uniform := gl.GetUniformLocation(program.program_id, "u_light")

    light_pos := linalg.normalize(Vector3{ 1, 2, 2.5 })
    gl.ProgramUniform3fv(program.program_id, light_uniform, 1, raw_data(light_pos[:]))

    scene: tinyobj.Scene
    tinyobj_cfg := tinyobj.default_config()
    res := tinyobj.load_obj_from_memory(&scene, raw_data(model_data), len(model_data), &tinyobj_cfg, nil)
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
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, slice.size(indices), raw_data(indices), gl.STATIC_DRAW)

    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, slice.size(vertices), raw_data(vertices), gl.STATIC_DRAW)

    set_vertex_vao()

    time_elapsed: f32 = 0
    start_time: time.Time

    scale := linalg.matrix4_scale_f32({1, 1, 1})
    translate := linalg.matrix4_translate_f32({ 0, 0, -5 })

    camera: Camera

    // window2: Window
    // if err := init_window(&window2, 800, 600, "Hello from second window"); err != nil {
    //     log.fatal("Unable to create second window: %v", err)
    //     return
    // }
    // defer destroy_window(&window2)
    //
    // triangle := [?]f32 {
    //      0.0,  0.5,
    //      0.5, -0.5,
    //     -0.5, -0.5,
    // }
    //
    // vbo2: u32
    // vao2: u32
    // gl.GenBuffers(1, &vbo2)
    // gl.GenVertexArrays(1, &vao2)
    //
    // gl.BindVertexArray(vao2)
    //
    // gl.BindBuffer(gl.ARRAY_BUFFER, vbo2)
    // gl.BufferData(gl.ARRAY_BUFFER, size_of(triangle), raw_data(triangle[:]), gl.STATIC_DRAW)
    //
    // gl.VertexAttribPointer(0, 2, gl.FLOAT, false, 2*size_of(triangle[0]), 0)
    // gl.EnableVertexAttribArray(0)

    dt: f32

    for !glfw.WindowShouldClose(window.handle) {
        defer free_all(context.temp_allocator)

        start_time = time.now()
        defer {
            dt = f32(time.diff(start_time, time.now()))/f32(time.Second)
            time_elapsed += dt
        }

        {
            start_frame(&window)
            defer end_frame(&window)

            if is_key_pressed(&window, glfw.KEY_ESCAPE) {
                glfw.SetWindowShouldClose(window.handle, true)
            }
            if is_key_pressed(&window, glfw.KEY_SPACE) {
                wireframe = !wireframe
                gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE if wireframe else gl.FILL)
            }

            camera_dir := camera_direction(camera)

            forward_move_dir := i32(is_key_down(&window, glfw.KEY_W)) - i32(is_key_down(&window, glfw.KEY_S))
            if forward_move_dir != 0 {
                camera.position += f32(forward_move_dir)*camera_dir*camera_move_speed*dt
            }
            sideways_move_dir := i32(is_key_down(&window, glfw.KEY_A)) - i32(is_key_down(&window, glfw.KEY_D))
            if sideways_move_dir != 0 {
                camera_right := camera_right(camera)
                camera.position += f32(sideways_move_dir)*camera_right*camera_move_speed*dt
            }

            if is_key_down(&window, glfw.KEY_Q) {
                up := camera_up(camera)
                camera.position -= up*camera_move_speed*dt
            }
            if is_key_down(&window, glfw.KEY_E) {
                up := camera_up(camera)
                camera.position += up*camera_move_speed*dt
            }

            if window.mouse_scroll.y < 0 {
                camera.fov = clamp(camera.fov - 5, 5, 150)
            } else if window.mouse_scroll.y > 0 {
                camera.fov = clamp(camera.fov + 5, 5, 150)
            }

            sensitivity :: 0.1
            camera.angles.x += f32(window.mouse_delta.x)*sensitivity
            camera.angles.y = clamp(camera.angles.y + f32(window.mouse_delta.y)*sensitivity, -89, 89)

            gl.ClearColor(f32(0x18)/255, f32(0x18)/255, f32(0x18)/255, 1)
            gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

            shader_program_use(program)

            perspective := linalg.matrix4_perspective(math.to_radians(fov), f32(window.width)/f32(window.height), near, far)
            view := camera_view(camera)
            rotate := linalg.matrix4_rotate_f32(time_elapsed, { 0, 1, 0 })
            model := translate*rotate*scale

            model_flat := linalg.matrix_flatten(model)
            view_flat := linalg.matrix_flatten(view)
            perspective_flat := linalg.matrix_flatten(perspective)

            gl.UniformMatrix4fv(model_uniform, 1, false, raw_data(model_flat[:]))
            gl.UniformMatrix4fv(view_uniform, 1, false, raw_data(view_flat[:]))
            gl.UniformMatrix4fv(perspective_uniform, 1, false, raw_data(perspective_flat[:]))

            gl.Uniform1f(time_uniform, time_elapsed)

            gl.BindVertexArray(vao)
            gl.DrawElements(gl.TRIANGLES, i32(len(indices)*3), gl.UNSIGNED_INT, nil)
        }

        // {
        //     start_frame(&window2)
        //     defer end_frame(&window2)
        //
        //     shader_program_use(program)
        //
        //     gl.BindVertexArray(vao)
        //     gl.DrawArrays(gl.TRIANGLES, 0, len(triangle))
        // }

    }
}

import gl "vendor:OpenGL"
import "vendor:glfw"
import "core:math"
import "core:math/linalg"
import "core:time"
import "core:log"
import "tinyobj"
import "core:slice"
import "core:fmt"
