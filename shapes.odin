// Example:
// ```odin
// start_frame(&window)
//     // 3D
//     begin_camera_3d(&window, camera)
//         draw_line_3d(&window.render_batch, (rect_model*Vector4{-0.5, -0.5, 0, 1}).xyz, (rect_model*Vector4{ 0.5, -0.5, 0, 1}).xyz, {255, 0, 0, 0xFF})
//         draw_line_3d(&window.render_batch, (rect_model*Vector4{-0.5, -0.5, 0, 1}).xyz, (rect_model*Vector4{-0.5,  0.5, 0, 1}).xyz, {255, 0, 0, 0xFF})
//         draw_line_3d(&window.render_batch, (rect_model*Vector4{ 0.5, -0.5, 0, 1}).xyz, (rect_model*Vector4{ 0.5,  0.5, 0, 1}).xyz, {255, 0, 0, 0xFF})
//         draw_line_3d(&window.render_batch, (rect_model*Vector4{-0.5,  0.5, 0, 1}).xyz, (rect_model*Vector4{ 0.5,  0.5, 0, 1}).xyz, {255, 0, 0, 0xFF})
//
//         draw_triangle_3d(&window.render_batch,
//             {-0.5, -0.5, -2},
//             { 0.5, -0.5, -2},
//             {-0.5,  0.5, -2},
//             {0, 0, 255, 0xFF}
//         )
//
//         draw_rectangle_3d(&window.render_batch, {-1, 0.5, 2}, {2, 1}, 45, 45, {255, 0, 255, 0xFF})
//     end_camera_3d(&window)
//
//     // 2D
//     draw_line_2d(&window2.render_batch, bounce_p1, bounce_p2, {0, 255, 0, 0xFF})
//
//     triangle_rot := la.matrix2_rotate(time_elapsed)
//     triangle_pos := Vector2{300, 300}
//     draw_triangle_2d(&window2.render_batch,
//         triangle_rot * Vector2{0,   0} + triangle_pos,
//         triangle_rot * Vector2{100, 0} + triangle_pos,
//         triangle_rot * Vector2{0, 100} + triangle_pos,
//         {0, 0, 255, 0xFF}
//     )
//     draw_rectangle_2d(&window2.render_batch, vector_cast(f32, window2.mouse_pos), {10, 10}, {255, 255, 0, 0xFF})
// end_frame(&window)
// ```
package main

begin_drawing :: #force_inline proc(rb: ^Render_Batch, width, height: i32) {
    when ODIN_DEBUG do assert_current_context()
    rb.current_transform = window_ortho(width, height)
    rb.draw_opts -= { .Depth_Test, .Backface_Culling }
}
end_drawing :: #force_inline proc(rb: ^Render_Batch) {
    when ODIN_DEBUG do assert_current_context()
    render_batch(rb)
}

begin_camera_3d_rb :: proc(rb: ^Render_Batch, camera: Camera, width, height: i32) {
    when ODIN_DEBUG do assert_current_context()
    view := camera_view(camera)
    perspective := camera_perspective(camera, window_aspect(width, height))
    rb.current_transform = perspective * view
    rb.draw_opts += { .Depth_Test }
}
begin_camera_3d_window :: proc(w: ^Window, c: Camera) {
    begin_camera_3d_rb(&w.render_batch, c, w.width, w.height)
}
begin_camera_3d :: proc{
    begin_camera_3d_rb,
    begin_camera_3d_window,
}

end_camera_3d_rb :: proc(rb: ^Render_Batch, width, height: i32) {
    when ODIN_DEBUG do assert_current_context()
    rb.current_transform = window_ortho(width, height)
    rb.draw_opts -= { .Depth_Test, .Backface_Culling }
}
end_camera_3d_window :: proc(w: ^Window) {
    end_camera_3d_rb(&w.render_batch, w.width, w.height)
}
end_camera_3d :: proc{
    end_camera_3d_rb,
    end_camera_3d_window,
}

// ===============================[Primitive shapes]=============================== //

draw_line_3d :: proc(rb: ^Render_Batch, p1, p2: Vector3, color: Color) {
    when ODIN_DEBUG do assert_current_context()
    append_draw_request(rb, .Line)
    append_vertices(rb, color, p1, p2)
}

draw_line_2d :: proc(rb: ^Render_Batch, p1, p2: Vector2, color: Color) {
    when ODIN_DEBUG do assert_current_context()
    append_draw_request(rb, .Line)
    append_vertices(rb, color, add_one_component(p1), add_one_component(p2))
}

draw_triangle_2d :: proc(rb: ^Render_Batch, p1, p2, p3: Vector2, color: Color) {
    when ODIN_DEBUG do assert_current_context()
    append_draw_request(rb, .Triangle)
    append_vertices(rb, color, add_one_component(p1), add_one_component(p2), add_one_component(p3))
}

draw_triangle_3d :: proc(rb: ^Render_Batch, p1, p2, p3: Vector3, color: Color) {
    when ODIN_DEBUG do assert_current_context()
    append_draw_request(rb, .Triangle)
    append_vertices(rb, color, p1, p2, p3)
}

draw_rectangle_2d :: proc(rb: ^Render_Batch, pos, size: Vector2, color: Color) {
    when ODIN_DEBUG do assert_current_context()

    append_draw_request(rb, .Triangle_Strip)
    ltc := add_one_component(pos)              // left top
    rtc := Vector3{ pos.x + size.x, pos.y, 1 } // right top
    lbc := Vector3{ pos.x, pos.y + size.y, 1 } // left bottom
    rbc := add_one_component(pos + size)       // right bottom
    append_vertices(rb, color, lbc, ltc, rbc, rtc)
}

draw_rectangle_3d :: proc(rb: ^Render_Batch, pos: Vector3, size: Vector2, yaw, pitch: f32, color: Color) {
    when ODIN_DEBUG do assert_current_context()

    rot_yaw := la.matrix4_rotate(math.to_radians(yaw), Vector3{0, 1, 0})
    rot_pitch := la.matrix4_rotate(math.to_radians(pitch), Vector3{1, 0, 0})
    translate := la.matrix4_translate(pos)

    lt4 := Vector4{ 0, 0, 0, 1}
    rt4 := Vector4{ size.x, 0, 0, 1 }
    lb4 := Vector4{ 0, -size.y, 0, 1 }
    rb4 := Vector4{ size.x, -size.y, 0, 1 }

    transform := rot_pitch * rot_yaw * translate

    ltc := (transform * lt4).xyz
    rtc := (transform * rt4).xyz
    lbc := (transform * lb4).xyz
    rbc := (transform * rb4).xyz

    append_draw_request(rb, .Triangle_Strip)
    append_vertices(rb, color, lbc, ltc, rbc, rtc)
}

import "core:math"
import la "core:math/linalg"
