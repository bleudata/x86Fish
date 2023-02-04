
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
# makes the fish blink
#
# Interface: 
#        Inputs: unsigned long arg
#       Outputs: none
#     Registers: %ebx - arg, temp for holding struct info
#                %eax - location value for poke, return value
#                %ecx - char value for  poke
#                %edi - struct / node pointer
#                %esi - temp for holding value in the struct
mp1_rtc_tasklet:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi
       
        # get mp_list_head
        movl mp1_list_head, %edi

        # check if null 
        cmpl $0, %edi
        je DONE_TASKLET 

        xor %ebx, %ebx
       # movw COUNTDOWN(%edi), %bx # just for debugging
       # movw ON_LENGTH(%edi), %bx
       # movw OFF_LENGTH(%edi), %bx
        cmpw $0, COUNTDOWN(%edi) # check if countdown is initially 0
        je COUNTDOWN_ZERO

LIST_LOOP:
        # decrement countdown
        addw $-1, COUNTDOWN(%edi)
        
       # comment cmpw $0, %bx
        cmpw $0, COUNTDOWN(%edi)
        jne CHECK_NEXT_STRUCT

COUNTDOWN_ZERO:
        movw STATUS(%edi), %bx # just for debugging
        cmpw $0, STATUS(%edi)
        je STATUS_OFF_TASKLET

        # clear registers for poke
        xor %ecx, %ecx
        xor %eax, %eax

        # need to change status to off
        movb OFF_CHAR(%edi), %cl
        movw $0, STATUS(%edi) # maybe don't need to change status
        movw STATUS(%edi), %bx # just for debugging
        movw LOCATION(%edi), %ax
        shll $1, %eax # maybe don't need shift, but try for now
        call mp1_poke
        movw OFF_LENGTH(%edi), %bx
        movw %bx, COUNTDOWN(%edi)
        jmp CHECK_NEXT_STRUCT

STATUS_OFF_TASKLET:
        # clear registerse for poke
        xor %ecx, %ecx
        xor %eax, %eax
        # need to change status to on
        movb ON_CHAR(%edi), %cl 
        movw $1, STATUS(%edi) # maybe don't need to change status
        movw LOCATION(%edi), %ax
        shll $1, %eax # maybe don't need to shift, but try for now
        call mp1_poke
        movw ON_LENGTH(%edi), %bx # bx = on_length
        movw %bx, COUNTDOWN(%edi)

CHECK_NEXT_STRUCT:
        movl NEXT(%edi), %edi 
        cmpl $0, %edi
        je DONE_TASKLET # end of list because next is null
        jmp LIST_LOOP # examine new struct

DONE_TASKLET:
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

        cmpl  $3, %ecx 
        ja ERROR_ICTL # %ecx > 3, out of range of jump table
        jmp *JUMP_TABLE(,%ecx, 4) # jump to cmd specified function

ERROR_ICTL:
        movl $-1, %eax 
	ret

# void mp1_ioctl_add:
# makes the fish appear
# 
# Interface: 
#        Inputs: unsigned long arg
#       Outputs: 0 if succesful add performed, -1 if error
#     Registers: %ebx - input arg old structure
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
        # pushl %eax # caller set up for mp1_malloc
        # pushl %ecx
        # pushl %edx
        pushl $STRUCT_SIZE # load size to push as argument

        call mp1_malloc # check %eax return value for error
        addl $4, %esp # pop arg off stack
        cmpl $0, %eax
        je ERROR_ADD # error, malloc returned NULL 
        movl %eax, %edi # edi = address of new struct
       # popl %edx
       # popl %ecx
       # popl %eax 

        # copy struct from user space to new memory
       # pushl %eax # caller set up mp1_copy_from_user
       # pushl %ecx
       # pushl %edx

        pushl $STRUCT_SIZE # size
        pushl %ebx # from
        pushl %edi # to

        call mp1_copy_from_user
        addl $12, %esp
        cmpl $0, %eax 
        jne FREE_MEMORY_ADD # error, not all bytes copied
       # popl %edx
       # popl %ecx
       # popl %eax 
         
        # check location
        xorl %eax, %eax
        movw LOCATION(%edi), %ax # eax = value of location
        cmpl $1999, %eax # location - (80*25-1) 
        ja FREE_MEMORY_ADD # location out of range error

        xorl %ecx, %ecx
        movw ON_LENGTH(%edi), %cx # ecx = value of onlength
        movw %cx, COUNTDOWN(%edi) # countdown = onlength 
        movw $1, STATUS(%edi) # status = 1

        # insert structure as new list head
        xorl %ecx, %ecx
        movl mp1_list_head, %ecx # ecx = old_head
        movl %ecx, NEXT(%edi) # new_node->next = old_head
        movl %edi, mp1_list_head # head = new_node

        # load registers for poke
        xorl %ecx, %ecx
        xorl %eax, %eax
        movw STATUS(%edi), %cx 
        cmpl $0, %ecx # ecx-0
        je STATUS_OFF_ADD
        xorl %ecx, %ecx
        movb ON_CHAR(%edi), %cl
        xorl %eax, %eax
        movw LOCATION(%edi), %ax
        shll $1, %eax
        call mp1_poke
        jmp SUCCESS_ADD

STATUS_OFF_ADD:
        xor %ecx, %ecx
        movb OFF_CHAR(%edi), %cl
        xor %eax, %eax
        movw LOCATION(%edi), %ax
        shll $1, %eax
        call mp1_poke

SUCCESS_ADD:
        xor %eax, %eax # retval = 0
        jmp DONE_ADD

FREE_MEMORY_ADD:
        # caller set up for mp1_free
        # pushl %eax
        # pushl %ecx
        # pushl %edx
        pushl %edi # address of memory to free

        call mp1_free
        # caller tear down mp1_free
        addl $4, %esp
        # popl %edx
        # popl %ecx
        # popl %eax 

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
#     Registers: %ebx - arg location to remove, address of current struct
#                     - address of struct whos ->next is struct to remove
#                %edi - address of struct to remove
#                %eax - return value, location of new struct, temp struct address storage    
mp1_ioctl_remove:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load arg, location of struct to remove
        movl mp1_list_head, %edi # check list head is valid
        cmpl $0, %edi 
        je ERROR_REMOVE # error if head is null

        # need to search list
        pushl %ebx # next push args to stack
        pushl mp1_list_head
        call mp1_search_list
        addl $8, %esp # pop 2x4bit args 
        cmpl $0, %eax
        je ERROR_REMOVE # didn't find location in list
        movl %eax, %edi # load remove address into edi

        # special case head node is node to remove
        cmpl mp1_list_head, %edi 
        je HEAD_REMOVE # node to remove is head

        # node to remove is in the middle of the list
        # need to find the node whos node->next is node to remove
        movl mp1_list_head, %ebx # set head to be the node being examined
LOOP_REMOVE:
        cmpl NEXT(%ebx), %edi
        je REMOVE_FROM_LIST
        movl NEXT(%ebx), %ebx # go to the next node to keep looking
        jmp LOOP_REMOVE 

REMOVE_FROM_LIST: # remove the node from the list
        movl NEXT(%edi), %eax # eax = node to remove -> next
        movl %eax, NEXT(%ebx) # ebx->next = node to remove-> next 
        movl $0, NEXT(%edi) # node to move->next = null 
        jmp FREE_MEMORY_REMOVE
HEAD_REMOVE:
        movl mp1_list_head, %edi # get address of head for free
        movl NEXT(%edi), %eax 
        movl %eax, mp1_list_head # new head = old head->next 
        movl $0, NEXT(%edi) # set old head->next to null
       
FREE_MEMORY_REMOVE: # free the memory from the removed node
        pushl %edi
        call mp1_free
        addl $4, %esp

SUCCESS_REMOVE: # set retval
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
#     Registers: %ebx - arg pointer to original struct
#                %ecx - location to find 
#                %eax - return value, location of new struct
#                %edi - address of new struct
mp1_ioctl_find:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load arg
        cmpl $0, %ebx 
        je ERROR_FIND # invalid structure input
        xor %ecx, %ecx
        movw LOCATION(%ebx), %cx # location to find in cx

        pushl %ecx # push the location to find
        pushl %ebx # pushl the list to search

        call mp1_search_list
        popl %ebx # pop args off
        popl %ecx 
        cmpl $0, %eax
        je ERROR_FIND # didn't find in list

        # found in list
        pushl $STRUCT_SIZE # size
        pushl %edi # from
        pushl %ebx # to

        call mp1_copy_to_user
        addl $12, %esp # pop 3x4bit args from stack
        cmpl $0, %eax 
        jne ERROR_FIND

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
#     Registers: %edx - arg, upper 16 bits = 1st char, rest = 2nd char
#                       %dx - 1st char, upper bits of arg
#                %ecx -  hold part of arg
#                       %cx - 2nd char, lower bits of arg
#                %eax - return value, temp for hold values of one struct       
#                %edi - address of char 1 struct
#                %esi - address of char 2 struct           

mp1_ioctl_sync:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %edx # load arg
        xor %ecx, %ecx
        movw %dx, %cx   # lower bits into cx
        shrl $16, %edx # shift right to get upper 16 bits into lower 16 bits dx

        # get ready to search for 1st char
        pushl %ecx # caller save arg registers
        pushl %edx

        pushl %edx # next push args
        pushl mp1_list_head

        call mp1_search_list
        addl $8, %esp # next pop 2x4bit args
        popl %edx # caller restore registers
        popl %ecx

        cmpl $0, %eax  
        je ERROR_SYNC # didn't find location matching char 1
        movl %eax, %edi # edi is address of struct with location for char 1

        # get ready to search for 2nd char
        pushl %ecx # caller save arg registers
        pushl %edx

        pushl %ecx
        pushl mp1_list_head

        call mp1_search_list
        addl $8, %esp # pop 2x4bit args off stack
        popl %edx # caller restore registers 
        popl %ecx

        cmpl $0, %eax
        je ERROR_SYNC # didn't find location matching char 2
        movl %eax, %esi # esi is address of struct with location for char 2

        # found location of both characters
        movw ON_LENGTH(%edi), %ax # copy onlength, offlength, countdown, status
        movw %ax, ON_LENGTH(%esi) # from char 1 edi to char 2 esi
        movw OFF_LENGTH(%edi), %ax
        movw %ax, OFF_LENGTH(%esi)
        movw COUNTDOWN(%edi), %ax
        movw %ax, COUNTDOWN(%esi)
        movw STATUS(%edi), %ax
        movw %ax, STATUS(%esi)

        # get ready for m1_poke for 2nd location
        xor %ecx, %ecx # clear registers for poke
        xor %eax, %eax
        cmpl $0, STATUS(%esi) 
        je STATUS_OFF_SYNC 
        movb ON_CHAR(%esi), %cl # on char for poke

STATUS_OFF_SYNC:
        movb OFF_CHAR(%esi), %cl # off char for poke

SUCCESS_SYNC:
        # call poke
        movw LOCATION(%esi), %ax  # location for poke
        shll $1, %eax # fix display error
        call mp1_poke 
        xor %eax, %eax # update retval for success
        jmp DONE_SYNC

ERROR_SYNC:
        movl $-1, %eax # update retval for fail

DONE_SYNC:
        popl  %edi # callee tear down registers
        popl  %esi
        popl  %ebx
        leave
	ret


# int mp1_search_list:
#
# Interface: 
#        Inputs: unsigned long list to search
#              : unsigned long location to find
#       Outputs: address of found struct, or null if not found
#     Registers: %ebx - list
#                %ecx - location to find    
#                %eax - return value, current location value
#                %edi - original list to search, address of new struct
mp1_search_list:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %edi # load list to search
        movl 12(%ebp), %ecx # load location to find

LOOP_SEARCH_LIST:
        # check location of current node
        movw LOCATION(%edi), %ax
        cmpw %ax, %cx 
        je DONE_SEARCH_LIST

        # didn't find location
        movl NEXT(%edi), %edi
        cmpl $0, NEXT(%edi) 
        jne LOOP_SEARCH_LIST # check the next node

DONE_SEARCH_LIST:
        movl  %edi, %eax # load return value 
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# for ioctl dispatcher
JUMP_TABLE:             
.long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync

.end
