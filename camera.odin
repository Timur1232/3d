package main

global_up := Vector3{ 0, 1, 0 }
camera_move_speed: f32 = 10
camera_turn_speed: f32 = 20

Camera :: struct {
    position: Vector3,
    angles: Vector2, // { yaw, pitch }
    fov: f32,
    near, far: f32,
}

@(require_results)
camera_view :: #force_inline proc(camera: Camera) -> Mat4 {
    view := la.matrix4_look_at(camera.position, camera.position + camera_direction(camera), camera_up(camera))
    return view
}

camera_perspective :: #force_inline proc(camera: Camera, aspect: f32) -> Mat4 {
    perspective := la.matrix4_perspective(math.to_radians(camera.fov), aspect, camera.near, camera.far)
    return perspective
}

@(require_results)
camera_direction :: #force_inline proc(camera: Camera) -> Vector3 {
    yaw := camera.angles.x
    pitch := camera.angles.y

    rot_yaw   := la.matrix3_rotate(math.to_radians(yaw), Vector3{0, 1, 0})
    rot_pitch := la.matrix3_rotate(math.to_radians(pitch), Vector3{1, 0, 0})

    dir := Vector3{ 0, 0, -1 } // forward
    dir *= rot_pitch * rot_yaw

    return dir
}

@(require_results)
camera_right :: #force_inline proc(camera: Camera) -> Vector3 {
    dir := camera_direction(camera)
    return la.normalize(la.cross(global_up, dir))
}

@(require_results)
camera_up :: #force_inline proc(camera: Camera) -> Vector3 {
    dir := camera_direction(camera)
    right := la.normalize(la.cross(global_up, dir))
    return la.cross(dir, right)
}

import "core:math"
import la "core:math/linalg"
