; PrOSBoot Menu Starting Point
;   Copyright (C) 2024 Gabriel Jickells
;
;   This program is free software: you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, either version 3 of the License, or
;   (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program.  If not, see <https://www.gnu.org/licenses/>.


COM_OFFSET equ 100h

org COM_OFFSET
bits 16
cpu 8086

main:
  mov si, message
  call puts

  .hang:
    jmp .hang

BIOS_VIDEO_PRINT_CHAR_AH equ 14
BIOS_VIDEO_INT equ 10h
; in si = pointer to NULL-terminated ASCII string
puts:
  push si
  push ax
  push bx
  xor bx, bx
  .loop:
    lodsb
    test al, al
    jz .end
    mov ah, BIOS_VIDEO_PRINT_CHAR_AH
    int BIOS_VIDEO_INT
    jmp .loop
  .end:
    pop bx
    pop ax
    pop si
    ret

CR equ 0dh
LF equ 0ah
NUL equ 0
message: db "PrOSBoot Menu v1.0 Copyright (C) 2024 Gabriel Jickells", CR, LF, NUL

hang jmp hang

