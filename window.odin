package main

window_keys_count :: 1024
window_mouse_buttons_count :: 16

Window :: struct {
    handle: glfw.WindowHandle,

    width: i32,
    height: i32,
    title: string,

    frames_count: u64,

    keys: []Key_State,

    mouse_buttons: []Key_State,
    mouse_pos: Vector2_f64,
    prev_mouse_pos: Vector2_f64,
    mouse_delta: Vector2_f64,
    mouse_scroll: Vector2_f64,

    render_batch: Render_Batch,

    is_current_context: bool,
}

Create_Window_Error_Enum :: enum {
    None,
    Create_Window_Err,
    Init_Render_Batch_Err,
}
Create_Window_Error :: union #shared_nil {
    Create_Window_Error_Enum,
    runtime.Allocator_Error,
}

DEFAULT_RENDER_BATCH_VERTEX_CAPACITY :: 1024*4
DEFAULT_RENDER_BATCH_DRAWS_CAPACITY  :: 256

// Automaticaly make created window as current context
init_window :: proc(window: ^Window, width, height: i32, title: string, debug := false) -> (err: Create_Window_Error) {
    defer if err != nil {
        destroy_window(window)
        log.error("Unable to create window: %v", err)
    }

    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, true)

    window_handle := glfw.CreateWindow(width, height, to_csrt_temp(title), nil, nil)
    if window_handle == nil {
        err = Create_Window_Error_Enum.Create_Window_Err
        return
    }
    window.handle = window_handle
    window.width = width
    window.height = height
    window.title = title

    glfw.SetWindowUserPointer(window_handle, window)

    window.keys = make([]Key_State, window_keys_count) or_return
    window.mouse_buttons = make([]Key_State, window_mouse_buttons_count) or_return

    make_context(window)

    glfw.SwapInterval(1)

    gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)
    gl.Viewport(0, 0, width, height)

    glfw.SetFramebufferSizeCallback(window_handle, proc "c" (window: glfw.WindowHandle, width, height: i32) {
        w := cast(^Window)glfw.GetWindowUserPointer(window)
        assert_contextless(w != nil)

        current_window := make_context(w)

        w.height = height
        w.width = width
        gl.Viewport(0, 0, width, height)

        if current_window != nil {
            make_context(current_window)
        }
    })

    glfw.SetKeyCallback(window_handle, key_callback)
    glfw.SetMouseButtonCallback(window_handle, mouse_callback)
    glfw.SetCursorPosCallback(window_handle, mouse_cursor_callback)
    glfw.SetScrollCallback(window_handle, mouse_scroll_callback)
    glfw.SetCursorEnterCallback(window_handle, mouse_cursor_enter_callback)

    if debug {
        gl.Enable(gl.DEBUG_OUTPUT)
        gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
        gl.DebugMessageCallback(proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, userParam: rawptr) {
            libc.printf("OpenGL message: %s\n", message)
        }, nil)
        log.info("Debug output is enabled")
    }

    gl.Enable(gl.DEPTH_TEST)
    // gl.Enable(gl.CULL_FACE)

    if ok := render_batch_init(&window.render_batch, DEFAULT_RENDER_BATCH_VERTEX_CAPACITY, DEFAULT_RENDER_BATCH_DRAWS_CAPACITY); !ok {
        log.error("Unable to initialize render batch")
        err = Create_Window_Error_Enum.Init_Render_Batch_Err
        return
    }

    log.infof("Window created\n    TITLE: %s\n    WIDTH: %v\n    HIEGHT: %v", title, width, height)

    return
}

destroy_window :: proc(w: ^Window) {
    if w == nil do return
    if w.keys != nil do delete(w.keys)
    if w.mouse_buttons != nil do delete(w.mouse_buttons)
    make_context(w)
    glfw.SetWindowUserPointer(w.handle, nil)
    glfw.DestroyWindow(w.handle)
    clear_context()
    render_batch_destroy(&w.render_batch)

    log.infof("Window (title: \"%s\") closed", w.title)

    w^ = {} // null the fields
}

get_current_window :: #force_inline proc "contextless" () -> ^Window {
    current_handle := glfw.GetCurrentContext()
    if current_handle != nil {
        current_window := cast(^Window)glfw.GetWindowUserPointer(current_handle)
        assert_contextless(current_window != nil)
        return current_window
    }
    return nil
}

get_window_from_handle :: #force_inline proc "contextless" (handle: glfw.WindowHandle) -> ^Window {
    w := cast(^Window)glfw.GetWindowUserPointer(handle)
    assert_contextless(w != nil)
    return w
}

// TODO: I dont know if this is a good way to handle window context
//
// Returns window of previous context (before MakeContextCurrent call) if there was any or nil
make_context :: proc "contextless" (w: ^Window) -> ^Window {
    if w.is_current_context do return nil
    current_window := get_current_window()
    if current_window != nil {
        current_window.is_current_context = false
    }
    glfw.MakeContextCurrent(w.handle)
    w.is_current_context = true
    return current_window
}

clear_context :: proc "contextless" () {
    current_window := get_current_window()
    if current_window != nil {
        current_window.is_current_context = false
    }
    glfw.MakeContextCurrent(nil)
}

start_frame :: #force_inline proc(w: ^Window) {
    make_context(w)
}

end_frame :: proc(w: ^Window) {
    // Frames increment must be before polling events, so logic for saving frames for key presses would work.
    w.frames_count += 1
    w.prev_mouse_pos = w.mouse_pos

    // Swapping must be before polling events, because there is strange bug that would segfault on terminating glfw, presumably due to wayland generating some events on swap buffers, that need handaling.
    glfw.SwapBuffers(w.handle)

    w.mouse_scroll = 0
    w.mouse_delta = 0
}

start_3d :: proc(w: ^Window, camera: Camera) {
    begin_camera_3d(&w.render_batch, w, camera)
}

end_3d :: proc(w: ^Window) {
    end_camera_3d(&w.render_batch, w)
}

window_aspect :: #force_inline proc(w: ^Window) -> f32 {
    return f32(w.width) / f32(w.height)
}

// ===============================[Input]=============================== //

is_key_pressed :: proc(w: ^Window, key: i32) -> bool {
    if w.keys[key].frame == 0 do return false
    res := w.keys[key].action == glfw.PRESS && w.keys[key].frame == w.frames_count
    return res
}

is_key_down :: proc(w: ^Window, key: i32) -> bool {
    if w.keys[key].frame == 0 do return false
    res := (w.keys[key].action == glfw.PRESS || w.keys[key].action == glfw.REPEAT) && w.keys[key].frame <= w.frames_count
    return res
}

is_key_up :: proc(w: ^Window, key: i32) -> bool {
    if w.keys[key].frame == 0 do return false
    res := w.keys[key].action == glfw.RELEASE && w.keys[key].frame == w.frames_count
    return res
}

is_key_repeated :: proc(w: ^Window, key: i32) -> bool {
    if w.keys[key].frame == 0 do return false
    res := w.keys[key].action == glfw.REPEAT && w.keys[key].frame == w.frames_count
    return res
}

is_mouse_pressed :: proc(w: ^Window, button: i32) -> bool {
    if w.mouse_buttons[button].frame == 0 do return false
    res := w.mouse_buttons[button].action == glfw.PRESS && w.mouse_buttons[button].frame == w.frames_count
    return res
}

is_mouse_down :: proc(w: ^Window, button: i32) -> bool {
    if w.mouse_buttons[button].frame == 0 do return false
    res := (w.mouse_buttons[button].action == glfw.PRESS || w.mouse_buttons[button].action == glfw.REPEAT) && w.mouse_buttons[button].frame <= w.frames_count
    return res
}

is_mouse_up :: proc(w: ^Window, button: i32) -> bool {
    if w.mouse_buttons[button].frame == 0 do return false
    res := w.mouse_buttons[button].action == glfw.RELEASE && w.mouse_buttons[button].frame == w.frames_count
    return res
}

Key_State :: struct {
    frame: u64,
    action: i32, // glfw.PRESS, glfw.RELEASE, glfw.REPEAT
}

// ===============================[Callbacks]=============================== //

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    w := get_window_from_handle(window)
    if int(key) < len(w.keys) {
        w.keys[key].frame = w.frames_count
        w.keys[key].action = action
    }
}

mouse_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
    w := get_window_from_handle(window)
    if int(button) < len(w.mouse_buttons) {
        w.mouse_buttons[button].frame = w.frames_count
        w.mouse_buttons[button].action = action
    }
}

mouse_cursor_callback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
    w := get_window_from_handle(window)
    w.prev_mouse_pos = w.mouse_pos
    w.mouse_pos.x = x
    w.mouse_pos.y = y
    w.mouse_delta = w.mouse_pos - w.prev_mouse_pos
}

mouse_scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
    w := get_window_from_handle(window)
    w.mouse_scroll.x = xoffset
    w.mouse_scroll.y = yoffset
}

mouse_cursor_enter_callback :: proc "c" (window: glfw.WindowHandle, entered: i32) {
    // w := get_window_from_handle(window)
}

// ===============================[Other]=============================== //

window_ortho :: #force_inline proc(window: ^Window) -> Mat4 {
    return linalg.matrix_ortho3d_f32(0, f32(window.width), f32(window.height), 0, 0, math.F32_MAX)
}

import "vendor:glfw"
import gl "vendor:OpenGL"
import "base:runtime"
import "core:c/libc"
import "core:log"
import "core:math"
import "core:math/linalg"
