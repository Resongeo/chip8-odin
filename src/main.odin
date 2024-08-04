package main

DISPLAY_WIDTH   :: 64
DISPLAY_HEIGHT  :: 32
DISPLAY_SCALE   :: 16
TARGET_FPS      :: 60
STEPS_PER_FRAME :: 10

ROM_ADDRESS :: 0x200
CARRY_FLAG  :: 0xf
FONT_SIZE   :: 0x5

main :: proc() {
    state: ^Chip8State = chip8_state_initialize()
    chip8_run(state)
}