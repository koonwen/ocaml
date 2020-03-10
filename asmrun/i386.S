/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           */
/*                                                                        */
/*   Copyright 1996 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

/* Asm part of the runtime system, Intel 386 processor */
/* Must be preprocessed by cpp */

#include "caml/m.h"

/* Linux/BSD with ELF binaries and Solaris do not prefix identifiers with _.
   Linux/BSD with a.out binaries and NextStep do. */

#if (defined(SYS_solaris) && !defined(__GNUC__))
#define CONCAT(a,b) a/**/b
#else
#define CONCAT(a,b) a##b
#endif

#if defined(SYS_linux_elf) || defined(SYS_bsd_elf) \
 || defined(SYS_solaris) || defined(SYS_beos) || defined(SYS_gnu)
#define G(x) x
#define LBL(x) CONCAT(.L,x)
#else
#define G(x) CONCAT(_,x)
#define LBL(x) CONCAT(L,x)
#endif

#if defined(SYS_linux_elf) || defined(SYS_bsd_elf) \
 || defined(SYS_solaris) || defined(SYS_beos) || defined(SYS_cygwin) \
 || defined(SYS_mingw) || defined(SYS_gnu)
#define FUNCTION_ALIGN 4
#else
#define FUNCTION_ALIGN 2
#endif

#define FUNCTION(name) \
        .globl G(name); \
        .align FUNCTION_ALIGN; \
        G(name):

#ifdef ASM_CFI_SUPPORTED
#define CFI_STARTPROC .cfi_startproc
#define CFI_ENDPROC .cfi_endproc
#define CFI_ADJUST(n) .cfi_adjust_cfa_offset n
#else
#define CFI_STARTPROC
#define CFI_ENDPROC
#define CFI_ADJUST(n)
#endif

#if defined(PROFILING)
#if defined(SYS_linux_elf) || defined(SYS_gnu)
#define PROFILE_CAML \
        pushl %ebp; CFI_ADJUST(4); \
        movl %esp, %ebp; \
        pushl %eax; CFI_ADJUST(4); \
        pushl %ecx; CFI_ADJUST(4); \
        pushl %edx; CFI_ADJUST(4); \
        CALL_VAR(mcount); \
        popl %edx; CFI_ADJUST(-4); \
        popl %ecx; CFI_ADJUST(-4); \
        popl %eax; CFI_ADJUST(-4); \
        popl %ebp; CFI_ADJUST(-4)
#define PROFILE_C \
        pushl %ebp; CFI_ADJUST(4); \
        movl %esp, %ebp; \
        CALL_VAR(mcount); \
        popl %ebp; CFI_ADJUST(-4)
#elif defined(SYS_bsd_elf)
#define PROFILE_CAML \
        pushl %ebp; CFI_ADJUST(4); \
        movl %esp, %ebp; \
        pushl %eax; CFI_ADJUST(4); \
        pushl %ecx; CFI_ADJUST(4); \
        pushl %edx; CFI_ADJUST(4); \
        CALL_VAR(.mcount); \
        popl %edx; CFI_ADJUST(-4); \
        popl %ecx; CFI_ADJUST(-4); \
        popl %eax; CFI_ADJUST(-4); \
        popl %ebp; CFI_ADJUST(-4)
#define PROFILE_C \
        pushl %ebp; CFI_ADJUST(4); \
        movl %esp, %ebp; \
        CALL_VAR(.mcount); \
        popl %ebp; CFI_ADJUST(-4)
#elif defined(SYS_macosx)
#define PROFILE_CAML \
        pushl %ebp; CFI_ADJUST(4); \
        movl %esp, %ebp; \
        pushl %eax; CFI_ADJUST(4); \
        pushl %ecx; CFI_ADJUST(4); \
        pushl %edx; CFI_ADJUST(4); \
        CALL_VAR(Lmcount$stub);  \
        popl %edx; CFI_ADJUST(-4); \
        popl %ecx; CFI_ADJUST(-4); \
        popl %eax; CFI_ADJUST(-4); \
        popl %ebp; CFI_ADJUST(-4)
#define PROFILE_C \
        pushl %ebp; CFI_ADJUST(4); \
        movl %esp, %ebp; \
        CALL_VAR(Lmcount$stub); \
        popl %ebp; CFI_ADJUST(-4)
#endif
#else
#define PROFILE_CAML
#define PROFILE_C
#endif

LBL(get_current_ip):
	calll LBL(inner_get_current_ip)
	addl	$_GLOBAL_OFFSET_TABLE_, %ebx
	ret
	LBL(inner_get_current_ip):
		movl (%esp), %ebx
		ret

#if defined(__PIC__)

#define CALL_VAR(label) \
        pushl   %ebx; \
        calll   LBL(get_current_ip); \
        call    *G(label)@GOT(%ebx); \
        popl    %ebx;

/* Store [srcreg] in global [dstlabel]. */
#define STORE_VAR(srcreg, dstlabel) \
        pushl   srcreg ; CFI_ADJUST(4) \
        pushl   %ebx ; CFI_ADJUST(4) \
        calll   LBL(get_current_ip) ; \
        movl    G(dstlabel)@GOT(%ebx), %ebx ; \
        addl    $4, %esp ; CFI_ADJUST(-4) \
        popl    (%ebx) ; CFI_ADJUST(-4) \
        subl    $8, %esp ; CFI_ADJUST(8) \
        popl    %ebx ; CFI_ADJUST(-4) \
        popl    srcreg ; CFI_ADJUST(-4)

#define PUSH_VAR(srclabel) \
        pushl   %ebx ; CFI_ADJUST(4) \
        calll   LBL(get_current_ip) ; \
        movl    G(srclabel)@GOT(%ebx), %ebx ; \
        movl    (%ebx), %ebx ; \
        xchgl   (%esp), %ebx ; /* so %ebx is restored and (%esp) contains the value */

/* Load global [srclabel] in register [dstreg]. */
#define LOAD_VAR(srclabel, dstreg) \
        PUSH_VAR(srclabel) ; \
        popl dstreg ; CFI_ADJUST(-4)

#define CMP_VAR(label, reg) \
        pushl   %ebx ; CFI_ADJUST(4) \
        calll   LBL(get_current_ip) ; \
        movl    G(label)@GOT(%ebx), %ebx ; \
        cmpl    (%ebx), reg ; \
        popl    %ebx ; CFI_ADJUST(-4)

#define POP_VAR(dstlabel) \
        xchgl   (%esp), %ebx ; \
        pushl   %ebx ; CFI_ADJUST(4) \
        calll   LBL(get_current_ip) ; \
        movl    G(dstlabel)@GOT(%ebx), %ebx ; \
        popl    (%ebx) ; CFI_ADJUST(-4) ; \
        popl    %ebx ; CFI_ADJUST(-4)

#define LEA_VAR(label, dst) \
        pushl   %ebx ; CFI_ADJUST(4) \
        calll   LBL(get_current_ip) ; \
        movl    G(label)@GOT(%ebx), %ebx ; \
        xchgl   (%esp), %ebx ; /* so %ebx is restored and (%esp) contains the address */ \
        popl    dst ; CFI_ADJUST(-4)

/* Subtract global [srclabel] of register [dstreg]. */
#define SUB_VAR(srclabel, dstreg) \
        PUSH_VAR(srclabel) ; \
        addl    $4, %esp ; CFI_ADJUST(-4) \
        subl    -4(%esp), dstreg ;

#define TESTL_VAR(imm, label) \
        PUSH_VAR(label) ; \
        addl    $4, %esp ; \
        testl   imm, -4(%esp)

#else

#define CALL_VAR(label) \
        call   G(label)

#define STORE_VAR(srcreg, dstlabel) \
        movl    srcreg, G(dstlabel)

#define LOAD_VAR(srclabel, dstreg) \
        movl    G(srclabel), dstreg

#define CMP_VAR(label, reg) \
        cmpl    G(label), %eax

#define PUSH_VAR(srclabel) \
        pushl   G(srclabel); CFI_ADJUST(4)

#define POP_VAR(dstlabel) \
        popl    G(dstlabel); CFI_ADJUST(-4)

#define LEA_VAR(label, dst) \
        leal    G(label), dst

#define SUB_VAR(srclabel, dstreg) \
        subl    G(caml_young_ptr), dstreg

#define TESTL_VAR(imm, label) \
        testl   imm, G(label)

#endif

/* PR#6038: GCC and Clang seem to require 16-byte alignment nowadays,
   even if only MacOS X's ABI formally requires it. */
#define ALIGN_STACK(amount) subl $ amount, %esp ; CFI_ADJUST(amount)
#define UNDO_ALIGN_STACK(amount) addl $ amount, %esp ; CFI_ADJUST(-amount)

/* Allocation */

        .text
        .globl  G(caml_system__code_begin)
G(caml_system__code_begin):

FUNCTION(caml_call_gc)
        CFI_STARTPROC
        PROFILE_CAML
    /* Record lowest stack address and return address */
        movl    0(%esp), %eax
        STORE_VAR(%eax, caml_last_return_address)
        leal    4(%esp), %eax
        STORE_VAR(%eax, caml_bottom_of_stack)
LBL(105):
#if !defined(SYS_mingw) && !defined(SYS_cygwin)
    /* Touch the stack to trigger a recoverable segfault
       if insufficient space remains */
        subl    $16384, %esp
        movl    %eax, 0(%esp)
        addl    $16384, %esp
#endif
    /* Build array of registers, save it into caml_gc_regs */
        pushl   %ebp; CFI_ADJUST(4)
        pushl   %edi; CFI_ADJUST(4)
        pushl   %esi; CFI_ADJUST(4)
        pushl   %edx; CFI_ADJUST(4)
        pushl   %ecx; CFI_ADJUST(4)
        pushl   %ebx; CFI_ADJUST(4)
        pushl   %eax; CFI_ADJUST(4)
        STORE_VAR(%esp, caml_gc_regs)
        /* MacOSX note: 16-alignment of stack preserved at this point */
    /* Call the garbage collector */
        CALL_VAR(caml_garbage_collection)
    /* Restore all regs used by the code generator */
        popl    %eax; CFI_ADJUST(-4)
        popl    %ebx; CFI_ADJUST(-4)
        popl    %ecx; CFI_ADJUST(-4)
        popl    %edx; CFI_ADJUST(-4)
        popl    %esi; CFI_ADJUST(-4)
        popl    %edi; CFI_ADJUST(-4)
        popl    %ebp; CFI_ADJUST(-4)
    /* Return to caller */
        ret
        CFI_ENDPROC

FUNCTION(caml_alloc1)
        CFI_STARTPROC
        PROFILE_CAML
        LOAD_VAR(caml_young_ptr, %eax)
        subl    $8, %eax
        STORE_VAR(%eax, caml_young_ptr)
        CMP_VAR(caml_young_limit, %eax)
        jb      LBL(100)
        ret
LBL(100):
        movl    0(%esp), %eax
        STORE_VAR(%eax, caml_last_return_address)
        leal    4(%esp), %eax
        STORE_VAR(%eax, caml_bottom_of_stack)
        ALIGN_STACK(12)
        call    LBL(105)
        UNDO_ALIGN_STACK(12)
        jmp     G(caml_alloc1)
        CFI_ENDPROC

FUNCTION(caml_alloc2)
        CFI_STARTPROC
        PROFILE_CAML
        LOAD_VAR(caml_young_ptr, %eax)
        subl    $12, %eax
        STORE_VAR(%eax, caml_young_ptr)
        CMP_VAR(caml_young_limit, %eax)
        jb      LBL(101)
        ret
LBL(101):
        movl    0(%esp), %eax
        STORE_VAR(%eax, caml_last_return_address)
        leal    4(%esp), %eax
        STORE_VAR(%eax, caml_bottom_of_stack)
        ALIGN_STACK(12)
        call    LBL(105)
        UNDO_ALIGN_STACK(12)
        jmp     G(caml_alloc2)
        CFI_ENDPROC

FUNCTION(caml_alloc3)
        CFI_STARTPROC
        PROFILE_CAML
        LOAD_VAR(caml_young_ptr, %eax)
        subl    $16, %eax
        STORE_VAR(%eax, caml_young_ptr)
        CMP_VAR(caml_young_limit, %eax)
        jb      LBL(102)
        ret
LBL(102):
        movl    0(%esp), %eax
        STORE_VAR(%eax, caml_last_return_address)
        leal    4(%esp), %eax
        STORE_VAR(%eax, caml_bottom_of_stack)
        ALIGN_STACK(12)
        call    LBL(105)
        UNDO_ALIGN_STACK(12)
        jmp     G(caml_alloc3)
        CFI_ENDPROC

FUNCTION(caml_allocN)
        CFI_STARTPROC
        PROFILE_CAML
        SUB_VAR(caml_young_ptr, %eax)   /* eax = size - caml_young_ptr */
        negl    %eax                    /* eax = caml_young_ptr - size */
        CMP_VAR(caml_young_limit, %eax)
        jb      LBL(103)
        STORE_VAR(%eax, caml_young_ptr)
        ret
LBL(103):
        SUB_VAR(caml_young_ptr, %eax)   /* eax = - size */
        negl    %eax                    /* eax = size */
        pushl   %eax; CFI_ADJUST(4)     /* save desired size */

        pushl   %ebx
        LOAD_VAR(caml_young_ptr, %ebx)
        subl    %eax, %ebx
        STORE_VAR(%ebx, caml_young_ptr) /* must update young_ptr */
        popl    %ebx

        movl    4(%esp), %eax
        STORE_VAR(%eax, caml_last_return_address)
        leal    8(%esp), %eax
        STORE_VAR(%eax, caml_bottom_of_stack)
        ALIGN_STACK(8)
        call    LBL(105)
        UNDO_ALIGN_STACK(8)
        popl    %eax; CFI_ADJUST(-4)    /* recover desired size */
        jmp     G(caml_allocN)
        CFI_ENDPROC

/* Call a C function from OCaml */

FUNCTION(caml_c_call)
        CFI_STARTPROC
        PROFILE_CAML
    /* Record lowest stack address and return address */
        movl    (%esp), %edx
        STORE_VAR(%edx, caml_last_return_address)
        leal    4(%esp), %edx
        STORE_VAR(%edx, caml_bottom_of_stack)
#if !defined(SYS_mingw) && !defined(SYS_cygwin)
    /* Touch the stack to trigger a recoverable segfault
       if insufficient space remains */
        subl    $16384, %esp
        movl    %eax, 0(%esp)
        addl    $16384, %esp
#endif
    /* Call the function (address in %eax) */
        jmp     *%eax
        CFI_ENDPROC

/* Start the OCaml program */

FUNCTION(caml_start_program)
        CFI_STARTPROC
        PROFILE_C
    /* Save callee-save registers */
        pushl   %ebx; CFI_ADJUST(4)
        pushl   %esi; CFI_ADJUST(4)
        pushl   %edi; CFI_ADJUST(4)
        pushl   %ebp; CFI_ADJUST(4)
    /* Initial entry point is caml_program */
        LEA_VAR(caml_program, %esi)
    /* Common code for caml_start_program and caml_callback* */
LBL(106):
    /* Build a callback link */
        PUSH_VAR(caml_gc_regs)
        PUSH_VAR(caml_last_return_address)
        PUSH_VAR(caml_bottom_of_stack)
        /* Note: 16-alignment preserved on MacOSX at this point */
    /* Build an exception handler */
        pushl   $ LBL(108); CFI_ADJUST(4)
        ALIGN_STACK(8)
        PUSH_VAR(caml_exception_pointer)
        STORE_VAR(%esp, caml_exception_pointer)
    /* Call the OCaml code */
        call    *%esi
LBL(107):
    /* Pop the exception handler */
        POP_VAR(caml_exception_pointer)
        addl    $12, %esp       ; CFI_ADJUST(-12)
LBL(109):
    /* Pop the callback link, restoring the global variables */
        POP_VAR(caml_bottom_of_stack)
        POP_VAR(caml_last_return_address)
        POP_VAR(caml_gc_regs)
    /* Restore callee-save registers. */
        popl    %ebp; CFI_ADJUST(-4)
        popl    %edi; CFI_ADJUST(-4)
        popl    %esi; CFI_ADJUST(-4)
        popl    %ebx; CFI_ADJUST(-4)
    /* Return to caller. */
        ret
LBL(108):
    /* Exception handler*/
    /* Mark the bucket as an exception result and return it */
        orl     $2, %eax
        jmp     LBL(109)
        CFI_ENDPROC

/* Raise an exception from OCaml */

FUNCTION(caml_raise_exn)
        CFI_STARTPROC
        TESTL_VAR($1, caml_backtrace_active)
        jne     LBL(110)
        LOAD_VAR(caml_exception_pointer, %esp)
        POP_VAR(caml_exception_pointer)
        UNDO_ALIGN_STACK(8)
        ret
LBL(110):
        movl    %eax, %esi          /* Save exception bucket in esi */
        LOAD_VAR(caml_exception_pointer, %edi)  /* SP of handler */
        movl    0(%esp), %eax       /* PC of raise */
        leal    4(%esp), %edx       /* SP of raise */
        ALIGN_STACK(12)
        pushl   %edi; CFI_ADJUST(4)         /* arg 4: sp of handler */
        pushl   %edx; CFI_ADJUST(4)         /* arg 3: sp of raise */
        pushl   %eax; CFI_ADJUST(4)         /* arg 2: pc of raise */
        pushl   %esi; CFI_ADJUST(4)         /* arg 1: exception bucket */
        CALL_VAR(caml_stash_backtrace)
        movl    %esi, %eax              /* Recover exception bucket */
        movl    %edi, %esp
        POP_VAR(caml_exception_pointer)
        UNDO_ALIGN_STACK(8)
        ret
        CFI_ENDPROC

/* Raise an exception from C */

FUNCTION(caml_raise_exception)
        CFI_STARTPROC
        PROFILE_C
        TESTL_VAR($1, caml_backtrace_active)
        jne     LBL(112)
        movl    4(%esp), %eax
        LOAD_VAR(caml_exception_pointer, %esp)
        POP_VAR(caml_exception_pointer)
        UNDO_ALIGN_STACK(8)
        ret
LBL(112):
        movl    4(%esp), %esi          /* Save exception bucket in esi */
        ALIGN_STACK(12)
        PUSH_VAR(caml_exception_pointer)  /* 4: sp of handler */
        PUSH_VAR(caml_bottom_of_stack)    /* 3: sp of raise */
        PUSH_VAR(caml_last_return_address)/* 2: pc of raise */
        pushl   %esi; CFI_ADJUST(4)                    /* 1: exception bucket */
        CALL_VAR(caml_stash_backtrace)
        movl    %esi, %eax              /* Recover exception bucket */
        LOAD_VAR(caml_exception_pointer, %esp)
        POP_VAR(caml_exception_pointer)
        UNDO_ALIGN_STACK(8)
        ret
        CFI_ENDPROC

/* Callback from C to OCaml */

FUNCTION(caml_callback_exn)
        CFI_STARTPROC
        PROFILE_C
    /* Save callee-save registers */
        pushl   %ebx; CFI_ADJUST(4)
        pushl   %esi; CFI_ADJUST(4)
        pushl   %edi; CFI_ADJUST(4)
        pushl   %ebp; CFI_ADJUST(4)
    /* Initial loading of arguments */
        movl    20(%esp), %ebx   /* closure */
        movl    24(%esp), %eax   /* argument */
        movl    0(%ebx), %esi    /* code pointer */
        jmp     LBL(106)
        CFI_ENDPROC

FUNCTION(caml_callback2_exn)
        CFI_STARTPROC
        PROFILE_C
    /* Save callee-save registers */
        pushl   %ebx; CFI_ADJUST(4)
        pushl   %esi; CFI_ADJUST(4)
        pushl   %edi; CFI_ADJUST(4)
        pushl   %ebp; CFI_ADJUST(4)
    /* Initial loading of arguments */
        movl    20(%esp), %ecx   /* closure */
        movl    24(%esp), %eax   /* first argument */
        movl    28(%esp), %ebx   /* second argument */
        LEA_VAR(caml_apply2, %esi)   /* code pointer */
        jmp     LBL(106)
        CFI_ENDPROC

FUNCTION(caml_callback3_exn)
        CFI_STARTPROC
        PROFILE_C
    /* Save callee-save registers */
        pushl   %ebx; CFI_ADJUST(4)
        pushl   %esi; CFI_ADJUST(4)
        pushl   %edi; CFI_ADJUST(4)
        pushl   %ebp; CFI_ADJUST(4)
    /* Initial loading of arguments */
        movl    20(%esp), %edx   /* closure */
        movl    24(%esp), %eax   /* first argument */
        movl    28(%esp), %ebx   /* second argument */
        movl    32(%esp), %ecx   /* third argument */
        LEA_VAR(caml_apply3, %esi)   /* code pointer */
        jmp     LBL(106)
        CFI_ENDPROC

FUNCTION(caml_ml_array_bound_error)
        CFI_STARTPROC
    /* Empty the floating-point stack */
        ffree   %st(0)
        ffree   %st(1)
        ffree   %st(2)
        ffree   %st(3)
        ffree   %st(4)
        ffree   %st(5)
        ffree   %st(6)
        ffree   %st(7)
    /* Record lowest stack address and return address */
        movl    (%esp), %edx
        STORE_VAR(%edx, caml_last_return_address)
        leal    4(%esp), %edx
        STORE_VAR(%edx, caml_bottom_of_stack)
    /* Re-align the stack */
        andl    $-16, %esp
    /* Branch to [caml_array_bound_error] (never returns) */
        CALL_VAR(caml_array_bound_error)
        CFI_ENDPROC

        .globl  G(caml_system__code_end)
G(caml_system__code_end):

        .data
        .globl  G(caml_system__frametable)
G(caml_system__frametable):
        .long   1               /* one descriptor */
        .long   LBL(107)        /* return address into callback */
#ifndef SYS_solaris
        .word   -1              /* negative frame size => use callback link */
        .word   0               /* no roots here */
#else
        .value  -1              /* negative frame size => use callback link */
        .value  0               /* no roots here */
#endif

        .globl  G(caml_extra_params)
G(caml_extra_params):
#ifndef SYS_solaris
        .space  64
#else
        .zero   64
#endif

#if defined(PROFILING) && defined(SYS_macosx)
        .section __IMPORT,__jump_table,symbol_stubs,self_modifying_code+pure_instructions,5
Lmcount$stub:
        .indirect_symbol mcount
        hlt ; hlt ; hlt ; hlt ; hlt
        .subsections_via_symbols
#endif

#if defined(SYS_linux_elf)
    /* Mark stack as non-executable, PR#4564 */
        .section .note.GNU-stack,"",%progbits
#endif
