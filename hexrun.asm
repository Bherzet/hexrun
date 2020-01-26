org 0x7c00

    showbyte  equ 0xff
    notadigit equ 0xff

    ; initialize the text mode (80x25 characters)
    mov ax, 0x03
    int 0x10

    ; setup the stack below this program
    mov ax, 0
    mov ss, ax
    mov sp, 0x7c00

    ; just for lodsb to work
    mov ds, ax

    ; target address is 0x0fe0:0000
    mov ax, 0xfe0
    mov es, ax
    xor di, di

    ; set the character_count to 0
    mov cl, 0

; -----------------------------------------------------------------------------
HELP:
    ; print help
    mov si, help
    call PRINTSTR

; -----------------------------------------------------------------------------
PROMPT:
    ; preserve the AX register (this code may be called from LOADBYTE)
    push ax

    ; print the prompt
    mov si, promt_text_start
    call PRINTSTR

    call PRINTADDR

    mov si, prompt_text_end
    call PRINTSTR

    ; restore the AX register
    pop ax

    ; should we print the byte?
    cmp al, showbyte
    jnz INPUT

    call PRINTHEX

    ; remove the last 2 characters (PRINTHEX always aligns to 4 bytes)
    mov si, dbackspace
    call PRINTSTR

    ; set the character_count to 2
    mov cl, 2

; -----------------------------------------------------------------------------
INPUT:
    ; wait for the key press
    xor ah, ah
    int 0x16

    ; if Enter was pressed, move to the next byte
    cmp al, 13
    je INPUT__MOVE_NEXT

    ; if Backspace was pressed, remove the last character
    cmp al, 0x08
    je INPUT__REMOVE_CHARACTER

    ; if F5 was pressed, execute the code (starting at [es:0])
    cmp ah, 0x3f
    je EXECUTE

    ; if 'U' was pressed, print hexadecimals in uppercase
    cmp al, 'U'
    je UHEX

    ; if 'u' was pressed, print hexadecimals in lowercase
    cmp al, 'u'
    je LHEX

    ; if 'H' was pressed, print help
    cmp al, 'H'
    je HELP

    ; if a left arrow was pressed, go to the previous byte and print it
    cmp ah, 0x4b
    je PREVBYTE

    ; if a right arrow was pressed, go to the next byte and print it
    cmp ah, 0x4d
    je NEXTBYTE

    ; if HOME was pressed, go to the first byte and print it
    cmp ah, 0x47
    je HOME

    ; if we already have 2 characters, wait for one of the keys above
    cmp cl, 2
    jge INPUT

    ; if the character is not a digit, ignore it
    call ISHEX
    cmp bl, notadigit
    je INPUT

    ; print the character
    mov ah, 0x0e
    int 0x10

    ; increase the character_count
    inc cl

    ; store the value (first digit to the upper 4 bits, second digit to the lower 4 bits)
    cmp cl, 1
    je INPUT__STORE1
    jne INPUT__STORE2

INPUT__MOVE_NEXT:
    ; set the character_count = 0
    xor cl, cl

    ; increase the pointer
    inc di

    ; ask for the next value
    jmp PROMPT

INPUT__REMOVE_CHARACTER:
    ; if there are 0 characters, do nothing
    cmp cl, 0
    je INPUT

    ; otherwise decrease character count by 1
    dec cl

    ; remove the last character (from the screen)
    mov si, backspace
    call PRINTSTR

    ; continue loading the input
    jmp INPUT

INPUT__STORE1:
    ; store the higher 4 bits of the value
    shl bl, 4
    mov byte [es:di], bl

    jmp INPUT

INPUT__STORE2:
    ; load the current value
    mov dl, byte [es:di]

    ; store the bottom 4 bits while preserving the upper 4
    and dl, 0xf0
    add dl, bl
    mov byte [es:di], dl

    jmp INPUT

; -----------------------------------------------------------------------------
NEXTBYTE:
    ; increment the pointer
    inc di
    jmp LOADBYTE

HOME:
    ; reset the pointer
    mov di, 0
    jmp LOADBYTE

PREVBYTE:
    ; decrease the pointer
    dec di

LOADBYTE:
    ; load the byte
    mov ah, byte [es:di]

    ; magic value to display the byte
    mov al, showbyte

    jmp PROMPT

; -----------------------------------------------------------------------------
EXECUTE:
    ; initial value of [es:di]
    jmp 0x0fe0:0x0000

; -----------------------------------------------------------------------------
; AL: input, BL: output (a value or notadigit if not digit)
ISHEX:
    ; set the result = 0
    xor bl, bl

    ; if AL < '0'
    cmp al, '0'
    jl ISHEX__FAIL

    ; if AL >= '0' && AL <= '9'
    cmp al, '9'
    jle ISHEX__DEC

    ; if AL < 'A'
    cmp al, 'A'
    jl ISHEX__FAIL

    ; if AL >= 'A' && AL <= 'F'
    cmp al, 'F'
    jle ISHEX__UPPERCASE

    ; if AL < 'a'
    cmp al, 'a'
    jl ISHEX__FAIL

    ; if AL >= 'a' && AL <= 'f'
    cmp al, 'f'
    jg ISHEX__FAIL

ISHEX__LOWERCASE:
    ; make the BL (which is now 0) overflow; see below
    sub bl, 'a' - 10
    jmp ISHEX__VALUE

ISHEX__UPPERCASE:
    ; make the BL (which is now 0) overflow; see below
    sub bl, 'A' - 10

ISHEX__VALUE:
    ; convert the letter to a number; this is equivalent to BL = AL - 'a'/'A' + 10
    add bl, al
    ret

ISHEX__DEC:
    ; convert the digit to a number; this is equivalent to BL = AL - '0'
    sub bl, '0'
    jmp ISHEX__VALUE

ISHEX__FAIL:
    mov bl, notadigit
    ret

ISHEX__EXIT:
    ret

; -----------------------------------------------------------------------------
; Prints the ASCIIZ string at DS:SI.
PRINTSTR:
    lodsb

    ; check for 0
    or al, al
    jz PRINTSTR__EXIT

    ; print the character
    mov ah, 0x0e
    int 0x10

    jmp PRINTSTR

PRINTSTR__EXIT:
    ret

; -----------------------------------------------------------------------------
; Prints the AX register as a hexadecimal number aligned to 4 decimal places.
PRINTHEX:
    ; store the CX register (it's used in the caller)
    push cx
    mov cx, 4

PRINTHEX__SETUP_STACK:
    ; fill the stack with 4 zeroes (we want to align to 4 characters)
    push 0
    loop PRINTHEX__SETUP_STACK

    ; set the stack pointer as if there were no added zeroes, but remember the original value
    mov bp, sp
    add sp, 8

    ; converting to base 16
    mov bx, 16

PRINTHEX__CALC:
    ; divide ax:dx by bx
    xor dx, dx
    div bx

    ; the reminder, thus the calculated digit
    push dx

    ; check for zero
    or ax, ax
    jz PRINTHEX__SHIFT_STACK

    jmp PRINTHEX__CALC

PRINTHEX__SHIFT_STACK:
    ; restore the original stack, so that we always have 4 values
    mov sp, bp
    mov cx, 4

PRINTHEX__PRINT:
    ; take out the digit
    pop ax

    ; al >= 10
    cmp al, 10
    jge PRINTHEX__HEX_DIGIT

    ; convert a digit (0 - 9) to ASCII
    add al, '0'
    jmp PRINTHEX__PRINT_DIGIT

PRINTHEX__HEX_DIGIT:
    ; convert a digit (10 - 15) to ASCII
    add al, 'a' - 10

PRINTHEX__PRINT_DIGIT:
    ; print the digit
    mov ah, 0x0e
    int 0x10

    ; continue looping (4 times in total, according to CX)
    loop PRINTHEX__PRINT

PRINTHEX__EXIT:
    ; restore the CX register
    pop cx
    ret

; -----------------------------------------------------------------------------
; Prints the current segment (ES) and address (DI) as two collon separated
; hexadecimal values.
PRINTADDR:
    mov ax, es
    call PRINTHEX

    ; print collon
    mov ax, 0x0e3a
    int 0x10

    mov ax, di
    call PRINTHEX

    ret

; -----------------------------------------------------------------------------
; Print all hexadecimal digits in uppercase.
UHEX:
    mov byte [cs:PRINTHEX__HEX_DIGIT + 1], 'A' - 10
    jmp PROMPT

; -----------------------------------------------------------------------------
; Print all hexadecimal digits in lowercase.
LHEX:
    mov byte [cs:PRINTHEX__HEX_DIGIT + 1], 'a' - 10
    jmp PROMPT

; -----------------------------------------------------------------------------
help db 0x0a, 0x0d, "hexrun by Bherzet, 2020.", 0x0a, 0x0d, \
    "[H]elp. [Backspace] or [Enter] values. Execute with [F5]. [U/u]ppercase digits.", 0x0a, 0x0d, \
    "Navigate [Left], [Right] or [Home].", 0x0a, 0x0d, 0x00

backspace db 0x08, 0x20, 0x08, 0x00
dbackspace db 0x08, 0x20, 0x08, 0x08, 0x20, 0x08, 0x00
promt_text_start db 0x0a, 0x0d, "[", 0x00
prompt_text_end db "]", ": ", 0x00

times 510 - ($ - $$) hlt
dw 0xaa55
