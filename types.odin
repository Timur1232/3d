package main

Vector4_f32 :: [4]f32
Vector4_f64 :: [4]f64

Vector3_f32 :: [3]f32
Vector3_f64 :: [3]f64
Vector3_i32 :: [3]i32
Vector3_u8  :: [3]u8

Vector2_f32 :: [2]f32
Vector2_f64 :: [2]f64

Vector4 :: Vector4_f32

Vector3  :: Vector3_f32
Vector3i :: Vector3_i32

Vector2 :: Vector2_f32

Color :: Vector3_u8

Mat4_f32 :: matrix[4, 4]f32
Mat3_f32 :: matrix[3, 3]f32

Mat4 :: Mat4_f32
Mat3 :: Mat3_f32

identity4_f32 :: Mat4_f32(1)
identity3_f32 :: Mat3_f32(1)

identity4 :: identity4_f32
identity3 :: identity3_f32
