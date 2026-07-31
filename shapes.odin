package main

// TODO: Change color type Vector3 -> Color

begin_drawing :: proc(window: ^Window) {
    when ODIN_DEBUG do assert_current_context(window)
    window.render_batch.current_transform = window_ortho(window)
    window.render_batch.draw_opts -= { .Depth_Test, .Backface_Culling }
}
end_drawing :: #force_inline proc(window: ^Window) {
    when ODIN_DEBUG do assert_current_context(window)
    render_batch(&window.render_batch)
}

begin_camera_3d :: proc(window: ^Window, camera: Camera) {
    when ODIN_DEBUG do assert_current_context(window)
    view := camera_view(camera)
    perspective := camera_perspective(camera, window_aspect(window))
    window.render_batch.current_transform = perspective * view
    window.render_batch.draw_opts += { .Depth_Test }
}
end_camera_3d :: proc(window: ^Window) {
    when ODIN_DEBUG do assert_current_context(window)
    window.render_batch.current_transform = window_ortho(window)
    window.render_batch.draw_opts -= { .Depth_Test, .Backface_Culling }
}

// ===============================[Primitive shapes]=============================== //

draw_line_3d :: proc(window: ^Window, p1, p2: Vector3, color: Color) {
    when ODIN_DEBUG do assert_current_context(window)
    append_draw_request(&window.render_batch, .Line)
    append_vertices(&window.render_batch, color, p1, p2)
}

draw_line_2d :: proc(window: ^Window, p1, p2: Vector2, color: Color) {
    when ODIN_DEBUG do assert_current_context(window)
    append_draw_request(&window.render_batch, .Line)
    append_vertices(&window.render_batch, color, add_one_component(p1), add_one_component(p2))
}

draw_triangle_2d :: proc(window: ^Window, p1, p2, p3: Vector2, color: Color) {
    when ODIN_DEBUG do assert_current_context(window)
    append_draw_request(&window.render_batch, .Triangle)
    append_vertices(&window.render_batch, color, add_one_component(p1), add_one_component(p2), add_one_component(p3))
}

draw_triangle_3d :: proc(window: ^Window, p1, p2, p3: Vector3, color: Color) {
    when ODIN_DEBUG do assert_current_context(window)
    append_draw_request(&window.render_batch, .Triangle)
    append_vertices(&window.render_batch, color, p1, p2, p3)
}

draw_rectangle_2d :: proc(window: ^Window, pos, size: Vector2, color: Color) {
    when ODIN_DEBUG do assert_current_context(window)

    append_draw_request(&window.render_batch, .Quad)
    lt := add_one_component(pos)              // left top
    rt := Vector3{ pos.x + size.x, pos.y, 1 } // right top
    lb := Vector3{ pos.x, pos.y + size.y, 1 } // left bottom
    rb := add_one_component(pos + size)       // right bottom
    append_vertices(&window.render_batch, color, lb, lt, rb, rt)
}

draw_rectangle_3d :: proc(window: ^Window, pos: Vector3, size: Vector2, yaw, pitch: f32, color: Color) {
    when ODIN_DEBUG do assert_current_context(window)

    rot_yaw := linalg.matrix4_rotate(math.to_radians(yaw), Vector3{0, 1, 0})
    rot_pitch := linalg.matrix4_rotate(math.to_radians(pitch), Vector3{1, 0, 0})
    translate := linalg.matrix4_translate(pos)

    lt4 := Vector4{ 0, 0, 0, 1}
    rt4 := Vector4{ size.x, 0, 0, 1 }
    lb4 := Vector4{ 0, -size.y, 0, 1 }
    rb4 := Vector4{ size.x, -size.y, 0, 1 }

    transform := rot_pitch * rot_yaw * translate

    lt := (transform * lt4).xyz
    rt := (transform * rt4).xyz
    lb := (transform * lb4).xyz
    rb := (transform * rb4).xyz

    append_draw_request(&window.render_batch, .Quad)
    append_vertices(&window.render_batch, color, lb, lt, rb, rt)
}

import "core:math"
import "core:math/linalg"
