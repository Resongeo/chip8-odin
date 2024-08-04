package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

Chip8State :: struct {
    memory: [4096]u8,   // 4 KiB zero initialized memory
    display: [DISPLAY_WIDTH * DISPLAY_HEIGHT]bool,
    pc: u16,            // program counter
    i: u16,             // index register
    v: [16]u8,          // variable register
    stack: [16]u16,
    sp: u8,             // stack pointer
    keys: [16]bool,     // state of the keys
    delay_timer: u8,
    sound_timer: u8,
}

@(private="file")
font := []u8 {
	0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
	0x20, 0x60, 0x20, 0x20, 0x70, // 1
	0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
	0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
	0x90, 0x90, 0xF0, 0x10, 0x10, // 4
	0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
	0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
	0xF0, 0x10, 0x20, 0x40, 0x40, // 7
	0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
	0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
	0xF0, 0x90, 0xF0, 0x90, 0x90, // A
	0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
	0xF0, 0x80, 0x80, 0x80, 0xF0, // C
	0xE0, 0x90, 0x90, 0x90, 0xE0, // D
	0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
	0xF0, 0x80, 0xF0, 0x80, 0x80  // F
}

chip8_state_initialize :: proc() -> ^Chip8State {
    state: ^Chip8State = new(Chip8State)
    copy(state.memory[:], font)

    if len(os.args) < 2 {
        fmt.println("Missing arguments. No ROM path provided")
        os.exit(1)
    }

    rom_path := os.args[1]
    file, err := os.open(rom_path)
    if err != os.ERROR_NONE {
        fmt.println("Could not open ROM:", rom_path)
        os.close(file)
        os.exit(1)
    }

    _, err = os.read(file, state.memory[ROM_ADDRESS:])
    if err != os.ERROR_NONE {
        fmt.println("Could not read from ROM:", rom_path)
        os.close(file)
        os.exit(1)
    }

    state.pc = ROM_ADDRESS

    rl.SetTraceLogLevel(rl.TraceLogLevel.NONE)
    rl.InitWindow(DISPLAY_WIDTH * DISPLAY_SCALE, DISPLAY_HEIGHT * DISPLAY_SCALE, "Odin CHIP-8")
    rl.SetTargetFPS(TARGET_FPS)

    return state
}

chip8_run :: proc(state: ^Chip8State) {
    for !rl.WindowShouldClose() {
        chip8_update_input(state)

        for _ in 0..<STEPS_PER_FRAME {
            chip8_step(state)
        }

        //chip8_decrement_timers(state)

        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.BLACK)

        // rendering
        for y in 0..<DISPLAY_HEIGHT {
            for x in 0..<DISPLAY_WIDTH {
                index := y * DISPLAY_WIDTH + x
                if state.display[index] {
                    rl.DrawRectangle(
                        i32(x * DISPLAY_SCALE),
                        i32(y * DISPLAY_SCALE),
                        DISPLAY_SCALE,
                        DISPLAY_SCALE,
                        rl.RAYWHITE
                    )
                }
            }
        }
    }
}

@(private="file")
chip8_step :: proc(state: ^Chip8State) {
    chip8_decrement_timers(state)

    // fetch opcode
    op := u16(state.memory[state.pc]) << 8 | u16(state.memory[state.pc + 1])
    state.pc += 2

	x   := u8((op & 0x0F00) >> 8)
	y   := u8((op & 0x00F0) >> 4)
	n   := u8(op & 0x000F)
	nn  := u8(op & 0x00FF)
	nnn := op & 0x0FFF

    switch op & 0xF000 {
        case 0x0000:
            switch op {
                // clear display
                case 0x00E0:
                    for _, index in state.display {
                        state.display[index] = false
                    }

                // returning from subroutine
                case 0x00EE:
                    state.sp -= 1
                    state.pc = state.stack[state.sp]
            }

        // jump
        case 0x1000:
            state.pc = nnn

        // call subroutine
        case 0x2000:
            state.stack[state.sp] = state.pc
            state.sp += 1
            state.pc = nnn

        // skip conditionally
        case 0x3000:
            if state.v[x] == nn {
                state.pc += 2
            }

        // skip conditionally
        case 0x4000:
            if state.v[x] != nn {
                state.pc += 2
            }

        // skip conditionally
        case 0x5000:
            if state.v[x] == state.v[y] {
                state.pc += 2
            }

        // set
        case 0x6000:
            state.v[x] = nn

        // add
        case 0x7000:
            state.v[x] += nn

        // logical and arithmetic instructions
        case 0x8000:
            switch op & 0x000F {
                // set
                case 0x0:
                    state.v[x] = state.v[y]
                
                // binary or
                case 0x1:
                    state.v[x] |= state.v[y]
                
                // binary and
                case 0x2:
                    state.v[x] &= state.v[y]
                
                // logical xor
                case 0x3:
                    state.v[x] ~= state.v[y]
                
                // add
                case 0x4:
                    result: u16 = u16(state.v[x]) + u16(state.v[y])
                    state.v[CARRY_FLAG] = result > 255 ? 1 : 0
                    state.v[x] = u8(result)
                
                // subtract
                case 0x5:
                    state.v[x] = state.v[x] - state.v[y]
                    state.v[CARRY_FLAG] = state.v[x] > state.v[y] ? 1 : 0

                // shift
                case 0x6:
                    state.v[CARRY_FLAG] = state.v[x] & 0x1 == 1 ? 1 : 0
                    state.v[x] >>= 1

                // subtract
                case 0x7:
                    state.v[x] = state.v[y] - state.v[x]
                    state.v[CARRY_FLAG] = state.v[y] > state.v[x] ? 1 : 0

                // shift
                case 0xE:
                    state.v[CARRY_FLAG] = state.v[x] >> 7
                    state.v[x] <<= 1
            }

        // skip conditionally
        case 0x9000:
            if state.v[x] != state.v[y] {
                state.pc += 2
            }

        // set index
        case 0xA000:
            state.i = nnn
        
        // jump with offset
        case 0xB000:
            state.pc = u16(state.v[0]) + nnn
        
        // random
        case 0xC000:
            state.v[x] = u8(rl.GetRandomValue(0, 255)) & nn

        // display
        case 0xD000:
            state.v[CARRY_FLAG] = 0
            sprite_x_pos := state.v[x] % DISPLAY_WIDTH
            sprite_y_pos := state.v[y] % DISPLAY_HEIGHT

            for row in 0..<n {
                pixel_y_pos := sprite_y_pos + row
                if pixel_y_pos >= DISPLAY_HEIGHT {
                    break
                }

                sprite_row := state.memory[state.i + u16(row)]

                for col in 0..<8 {
                    pixel_x_pos := sprite_x_pos + u8(col)
                    if pixel_x_pos >= DISPLAY_WIDTH {
                        break
                    }

                    pixel_index := u16(pixel_y_pos) * DISPLAY_WIDTH + u16(pixel_x_pos)

                    should_swap_pixel := bool((sprite_row >> (7 - u8(col))) & 1)
                    pixel_is_on := state.display[pixel_index]

                    if should_swap_pixel {
                        if pixel_is_on {
                            state.display[pixel_index] = false
                            state.v[CARRY_FLAG] = 1
                        } else {
                            state.display[pixel_index] = true
                        }
                    }
                }
            }
        
        // skip if key
        case 0xE000:
            switch op & 0x00FF {
                // pressed
                case 0x9E:
                    if state.keys[state.v[x]] {
                        state.pc += 2
                    }
                
                // not pressed
                case 0xA1:
                    if !state.keys[state.v[x]] {
                        state.pc += 2
                    }
            }
        
        // timers, add to index, get key
        case 0xF000:
            switch op & 0x00FF {
                // set
                case 0x07:
                    state.v[x] = state.delay_timer

                // set
                case 0x15:
                    state.delay_timer = state.v[x]

                // set
                case 0x18:
                    state.sound_timer = state.v[x]

                // add to index
                case 0x1E:
                    state.i += u16(state.v[x])

                // get key
                case 0x0A:
                    for key in 0..<16 {
                        if state.keys[key] {
                            state.v[x] = u8(key)
                            return
                        }
                    }

                    state.pc -= 2

                // font character
                case 0x29:
                    state.i = u16(state.v[x]) * FONT_SIZE

                // binary-coded decimal conversion
                case 0x33:
                    value := state.v[x]
                    ones := value % 10
                    value /= 10
                    tens := value % 10
                    value /= 10
                    hundreds := value

                    state.memory[state.i] = hundreds
                    state.memory[state.i + 1] = tens
                    state.memory[state.i + 2] = ones
                
                // store and load memory
                case 0x55:
                    for offset in 0..=x {
                        state.memory[state.i + u16(offset)] = state.v[offset]
                    }
                
                // store and load memory
                case 0x65:
                    for offset in 0..=x {
                        state.v[offset] = state.memory[state.i + u16(offset)]
                    }
            }
    }
}

@(private="file")
chip8_update_input :: proc(state: ^Chip8State) {
	// key release
    if rl.IsKeyPressed(rl.KeyboardKey.X) {
		state.keys[0] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.ONE) {
		state.keys[1] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.TWO) {
		state.keys[2] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.THREE) {
		state.keys[3] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.Q) {
		state.keys[4] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.W) {
		state.keys[5] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.E) {
		state.keys[6] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.A) {
		state.keys[7] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.S) {
		state.keys[8] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.D) {
		state.keys[9] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.Z) {
		state.keys[10] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.C) {
		state.keys[11] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.FOUR) {
		state.keys[12] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.R) {
		state.keys[13] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.F) {
		state.keys[14] = true
	}
	if rl.IsKeyPressed(rl.KeyboardKey.V) {
		state.keys[15] = true
	}

	// key release
	if rl.IsKeyReleased(rl.KeyboardKey.X) {
		state.keys[0] = false
	}
	if rl.IsKeyReleased(rl.KeyboardKey.ONE) {
		state.keys[1] = false
	}
	if rl.IsKeyReleased(rl.KeyboardKey.TWO) {
		state.keys[2] = false
	}
	if rl.IsKeyReleased(rl.KeyboardKey.THREE) {
		state.keys[3] = false
	}
	if rl.IsKeyReleased(rl.KeyboardKey.Q) {
        state.keys[4] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.W) {
        state.keys[5] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.E) {
        state.keys[6] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.A) {
        state.keys[7] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.S) {
        state.keys[8] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.D) {
        state.keys[9] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.Z) {
        state.keys[10] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.C) {
        state.keys[11] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.FOUR) {
        state.keys[12] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.R) {
        state.keys[13] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.F) {
        state.keys[14] = false
    }
    if rl.IsKeyReleased(rl.KeyboardKey.V) {
        state.keys[15] = false
    }
}

@(private="file")
chip8_decrement_timers :: proc(state: ^Chip8State) {
    delay := i16(state.delay_timer) - 1
	delay = max(delay, 0)
	state.delay_timer = u8(delay)

	sound := i16(state.sound_timer) - 1
	sound = max(sound, 0)
	state.sound_timer = u8(sound)
}