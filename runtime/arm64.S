/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*             Xavier Leroy, projet Gallium, INRIA Rocquencourt           */
/*                                                                        */
/*   Copyright 2013 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

/* Asm part of the runtime system, ARM processor, 64-bit mode */
/* Must be preprocessed by cpp */

#include "caml/m.h"

/* Special registers */

#define DOMAIN_STATE_PTR x28
/* TODO: maybe adding TRAP_PTR to x86_64 will be worth it with effects */
#define TRAP_PTR x26
#define ALLOC_PTR x27
#define ADDITIONAL_ARG x8
#define TMP x16
#define TMP2 x17

#define C_ARG_1 x0
#define C_ARG_2 x1
#define C_ARG_3 x2
#define C_ARG_4 x3

#define C_NON_VOLATILE_1 x19

/* Support for CFI directives */

#if defined(ASM_CFI_SUPPORTED)
#define CFI_STARTPROC .cfi_startproc
#define CFI_ENDPROC .cfi_endproc
#define CFI_ADJUST(n) .cfi_adjust_cfa_offset n
#define CFI_REGISTER(r1,r2) .cfi_register r1,r2
#define CFI_OFFSET(r,n) .cfi_offset r,n
#else
#define CFI_STARTPROC
#define CFI_ENDPROC
#define CFI_ADJUST(n)
#define CFI_REGISTER(r1,r2)
#define CFI_OFFSET(r,n)
#endif

/* struct stack_info */
#define Stack_sp(REG) [REG, 0]
#define Stack_exception          8
#define Stack_handler            16

/* struct stack_handler */
#define Handler_value(REG)       0(REG)
#define Handler_exception(REG)   8(REG)
#define Handler_effect(REG)     16(REG)
#define Handler_parent          24

/* struct c_stack_link */
/* TODO: does this 32 here because of stack alignment makes sense? */
#define Sizeof_cstack           32
#define Cstack_stack(REG) [REG, 0]
#define Cstack_sp(REG) [REG, 8]
#define Cstack_prev(REG) [REG, 16]

        .set    domain_curr_field, 0
#if defined(SYS_macosx)
#define DOMAIN_STATE(c_type, name) DOMAIN_STATE c_type, name
        .macro DOMAIN_STATE c_type, name
        .equ    domain_field_caml_\name, domain_curr_field
        .set    domain_curr_field, domain_curr_field + 1
        .endm
#else
#define DOMAIN_STATE(c_type, name) \
        .equ    domain_field_caml_##name, domain_curr_field ; \
        .set    domain_curr_field, domain_curr_field + 1
#endif
#include "../runtime/caml/domain_state.tbl"
#undef DOMAIN_STATE

#define Caml_state(var) [DOMAIN_STATE_PTR, 8*domain_field_caml_##var]

/* Globals and labels */
#if defined(SYS_macosx)
#define G(sym) _##sym
#define L(lbl) L##lbl
#else
#define G(sym) sym
#define L(lbl) .L##lbl
#endif

#if defined(SYS_macosx)

#define ADDRGLOBAL(reg,symb) ADDRGLOBAL reg, symb
        .macro ADDRGLOBAL reg, symb
        adrp        TMP2, G(\symb)@GOTPAGE
        ldr         \reg, [TMP2, G(\symb)@GOTPAGEOFF]
        .endm
#elif defined(__PIC__)
#define ADDRGLOBAL(reg,symb) \
        adrp    TMP2, :got:G(symb); \
        ldr     reg, [TMP2, #:got_lo12:G(symb)]
#else

#define ADDRGLOBAL(reg,symb) \
        adrp    reg, G(symb); \
        add     reg, reg, #:lo12:G(symb)

#endif

#if defined(FUNCTION_SECTIONS)
#define TEXT_SECTION(name) .section .text.caml.##name,"ax",%progbits
#else
#define TEXT_SECTION(name)
#endif

#if defined(FUNCTION_SECTIONS)
        TEXT_SECTION(caml_hot__code_begin)
        .globl  G(caml_hot__code_begin)
G(caml_hot__code_begin):

        TEXT_SECTION(caml_hot__code_end)
        .globl  G(caml_hot__code_end)
G(caml_hot__code_end):
#endif

#if defined(SYS_macosx)

#define FUNCTION(name) FUNCTION name
        .macro FUNCTION name
        TEXT_SECTION(G(\name))
        .align 2
        .globl G(\name)
G(\name):
        .endm
#define END_FUNCTION(name)

#define OBJECT(name) OBJECT name
        .macro OBJECT name
        .data
        .align  3
        .globl  G(\name)
G(\name):
        .endm
#define END_OBJECT(name)

#else

#define FUNCTION(name) \
        TEXT_SECTION(name); \
        .align  2; \
        .globl  G(name); \
        .type   G(name), %function; \
G(name):
#define END_FUNCTION(name) \
        .size   G(name), .-G(name)

#define OBJECT(name) \
        .data; \
        .align  3; \
        .globl  G(name); \
        .type   G(name), %object; \
G(name):
#define END_OBJECT(name) \
        .size   G(name), .-G(name)
#endif

/******************************************************************************/
/* Stack switching operations */
/******************************************************************************/

#define FILL_C_STACK
/* Switch from OCaml to C stack. Clobbers TMP, TMP2. */

/* TODO:  not implemented */
#define SWITCH_OCAML_TO_C_CFI

#define SWITCH_OCAML_TO_C                                   \
    /* Fill in Caml_state->current_stack->sp */             \
        ldr     TMP, Caml_state(current_stack);             \
        mov     TMP2, sp;                                   \
        str     TMP2, Stack_sp(TMP);                        \
    /* Fill in Caml_state->c_stack */                       \
        ldr     TMP2, Caml_state(c_stack);                  \
        str     TMP, Cstack_stack(TMP2);                    \
        mov     TMP, sp;                                    \
        str     TMP, Cstack_sp(TMP2);                       \
    /* Switch to C stack */                                 \
        mov     sp, TMP2;                                   \
    /* Make the exn_handler and young_ptr available to C */ \
        str     ALLOC_PTR, Caml_state(young_ptr);           \
        str     TRAP_PTR, Caml_state(exn_handler);          \
        SWITCH_OCAML_TO_C_CFI

/* Switch from C to OCaml stack.  Clobbers TMP. */
#define SWITCH_C_TO_OCAML                                           \
    /* Assert that %rsp == Caml_state->c_stack &&
        Caml_state->c_stack->sp == Caml_state->current_stack->sp */ \
    /* TODO: this debug 
        IF_DEBUG(cmpq %rsp, Caml_state(c_stack); je 8f; int3; 8:    \
                 movq Caml_state(current_stack), %r11;              \
                 movq Stack_sp(%r11), %r11;                         \
                 cmpq %r11, Cstack_sp(%rsp); je 8f; int3; 8:)       \ */
        mov     TMP, sp;                                            \
        ldr     TMP, Cstack_sp(TMP);                                \
        mov     sp, TMP;                                            \
    /* Load the exn_handler and young_ptr from Caml_state */        \
        ldr     ALLOC_PTR, Caml_state(young_ptr);                   \
        ldr     TRAP_PTR, Caml_state(exn_handler);                  \
    /* TODO: CFI_RESTORE_STATE */

/* Save all of the registers that may be in use to a free gc_regs bucket.
   Returns: bucket in TMP skipping x29 and x30. Clobbers TMP2 */
#define SAVE_ALL_REGS                                               \
        ldr     TMP, Caml_state(gc_regs_buckets);                   \
        ldr     TMP2, [TMP]; /* TODO: what is "next ptr" here? */   \
        str     TMP2, Caml_state(gc_regs_buckets);                  \
        /* TODO: maybe just do an add TMP, TMP, 16 at the end?*/    \
        stp     x29, x30,   [TMP], 16;                              \
    /* Save allocatable integer registers on the stack, in the order
       given in proc.ml */                                          \
        stp     x0, x1,     [TMP, 0];                               \
        stp     x2, x3,     [TMP, 16];                              \
        stp     x4, x5,     [TMP, 32];                              \
        stp     x6, x7,     [TMP, 48];                              \
        stp     x8, x9,     [TMP, 64];                              \
        stp     x10, x11,   [TMP, 80];                              \
        stp     x12, x13,   [TMP, 96];                              \
        stp     x14, x15,   [TMP, 112];                             \
        stp     x19, x20,   [TMP, 128];                             \
        stp     x21, x22,   [TMP, 144];                             \
        stp     x23, x24,   [TMP, 160];                             \
        str     x25,        [TMP, 176];                             \
        /* TODO: what goes on the [TMP, 184]? */                    \
    /* Save caller-save floating-point registers on the stack
        (callee-saves are preserved by caml_garbage_collection) */  \
        stp     d0, d1,     [TMP, 192];                             \
        stp     d2, d3,     [TMP, 208];                             \
        stp     d4, d5,     [TMP, 224];                             \
        stp     d6, d7,     [TMP, 240];                             \
        stp     d16, d17,   [TMP, 256];                             \
        stp     d18, d19,   [TMP, 272];                             \
        stp     d20, d21,   [TMP, 288];                             \
        stp     d22, d23,   [TMP, 304];                             \
        stp     d24, d25,   [TMP, 320];                             \
        stp     d26, d27,   [TMP, 336];                             \
        stp     d28, d29,   [TMP, 352];                             \
        stp     d30, d31,   [TMP, 368];                             \
        str     ALLOC_PTR,  Caml_state(young_ptr);

/* TODO: TMP is volatile, is not preserved after a C call */
/* Undo SAVE_ALL_REGS. Expects gc_regs bucket in TMP. Clobbers TMP2 */
#define RESTORE_ALL_REGS                                            \
        ldp     x29, x30, [TMP, -16]!;                              \
        ldr     TMP2, Caml_state(gc_regs_buckets);                  \
        str     TMP2, [TMP, 0];                                     \
        str     TMP, Caml_state(gc_regs_buckets);                   \
        /* above:  ldp     x29, x30, [TMP, -16]!; */                \
        ldp     x0, x1,     [TMP, 16];                              \
        ldp     x2, x3,     [TMP, 32];                              \
        ldp     x4, x5,     [TMP, 48];                              \
        ldp     x6, x7,     [TMP, 64];                              \
        ldp     x8, x9,     [TMP, 80];                              \
        ldp     x10, x11,   [TMP, 96];                              \
        ldp     x12, x13,   [TMP, 112];                             \
        ldp     x14, x15,   [TMP, 128];                             \
        /* TODO: why is x19-x30 being stored? But not x28 */        \
        ldp     x19, x20,   [TMP, 144];                             \
        ldp     x21, x22,   [TMP, 160];                             \
        ldp     x23, x24,   [TMP, 176];                             \
        ldr     x25,        [TMP, 192];                             \
        ldp     d0, d1,     [TMP, 208];                             \
        ldp     d2, d3,     [TMP, 224];                             \
        ldp     d4, d5,     [TMP, 240];                             \
        ldp     d6, d7,     [TMP, 256];                             \
        ldp     d16, d17,   [TMP, 272];                             \
        ldp     d18, d19,   [TMP, 288];                             \
        ldp     d20, d21,   [TMP, 304];                             \
        ldp     d22, d23,   [TMP, 320];                             \
        ldp     d24, d25,   [TMP, 336];                             \
        ldp     d26, d27,   [TMP, 352];                             \
        ldp     d28, d29,   [TMP, 368];                             \
        ldp     d30, d31,   [TMP, 384];                             \
        /* TODO: what about the exception pointer below? */         \
        /* ldr     TRAP_PTR, Caml_state(exception_pointer) */       \
        ldr     ALLOC_PTR,  Caml_state(young_ptr);



/* Allocation functions and GC interface */
        TEXT_SECTION(caml_system__code_begin)
        .globl  G(caml_system__code_begin)
G(caml_system__code_begin):

FUNCTION(caml_call_gc)
        CFI_STARTPROC
L(caml_call_gc):
        SAVE_ALL_REGS
        str     TMP, Caml_state(gc_regs)
        SWITCH_OCAML_TO_C
        bl      G(caml_garbage_collection)
        SWITCH_C_TO_OCAML
        ldr     TMP, Caml_state(gc_regs)
        RESTORE_ALL_REGS
        ret
        CFI_ENDPROC
        END_FUNCTION(caml_call_gc)

FUNCTION(caml_alloc1)
        CFI_STARTPROC
        ldr     TMP, Caml_state(young_limit)
        sub     ALLOC_PTR, ALLOC_PTR, #16
        cmp     ALLOC_PTR, TMP
        b.lo    L(caml_call_gc)
        ret
        CFI_ENDPROC
        END_FUNCTION(caml_alloc1)

FUNCTION(caml_alloc2)
        CFI_STARTPROC
        ldr     TMP, Caml_state(young_limit)
        sub     ALLOC_PTR, ALLOC_PTR, #24
        cmp     ALLOC_PTR, TMP
        b.lo    L(caml_call_gc)
        ret
        CFI_ENDPROC
        END_FUNCTION(caml_alloc2)

FUNCTION(caml_alloc3)
        CFI_STARTPROC
        ldr     TMP, Caml_state(young_limit)
        sub     ALLOC_PTR, ALLOC_PTR, #32
        cmp     ALLOC_PTR, TMP
        b.lo    L(caml_call_gc)
        ret
        CFI_ENDPROC
        END_FUNCTION(caml_alloc3)

FUNCTION(caml_allocN)
        CFI_STARTPROC
        ldr     TMP, Caml_state(young_limit)
        sub     ALLOC_PTR, ALLOC_PTR, ADDITIONAL_ARG
        cmp     ALLOC_PTR, TMP
        b.lo    L(caml_call_gc)
        ret
        CFI_ENDPROC
        END_FUNCTION(caml_allocN)

/* Call a C function from OCaml */
/* Function to call is in ADDITIONAL_ARG */

FUNCTION(caml_c_call)
        CFI_STARTPROC
    /* Preserve return address in callee-save register x19 */
        mov     x19, x30
        CFI_REGISTER(30, 19)
        SWITCH_OCAML_TO_C
    /* Call the function */
        blr     ADDITIONAL_ARG
        SWITCH_C_TO_OCAML
    /* Return */
        ret     x19
        CFI_ENDPROC
        END_FUNCTION(caml_c_call)

FUNCTION(caml_c_call_stack_args)
        CFI_STARTPROC
    /* C stack args        : begin=ADDITIONAL_ARG end=sp */
    /* Load end of stack args in x19 */
        mov     x19, sp
        SWITCH_OCAML_TO_C
        mov     x20, sp
1:
        ldp     TMP, TMP2,      [ADDITIONAL_ARG], -16
        stp     TMP, TMP2,      [x20, -16]!

    /* TODO: should I do anything with frame pointer? */
        CFI_ENDPROC
        END_FUNCTION(caml_c_call_stack_args)
        
/* Start the OCaml program */

FUNCTION(caml_start_program)
        CFI_STARTPROC
        mov     x8, C_ARG_1
        ADDRGLOBAL(x9, caml_program)

/* Code shared with caml_callback* */
/* Address of domain state is in x8 */
/* Address of OCaml code to call is in x9 */
/* Arguments to the OCaml code are in x0...x7 */
/* TODO: why domain_state cannot be on DOMAIN_STATE_PTR? */;
L(jump_to_caml):
    /* Set up stack frame and save callee-save registers */
        CFI_OFFSET(29, -160)
        CFI_OFFSET(30, -152)
        stp     x29, x30, [sp, -160]!
        CFI_ADJUST(160)
        add     x29, sp, #0
        stp     x19, x20, [sp, 16]
        stp     x21, x22, [sp, 32]
        stp     x23, x24, [sp, 48]
        stp     x25, x26, [sp, 64]
        stp     x27, x28, [sp, 80]
        stp     d8, d9, [sp, 96]
        stp     d10, d11, [sp, 112]
        stp     d12, d13, [sp, 128]
        stp     d14, d15, [sp, 144]
    /* Load domain statepointer from argument */
        mov     DOMAIN_STATE_PTR, x8
    /* Load young_ptr into ALLOC_PTR */
        ldr     ALLOC_PTR, Caml_state(young_ptr)
    /* Build struct c_stack_link on the C stack */
        sub     sp, sp, Sizeof_cstack
        CFI_ADJUST(Sizeof_cstack)
        str     wzr, Cstack_stack(sp)
        str     wzr, Cstack_sp(sp)
        ldr     TMP, Caml_state(c_stack)
        str     TMP, Cstack_prev(sp)
        mov     TMP, sp
        str     TMP, Caml_state(c_stack)
    /* Load the OCaml stack. */
        ldr     TMP, Caml_state(current_stack)
        ldr     TMP, Stack_sp(TMP)
    /* Store the stack pointer to allow DWARF unwind */
        mov     TMP2, sp
    /* TODO: clearly all those str and sub below should be stps */
        str     TMP2, [TMP, -16]!
        ldr     TMP2, Caml_state(gc_regs)
        str     TMP2, [TMP, 8]
    /* Build a handler for exceptions raised in OCaml on the OCaml stack. */
        sub     TMP, TMP, #16
        adr     TMP2, L(trap_handler)
        str     TMP2, [TMP, 8]
    /* link in the previous exn_handler so that copying stacks works */
        ldr     TMP2, Caml_state(exn_handler)
        str     TMP2, [TMP, 0]
        str     TMP, Caml_state(exn_handler)
        mov     TRAP_PTR, TMP
    /* Switch stacks and call the OCaml code */
        mov     sp, TMP
    /* Call the OCaml code */
    /*
    | cstack
    | ------------------------
    | gc_regs
    | ------------------------
    | cstack_sp
    | ------------------------
    | trap_handler
    | ------------------------
    | exn_handler
    | ------------------------
    */
        blr     x9
L(caml_retaddr):
    /* Pop the trap frame, restoring caml_exception_pointer */
        ldr     TMP, [sp], 16
        CFI_ADJUST(-16)
        str     TMP, Caml_state(exn_handler)
    /* Pop the callback link, restoring the global variables */
L(return_result):
    /* restore GC regs */
        ldr     TMP2, [TMP, 8]
        str     TMP2, Caml_state(gc_regs)
        add     TMP, TMP, #16
        CFI_ADJUST(-16)
    /* Update alloc ptr */
        str     ALLOC_PTR, Caml_state(young_ptr)
    /* Return to C stack. */
        ldr     TMP2, Caml_state(current_stack)
        str     TMP, Stack_sp(TMP2)
        mov     TMP, sp
        ldr     TMP, Caml_state(c_stack)
    /* Pop the struct c_stack_link */
        ldr     TMP, Cstack_prev(sp)
        str     TMP, Caml_state(c_stack)
        add     sp, sp, #24
        CFI_ADJUST(-24)
    /* Reload callee-save registers and return address */
        ldp     x19, x20, [sp, 16]
        ldp     x21, x22, [sp, 32]
        ldp     x23, x24, [sp, 48]
        ldp     x25, x26, [sp, 64]
        ldp     x27, x28, [sp, 80]
        ldp     d8, d9, [sp, 96]
        ldp     d10, d11, [sp, 112]
        ldp     d12, d13, [sp, 128]
        ldp     d14, d15, [sp, 144]
        ldp     x29, x30, [sp], 160
        CFI_ADJUST(-160)
    /* Return to C caller */
        ret
        CFI_ENDPROC
        END_FUNCTION(caml_start_program)

/* The trap handler */

        .align  2
L(trap_handler):
        CFI_STARTPROC
    /* Save exception pointer */
        str     TRAP_PTR, Caml_state(exn_handler)
    /* Encode exception bucket as an exception result */
        orr     x0, x0, #2
    /* exn handler already popped here */
        mov     TMP, sp
    /* Return it */
        b       L(return_result)
        CFI_ENDPROC

/* Raise an exception from OCaml */
/* TODO: what about caml_reraise_exn? */
/* TODO: fix mismatch between TRAP_Ptr and exn_handler */
FUNCTION(caml_raise_exn)
        CFI_STARTPROC
L(caml_raise_exn):
    /* Test if backtrace is active */
        ldr     TMP, Caml_state(backtrace_active)
        cbnz    TMP, 2f
1:  /* Cut stack at current trap handler */
        mov     sp, TRAP_PTR
    /* Pop previous handler and jump to it */
        ldr     TMP, [sp, 8]
        ldr     TRAP_PTR, [sp], 16
        br      TMP
2:  /* Preserve exception bucket in callee-save register x19 */
        mov     C_NON_VOLATILE_1, C_ARG_1
    /* Stash the backtrace */
                                    /* arg1: exn bucket, already in x0 */
        mov     C_ARG_2, x30        /* arg2: pc of raise */
        mov     C_ARG_3, sp         /* arg3: sp of raise */
        mov     C_ARG_4, TRAP_PTR   /* arg4: sp of handler */
        bl      G(caml_stash_backtrace)
    /* Restore exception bucket and raise */
        mov     x0, C_NON_VOLATILE_1
        b       1b
        CFI_ENDPROC
        END_FUNCTION(caml_raise_exn)

/* Raise an exception from C */

FUNCTION(caml_raise_exception)
        CFI_STARTPROC
    /* Load the domain state ptr */
        mov     DOMAIN_STATE_PTR, C_ARG_1
    /* Load the exception bucket */
        mov     x0, C_ARG_2
    /* Reload trap ptr and alloc ptr */
        ldr     TRAP_PTR, Caml_state(exn_handler)
        ldr     ALLOC_PTR, Caml_state(young_ptr)
    /* Test if backtrace is active */
        ldr     TMP, Caml_state(backtrace_active)
        cbnz    TMP, 2f
1:  /* Cut stack at current trap handler */
        mov     sp, TRAP_PTR
    /* Pop previous handler and jump to it */
        ldr     TMP, [sp, 8]
        ldr     TRAP_PTR, [sp], 16
        br      TMP
2:  /* Preserve exception bucket in callee-save register x19 */
        mov     x19, x0
    /* Stash the backtrace */
                                                      /* arg1: exn bucket */
        ldr     x1, Caml_state(last_return_address)   /* arg2: pc of raise */
        ldr     x2, Caml_state(bottom_of_stack)       /* arg3: sp of raise */
        mov     x3, TRAP_PTR   /* arg4: sp of handler */
        bl      G(caml_stash_backtrace)
    /* Restore exception bucket and raise */
        mov     x0, x19
        b       1b
        CFI_ENDPROC
        END_FUNCTION(caml_raise_exception)

/* Raise a Stack_overflow exception on return from segv_handler()
   (in runtime/signals_nat.c).  On entry, the stack is full, so we
   cannot record a backtrace.
   No CFI information here since this function disrupts the stack
   backtrace anyway.
   Since we have returned from the signal handler, the DOMAIN_STATE_PTR,
   TRAP_PTR and ALLOC_PTR registers should have the same values
   they had in the faulting OCaml code, so don't try to reload them. */

FUNCTION(caml_stack_overflow)
    /* Load the exception bucket */
        ADDRGLOBAL(x0, caml_exn_Stack_overflow)
    /* Cut stack at current trap handler */
        mov     sp, TRAP_PTR
    /* Pop previous handler and jump to it */
        ldr     TMP, [sp, 8]
        ldr     TRAP_PTR, [sp], 16
        br      TMP
        END_FUNCTION(caml_stack_overflow)

/* Callback from C to OCaml */

FUNCTION(caml_callback_asm)
        CFI_STARTPROC
    /* Initial shuffling of arguments */
    /* (x0 = Caml_state, x1 = closure, [x2] = first arg) */
        mov     x8, x0
        ldr     x0, [x2]        /* x0 = first arg */
                                /* x1 = closure environment */
        ldr     x9, [x1]       /* code pointer */
        b       L(jump_to_caml)
        CFI_ENDPROC
        END_FUNCTION(caml_callback_asm)

FUNCTION(caml_callback2_asm)
        CFI_STARTPROC
    /* Initial shuffling of arguments */
    /* (x0 = Caml_state, x1 = closure, [x2] = arg1, [x2,8] = arg2) */
        mov     x8, x0
        mov     TMP2, x1
        ldp     x0, x1, [x2, 0] /* x0 = first arg, x1 = second arg */
        mov     x2, TMP2         /* x2 = closure environment */
        ADDRGLOBAL(x9, caml_apply2)
        b       L(jump_to_caml)
        CFI_ENDPROC
        END_FUNCTION(caml_callback2_asm)

FUNCTION(caml_callback3_asm)
        CFI_STARTPROC
    /* Initial shuffling of arguments */
    /* (x0 = Caml_state, x1 = closure, [x2] = arg1, [x2,8] = arg2,
        [x2,16] = arg3) */
        mov     x8, x0
        mov     x3, x1          /* x3 = closure environment */
        ldp     x0, x1, [x2, 0] /* x0 = first arg, x1 = second arg */
        ldr     x2, [x2, 16]    /* x2 = third arg */
        ADDRGLOBAL(x9, caml_apply3)
        b       L(jump_to_caml)
        CFI_ENDPROC
        END_FUNCTION(caml_callback3_asm)

FUNCTION(caml_ml_array_bound_error)
        CFI_STARTPROC
    /* Load address of [caml_array_bound_error] in ADDITIONAL_ARG */
        ADDRGLOBAL(ADDITIONAL_ARG, caml_array_bound_error)
    /* Call that function */
        b       G(caml_c_call)
        CFI_ENDPROC
        END_FUNCTION(caml_ml_array_bound_error)

         TEXT_SECTION(caml_system__code_end)
        .globl  G(caml_system__code_end)
G(caml_system__code_end):

/* GC roots for callback */

OBJECT(caml_system__frametable)
        .quad   1               /* one descriptor */
        .quad   L(caml_retaddr) /* return address into callback */
        .short  -1              /* negative frame size => use callback link */
        .short  0               /* no roots */
        .align  3
        END_OBJECT(caml_system__frametable)

#if !defined(SYS_macosx)
/* Mark stack as non-executable */
        .section .note.GNU-stack,"",%progbits
#endif
