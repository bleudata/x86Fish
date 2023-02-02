
.data					# section declaration

        # Useful offset constants for accessing members of a 
        # struct mp1_blink_struct structure
        LOCATION   = 0    
        ON_CHAR    = 2
        OFF_CHAR   = 3 
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16

# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
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

# void mp1_rtc_tasklet:
# called when RTC interrupt is generated
# examine list of blink_struct.
# first decrement countdown status field. if = 1, location has on_character. if = 0, off_char
# function switches to the opposite charater by switching status field with(or and..? call to poke
# finally, copy value from opposite length field to countdown
# the go to next item in list, return when reach end of list
#
# Interface: 
#        Inputs: unsigned long
#       Outputs: %eax will be -1 for an error if the cmd value was not 0-3
#     Registers: %eax return value
#            %
mp1_rtc_tasklet:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi


DONE:
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# int mp1_ioctl:
# dispatcher function, uses jump table to call other functions
#
# Interface: 
#        Inputs: unsigned long arg (left)
#                unsigned long cmd (right)
#       Outputs: -1 for an error if the cmd value was not 0-3, 0 if succesful 
#     Registers: %ebx -  cmd
#                %ecx - arg
#       
mp1_ioctl:
        
# 0 = add
# 1 = remove
# 2 = find
# 3 = sync
# other = return -1, error
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load cmd
        movl 12(%ebp), %ecx # load arg

        # caller save registers before jump, maybe don't need this 
        pushl %eax
        pushl %ecx
        pushl %edx 
        cmpl  $3, %ebx # %ebx-3
        ja ERROR # %ebx > 3, index out of range of jump table

        jmp *JUMP_TABLE(,%esi, 4)
ERROR:
        movl $-1, %eax 

DONE:
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# void mp1_ioctl_add:
#
# Interface: 
#        Inputs: unsigned long arg
#       Outputs: 0 if succesful add performed, -1 if error
#     Registers: %ebx - arg
mp1_ioctl_add:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load arg

SUCCESS:
        xor %eax, %eax
        jmp DONE

ERROR:
        movl $-1, %eax

DONE:
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# void mp1_ioctl_remove:
#
# Interface: 
#        Inputs: unsigned long arg
#       Outputs: 0 if succesful, -1 if not
#     Registers: %ebx - arg      
mp1_ioctl_remove:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load arg

SUCCESS:
        xor %eax, %eax
        jmp DONE

ERROR:
        movl $-1, %eax
DONE:
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# void mp1_ioctl_find:
#
# Interface: 
#        Inputs: unsigned long arg
#       Outputs: 0 is succesful, -1 if error
#     Registers: %ebx - arg     
mp1_ioctl_find:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load arg


SUCCESS:
        xor %eax, %eax
        jmp DONE

ERROR:
        movl $-1, %eax
DONE:
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# void mp1_ioctl_sync:
#
# Interface: 
#        Inputs: unsigned long arg 
#       Outputs: 0 if succesful, -1 if error
#     Registers: %ebx - arg, upper 16 bits = first integer
#                %bx - arg, second integer      
#                %eax - return value                  

mp1_ioctl_sync:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load arg


SUCCESS:
        xor %eax, %eax
        jmp DONE

ERROR:
        movl $-1, %eax

DONE:
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# for ioctl dispatcher
JUMP_TABLE:             
.long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_synch

.end
