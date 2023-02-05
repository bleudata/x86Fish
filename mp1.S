
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
#     Registers: %ebx - arg, temp for holding struct info/values
#                %eax - location value for poke
#                %ecx - char value for  poke
#                %edi - struct / node pointer
mp1_rtc_tasklet:
        pushl %ebp # callee stack setup ebp and save registers
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi
       
       # check if head is null
        movl mp1_list_head, %edi
        cmpl $0, %edi 
        je DONE_TASKLET # done if head null

        # head not null, check if countdown = 0
        cmpw $0, COUNTDOWN(%edi) # check if countdown is initially 0
        je COUNTDOWN_ZERO

LIST_LOOP:
        # decrement countdown and check again if 0
        addw $-1, COUNTDOWN(%edi)
        cmpw $0, COUNTDOWN(%edi)
        jne CHECK_NEXT_STRUCT # done with this struct if not 0

COUNTDOWN_ZERO:
        # clear registers for poke and checking 16 bit values
        xor %ecx, %ecx
        xor %eax, %eax
        xor %ebx, %ebx

        cmpw $0, STATUS(%edi) # check status 
        je STATUS_OFF_TASKLET

        # current status = ON, change status to OFF
        movb OFF_CHAR(%edi), %cl # load char
        movw $0, STATUS(%edi) # change status to OFF
        movw LOCATION(%edi), %ax # get location
        shll $1, %eax # shift location to fix display
        call mp1_poke
        movw OFF_LENGTH(%edi), %bx # change countdown to OFF_LENGTH
        movw %bx, COUNTDOWN(%edi)
        jmp CHECK_NEXT_STRUCT

STATUS_OFF_TASKLET:
        # current status = OFF, change status to ON
        movb ON_CHAR(%edi), %cl # load char
        movw $1, STATUS(%edi) # change status to ON
        movw LOCATION(%edi), %ax # get location
        shll $1, %eax # shift location to fix display
        call mp1_poke
        movw ON_LENGTH(%edi), %bx # change countdown to ON_LENGTH
        movw %bx, COUNTDOWN(%edi)

CHECK_NEXT_STRUCT:
        movl NEXT(%edi), %edi 
        cmpl $0, %edi # check if reached end of list
        je DONE_TASKLET # end of list 
        jmp LIST_LOOP # more in list, loop back for next struct

DONE_TASKLET:
        popl  %edi # callee tear down 
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
        pushl %ebp # callee stack set up 
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load arg
        cmpl $0, %ebx # check if invalid struct arg 
        je ERROR_ADD

        # allocate memory for copy of structure
        pushl $STRUCT_SIZE # push size for malloc
        call mp1_malloc
        addl $4, %esp # pop arg off stack
        cmpl $0, %eax # check %eax return value for error
        je ERROR_ADD # error, malloc returned NULL 
        movl %eax, %edi # edi = address of new struct

        # copy struct from user space to new memory
        pushl $STRUCT_SIZE # size
        pushl %ebx # from
        pushl %edi # to

        call mp1_copy_from_user
        addl $12, %esp
        cmpl $0, %eax 
        jne FREE_MEMORY_ADD # error, not all bytes copied

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

        
        xorl %ecx, %ecx # clear out any garbage
        xorl %eax, %eax
        movw STATUS(%edi), %cx 
        cmpl $0, %ecx # check status
        je STATUS_OFF_ADD # current status off
        movb ON_CHAR(%edi), %cl # load char/location for poke
        movw LOCATION(%edi), %ax
        shll $1, %eax # shift to fix display
        call mp1_poke
        jmp SUCCESS_ADD

STATUS_OFF_ADD:
        movb OFF_CHAR(%edi), %cl # load char/location for poke
        movw LOCATION(%edi), %ax
        shll $1, %eax # shift to fix display
        call mp1_poke

SUCCESS_ADD:
        xor %eax, %eax # retval = 0
        jmp DONE_ADD

FREE_MEMORY_ADD:
        pushl %edi # address of memory to free
        call mp1_free
        addl $4, %esp # pop arg 

ERROR_ADD:
        movl $-1, %eax # retval = -1

DONE_ADD:
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# void mp1_ioctl_remove:
# Remove a struct from the list based on  location
# Interface: 
#        Inputs: unsigned long arg, location field of struct to remove
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

        
        cmpl mp1_list_head, %edi # special case head node is node to remove
        je HEAD_REMOVE # node to remove is head

        # node to remove is in the middle of the list
        # need to find the node whos node->next is node to remove
        movl mp1_list_head, %ebx # head is first node to check
LOOP_REMOVE:
        cmpl NEXT(%ebx), %edi # if the current node points to node to remove
        je REMOVE_FROM_LIST # go to start removing
        movl NEXT(%ebx), %ebx # keep looking, go to next node
        jmp LOOP_REMOVE 

REMOVE_FROM_LIST: # remove the node from the list
        movl NEXT(%edi), %eax # eax = node to remove -> next
        movl %eax, NEXT(%ebx) # set ebx->next = node to remove-> next 
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
        xor %eax, %eax # retval = 0
        jmp DONE_REMOVE

ERROR_REMOVE:
        movl $-1, %eax # retval = -1
DONE_REMOVE:
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# void mp1_ioctl_find:
# find and copy element from kernel to user structure
# works with sync to make I/M flash in sync with the rest of the fish frame
# Interface: 
#        Inputs: unsigned long arg
#       Outputs: 0 is succesful, -1 if error
#     Registers: %ebx - arg pointer to original struct in user space
#                %ecx - location to find 
#                %eax - return value, location of new struct
#                %edi - address of new struct
#                %esi - address of original struct in kernel space
mp1_ioctl_find:
        pushl %ebp
        movl  %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %ebx # load arg
        cmpl $0, %ebx 
        je ERROR_FIND # invalid structure input
        

        # malloc space to copy struct from user 
        pushl $STRUCT_SIZE # load size to push as argument
        call mp1_malloc # check %eax return value for error
        addl $4, %esp # pop arg off stack
        cmpl $0, %eax
        je ERROR_FIND # error, malloc returned NULL 
        movl %eax, %esi # esi = address of new struct

        # next push args for  copy_from_user
        pushl $STRUCT_SIZE # size
        pushl %ebx # from
        pushl %esi # to

        call mp1_copy_from_user
        addl $12, %esp # pop args
        cmpl $0, %eax 
        jne ERROR_FIND # error, not all bytes copied

        # get location
        xorl %ecx, %ecx
        movw LOCATION(%esi), %cx # cx = location to find 
        
        # look for location in the list 
        pushl %ecx # push the location to find
        pushl %esi # pushl the list to search

        call mp1_search_list
        popl %esi # pop args off
        popl %ecx 
        cmpl $0, %eax
        je ERROR_FIND # didn't find in list
        movl %eax, %edi
        # found in list, now copy to user space
        pushl $STRUCT_SIZE # size
        pushl %edi # from
        pushl %ebx # to

        call mp1_copy_to_user
        addl $12, %esp # pop 3x4bit args from stack
        cmpl $0, %eax 
        jne ERROR_FIND # not all bytes copied

SUCCESS_FIND:
        xor %eax, %eax # retval = 0 for success
        jmp DONE_FIND

ERROR_FIND:
        movl $-1, %eax # retval = -1 for fail
DONE_FIND:
        # free the original struct from kernel space
        pushl %esi
        call mp1_free
        addl $4, %esp
        # callee tear down
        popl  %edi
        popl  %esi
        popl  %ebx
        leave
	ret

# void mp1_ioctl_sync:
# Syncs I/M flashing with rest of fish frame, works with find
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
        movw %dx, %cx  # lower bits into cx
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

        pushl %ecx # push args
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
        cmpl $0, STATUS(%esi) # check status
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
# Looks for a specified location in a given list. Returns the address of the struct 
# if the desired location is found. Helper function
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
        movw LOCATION(%edi), %ax # get location of current node
        cmpw %ax, %cx  # if it's equal to target, done
        je DONE_SEARCH_LIST

        # didn't find location
        movl NEXT(%edi), %edi # get the next node
        cmpl $0, %edi # if next node is null, checking the tail
        je DONE_SEARCH_LIST
        cmpl $0, NEXT(%edi) # if next isn't null
        jne LOOP_SEARCH_LIST # check the next node

DONE_SEARCH_LIST:
        movl  %edi, %eax # load return value 
        popl  %edi # callee tear down
        popl  %esi
        popl  %ebx
        leave
	ret

# functions for ioctl dispatcher
JUMP_TABLE:             
.long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync

.end
