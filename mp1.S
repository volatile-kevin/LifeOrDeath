
# mp1.S - life-or-death version
# Good luck, and have fun!

.data

    # Constants for accessing the fields of a struct keystroke_args
    # struct keystroke_args is defined in rtc.h and mp1.h

	KA_SIZE	  = 14   # 14 bytes when copying
	KA_STACK  = 16   # use 16 bytes on stack for alignment
	DIRECTION = 0
	SELECTOR  = 2
	GUESS     = 4
	HINT      = 9

    # Constants for accessing the fields of a struct game_status
    # struct game_status is defined in rtc.h and mp1.h

	GS_SIZE   = 8	# 8 bytes
	POP 	  = 0
	INF	  = 4

    # Constants for screen size

    	SCR_WIDTH  = 80
	SCR_HEIGHT = 20
	SCR_SIZE   = ((SCR_WIDTH) * (SCR_HEIGHT))
	SELECTOR_OFFSET = 1760
    # ASCII cell images

        CELL_LIVE = 0x78
	CELL_DEAD = 0x20


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl rand_seed, aggression

			.align 8
rand_seed:		.quad 0x0	# Pseudo-random number seed
aggression:		.long 0x0	# Aggression level of virus


# Data private to this file

current_board:		.long 0x0	# Address of current board
next_board:		.long 0x0	# Address of next board
population:		.long 0x0	# Remaining human population
infection:		.long 0x0	# Count of live virus cells
select_image:		.string "==>"	# Picture of the selector
select_blank:		.string "   "	# Picture to overwrite selector
base_array:             .string "ACGT"  # Array of characters for bases


.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long ignore);
# Performs three tasks:
#	(1) updates the life game board and calculates infection count
#	(2) swaps the two boards
#	(3) applies population reduction based on infection count
#	(4) redraws the screen
#	(5) notifies the user code by calling mp1_notify_user
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
# this function is called by the RTC and iterates through both current_board
# and next_board and calls tick_result and neighbor_count to find the next
# value of the cell. The boards are then swapped and the screen is drawn
# by calling draw screen
mp1_rtc_tasklet:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %edi
		pushl %esi												 # callee save registers

		movl current_board, %eax
		cmpl $0, %eax
		je DONE                              # if current_board is 0, return

		xorl %ebx, %ebx                      # initialize cell row counter
		xorl %edi, %edi											 # initialize cell column counter
		xorl %ecx, %ecx										   # initialize live cell counter

		DOA_LOOP:
			cmpl $0, %edi
			je INCREMENT_CELLS_BORDER
			cmpl $SCR_WIDTH-1, %edi
			jge INCREMENT_CELLS_BORDER
			cmpl $0, %ebx
			je INCREMENT_CELLS_BORDER
			cmpl $SCR_HEIGHT-1, %ebx
			jge INCREMENT_CELLS_BORDER					# jump to INCREMENT_CELLS if cell is on border


			movl current_board, %eax
			movl %ebx, %esi
			imul $SCR_WIDTH, %esi
			addl %edi, %esi											# calculate the offset
			addl %esi, %eax 								  	# add it to current position
			movl %eax, %esi											# copy it to a new register

			pushl %ecx
			pushl %edx                       	  # Caller save registers
			pushl %esi											  	# push parameter (*cell)
			call neighbor_count
			popl %esi                           # pop parameter from stack (*cell)
			popl %edx
			popl %ecx

			movl (%esi), %esi									  # dereference the cell pointer
			pushl %ecx                          # Caller save registers
			pushl %edx													# push neighbors parameter
			pushl %eax
			pushl %esi													# push cell value
			call tick_result
			popl %esi
			popl %esi
			popl %edx
			popl %ecx														# Caller restore registers

			pushl %ecx											    # save ecx
			movl %eax, %ecx
			movl next_board, %edx
			movl %ebx, %eax
			imul $SCR_WIDTH, %eax
			addl %edi, %eax
			addl %eax, %edx										  # find offset and add to next_board
			movb %cl, (%edx)									  # 1 byte store new cell value into next_board
			popl %ecx												    # restore ecx

			cmpl $1, %esi											  # if cell is alive (==1)
			je INCREMENT_LIVE
			jmp INCREMENT_CELLS

		INCREMENT_LIVE:
			incl %ecx												    # increment live cell counter
			jmp INCREMENT_CELLS

		INCREMENT_CELLS:
			cmpl $SCR_SIZE, %eax									  # compare 1600 to width*bh+bl
			jge DONE													  # if cell counter has reached 1600, done

			cmpl $SCR_WIDTH-1, %edi							# if column counter has reached 80, increment row
			je INCREMENT_ROW
			incl %edi
			jmp DOA_LOOP

		INCREMENT_CELLS_BORDER:
			movl next_board, %edx
			movl %ebx, %eax											# jump to this label if on the border
			imul $SCR_WIDTH, %eax								# calculate offset and put it in %eax
			addl %edi, %eax
			addl %eax, %edx
			movb $0, (%edx)
			jmp INCREMENT_CELLS

		INCREMENT_ROW:									      # increment row and reset column counter to 0
			incl %ebx
			xorl %edi, %edi
			jmp DOA_LOOP



		DONE:
			imul $10, %ecx
			movl %ecx, infection							# Store infection value

			movl current_board, %eax
			movl next_board, %ebx
			movl %ebx, current_board
			movl %eax, next_board							# swap boards

			movl population, %esi
			subl %ecx, %esi
			js RESET_POPULATION
			movl %esi, population
			jmp DONE_TASKLET
		RESET_POPULATION:										# reset population to 0 if it drops below
			movl $0, %esi
			movl %esi, population
			jmp DONE_TASKLET

		DONE_TASKLET:
			pushl %eax
			pushl %ecx
			pushl %edx                         # Caller save registers
			call draw_screen
			popl %edx
			popl %ecx
			popl %eax                          # Caller restore registers

			pushl %eax
			pushl %ecx
			pushl %edx                         # Caller save registers
			call mp1_notify_user
			popl %edx
			popl %ecx
			popl %eax                          # Caller restore registers

			popl %esi
			popl %edi
			popl %ebx													# Callee restore registers
			leave
			ret


# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
# this is the dispatch function that takes in the cmd argument
# to jump to another ioctl
mp1_ioctl:											# dispatch function
		movl 8(%esp), %ecx					# arg is 8 below stack ptr
		cmpl $4, %ecx
		jbe DISPATCH_IOCTL					# if the arg is from 0 to 4, success
		movl $-1, %eax
		ret
	DISPATCH_IOCTL:
		jmp *jump_table(,%ecx,4)


# ----------------- Functions private to this file -------------------

# this function iterates through all cells and passes in corresponding characters
# and offset to be passed into mp1_poke
draw_screen:
# For simplicity, your implementation may assume a SCR_WIDTH of 80.
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx
	pushl %edi
	pushl %esi												 # callee save registers

	xorl %esi, %esi										 # current cell counter
	movl current_board, %edx

		PRINT_LOOP:
			cmpb $0, (%edx)								 # if the cell is 0, pass in dead, if 1, pass in alive
			je DRAW_DEAD
			movb $CELL_LIVE, %cl
			jmp CONTINUE_DRAW
		DRAW_DEAD:
			movb $CELL_DEAD, %cl
			jmp CONTINUE_DRAW

		CONTINUE_DRAW:									# double the offset to be passed into mp1_poke
			imul $2, %esi, %eax
			pushl %edx
			call mp1_poke
			popl %edx
			incl %esi											# increment both counters
			incl %edx
			cmpl $SCR_SIZE, %esi
			jl PRINT_LOOP
		DRAW_DONE:
			popl %esi
			popl %edi
			popl %ebx													# Callee restore registers
			leave
			ret

# this function starts the game by allocating space for boards,
# writing in all 0s for both boards, and initializing the values
# of certain variables
mp1_ioctl_startgame:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %edi
		pushl %esi												 # callee save registers

		movl 8(%ebp), %ebx								 # copy arg into a register to be pushed, arg is 8 below base ptr
		pushl %eax
		pushl %ecx
		pushl %edx                         # Caller save registers
		pushl %ebx												 # push arg
		call seed_generator
		popl %ebx													 # pop arg
		popl %edx
		popl %ecx
		popl %eax                          # Caller restore registers

		movl $SCR_SIZE, %edi									 # put size = 1600 into a register
		pushl %eax
		pushl %ecx
		pushl %edx                         # Caller save registers
		pushl %edi												 # push size
		call mp1_malloc
		popl %edi													 # pop size
		popl %edx
		popl %ecx
		movl %eax, current_board
		popl %eax                          # Caller restore registers
		cmpl $0, %eax
		je MALLOC_FAIL										 # if malloc fails, return -1


		pushl %eax
		pushl %ecx
		pushl %edx                         # Caller save registers
		pushl %edi												 # push size
		call mp1_malloc
		popl %edi													 # pop size
		popl %edx
		popl %ecx
		movl %eax, next_board
		popl %eax                          # Caller restore registers
		cmpl $0, %eax
		je MALLOC_FAIL										 # if malloc fails, return -1

		xorl %esi, %esi 									 # clear a register for index

		ZERO_LOOP:												 # loop to write in 0 for all cells (both boards)
		  movl current_board, %eax
		  movl next_board, %ebx
			addl %esi, %eax
			addl %esi, %ebx
			movb $0, (%eax)
			movb $0, (%ebx)

			cmpl $SCR_SIZE, %esi									# stop once the counter reaches 20*80
			jge DONE_ZERO
			incl %esi
			jmp ZERO_LOOP

		DONE_ZERO:
			movl current_board, %esi
			pushl %eax
			pushl %ecx
			pushl %edx                         # Caller save registers
			pushl %esi
			call init_virus
			popl %esi
			popl %edx
			popl %ecx
			movl %eax, %edi
			popl %eax                          # Caller restore registers
			movl %edi, infection							 # infection = ret val of init_virus
			movl $80, aggression								# initial aggression
			movl $8000000, population							# initial population
			movl $0, %eax											 # if both mallocs succeed, return 0
			jmp DONE_FINAL

		MALLOC_FAIL:												 # label that returns -1, called if malloc fails
			movl $-1, %eax
			jmp DONE_FINAL
		DONE_FINAL:
			popl %esi
			popl %edi
			popl %ebx													 # Callee restore registers
			leave
			ret

# this function ends the game by freeing the allocated board space
# and setting the board pointers to 0
mp1_ioctl_endgame:
			pushl %ebp
			movl %esp, %ebp
			pushl %ebx
			pushl %edi
			pushl %esi												 # callee save registers

			movl current_board, %edi
			pushl %eax
			pushl %ecx
			pushl %edx                         # Caller save registers
			pushl %edi												 # push size
			call mp1_free
			popl %edi													 # pop size
			popl %edx
			popl %ecx
			popl %eax                          # Caller restore registers

			movl next_board, %esi
			pushl %eax
			pushl %ecx
			pushl %edx                         # Caller save registers
			pushl %esi												 # push size
			call mp1_free
			popl %esi													 # pop size
			popl %edx
			popl %ecx
			popl %eax                          # Caller restore registers

			movl $0, next_board
			movl $0, current_board
			movl $0, %eax
			popl %esi
			popl %edi
			popl %ebx													# Callee restore registers
			leave
			ret
	# struct keystroke_args {
	    # unsigned short direction;	/* keystroke direction: 0 is left,   */
	    				/*    1 is down, 2 is right, 3 is up */
	    # unsigned short selector;	/* selector position (0 to 4)        */
	   	# unsigned char guess[5];	/* current DNA fragment guess        */
	    # unsigned char hint[5];	/* current DNA fragment hints        */
	# };
# this function takes in the user's keyboard input (arrow keys only)
# Logic:
# use mp1_copy_from_user to get the struct containing all the current data
# split the direction input into L/R or U/D
# split L/R into L or R and U/D into U or D
# L or R:
# cyclically update the selector arrow by deleting and re drawing it
# by calling mp1_poke
# U or D:
# cyclically update the base in the current selector and redraw it
# with mp1_poke
# write in the new values back to the struct and copy it back to the user
mp1_ioctl_keystroke:
		pushl %ebp
		movl %esp, %ebp
		cmpl $0, 8(%ebp)								# copy arg into a register to be pushed, arg is 8 below base ptr
		je ARG_FROMTO_FAILED							 # if arg is 0, immediately fail
		pushl %ebx
		pushl %edi
		pushl %esi												 # callee save registers

		subl $KA_STACK, %esp							 # allocate space for struct on stack
		movl %esp, %ebx
		pushl $KA_SIZE									 	 # push size
		pushl 8(%ebp)										   # push pointer from, arg is 8 below base ptr
		pushl %ebx											   # push pointer to
		call mp1_copy_from_user
		cmp $0, %eax
		jne COPY_FROMTO_FAILED						 # if mp1_copy_to_user returns not 1, it failed
		popl %eax
		popl %eax
		popl %eax													 # pop 3 times to take off parameters
		jmp DO_THE_RIGHT_THING						 # the empty 16 bytes should have the copied data


		# DIRECTION = 0
		# SELECTOR  = 2
		# GUESS     = 4
		# HINT      = 9
	DO_THE_RIGHT_THING:
		movw (%esp), %ax  									# put the direction and selector into a register
		andw $1, %ax												# and the direction with 1 to split L/R and U/D
		cmpw $0, %ax
		je LEFT_RIGHT
		jmp UP_DOWN

	LEFT_RIGHT:
		xorl %eax, %eax
		movw SELECTOR(%esp), %ax						# put the current selector value into a register
		imul $10, %eax	
		addl $14, %eax												# find offset of (14+10S, 22)
		addl $SELECTOR_OFFSET, %eax										# calculate offset, put it into eax
		imul $2, %eax												# double it before calling mp1_poke

		movb select_blank, %cl
		call mp1_poke

		addl $2, %eax
		movb select_blank, %cl
		call mp1_poke

		addl $2, %eax
		movb select_blank, %cl
		call mp1_poke												# increment the offset by 2 each time

		xorl %eax, %eax
		movw (%esp), %ax  									# put the direction and selector into a register
		andw $2, %ax												# and it with 2 to split L and R
		cmpw $0, %ax
		je LEFT
		jmp RIGHT

	LEFT:
		xorl %eax, %eax
		movw SELECTOR(%esp), %ax						# put the current selector value into a register
		cmpw $0, %ax
		je LEFT_CYCLE
		decl %eax														# subtract one to the selector
		movl %eax, %edi											# save the value

		imul $10, %eax
		addl $14, %eax													# find offset of (14+10S, 22)
		addl $SELECTOR_OFFSET, %eax										# calculate offset, put it into eax
		imul $2, %eax

		movl select_image, %ebx
		movb %bl, %cl									      # put the first char of ==> into cl
		call mp1_poke

		movl select_image, %ebx
		addl $2, %eax
		shrl $8, %ebx
		movb %bl, %cl
		call mp1_poke

		movl select_image, %ebx
		addl $2, %eax												# double offset before mp1_poke
		shrl $16, %ebx											# shift right 8 times to get to next char
		movb %bl, %cl
		call mp1_poke

		jmp UPDATECOPY_SELECTOR


	LEFT_CYCLE:
		movl $4, %eax                     # if left and selector = 0, then selector = 4
		movl %eax, %edi										# save the value
		imul $10, %eax
		addl $14, %eax												# find offset of (14+10S, 22)
		addl $SELECTOR_OFFSET, %eax									# calculate offset, put it into eax
		imul $2, %eax

		movl select_image, %ebx
		movb %bl, %cl									    # put the first char of ==> into cl
		call mp1_poke

		movl select_image, %ebx
		addl $2, %eax
		shrl $8, %ebx
		movb %bl, %cl
		call mp1_poke

		movl select_image, %ebx
		addl $2, %eax											# double offset before mp1_poke
		shrl $16, %ebx										# shift right 8 times to get to next char
		movb %bl, %cl
		call mp1_poke

		jmp UPDATECOPY_SELECTOR


	RIGHT:
		xorl %eax, %eax
		movw SELECTOR(%esp), %ax						# put the current selector value into a register
		cmpw $4, %ax
		je RIGHT_CYCLE
		incl %eax														# add one to the selector
		movl %eax, %edi											# save the value

		imul $10, %eax
		addl $14, %eax													# find offset of (14+10S, 22)
		addl $SELECTOR_OFFSET, %eax										# calculate offset, put it into eax
		imul $2, %eax												# double it before mp1_poke

		movl select_image, %ebx
		movb %bl, %cl									      # put the first char of ==> into cl
		call mp1_poke

		movl select_image, %ebx
		addl $2, %eax
		shrl $8, %ebx
		movb %bl, %cl
		call mp1_poke

		movl select_image, %ebx
		addl $2, %eax
		shrl $16, %ebx											# shift right 8 times to get to next char
		movb %bl, %cl
		call mp1_poke

		jmp UPDATECOPY_SELECTOR

	RIGHT_CYCLE:
		movl $0, %eax                       # if left and selector = 0, then selector = 4
		movl %eax, %edi											# save the value
		imul $10, %eax
		addl $14, %eax													# find offset of (14+10S, 22)
		addl $SELECTOR_OFFSET, %eax										# calculate offset, put it into eax
		imul $2, %eax

		movl select_image, %ebx
		movb %bl, %cl									      # put the first char of ==> into cl
		call mp1_poke

		movl select_image, %ebx
		addl $2, %eax
		shrl $8, %ebx
		movb %bl, %cl
		call mp1_poke

		movl select_image, %ebx
		addl $2, %eax
		shrl $16, %ebx											# shift right 8 times to get to next char
		movb %bl, %cl
		call mp1_poke

		jmp UPDATECOPY_SELECTOR

# update and copy selector to user
	UPDATECOPY_SELECTOR:
		movl %edi, %eax
		movw %ax, SELECTOR(%esp)
		movl  %esp, %ebx                   # esp points to top of struct
		pushl $KA_SIZE										 # push size
		pushl %ebx												 # push pointer from
		pushl 8(%ebp)                      # push pointer to, arg is 8 below base ptr
		call mp1_copy_to_user
		cmpl $0, %eax											 # if mp1_copy_to_user fails it will return !=0
		jne COPY_FROMTO_FAILED
		popl %eax
		popl %eax
		popl %eax

		popl %esi
		popl %edi
		popl %ebx													# Callee restore registers
		movl $0, %eax											# return 0 success
		leave
		ret

	KEYSTROKE_COPY_TO_FAIL:
		movl $-1, %eax										# return -1 fail
	UP_DOWN:
		xorl %eax, %eax
		movl (%esp), %eax  								# put the direction and selector into a register
		andb $2, %al											# and with 2 to split U and D
		cmpb $0, %al
		je DOWN
		jmp UP

	DOWN:
		xorl %eax, %eax
		xorl %ecx, %ecx
		xorl %ebx, %ebx										 # clear registers
		movw SELECTOR(%esp), %bx					 # put the current selector value into a register
		movb GUESS(%esp,%ebx,1), %cl       # put current guess into a register
		movb HINT(%esp,%ebx,1), %al

		CHECK_GUESS_DOWN:
			decb %cl												 # decrement the base
			cmpb $-1, %cl										 # if the base is A, make the next base T
			je DOWN_CYCLE
			jmp DOWN_CONTINUE

		DOWN_CYCLE:
			movb $3, %cl										 # makes next base T
			jmp DOWN_CONTINUE

		DOWN_CONTINUE:
			movb $1, %dl
			shl %cl, %dl											# checks if guess is in hint by:
			test %dl, %al											# and 1 left shifted GUESS times with hint
			jz CHECK_GUESS_DOWN
			jmp UPDATECOPY_GUESS

	UP:
		xorl %eax, %eax
		xorl %ecx, %ecx
		xorl %ebx, %ebx
		movw SELECTOR(%esp), %bx					  # put the current selector value into a register
		movb GUESS(%esp,%ebx,1), %cl        # put current guess into a register
		movb HINT(%esp,%ebx,1), %al

		CHECK_GUESS_UP:
			incb %cl
			cmpb $4, %cl											# if the base is T, make next base A
			je UP_CYCLE
			jmp UP_CONTINUE

		UP_CYCLE:
			movb $0, %cl									    # if guess is T, Up is pressed, guess = A
			jmp UP_CONTINUE

		UP_CONTINUE:
			movb $1, %dl
			shl %cl, %dl											# checks if guess is in hint by:
			test %dl, %al										  # and 1 left shifted GUESS times with hint
			jz CHECK_GUESS_UP
			jmp UPDATECOPY_GUESS


# update and copy guess to user
	UPDATECOPY_GUESS:
		movb %cl, GUESS(%esp,%ebx,1)        # put current guess into a register
		movl base_array, %edi								# put base_array into a register to access base chars
		imul $8, %ecx
		shr %cl, %edi												# shift it 8*guess times
		movl %edi, %ecx

		imul $10, %ebx
		addl $18, %ebx
		addl $SELECTOR_OFFSET, %ebx
		imul $2, %ebx												# find offset of (18+10S, 22)
		movl %ebx, %eax
		call mp1_poke

		movl  %esp, %ebx                   # esp points to top of infection and population struct
		pushl $KA_SIZE										 # push size
		pushl %ebx												 # push pointer from
		pushl 8(%ebp)                      # push pointer to
		call mp1_copy_to_user
		cmpl $0, %eax											 # if mp1_copy_to_user fails it will return !=0
		jne COPY_FROMTO_FAILED
		popl %eax
		popl %eax
		popl %eax													# teardown parameters

		popl %esi
		popl %edi
		popl %ebx													# Callee restore registers
		movl $0, %eax											# return 0 success
		leave
		ret

	COPY_FROMTO_FAILED:
		popl %eax
		popl %eax
		popl %eax													# teardown parameters

		popl %esi
		popl %edi
		popl %ebx													# Callee restore registers
		movl $-1, %eax										# return -1 fail
		leave
		ret
	ARG_FROMTO_FAILED:
		mov $-1, %eax
		leave
		ret

# this function retrieves certain variables from the kernel to the user
# by using mp1_copy_to_user
mp1_ioctl_getstatus:
		pushl %ebp
		movl %esp, %ebp
		cmpl $0, 8(%ebp)
		je ARG_TO_FAILED
		pushl %ebx
		pushl %edi
		pushl %esi

		pushl infection
		pushl population
		movl  %esp, %ebx                   # esp points to top of infection and population struct
		pushl $GS_SIZE										 # push size
		pushl %ebx												 # push pointer from
		pushl 8(%ebp)                      # push pointer to

		call mp1_copy_to_user
		cmpl $0, %eax
		jne COPY_TO_FAILED								 # if mp1_copy_to_user returns not 1, it failed
		popl %eax
		popl %eax
		popl %eax
		popl %eax
		popl %eax													 # pop off all arguments

		popl %esi
		popl %edi
		popl %ebx													 # Callee restore register
		jmp DONE_COPY
		ARG_TO_FAILED:
			movl $-1, %eax									 # return -1 fail
			leave
			ret
		COPY_TO_FAILED:
			popl %eax
			popl %eax
			popl %eax
			popl %eax
			popl %eax

			popl %esi
			popl %edi
			popl %ebx												  # Callee restore
			movl $-1, %eax										# return -1 fail
			leave
			ret
		DONE_COPY:
			movl $0, %eax											# return 0 is success
			leave
			ret
# this function handles the work for the vaccination function in the game
# (called by space bar input)
# it will iterate through all cells and generate a random number to determine
# whether or not the current cell should survive or die
# aggression is then updated to increase the rate of the spread of the virus
mp1_ioctl_vaccinate:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %edi
		pushl %esi												 # callee save registers

		movl 8(%ebp), %ebx								 # copy arg into a register to be pushed
		cmpl $0, %ebx
		je ARG_FAIL_VAX
		xorl %ecx, %ecx
		movw %bx, %cx											 # put the low 16 bits into another register
		shrl $16, %ebx										 # right shift 16x to put the high 16 bits into the low

		xorl %esi, %esi										 # clear a register for counting

		LOOP_GENERATE:
			movl current_board, %eax
			addl %esi, %eax
			cmpl $0, (%eax)
			je INCREMENT_VAX

			pushl %eax
			pushl %ecx
			pushl %edx                         # Caller save registers
			call generate
			popl %edx
			popl %ecx
			popl %edi                          # Caller restore registers

			xorl %edx, %edx
			movl $100, %edi
			idiv %edi													 # divide random number (eax) by 100
																			   # remainder is stored in edx
			cmpb %cl, %dl
			jle KILL													 # if remainder is =< percent, kill
			jmp INCREMENT_VAX

		KILL:
			movl current_board, %edi
			addl %esi, %edi
			movb $0, (%edi)										 # kill the current cell
			jmp INCREMENT_VAX

		INCREMENT_VAX:
			cmpl $SCR_SIZE, %esi
			jge DONE_GENERATE
			incl %esi
			jmp LOOP_GENERATE

		DONE_GENERATE:
			addw %bx, aggression							# add to aggression value
			popl %esi
			popl %edi
			popl %ebx													# Callee restore registers
			mov $0, %eax											# return 0 always
			leave
			ret

		ARG_FAIL_VAX:
			popl %esi
			popl %edi
			popl %ebx													# Callee restore registers
			mov $0, %eax											# return 0 always
			leave
			ret
jump_table:
	.long mp1_ioctl_startgame, mp1_ioctl_endgame, mp1_ioctl_keystroke, mp1_ioctl_getstatus, mp1_ioctl_vaccinate
