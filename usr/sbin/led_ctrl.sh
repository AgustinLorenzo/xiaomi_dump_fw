#!/bin/sh
blink_led_blue() {
    gpio 2 1
    gpio 3 1
    gpio l 1000 3
}

blink_led_red() {
    gpio 2 1
    gpio 3 1
    gpio l 1000 2
}
