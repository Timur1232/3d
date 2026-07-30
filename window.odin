package main

window_keys_count :: 1024
window_mouse_buttons_count :: 16

Window :: struct {
    handle: glfw.WindowHandle,

    width: i32,
    height: i32,
    title: string,

    frames_count: int,

    keys: []Key_State,

    mouse_buttons: []Key_State,
    mouse_pos: Vector2_f64,
    prev_mouse_pos: Vector2_f64,
    mouse_delta: Vector2_f64,

    is_current_context: bool,
}

Create_Window_Error_Enum :: enum {
    None,
    Unable_To_Create,
}
Create_Window_Error :: union #shared_nil {
    Create_Window_Error_Enum,
    runtime.Allocator_Error,
}

// Automaticaly make created window as current context
init_window :: proc(window: ^Window, width, height: i32, title: string) -> (err: Create_Window_Error) {
    defer if err != nil {
        destroy_window(window)
    }

    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, gl_version_major)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, gl_version_minor)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, true)

    window_handle := glfw.CreateWindow(width, height, to_csrt_temp(title), nil, nil)
    if window_handle == nil {
        err = Create_Window_Error_Enum.Unable_To_Create
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

    gl.load_up_to(gl_version_major, gl_version_minor, glfw.gl_set_proc_address)
    gl.Viewport(0, 0, width, height)

    glfw.SetFramebufferSizeCallback(window_handle, proc "c" (window: glfw.WindowHandle, width, height: i32) {
        w := cast(^Window)glfw.GetWindowUserPointer(window)
        assert_contextless(w != nil)
        make_context(w)
        gl.Viewport(0, 0, width, height)
        w.height = height
        w.width = width
    })

    glfw.SetKeyCallback(window_handle, key_callback)
    glfw.SetMouseButtonCallback(window_handle, mouse_callback)
    glfw.SetCursorPosCallback(window_handle, mouse_cursor_callback)

    return
}

destroy_window :: proc(w: ^Window) {
    if w == nil do return
    if w.keys != nil do delete(w.keys)
    if w.mouse_buttons != nil do delete(w.mouse_buttons)
    free(w)
    glfw.DestroyWindow(w.handle)
    clear_context()
}

get_current_window :: proc "contextless" () -> ^Window {
    current_handle := glfw.GetCurrentContext()
    if current_handle != nil {
        current_window := cast(^Window)glfw.GetWindowUserPointer(current_handle)
        assert_contextless(current_window != nil)
        return current_window
    }
    return nil
}

// TODO: I dont know if this is a good way to handle window context
make_context :: proc "contextless" (w: ^Window) {
    if w.is_current_context do return
    current_window := get_current_window()
    if current_window != nil {
        current_window.is_current_context = false
    }
    glfw.MakeContextCurrent(w.handle)
    w.is_current_context = true
}

clear_context :: proc "contextless" () {
    current_window := get_current_window()
    if current_window != nil {
        current_window.is_current_context = false
    }
    glfw.MakeContextCurrent(nil)
}

start_frame :: proc(w: ^Window) {
    make_context(w)
}

end_frame :: proc(w: ^Window) {
    // Frames increment must be before polling events, so logic for saving frames for key presses would work.
    w.frames_count += 1
    w.prev_mouse_pos = w.mouse_pos

    // Swapping must be before polling events, because there is strange bug that would segfault on terminating glfw, presumably due to wayland generating some events on swap buffers, that need handaling.
    glfw.SwapBuffers(w.handle)

    glfw.PollEvents()

    w.mouse_delta = w.mouse_pos - w.prev_mouse_pos
}

is_key_pressed :: proc(w: ^Window, key: i32) -> bool {
    if w.keys[key].frame == null_frame do return false
    res := w.keys[key].action == glfw.PRESS && w.keys[key].frame == w.frames_count
    return res
}

is_key_down :: proc(w: ^Window, key: i32) -> bool {
    if w.keys[key].frame == null_frame do return false
    res := (w.keys[key].action == glfw.PRESS || w.keys[key].action == glfw.REPEAT) && w.keys[key].frame <= w.frames_count
    return res
}

is_key_up :: proc(w: ^Window, key: i32) -> bool {
    if w.keys[key].frame == null_frame do return false
    res := w.keys[key].action == glfw.RELEASE && w.keys[key].frame == w.frames_count
    return res
}

is_key_repeated :: proc(w: ^Window, key: i32) -> bool {
    if w.keys[key].frame == null_frame do return false
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

null_frame :: 0
invalid_action :: -1

Key_State :: struct {
    frame: int,
    action: i32, // glfw.PRESS, glfw.RELEASE, glfw.REPEAT
}

// ===============================[Callbacks]=============================== //

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    w := cast(^Window)glfw.GetWindowUserPointer(window)
    assert_contextless(w != nil)
    if int(key) < len(w.keys) {
        w.keys[key].frame = w.frames_count
        w.keys[key].action = action
    }
}

mouse_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
    w := cast(^Window)glfw.GetWindowUserPointer(window)
    assert_contextless(w != nil)
    if int(button) < len(w.mouse_buttons) {
        w.mouse_buttons[button].frame = w.frames_count
        w.mouse_buttons[button].action = action
    }
}

mouse_cursor_callback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
    w := cast(^Window)glfw.GetWindowUserPointer(window)
    assert_contextless(w != nil)
    w.mouse_pos.x = x
    w.mouse_pos.y = y
}

import "vendor:glfw"
import gl "vendor:OpenGL"
import "base:runtime"
