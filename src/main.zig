const w4 = @import("wasm4.zig");
const std = @import("std");

///  BoundedArray at the size of our grid of life
///  note: if I understood how the framebuffer really work (i saw it store x,y pos and colors) maybe it could be really optimized
const BoundedLifeArray = std.BoundedArray(bool, w4.SCREEN_SIZE * w4.SCREEN_SIZE);

///  past buffer from the newly created type
var past = BoundedLifeArray.init(w4.SCREEN_SIZE * w4.SCREEN_SIZE) catch @panic("can't create future array");

///  random
var prng: std.rand.DefaultPrng = undefined;
var random: std.rand.Random = undefined;

///  colors
const ALIVE: u32 = 0xfff6d3;
const DEAD: u32 = 0x4231;

///  frame count duuuh
var frame_count: u32 = 0;

/// used for neighbor computation
var count: u4 = 0;

/// vars used for loops
var x: usize = 0;
var y: usize = 0;
var index: usize = 0;
var alive: bool = false;
/// input
var prev_state: u8 = 0;

/// settings
var isPause: bool = false;
var sizeMouse: f32 = 5;
/// 1 == normal, increasing == slower
var speed: u32 = 1; 
var seed: u32 = 1123; 
var isInverseMode: bool = false;

/// used for drawing rectangles
var topLeftX: i32 = 0;
var topLeftY: i32 = 0;
var bottomLeftX: i32 = 0;
var bottomLeftY: i32 = 0;

///  init
export fn start() void {
    w4.PALETTE.* = .{
        ALIVE,
        DEAD,
        0xeb6b6f,
        0x7c3f58,
    };
    reset(seed);
}

/// main loop
export fn update() void {
    frame_count += 1;
    if (frame_count >= 60) {
        frame_count = 0;
    }
    computeMouse();
    input();
    gameOfLife();
    drawMouse();
}

/// set pixel from wasm4 documentation https://wasm4.org/docs/guides/basic-drawing#direct-framebuffer-access
pub fn pixel(xp: usize, yp: usize) void {
    // The byte index into the framebuffer that contains (x, y)
    const indexFrameBuffer = (@intCast(usize, yp) * 160 + @intCast(usize, xp)) >> 2;

    // Calculate the bits within the byte that corresponds to our position
    const shiftBuffer = @intCast(u3, (xp & 0b11) * 2);
    const maskBuffer = @as(u8, 0b11) << shiftBuffer;

    // Use the first DRAW_COLOR as the pixel color
    const paletteColor = @intCast(u8, w4.DRAW_COLORS.* & 0b1111);
    if (paletteColor == 0) {
        // Transparent
        return;
    }
    const computedColor = (paletteColor - 1) & 0b11;

    // Write to the framebuffer
    w4.FRAMEBUFFER[indexFrameBuffer] = (computedColor << shiftBuffer) | (w4.FRAMEBUFFER[indexFrameBuffer] & ~maskBuffer);
}

/// because i'm a bit dumb and lazy, I just re-compute the color and check if it match 
/// note: could be a good idea one day to learn how to do stuff like that
pub fn isColor(xp: usize, yp: usize, c: u16) bool {
    // The byte index into the framebuffer that contains (x, y)
    const indexFrameBuffer = (@intCast(usize, yp) * 160 + @intCast(usize, xp)) >> 2;

    // Calculate the bits within the byte that corresponds to our position
    const shiftBuffer = @intCast(u3, (xp & 0b11) * 2);
    const maskBuffer = @as(u8, 0b11) << shiftBuffer;

    // Use the first DRAW_COLOR as the pixel color
    const paletteColor = @intCast(u8, c & 0b1111);
    if (paletteColor == 0) {
        // Transparent
        return false;
    }
    const computedColor = (paletteColor - 1) & 0b11;
    //  i'm that kind of lazy
    const copy = w4.FRAMEBUFFER[indexFrameBuffer];

    // Write to the framebuffer
    return if ((computedColor << shiftBuffer) | (copy & ~maskBuffer) == w4.FRAMEBUFFER[indexFrameBuffer]) true else false;
}

/// manage input
fn input() void {
    const gamepad = w4.GAMEPAD1.*;
    const just_pressed = gamepad & (gamepad ^ prev_state);
    if (!isPause and !isInverseMode) {
        if (just_pressed & w4.BUTTON_LEFT != 0) {
            speed -= 1;
            if (speed == 0) {
                speed = 1;
            }
        }
        if (just_pressed & w4.BUTTON_RIGHT != 0) {
            speed += 1;
            if (speed > 60) {
                speed = 60;
            }
        }
    } else {
        if (just_pressed & w4.BUTTON_LEFT != 0) {
            seed -= random.intRangeAtMost(u32, 100, 500);
            if (seed == 0) {
                seed = 0;
            }
            reset(seed);
        }
        if (just_pressed & w4.BUTTON_RIGHT != 0) {
            seed += random.intRangeAtMost(u32, 100, 500);
            reset(seed);
        }
    }
    if (just_pressed & w4.BUTTON_UP != 0) {
        sizeMouse += 1;
    }
    if (just_pressed & w4.BUTTON_DOWN != 0) {
        sizeMouse -= 1;
        if (sizeMouse <= 0) {
            sizeMouse = 1;
        }
    }
    if (just_pressed & w4.BUTTON_1 != 0) {
        isPause = !isPause;
    }
    if (just_pressed & w4.BUTTON_2 != 0) {
        isInverseMode = !isInverseMode;
    }
    prev_state = gamepad;
}

///  compute the world
fn gameOfLife() void {
    //  reset globals buffer
    index = 0;
    x = 0;
    y = 0;
    if (isPause or frame_count % speed != 0) {
        //  just paint
        //  note: could do better than double loop
        while (x < w4.SCREEN_SIZE) : (x += 1) {
            while (y < w4.SCREEN_SIZE) : (y += 1) {
                index = (w4.SCREEN_SIZE * x) + y;
                alive = past.get(index);
                if (alive) {
                    w4.DRAW_COLORS.* = 0x1;
                } else {
                    w4.DRAW_COLORS.* = 0x2;
                }
                pixel(x, y);
            }
            y = 0;
        }
        return;
    }
    //  compute next life from past
    //  note: could do better than double loop
    while (x < w4.SCREEN_SIZE) : (x += 1) {
        while (y < w4.SCREEN_SIZE) : (y += 1) {
            index = (w4.SCREEN_SIZE * x) + y;
            alive = past.get(index);
            //  
            alive = nextLife(@intCast(i32, x), @intCast(i32, y), alive);
            if (alive) {
                w4.DRAW_COLORS.* = 0x1;
            } else {
                w4.DRAW_COLORS.* = 0x2;
            }
            pixel(x, y);
        }
        y = 0;
    }
    //  reset globals buffer
    //  copy the future to the past to loop computation
    x = 0;
    y = 0;
    //  note: could do better than double loop
    while (x < w4.SCREEN_SIZE) : (x += 1) {
        while (y < w4.SCREEN_SIZE) : (y += 1) {
            index = (w4.SCREEN_SIZE * x) + y;
            if (isColor(x, y, 0x1)) {
                past.set(index, true);
            }
            if (isColor(x, y, 0x2)) {
                past.set(index, false);
            }
        }
        y = 0;
    }
}

/// set state to coords
fn setLife(xp: usize, yp: usize, life: bool) void {
    index = (w4.SCREEN_SIZE * xp) + yp;
    past.set(index, life);
}

/// Draw life rectangle while keeping boundaries
fn drawRectangle(cx: i16, cy: i16, s: f32) void {
    topLeftX = cx - @floatToInt(i16, s/2);
    topLeftY = cy - @floatToInt(i16, s/2);
    bottomLeftX = cx + @floatToInt(i16, s/2);
    bottomLeftY = cy + @floatToInt(i16, s/2);
    if (topLeftX < 0) topLeftX = 0;
    if (topLeftY < 0) topLeftY = 0;
    if (topLeftX > 160) topLeftX = 160;
    if (topLeftY > 160) topLeftY = 160;
    if (bottomLeftX > 160) bottomLeftX = 160;
    if (bottomLeftY > 160) bottomLeftY = 160;
    x = @intCast(usize, topLeftX);
    y = @intCast(usize, topLeftY);
    while (x < bottomLeftX) : (x += 1) {
        while (y < bottomLeftY) : (y += 1) {
            setLife(x, y, true);
        }
        y = @intCast(usize, topLeftY);
    }
}

///  compute the mouse
fn computeMouse() void {
    //  click to create life
    if (w4.MOUSE_BUTTONS.* == w4.MOUSE_LEFT) {
        if (w4.MOUSE_X.* >= 0 and w4.MOUSE_X.* <= 160 and w4.MOUSE_Y.* >= 0 and w4.MOUSE_Y.* <= 160) {
            drawRectangle(w4.MOUSE_X.*, w4.MOUSE_Y.*, sizeMouse);
        }
    }
    if (w4.MOUSE_BUTTONS.* == w4.MOUSE_RIGHT) {
        if (w4.MOUSE_X.* >= 0 and w4.MOUSE_X.* <= 160 and w4.MOUSE_Y.* >= 0 and w4.MOUSE_Y.* <= 160) {
            setLife(@intCast(usize, w4.MOUSE_X.*), @intCast(usize, w4.MOUSE_Y.*), false);
        }
    }
}

/// visualization mouse
fn drawMouse() void {
    if (w4.MOUSE_X.* >= 0 and w4.MOUSE_X.* <= 160 and w4.MOUSE_Y.* >= 0 and w4.MOUSE_Y.* <= 160) {
        w4.DRAW_COLORS.* = 0x03;
        w4.rect(w4.MOUSE_X.* - @floatToInt(i16, sizeMouse/2), w4.MOUSE_Y.* - @floatToInt(i16, sizeMouse/2), @floatToInt(u32, sizeMouse), @floatToInt(u32, sizeMouse));
    }
}

///  reset the world
fn reset(inputSeed: u64) void {
    //  change the seed yourself
    prng = std.rand.DefaultPrng.init(inputSeed); 
    random = prng.random();
    //  reset
    x = 0;
    y = 0;
    index = 0;
    //  generate random seed
    //  note: could do better than double loop
    while (x < w4.SCREEN_SIZE) : (x += 1) {
        while (y < w4.SCREEN_SIZE) : (y += 1) {
            index = (w4.SCREEN_SIZE * x) + y;
            if (random.intRangeAtMost(i32, 0, 50) > 25) {
                past.set(index, false);
            } else {
                past.set(index, true);
            }
        }
        y = 0;
    }
}

/// compute for one cell current state
fn isSurvive(xp: i32, yp: i32) u4 {
    //  if not in bound, just fuck off
    if (xp >= w4.SCREEN_SIZE) return 0;
    if (yp >= w4.SCREEN_SIZE) return 0;
    if (xp < 0) return 0;
    if (yp < 0) return 0;
    if (past.get((w4.SCREEN_SIZE * @intCast(u32, xp)) + @intCast(u32, yp))) {
        return 1; 
    } else {
        return 0;
    }
}

/// rule of life
fn nextLife(xp: i32, yp: i32, isAlive: bool) bool {
    count = isSurvive(xp - 1, yp - 1) + isSurvive(xp, yp - 1) + isSurvive(xp + 1, yp - 1) + isSurvive(xp - 1, yp) + isSurvive(xp + 1, yp) + isSurvive(xp - 1, yp + 1) + isSurvive(xp, yp + 1) + isSurvive(xp + 1, yp + 1);
    return if (count == 3 or (isAlive and count == 2)) true else false;
}
