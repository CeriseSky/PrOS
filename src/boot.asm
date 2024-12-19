; PrOSBoot Boot Record 1.0
;   Copyright (C) 2024 Gabriel Jickells
;
;   This program is free software: you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, either version 3 of the License, or
;   (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program. If not, see <https://www.gnu.org/licenses/>.

bits 16         ; x86 processors booting from legacy mode start in 16-bit real
                ; mode for backwards compatibility with older operating systems
cpu 8086

BIOS_LOAD_ADDRESS equ 7c00h
org BIOS_LOAD_ADDRESS

BIOS_VIDEO_PRINT_CHAR_AH equ 0eh
BIOS_VIDEO_INT equ 10h

BIOS_DISK_READ_SECTORS_AH equ 02h
BIOS_DISK_RESET_AH equ 00h
BIOS_DISK_INT equ 13h
BIOS_DRIVE_A equ 00h

BYTES_PER_SECTOR equ 1<<BPS_EXP
BPS_EXP equ 9

CR equ 0dh
LF equ 0ah

DOS_160K_DISKETTE_DESCRIPTOR equ 0feh
DOS_320K_DISKETTE_DESCRIPTOR equ 0ffh

struc FAT_NAME
  .name: resb FAT_NAME_LENGTH
  .ext: resb FAT_EXT_LENGTH
endstruc
FAT_NAME_LENGTH equ 8
FAT_EXT_LENGTH equ 3
FAT_NAME_EXT_LENGTH equ 11
FAT_SIGNATURE equ 29h
struc FAT_directory_entry
  .name: resb FAT_NAME_EXT_LENGTH
  .attributes: resb 1
  ._reserved: resb 1
  .creation_time_cents: resb 1
  .creation_time: resw 1
  .creation_date: resw 1
  .access_date: resw 1
  ._reserved2: resw 1
  .modified_time: resw 1
  .modified_date: resw 1
  .first_cluster: resw 1
  .size: resd 1

  .__struc_size:
endstruc

jmp setup       ; I wasted so much time trying to figure out why the code
nop             ; wouldn't work because I forgot these 2 lines.

; constants allow the code to avoid using (expensive) access to memory
; when retrieving values from the BPB
SECTORS_PER_CLUSTER equ 1
RESERVED_SECTORS equ 1
TOTAL_FATS equ 2
ROOT_DIR_CAPACITY equ 16
SECTORS_PER_FAT equ 1
TOTAL_HEADS equ 1

bpb:
  .oem_ID: db "PrOSWoES"
  .bytes_per_sector: dw BYTES_PER_SECTOR
  .sectors_per_cluster: db SECTORS_PER_CLUSTER
  .reserved_sectors: dw RESERVED_SECTORS
  .total_FATs: db TOTAL_FATS
  .root_dir_capacity: dw ROOT_DIR_CAPACITY
  .total_sectors: dw 320
  .media_descriptor: db DOS_160K_DISKETTE_DESCRIPTOR
  .sectors_per_fat: dw SECTORS_PER_FAT
  .sectors_per_track: dw 8
  .total_heads: dw TOTAL_HEADS
  .hidden_sectors: dd 0
  .total_sectors32: dd 0
ebpb:
  .drive_number: db BIOS_DRIVE_A
  ._reserved: db 0
  .signature: db FAT_SIGNATURE
  .serial: db "YKSC" ; arbitrarily chosen
  .label: db "Cerise Sky "
  .type: db "FAT12   "

; Different BIOSes aren't expected to put the boot record program in a well
; defined state before executing it so one must be created now
setup:
  cli         ; prevents a bug when resetting ss on 8088 CPUs
  xor ax, ax
  mov ds, ax
  mov es, ax
  mov ss, ax
  sti

    mov sp, BIOS_LOAD_ADDRESS

    jmp 0:main

; in ax = lba
; out ch = cylinder
; out cl = sector
; out dh = head
lba2chs:
  push ax
  push dx
  xor dx, dx
  div word [bpb.sectors_per_track]
  inc dx      ; sector = (lba MOD SPT) + 1
  mov cl, dl
  xor dx, dx
  div word [bpb.total_heads]
  mov ch, al  ; cylinder = (lba / SPT) / heads
  mov al, dl  ; head = (lba / SPT) MOD heads
  pop dx
  mov dh, al
  pop ax
  ret

; error handling has been turned off to save boot record space
; in ax = start lba
; in es:bx = location to read into
; in cl = count
; in dl = drive
read_sectors:
  ;push di
  push cx
  call lba2chs
  pop ax
  ;mov di, 3       ;  3 tries
  .try:
      mov ah, BIOS_DISK_READ_SECTORS_AH
      stc ; some BIOSes don't set this properly
      int BIOS_DISK_INT
      jnc .end
  ;.catch:
  ;    test di, di
  ;    jz hang
  ;    dec di
  ;    mov ah, BIOS_DISK_RESET_AH
  ;    stc
  ;    int BIOS_DISK_INT
  ;    jc hang
  ;    jmp .try
  .end:
  ;    pop di
      ret

; in si = string
; in dl = character
; out di = pointer to found character, or NULL
; destroys ax
strchr:
  push si
  ;push ax
  xor di, di
  .loop:
    lodsb

    test al, al
    jz .end

    cmp al, dl
    je .found

    jmp .loop
  .found:
    mov di, si
    dec di      ; si was incremented past where it should be by lodsb
  .end:
    ;pop ax
    pop si
    ret

; in si = string
; out cx = length
; destroys ax
strlen:
  push si
  ;push ax
  xor cx, cx
  .loop:
    lodsb
    test al, al
    jz .end
    inc cx
    jmp .loop
  .end:
    ;pop ax
    pop si
    ret

; in ax = cluster
; out ax = lba
; destroys dx
FIRST_CLUSTER equ 2
cluster2lba:
  sub ax, FIRST_CLUSTER
  mul byte [bpb.sectors_per_cluster]
  add ax, [data_section_lba]
  ret

main:
  mov si, path
  mov byte [flags], 0
  mov byte [ebpb.drive_number], dl


  ; FAT is read before the root directory because its size needs
  ; to be taken into account before allocating memory for the root
  FAT_BUFFER equ 500h ; earliest memory address not in use
  .read_fat:
    mov ax, RESERVED_SECTORS
    mov bx, FAT_BUFFER
    mov cl, SECTORS_PER_FAT
    ;mov dl, [ebpb.drive_number]
    call read_sectors
  .get_fat_size:
    ;xor ax, ax                 ; makes the dangerous assumption there are
                               ; less than 256 reserved sectors (which is
                               ; possible with this disk size)
    mov al, cl

    ; smaller way of multiplying by BYTES_PER_SECTOR
    mov cl, BPS_EXP
    shl ax, cl

    add bx, ax
    mov word [directory_pointer], bx

  .read_root_directory:
    .get_root_dir_location:
      xor ax, ax
      mov al, TOTAL_FATS
      mul word [bpb.sectors_per_fat]
      add ax, RESERVED_SECTORS
      push ax ; ready for read_sectors call (pop into ax)
    .get_root_dir_size:
      mov ax, ROOT_DIR_CAPACITY
      mov cx, FAT_directory_entry.__struc_size
      mul cx
      add ax, BYTES_PER_SECTOR - 1    ; forces division to round up

      ; smaller way of dividing by BYTES_PER_SECTOR
      mov cl, BPS_EXP
      shr ax, cl
    .prepare:
      mov cx, ax
      pop ax
      add ax, cx
      mov word [data_section_lba], ax
      sub ax, cx
    .read_root_sectors:
      ;mov bx, [directory_pointer]
      mov dl, [ebpb.drive_number]
      call read_sectors

  ; it is implied that we are starting from the root directory, so it
  ; doesn't need to be specified
  ;.check_start:
  ;    cmp byte [si], '/'
  ;    jne .check_start.end
  ;    inc si
  ;.check_start.end:
  .loop:
    ;test byte [flags], FLAG_FINISHED
    ;jnz hang

    .empty_name_buffer:
      mov al, ' '
      mov cx, FAT_NAME_EXT_LENGTH
      mov di, name_buffer
      rep stosb

    .split:
      mov dl, '/'
      call strchr
      mov word [next_section], 0
      test di, di
      jz .split.end
      mov byte [di], 0
      inc di
      mov word [next_section], di
    .split.end:

    push si
    .handle_ext:
      mov dl, '.'
      call strchr

      test di, di
      jz .handle_ext.end

      mov byte [di], 0
      inc di

      mov si, di
      call strlen
      mov di, name_buffer + FAT_NAME.ext
      cmp cx, FAT_EXT_LENGTH
      jb .shorter_ext

      .longer_ext:
        mov cx, FAT_EXT_LENGTH
      .shorter_ext:

      rep movsb
    .handle_ext.end:
      pop si

    .handle_name:
      call strlen
      mov di, name_buffer + FAT_NAME.name
      cmp cx, FAT_NAME_LENGTH
      jb .shorter_name

      .longer_name:
        mov cx, FAT_NAME_LENGTH
      .shorter_name:

      rep movsb
    .handle_name.end:

    mov cx, FAT_NAME_EXT_LENGTH
    mov si, name_buffer
    .convert_to_upper:
      lodsb
      cmp al, 'a'
      jb .convert_to_upper.continue
      cmp al, 'z'
      ja .convert_to_upper.continue
      sub al, 'a' - 'A'
      mov byte [si - 1], al
      .convert_to_upper.continue:
        loop .convert_to_upper
      .convert_to_upper.end:

    mov si, [directory_pointer]
    .find_file:
      push si
      mov di, name_buffer
      mov cx, FAT_NAME_EXT_LENGTH
      repe cmpsb
      pop si
      je .find_file.end
      add si, FAT_directory_entry.__struc_size
      jmp .find_file
    .find_file.end:

    FAT_ATTR_DIRECTORY equ 10h
    .get_properties:
      test byte [si + FAT_directory_entry.attributes], FAT_ATTR_DIRECTORY
      jz .get_location
      or byte [flags], FLAG_FINISHED

    .get_location:
      mov ax, [si + FAT_directory_entry.first_cluster]

    FAT_LAST_CLUSTER equ 0ff8h
    mov bx, [directory_pointer]
    .read_file:
      cmp ax, FAT_LAST_CLUSTER
      jae .read_file.end

      push ax
      call cluster2lba
      mov cl, SECTORS_PER_CLUSTER
      mov dl, [ebpb.drive_number]
      call read_sectors

      mov ax, BYTES_PER_SECTOR
      mul word [bpb.sectors_per_cluster]
      add bx, ax

      pop ax
      push ax
      mov cx, 3
      mul cx
      shr ax, 1
      mov si, ax
      mov ax, [FAT_BUFFER + si]
      pop cx
      test cl, 1
      jz .even_cluster

      .odd_cluster:
        mov cl, 4
        shr ax, cl

      .even_cluster:
        and ax, 0fffh

      jmp .read_file

      .read_file.end:

      .check_loop:
        mov di, [next_section]
        test di, di
        jz .end

      mov si, di
      jmp .loop

  .end:

  ; should be a check for if flags say we are done or not here

  .run:
    COM_OFFSET equ 100h
    mov ax, [directory_pointer]
    ;test al, 0fh
    ;jnz hang
    sub ax, COM_OFFSET
    mov cl, 4
    shr ax, cl
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, COM_OFFSET
    mov bp, sp
    push ax
    push bp
    retf

hang:
    jmp hang

path: db "system/boot/boot.com", 0

BOOT_SIGNATURE equ 0aa55h
pad times BYTES_PER_SECTOR-($-$$+2) db 0
dw BOOT_SIGNATURE

buffer:

section .bss

FLAG_FINISHED equ 1
flags: resb 1
next_section: resw 1
name_buffer: resb FAT_NAME_EXT_LENGTH
directory_pointer: resw 1
data_section_lba: resw 1

