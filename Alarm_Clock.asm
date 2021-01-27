; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 440 Hz square wave at pin P3.7 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 2 on the LCD.  Also resets it to 
; zero if the 'BOOT' pushbutton connected to P3.7 is pressed.
$NOLIST
$MODEFM8LB1
$LIST

CLK           EQU 24000000 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 544*2    ; Tone changed to C#
TIMER0_RELOAD EQU ((65536-(CLK/(TIMER0_RATE))))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/(TIMER2_RATE))))

;TODO if time: Add power button
AMPM_SET	  equ P0.0 ; switch between AM and PM
CA_SWITCH     equ P0.1 ; switches buttons between controlling clock and alarm
ALARM_OFF     equ P0.3 ; turns off alarm sound
SOUND_OUT     equ P2.1
SECONDS       equ P2.3 ; adjust seconds
MINUTES		  equ P2.6 ; adjust minutes
HOURS		  equ P3.2 ; adjust hours
BOOT_BUTTON   equ P3.7

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:        ds 2 ; Used to determine when half second has passed
CurrentHour:     ds 2  
CurrentMinute:   ds 2
CurrentSecond:   ds 2
CurrentAMPM:     ds 1
AlarmHour:       ds 2
AlarmMinute:     ds 2
AlarmSecond:     ds 2
AlarmAMPM:       ds 1
is_AM: ds 1
AM: db 'AM', 0 
PM: db 'PM', 0

; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed

cseg
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P2.0
LCD_RW equ P1.7
LCD_E  equ P1.6
LCD_D4 equ P1.1
LCD_D5 equ P1.0
LCD_D6 equ P0.7
LCD_D7 equ P0.6
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                           1234567890123456    <- This helps determine the location of the counter
Initial_Message_Point:  db 'xx:xx:xx xx   <-', 0 ; hour:minute:second am/pm
Initial_Message:        db 'xx:xx:xx xx', 0

;-----------------------------------;
; Routine to initialize the timer 0 ;
;-----------------------------------;
Timer0_Init:
	orl CKCON0, #00000100B ; Timer 0 uses the system clock
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret

;---------------------------------;
; ISR for timer 0.                ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	; Timer 0 can not autoreload so we need to reload it in the ISR:
	clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb TR0
	cpl SOUND_OUT ; Toggle the pin connected to the speaker
	reti

;---------------------------------;
; Routine to initialize timer 2   ;
;---------------------------------;
Timer2_Init:
	orl CKCON0, #0b00010000 ; Timer 2 uses the system clock
	mov TMR2CN0, #0 ; Stop timer/counter.  Autoreload mode.
	mov TMR2H, #high(TIMER2_RELOAD)
	mov TMR2L, #low(TIMER2_RELOAD)
	; Set the reload value
	mov TMR2RLH, #high(TIMER2_RELOAD)
	mov TMR2RLL, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2H  ; Timer 2 doesn't clear TF2H automatically. Do it in ISR
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(500), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(500), Timer2_ISR_done
	
	; 500 milliseconds have passed.  Set a flag so the main program knows
	setb half_seconds_flag ; Let the main program know half second had passed
	cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	setb SOUND_OUT
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Increment the BCD counter
	mov a, CurrentSecond
	;jnb UPDOWN, Timer2_ISR_decrement
	add a, #0x01
	sjmp Timer2_ISR_da
;Timer2_ISR_decrement:
	;add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.
Timer2_ISR_da:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov CurrentSecond, a
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti


;---------------------------------;
; Hardware initialization         ;
;---------------------------------;
Initialize_All:
    ; DISABLE WDT: provide Watchdog disable keys
	mov	WDTCN,#0xDE ; First key
	mov	WDTCN,#0xAD ; Second key

	; Setup the stack start to the begining of memory only accesible with pointers
    mov SP, #7FH
    
    ; Enable crossbar and weak pull-ups
	mov	XBR0,#0x00
	mov	XBR1,#0x00
	mov	XBR2,#0x40

	mov	P2MDOUT,#0x02 ; make sound output pin (P2.1) push-pull
	
	; Switch clock to 24 MHz
	mov	CLKSEL, #0x00 ; 
	mov	CLKSEL, #0x00 ; Second write to CLKSEL is required according to the user manual (page 77)
	
	; Wait for 24 MHz clock to stabilze by checking bit DIVRDY in CLKSEL
waitclockstable:
	mov a, CLKSEL
	jnb acc.7, waitclockstable 

	; Initialize the two timers used in this program
    lcall Timer0_Init
    lcall Timer2_Init

    lcall LCD_4BIT ; Initialize LCD
    
    setb EA   ; Enable Global interrupts

	ret

MinuteIncrement:
	clr a 
	mov a, CurrentMinute
	;jnb UPDOWN, Timer2_ISR_decrement
	add a, #0x01
	sjmp Timer2_ISR_da_minute
;Timer2_ISR_decrement:
	;add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.
Timer2_ISR_da_minute:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov CurrentMinute, a
	ret

HourIncrement:
	clr a 
	mov a, CurrentHour
	;jnb UPDOWN, Timer2_ISR_decrement
	add a, #0x01
	sjmp Timer2_ISR_da_hour
;Timer2_ISR_decrement:
	;add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.
Timer2_ISR_da_hour:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov CurrentHour, a
	ret
;---------------------------------;
; Main program.                   ;
;---------------------------------;
main:
	lcall Initialize_All
	
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message_Point)
    Set_Cursor(2, 1)
    Send_Constant_String(#Initial_Message)
	Set_Cursor(1, 10)

    setb half_seconds_flag
	mov CurrentHour, #0x00
    mov CurrentMinute, #0x00
    mov CurrentSecond, #0x00
    mov AlarmHour, #0x00
    mov AlarmMinute, #0x00
    mov AlarmSecond, #0x00
    ; TODO don't know if AM/PM should be here yet

	Set_Cursor(1,10)
	Send_Constant_String(#AM) ; intialise with AM

    Set_Cursor(2,10)
	Send_Constant_String(#AM) ; intialise with AM
	mov is_AM, #1


	; After initialization the program stays in this 'forever' loop
loop:
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	jnb BOOT_BUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
	; A valid press of the 'BOOT' button has been detected, reset the BCD counter.
	; But first stop timer 2 and reset the milli-seconds counter, to resync everything.
	clr TR2                 ; Stop timer 2
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Now clear the BCD counter
	;mov CurrentHour, a
    ;mov CurrentMinute, a
    mov CurrentSecond, a
	setb TR2                ; Start timer 2

	sjmp Button_Interrupt            ; Display the new value

Add_Hour:
    lcall HourIncrement
    ljmp loop_b

Add_Minute:
    lcall MinuteIncrement
    ljmp loop_b

loop_a:
	jnb half_seconds_flag, loop

Button_Interrupt:
    jnb HOURS, Add_Hour
    jnb MINUTES, Add_Minute
    jnb SECONDS, loop
	jb AMPM_SET, loop_b
    ;Wait_Milli_Seconds(#50) ; not really necessary here
    ;jb AMPM_SET, loop_b
	jnb AMPM_SET, AMPM_Display ; otherwise, continue

AMPM_Display:
	mov a, is_AM
	cjne a, #0, Display_PM ; if button is pressed and the flag is currently AM, set to PM
	Set_Cursor(1,10)
	Send_Constant_String(#AM)
	;cpl AMPM_SET
	mov is_AM, #1
	;clr a
	sjmp loop_b
	

Display_PM:
	Set_Cursor(1,10)
	Send_Constant_String(#PM)
	;cpl AMPM_SET	
	mov is_AM, #0
	;clr a
	sjmp loop_b


loop_b:
	;displaying block
    clr half_seconds_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 2
	;Set_Cursor(1, 10)
	;Display_BCD(AM)
	Set_Cursor(1, 7)
    Display_BCD(CurrentSecond)
	Set_Cursor(1, 4)
	Display_BCD(CurrentMinute)
	Set_Cursor(1, 1)
	Display_BCD(CurrentHour)

    Set_Cursor(2, 7)
    Display_BCD(AlarmSecond)
	Set_Cursor(2, 4)
	Display_BCD(AlarmMinute)
	Set_Cursor(2, 1)
	Display_BCD(AlarmHour)

	mov a, CurrentSecond
    cjne a, #60H, IntermediateLoop ; keep going if you haven't reached 60 yet, otherwise change minute place
	clr a
	mov CurrentSecond, a
	Set_Cursor(1, 7)
	Display_BCD(CurrentSecond)
	lcall MinuteIncrement
	;mov a, CurrentMinute
	;mov CurrentSecond, a
	Set_Cursor(1, 4)     ; minutes place
    Display_BCD(CurrentMinute)
	clr a
	mov a, CurrentMinute
	cjne a, #60H, IntermediateLoop ; send to Hour Increment
	lcall HourIncrement 
	Set_Cursor(1, 1)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(CurrentHour) ; This macro is also in 'LCD_4bit.inc'


Intermediate_Adjust:
    Wait_Milli_Seconds(#50) ; otherwise explodes
    ljmp Button_Interrupt
IntermediateLoop:
	ljmp loop

END
