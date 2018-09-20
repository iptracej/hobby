;
; boot.asm
;
; Most of the codes are taken from Linux 0.0.1 version
; 

SECTORS	EQU 18		; number of sectors per track
SYSSEG	EQU 0x1000	; segment where to load 32 bit program
ENDSEG	EQU 0x9000	; end segment of 32 bit program

; BIOS loads bootsector at linear address 0x7c00

	ORG 0x7c00

	SECTION .text

	BITS 16

start:
	; save boot drive		;DS = 0x7c00
	mov [bootdrv],dl

	; change cursor
	mov	ah,0x3   		; get cursor info
	mov	bh,0			; page 0
	int	0x10			; call bios
	mov	cl,0x1			; starting scan line = 1
	mov	ah,0x1			; set cursor info
	int	0x10			; call bios

	; print message
	mov	si,message
	call	print_string

	; load 32 bit program
	call   read_program
	call   kill_motor

	; clear interrupts
	cli

	; set up IDT & GDT
	lidt [idt_info]
	lgdt [gdt_info]

	; enable A20
	call	empty_8042
	mov	al,0xd1		; command write
	out	0x64,al
	call	empty_8042
	mov	al,0xdf		; A20 on
	out	0x60,al
	call	empty_8042

	; enable protected mode
	mov	ax,0x0001		; protected mode (PE) bit
	lmsw	ax			; This is it!

	; jump to 32 bit code
	jmp	dword 0x8:kernel_32	; offset to kernel_32 function,  (0x8 = code segment)

;
; Empty 8042 function
;
; This routine checks that the keyboard command queue is empty
; No timeout is used - if this hangs there is something wrong with
; the machine, and we probably couldn't proceed anyway.
;

empty_8042:
	in	al,0x64		; 8042 status port
	test	al,2		; is input buffer full?
	jnz	empty_8042	; yes - loop
	ret

;
; Print string
;

print_string:
	mov	ah,0xe		; bios function index
	mov	bh,0		; console page 0
.next:	mov	al,[si]		; move char into al
	cmp	al,0		; is char == 0?
	jz	.done		; yes, exit
	int	0x10		; call bios
	inc	si		; increment char pointer
	jmp	.next		; next char
.done:	ret

;
; Print sign
;

print_sign:
	push 	bx
	mov	ah,0xe
	mov	al,'#'
	int	0x10
	pop	bx
	ret
;
; Read program function 
;
; This routine loads the system at linear address 0x10000, making sure
; no 64kB boundaries are crossed. We try to load it as fast as
; possible, loading whole tracks whenever we can.
;
; This routine has to be recompiled to fit another drive type,
; just change the "sectors" variable at the start of the file
; (originally 18, for a 1.44Mb drive)
;

; SECTORS	EQU 18		; number of sectors per track
; SYSSEG	EQU 0x1000	; segment where to load 32 bit program
; ENDSEG	EQU 0x9000	; end segment of 32 bit program
	
read_program:
				
	mov ax,SYSSEG		; es is starting segment
	mov es,ax		;  to load the program read from floppy
	xor bx,bx		; bx is starting address within segment
				; ax = 0x1000, es = 0x1000, bx=0
rp_read:
	call print_sign
	mov ax,es		;  ax = es;
	cmp ax,ENDSEG		; have we loaded all yet? (ax == 0x9000)
	jb ok1_read		; Jump if below (<) ( carry = 1)
	ret
ok1_read:
	mov ax,SECTORS		; ax = 18 (first time)
	sub ax,[sread]		; 18 - 1 
	mov cx,ax		; cx = 17
	shl cx,9		; ? 
	add cx,bx		; ?
	jnc ok2_read		; Jump if no carry (carry = 0)
	je ok2_read		; Jump if equal (=) (Zero = 1) 
	xor ax,ax               ; ax = 0
	sub ax,bx               ; ?
	shr ax,9                ; ?
ok2_read:
	call read_track
	mov cx,ax
	add ax,[sread]
	cmp ax,SECTORS
	jne ok3_read		; Jump if not equal () (Zero = 0)
	mov ax,1
	sub ax,[head]
	jne ok4_read
	inc word [track]
ok4_read:
	mov [head],ax
	xor ax,ax
ok3_read:
	mov [sread],ax
	shl cx,9
	add bx,cx
	jnc rp_read
	mov ax,es
	add ax,0x1000
	mov es,ax
	xor bx,bx
	jmp rp_read

;bootdrv:	DW	1	; drive booted from
;sread:		DW	1	; sectors read of current track
;head:		DW	0	; current head
;track:		DW	0	; current track
	
read_track:
	push ax
	push bx
	push cx
	push dx
	
	mov dx,[track]		; dl = 0
	mov cx,[sread]		; cl = sread
	inc cx			; cl = sread + 1;
	mov ch,dl		; ch = 0;
	
	mov dx,[head]		; dx = 0;
	mov dh,dl		; dh = 0;
	
	mov dl,0		; dl = 0
	and dx,0x0100		; dh = 1
	
	mov ah,2
	int 0x13
	jc bad_rt
	pop dx
	pop cx
	pop bx
	pop ax
	ret
bad_rt:	mov ax,0		; reset the Floppy Drive
	mov dx,0		;  dl = 0
	int 0x13
	pop dx
	pop cx
	pop bx
	pop ax
	jmp read_track

kill_motor:
	push dx
	mov dx,0x3f2
	mov al,0
	outb
	pop dx
	ret	


;
; 32 bit function
;

		BITS 32

kernel_32:	
		; set segment registers
		mov eax,0x10	; code segment register is already loaded, now load
		mov ds,eax	; all the data segment registers with GDT descriptor 0x10
		mov es,eax	; this finishes the flat memory model setup
		mov fs,eax
		mov gs,eax
		mov ss,eax
		
		; disable caching
		mov eax,cr0
		or eax,0x60000000	; cache disable | not write through
		mov cr0,eax
		wbinvd				; flush cache

		; count memory
		mov eax,0x100000		; start at 1 mb mark
		mov ebx,0x400			; 1 kb increments
		mov ecx,0x12345678		; random bit pattern
.next:		mov edx,[eax]			; save what was there
		mov [eax],ecx			; write bit pattern
		cmp [eax],ecx			; compare with bit pattern
		jne .done			; exit if pattern was lost
		mov [eax],edx			; restore what was there
		add eax,ebx			; increment pointer
		jmp .next
.done:		mov esp,eax			; set stack pointer


		; enable caching
		mov eax,cr0
		and eax,0x9fffffff	; !(cache disable | not write through)
		mov cr0,eax
	    

		; jump to loaded program
		jmp 0x10000			
	       


; Data

	SECTION .data
gdt:
		; descriptor 0x0 (dummy segment)
		DW	0,0,0,0

		; descriptor 0x8 (code segment 0-FFFFFFFF)
		DW	0xffff		; limit 15-0
		DW	0x0000		; base 15-0
		DW	0x9a00		; 9a = code read/exec, 00 = base 23-16 
		DW	0x00cf		; 00 = base 31-24, c = 4096/386, f = limit 19-16

		; descriptor 0x10 (data segment 0-FFFFFFFF)
		DW	0xffff		; limit 15-0
		DW	0x0000		; base 15-0
		DW	0x9200		; 92 = data read/write, 00 = base 23-16
		DW	0x00cf		; 00 = base 31-24, c = 4096/386, f = limit 19-16

gdt_info:
		DW	0x18		; gdt limit in bytes, 3 gdt entries
		DW	gdt,0x0		; gdt base address low, high

idt_info:
		DW	0		; limit
		DW	0, 0		; base
		
bootdrv:	DW	1	; drive booted from
sread:		DW	1	; sectors read of current track
head:		DW	0	; current head
track:		DW	0	; current track

message:	DB	'Loading ',0

; bootsector must be 512 bytes long, adjust this constant to vary the length
; of the bootsector section of the os image

times 121 DB 0

; times   510 - ($-$$) db 0

; bootsector signature

DW 0xAA55
