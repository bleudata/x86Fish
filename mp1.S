
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
#        Inputs: unsigned long arg
#       Outputs: %eax will be -1 for an error if the cmd value was not 0-3
#     Registers: %ebx - arg
#                %eax return value
#                %ecx - struct / node pointer
#                %esi - temp for holding value in the struct
mp1_rtc_tasklet:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        # make two local variables 
        # get values from the stack 
       
        movl 8(%ebp), %ebx
LIST_LOOP:


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
#       Outputs: 0 if succesful, -1 if cmd is not 0-3 or other error
#     Registers: %ebx -  arg
#                %ecx - cmd

#       
mp1_ioctl:

        movl 4(%esp), %ebx # load arg
        movl 8(%esp), %ecx # load cmd

        cmpl  $3, %ecx # %ecx-3
        ja ERROR_ICTL # %ecx > 3, index out of range of jump table
        jmp *JUMP_TABLE(,%ecx, 4) # jump to cmd specified function

ERROR_ICTL:
        movl $-1, %eax 

	ret

# void mp1_ioctl_add:
# 1. mp1_malloc to store a new copy of the structure
# 2. user mp1_copy_from_user to copy entire mp1 blink struct to newly allocated memory
# 3. Set countdown = onlength 
# 4. Set status = 1
# 5. insert struct add head of list using mp1_list_head pointer
# 6. call mp1_poke to display character
# 7. Should return 0 if successful 
# Interface: 
#        Inputs: unsigned long arg
#       Outputs: 0 if succesful add performed, -1 if error
#     Registers: %ebx - input arg
#                %ecx - temp storage for computations
#                       %cl - char for poke                        
#                %eax - return value, temp storage, location for poke
#                %edi - address of new struct
mp1_ioctl_add:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load arg
        cmpl $0, %ebx # invalid struct arg 
        je ERROR_ADD

        # allocate memory for copy of structure
        ; pushl %eax # caller set up for mp1_malloc
        ; pushl %ecx
        ; pushl %edx
        pushl $STRUCT_SIZE # load size to push as argument

        call mp1_malloc # check %eax return value for error
        cmpl $0, %eax
        je ERROR_ADD # error, malloc returned NULL 
        movl %eax, %edi # edi = address of new struct
        addl $4, %esp # no error, caller tear down m1_malloc
        ; popl %edx
        ; popl %ecx
        ; popl %eax 

        # copy struct from user space to new memory
        ; pushl %eax # caller set up mp1_copy_from_user
        ; pushl %ecx
        ; pushl %edx

        pushl $STRUCT_SIZE # size
        pushl %ebx # from
        pushl %edi # to

        call mp1_copy_from_user
        cmpl $0, %eax # check if return address is null
        je TEARDOWN_COPY_USER # error, not all bytes copied
        addl $12, %esp
        ; popl %edx
        ; popl %ecx
        ; popl %eax 
         
        # check location
        xorl %eax, %eax
        movw LOCATION(%edi), %ax # eax = value of location
        cmpl $1999, %eax # location - (80*25-1) 
        ja FREE_MEMORY # location out of range error

        xor %ecx, %ecx
        movw ON_LENGTH(%edi), %cx # ecx = value of onlength
        movw %cx, COUNTDOWN(%edi) # countdown = onlength 
        movw $1, STATUS(%edi) # status = 1

        # insert structure as new list head
        xor %ecx, %ecx
        movl mp1_list_head, %ecx # ecx = old_head
        movw %cx, NEXT(%edi) # new_node->next = old_head
        movl %edi, mp1_list_head # head = new_node

        # load registers for poke
        xor %ecx, %ecx
        xor %eax, %eax
        movw STATUS(%edi), %cx 
        cmpl $0, %ecx # ecx-0
        je STATUS_OFF
        movb ON_CHAR(%edi), %cl
        movb LOCATION(%edi), %al
       # call mp1_poke
        jmp SUCCESS_ADD

STATUS_OFF:
        movb OFF_CHAR(%edi), %cl
        movb LOCATION(%edi), %al
        # call mp1_poke

SUCCESS_ADD:
        xor %eax, %eax # retval = 0
        jmp DONE_ADD

TEARDOWN_COPY_USER:
        # tear down the previous call
        # 3 arg + 3 caller saved registers 
        addl $12, %esp 
        ; popl %edx
        ; popl %ecx
        ; popl %eax 

FREE_MEMORY:

        # caller set up for mp1_free
        ; pushl %eax
        ; pushl %ecx
        ; pushl %edx
        pushl %eax # address of memory to free

        call mp1_free
        # caller tear down mp1_free
        addl $4, %esp
        ; popl %edx
        ; popl %ecx
        ; popl %eax 
        
ERROR_ADD:
        movl $-1, %eax # retval = -1

DONE_ADD:
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

SUCCESS_REMOVE:
        xor %eax, %eax
        jmp DONE_REMOVE

ERROR_REMOVE:
        movl $-1, %eax
DONE_REMOVE:
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



SUCCESS_FIND:
        xor %eax, %eax
        jmp DONE_FIND

ERROR_FIND:
        movl $-1, %eax
DONE_FIND:
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

SUCCESS_SYNC:
        xor %eax, %eax
        jmp DONE_SYNC

ERROR_SYNC:
        movl $-1, %eax

DONE_SYNC:
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# for ioctl dispatcher
JUMP_TABLE:             
.long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync

.end
