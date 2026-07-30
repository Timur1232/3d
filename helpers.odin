package main

TEMP_STRING_BUFFER_SIZE :: #config(TEMP_STRING_BUFFER_SIZE, 1024)
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
