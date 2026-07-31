package main

TEMP_STRING_BUFFER_SIZE :: #config(TEMP_STRING_BUFFER_SIZE, 1024*4)
TEMP_STRING_BUFFER_STATIC :: #config(TEMP_STRING_BUFFER_STATIC, true)

to_csrt_temp :: proc(str: string) -> cstring {
    when TEMP_STRING_BUFFER_STATIC {
        @(static)
        buf: [TEMP_STRING_BUFFER_SIZE]u8
        assert(len(buf) > len(str))
    } else {
        @(static)
        buf: []u8
        if len(buf) <= 0 {
            buf = make([]u8, TEMP_STRING_BUFFER_SIZE)
        }
        if len(buf) <= len(str) {
            current_len := len(buf)
            delete(buf)
            buf := make([]u8, current_len*2)
        }
    }

    copy(buf[:], str)
    buf[len(str)] = 0
    return cstring(raw_data(buf[:]))
}

add_one_component :: proc(v: $T/[$N]$E) -> [N+1]E
    where intrinsics.type_is_numeric(E) {
    vo: [N+1]E
    for i in 0..<N {
        vo[i] = v[i]
    }
    vo[N] = 1
    return vo
}

vector_cast :: proc($C: typeid, v: $T/[$N]$E) -> [N]C
    where intrinsics.type_is_numeric(C) {
    vo: [N]C
    for i in 0..<N {
        vo[i] = cast(C)v[i]
    }
    return vo
}

assert_opengl :: #force_inline proc(message := "OpenGL must be loaded", loc := #caller_location) {
    assert(gl.impl_GenBuffers != nil, message, loc)
}

assert_context_global :: #force_inline proc(message := "Current context must be set", loc := #caller_location) {
    w := get_current_window()
    assert(w != nil, message, loc)
}

assert_context_window :: #force_inline proc(window: ^Window, message := "Current context must be set", loc := #caller_location) {
    assert(window.is_current_context, message, loc)
}

assert_current_context :: proc{
    assert_context_global,
    assert_context_window,
}

normalize_color :: #force_inline proc(color: Color) -> Vector4 {
    return vector_cast(f32, color)/255
}

import "base:intrinsics"
import gl "vendor:OpenGL"
