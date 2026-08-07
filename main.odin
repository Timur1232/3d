package main

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

ASSETS_DIR :: "assets/"
MODELS_DIR :: ASSETS_DIR+"models/"
SHADERS_DIR :: ASSETS_DIR+"shaders/"

MODEL_PATH :: MODELS_DIR+"monkey.obj"
@(private="file")
model_data := #load(MODEL_PATH)

@(private="file")
vs_source := #load(SHADERS_DIR+"vs.glsl")
@(private="file")
flat_fs_source := #load(SHADERS_DIR+"flat_fs.glsl")
@(private="file")
smooth_fs_source := #load(SHADERS_DIR+"smooth_fs.glsl")

@(private="file")
wireframe_vs_source := #load(SHADERS_DIR+"wireframe_vs.glsl")
@(private="file")
wireframe_fs_source := #load(SHADERS_DIR+"wireframe_fs.glsl")

FOV  : f32 : 60
NEAR :: 0.1
FAR  :: 100

LOWEST_LOG_LEVEL : log.Level : .Debug when ODIN_DEBUG else .Info

BACKGROUND_COLOR :: Color{ 0x10, 0x10, 0x10, 0xFF }

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

    ok: bool
    shader_flat: Shader
    shader_flat, ok = shader_create_from_source(vs_source, flat_fs_source)
    if !ok {
        log.fatal("Problem with shader program")
        return
    }
    defer shader_delete(shader_flat)

    light_pos := la.normalize(Vector3{ 1, 2, 2.5 })
    shader_default_uniform(shader_flat, .Light_Pos, light_pos)

    shader_smooth: Shader
    shader_smooth, ok = shader_create_from_source(vs_source, smooth_fs_source)
    if !ok {
        log.fatal("Problem with shader program")
        return
    }
    defer shader_delete(shader_smooth)

    shader_default_uniform(shader_smooth, .Light_Pos, light_pos)

    shader_wireframe: Shader
    shader_wireframe, ok = shader_create_from_source(wireframe_vs_source, wireframe_fs_source)
    if !ok {
        log.error("Problem with wireframe shader program")
    }
    defer shader_delete(shader_wireframe)

    wireframe_color_uniform := gl.GetUniformLocation(shader_wireframe.id, "u_wireframe_color")
    gl.ProgramUniform3f(shader_wireframe.id, wireframe_color_uniform, 0, 0, 0)

    scene: tinyobj.Scene
    tinyobj_cfg := tinyobj.default_config()
    res := tinyobj.load_obj_from_memory(&scene, raw_data(model_data), len(model_data), &tinyobj_cfg, nil)
    if res != .Ok {
        log.error("Unable to load obj file %s: %s", MODEL_PATH, tinyobj.result_string(res))
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
            vertices[idx.vertex_index].normal += {
                scene.attrib.normals.ptr[idx.normal_index*3 + 0],
                scene.attrib.normals.ptr[idx.normal_index*3 + 1],
                scene.attrib.normals.ptr[idx.normal_index*3 + 2],
            }
        }

        for &v in vertices {
            v.normal = la.normalize(v.normal)
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

    set_vertex_attributes(Vertex)

    time_elapsed: f32 = 0
    start_time: time.Time

    scale := la.matrix4_scale_f32({1, 1, 1})
    translate := la.matrix4_translate_f32({ 0, 0, -5 })

    wireframe := false
    show_normals := false
    draw_flat_shader := true

    camera: Camera
    camera.position = {-3.6456196, 1.63629258, 1.87133658}
    camera.angles = {49.500004, 20.49999}
    camera.fov = FOV
    camera.near = NEAR
    camera.far = FAR

    dt: f32

    window2: Window
    defer if window_valid(&window2) do destroy_window(&window2)

    bounce_p1 := Vector2(10)
    bounce_vel1 := Vector2{ 5, 5 }
    bounce_p2 := Vector2(150)
    bounce_vel2 := Vector2{ 5, -5 }

    capture_cursor := false

    for !glfw.WindowShouldClose(window.handle) {
        defer free_all(context.temp_allocator)

        glfw.PollEvents()

        start_time = time.now()
        defer {
            dt = f32(time.diff(start_time, time.now()))/f32(time.Second)
            time_elapsed += dt
        }

        // Main window
        {
            start_frame(&window)
            defer end_frame(&window)

            if is_key_pressed(&window, glfw.KEY_ESCAPE) {
                glfw.SetWindowShouldClose(window.handle, true)
                log.info("Close request")
            }
            if is_key_pressed(&window, glfw.KEY_SPACE) {
                wireframe = !wireframe
                log.info("WIREFRAME:", wireframe)
            }

            if is_key_pressed(&window, glfw.KEY_1) {
                if err := init_window(&window2, 500, 500, "Hello from second window", debug = ODIN_DEBUG); err != nil {
                    log.fatal("Unable to create second window: %v", err)
                    return
                }
                make_context(&window)
            }

            camera_dir := camera_direction(camera)

            moving_slow := false
            if is_key_down(&window, glfw.KEY_LEFT_SHIFT) {
                moving_slow = true
            }

            forward_move_dir := i32(is_key_down(&window, glfw.KEY_W)) - i32(is_key_down(&window, glfw.KEY_S))
            if forward_move_dir != 0 {
                speed := camera_move_speed * (0.3 if moving_slow else 1)
                camera.position += f32(forward_move_dir)*camera_dir*speed*dt
            }
            sideways_move_dir := i32(is_key_down(&window, glfw.KEY_A)) - i32(is_key_down(&window, glfw.KEY_D))
            if sideways_move_dir != 0 {
                speed := camera_move_speed * (0.3 if moving_slow else 1)
                camera_right := camera_right(camera)
                camera.position += f32(sideways_move_dir)*camera_right*speed*dt
            }

            if is_key_down(&window, glfw.KEY_Q) {
                speed := camera_move_speed * (0.3 if moving_slow else 1)
                camera.position -= global_up*speed*dt
            }
            if is_key_down(&window, glfw.KEY_E) {
                speed := camera_move_speed * (0.3 if moving_slow else 1)
                camera.position += global_up*speed*dt
            }

            if window.mouse_scroll.y < 0 {
                camera.fov = clamp(camera.fov + 5, 5, 150)
                log.info("FOV:", camera.fov)
            } else if window.mouse_scroll.y > 0 {
                camera.fov = clamp(camera.fov - 5, 5, 150)
                log.info("FOV:", camera.fov)
            }

            if is_key_pressed(&window, glfw.KEY_N) {
                show_normals = !show_normals
                log.info("SHOW NORMALS:", show_normals)
            }
            if is_key_pressed(&window, glfw.KEY_F) {
                draw_flat_shader = !draw_flat_shader
                log.info("FLAT SHADING:", draw_flat_shader)
            }

            if is_key_pressed(&window, glfw.KEY_C) {
                log.infof("Camera info:\n    POSITION: %v\n    ANGLES: %v\n    FOV: %v\n    NEAR: %v\n    FAR: %v", camera.position, camera.angles, camera.fov, camera.near, camera.far)
            }

            if is_mouse_pressed(&window, glfw.MOUSE_BUTTON_LEFT) {
                capture_cursor = !capture_cursor
                glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED if capture_cursor else glfw.CURSOR_NORMAL)
                log.info("CURSOR CAPTURE:", capture_cursor)
            }

            if capture_cursor {
                sensitivity :: 0.15
                camera.angles.x += f32(window.mouse_delta.x)*sensitivity
                camera.angles.y = clamp(camera.angles.y + f32(window.mouse_delta.y)*sensitivity, -89, 89)
            }

            clear_color( BACKGROUND_COLOR)

            current_shader := shader_flat if draw_flat_shader else shader_smooth

            shader_use(current_shader)

            perspective := camera_perspective(camera, window_aspect(window.width, window.height))
            view := camera_view(camera)
            rotate := la.matrix4_rotate_f32(0, { 0, 1, 0 })
            model := translate*rotate*scale

            shader_default_uniform(current_shader, .Time, time_elapsed)
            shader_default_uniform(current_shader, .Model, model)
            shader_default_uniform(current_shader, .View, view)
            shader_default_uniform(current_shader, .Perspective, perspective)

            gl.BindVertexArray(vao)
            gl.DrawElements(gl.TRIANGLES, i32(len(indices)*3), gl.UNSIGNED_INT, nil)

            if wireframe {
                gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
                shader_use(shader_wireframe)

                shader_default_uniform(shader_wireframe, .Model, model)
                shader_default_uniform(shader_wireframe, .Perspective, perspective)
                shader_default_uniform(shader_wireframe, .View, view)

                gl.DrawElements(gl.TRIANGLES, i32(len(indices)*3), gl.UNSIGNED_INT, nil)
                gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
            }

            rect_rot := la.matrix4_rotate_f32(-time_elapsed, {0, 1, 0})
            rect_trans := la.matrix4_translate_f32({0, 0, -2})
            rect_model := rect_trans*rect_rot

            begin_camera_3d(&window, camera)

                if show_normals {
                    for v in vertices {
                        draw_line_3d(&window.render_batch, (model*add_one_component(v.position)).xyz, (model*add_one_component(v.position + v.normal/4)).xyz, {0, 0, 255, 0xFF})
                    }
                }

                draw_line_3d(&window.render_batch, (rect_model*Vector4{-0.5, -0.5, 0, 1}).xyz, (rect_model*Vector4{ 0.5, -0.5, 0, 1}).xyz, {255, 0, 0, 0xFF})
                draw_line_3d(&window.render_batch, (rect_model*Vector4{-0.5, -0.5, 0, 1}).xyz, (rect_model*Vector4{-0.5,  0.5, 0, 1}).xyz, {255, 0, 0, 0xFF})
                draw_line_3d(&window.render_batch, (rect_model*Vector4{ 0.5, -0.5, 0, 1}).xyz, (rect_model*Vector4{ 0.5,  0.5, 0, 1}).xyz, {255, 0, 0, 0xFF})
                draw_line_3d(&window.render_batch, (rect_model*Vector4{-0.5,  0.5, 0, 1}).xyz, (rect_model*Vector4{ 0.5,  0.5, 0, 1}).xyz, {255, 0, 0, 0xFF})

                draw_triangle_3d(&window.render_batch,
                    {-0.5, -0.5, -2},
                    { 0.5, -0.5, -2},
                    {-0.5,  0.5, -2},
                    {0, 0, 255, 0xFF}
                )

                draw_rectangle_3d(&window.render_batch, {-1, 0.5, 2}, {2, 1}, 45, 45, {255, 0, 255, 0xFF})
            end_camera_3d(&window)

            if !capture_cursor {
                mouse_pos := vector_cast(f32, window.mouse_pos)
                draw_triangle_2d(
                    &window.render_batch,
                    mouse_pos,
                    mouse_pos + {20, 0},
                    mouse_pos + {0, 20},
                    {255, 255, 0, 0xFF}
                )
                draw_line_2d(&window.render_batch, mouse_pos, mouse_pos + vector_cast(f32, window.mouse_delta), {0, 0, 255, 0xFF})
            }
        }

        // Second window
        if window_valid(&window2) {
            defer if glfw.WindowShouldClose(window2.handle) {
                destroy_window(&window2)
            }

            start_frame(&window2)
            defer end_frame(&window2)

            new_bounce_p1 := bounce_p1 + bounce_vel1
            if new_bounce_p1.x <= 0 || new_bounce_p1.x >= f32(window2.width) {
                new_bounce_p1.x = clamp(new_bounce_p1.x, 0, f32(window2.width))
                bounce_vel1.x = -bounce_vel1.x
            }
            if new_bounce_p1.y <= 0 || new_bounce_p1.y >= f32(window2.height) {
                new_bounce_p1.y = clamp(new_bounce_p1.y, 0, f32(window2.height))
                bounce_vel1.y = -bounce_vel1.y
            }
            new_bounce_p2 := bounce_p2 + bounce_vel2
            if new_bounce_p2.x <= 0 || new_bounce_p2.x >= f32(window2.width) {
                new_bounce_p2.x = clamp(new_bounce_p2.x, 0, f32(window2.width))
                bounce_vel2.x = -bounce_vel2.x
            }
            if new_bounce_p2.y <= 0 || new_bounce_p2.y >= f32(window2.height) {
                new_bounce_p2.y = clamp(new_bounce_p2.y, 0, f32(window2.height))
                bounce_vel2.y = -bounce_vel2.y
            }

            bounce_p1 = new_bounce_p1
            bounce_p2 = new_bounce_p2

            clear_color(BACKGROUND_COLOR)

            draw_line_2d(&window2.render_batch, bounce_p1, bounce_p2, {0, 255, 0, 0xFF})

            triangle_rot := la.matrix2_rotate(time_elapsed)
            triangle_pos := Vector2{300, 300}

            draw_triangle_2d(&window2.render_batch,
                triangle_rot * Vector2{0,   0} + triangle_pos,
                triangle_rot * Vector2{100, 0} + triangle_pos,
                triangle_rot * Vector2{0, 100} + triangle_pos,
                {0, 0, 255, 0xFF}
            )

            draw_rectangle_2d(&window2.render_batch, vector_cast(f32, window2.mouse_pos), {10, 10}, {255, 255, 0, 0xFF})
        }
    }
}

import gl "vendor:OpenGL"
import "vendor:glfw"
import la "core:math/linalg"
import "core:time"
import "core:log"
import "tinyobj"
import "core:slice"
