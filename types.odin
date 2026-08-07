package main

Vector4 :: la.Vector4f32

Vector3  :: la.Vector3f32
Vector3i32 :: [3]i32
Vector3i :: Vector3i32

Vector2 :: la.Vector2f32

Vector4u8 :: [4]u8
Color :: Vector4u8

normalize_color :: #force_inline proc(color: Color) -> Vector4 {
    return vector_cast(f32, color)/255
}

Mat4 :: la.Matrix4f32
Mat3 :: la.Matrix3f32

identity4_f32 :: la.Matrix4f32(1)
identity3_f32 :: la.Matrix3f32(1)

identity4 :: identity4_f32
identity3 :: identity3_f32

import la "core:math/linalg"
