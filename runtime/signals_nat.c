/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*             Xavier Leroy, projet Gallium, INRIA Rocquencourt           */
/*                                                                        */
/*   Copyright 2007 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#define CAML_INTERNALS

/* Signal handling, code specific to the native-code compiler */

#if defined(TARGET_amd64) && defined (SYS_linux)
#define _GNU_SOURCE
#endif
#if defined(TARGET_i386) && defined (SYS_linux_elf)
#define _GNU_SOURCE
#endif
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include "caml/codefrag.h"
#include "caml/fail.h"
#include "caml/memory.h"
#include "caml/osdeps.h"
#include "caml/signals.h"
#include "caml/signals_machdep.h"
#include "signals_osdep.h"
#include "caml/stack.h"
#include "caml/memprof.h"
#include "caml/finalise.h"

#ifndef NSIG
#define NSIG 64
#endif

typedef void (*signal_handler)(int signo);

#ifdef _WIN32
extern signal_handler caml_win32_signal(int sig, signal_handler action);
#define signal(sig,act) caml_win32_signal(sig,act)
extern void caml_win32_overflow_detection();
#endif

/* This routine is the common entry point for garbage collection
   and signal handling.  It can trigger a callback to OCaml code.
   With system threads, this callback can cause a context switch.
   Hence [caml_garbage_collection] must not be called from regular C code
   (e.g. the [caml_alloc] function) because the context of the call
   (e.g. [intern_val]) may not allow context switching.
   Only generated assembly code can call [caml_garbage_collection],
   via the caml_call_gc assembly stubs.  */

void caml_garbage_collection(void)
{
  frame_descr* d;
  intnat allocsz = 0, i, nallocs;
  unsigned char* alloc_len;

  { /* Find the frame descriptor for the current allocation */
    uintnat h = Hash_retaddr(Caml_state->last_return_address);
    while (1) {
      d = caml_frame_descriptors[h];
      if (d->retaddr == Caml_state->last_return_address) break;
      h = (h + 1) & caml_frame_descriptors_mask;
    }
    /* Must be an allocation frame */
    CAMLassert(d && d->frame_size != 0xFFFF && (d->frame_size & 2));
  }

  /* Compute the total allocation size at this point,
     including allocations combined by Comballoc */
  alloc_len = (unsigned char*)(&d->live_ofs[d->num_live]);
  nallocs = *alloc_len++;
  for (i = 0; i < nallocs; i++) {
    allocsz += Whsize_wosize(Wosize_encoded_alloc_len(alloc_len[i]));
  }
  /* We have computed whsize (including header), but need wosize (without) */
  allocsz -= 1;

  caml_alloc_small_dispatch(allocsz, CAML_DO_TRACK | CAML_FROM_CAML,
                            nallocs, alloc_len);
}

DECLARE_SIGNAL_HANDLER(handle_signal)
{
  int saved_errno;
  /* Save the value of errno (PR#5982). */
  saved_errno = errno;
#if !defined(POSIX_SIGNALS) && !defined(BSD_SIGNALS)
  signal(sig, handle_signal);
#endif
  if (sig < 0 || sig >= NSIG) return;
  caml_record_signal(sig);
  /* Some ports cache [Caml_state->young_limit] in a register.
     Use the signal context to modify that register too, but only if
     we are inside OCaml code (not inside C code). */
#if defined(CONTEXT_PC) && defined(CONTEXT_YOUNG_LIMIT)
  if (caml_find_code_fragment_by_pc((char *) CONTEXT_PC) != NULL)
    CONTEXT_YOUNG_LIMIT = (context_reg) Caml_state->young_limit;
#endif
  errno = saved_errno;
}

int caml_set_signal_action(int signo, int action)
{
  signal_handler oldact;
#ifdef POSIX_SIGNALS
  struct sigaction sigact, oldsigact;
#else
  signal_handler act;
#endif

#ifdef POSIX_SIGNALS
  switch(action) {
  case 0:
    sigact.sa_handler = SIG_DFL;
    sigact.sa_flags = 0;
    break;
  case 1:
    sigact.sa_handler = SIG_IGN;
    sigact.sa_flags = 0;
    break;
  default:
    SET_SIGACT(sigact, handle_signal);
    break;
  }
  sigemptyset(&sigact.sa_mask);
  if (sigaction(signo, &sigact, &oldsigact) == -1) return -1;
  oldact = oldsigact.sa_handler;
#else
  switch(action) {
  case 0:  act = SIG_DFL; break;
  case 1:  act = SIG_IGN; break;
  default: act = handle_signal; break;
  }
  oldact = signal(signo, act);
  if (oldact == SIG_ERR) return -1;
#endif
  if (oldact == (signal_handler) handle_signal)
    return 2;
  else if (oldact == SIG_IGN)
    return 1;
  else
    return 0;
}

/* Machine- and OS-dependent handling of bound check trap */

#if defined(TARGET_power) \
  || defined(TARGET_s390x)
DECLARE_SIGNAL_HANDLER(trap_handler)
{
#if defined(SYS_rhapsody)
  /* Unblock SIGTRAP */
  { sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGTRAP);
    caml_sigmask_hook(SIG_UNBLOCK, &mask, NULL);
  }
#endif
  Caml_state->exception_pointer = (char *) CONTEXT_EXCEPTION_POINTER;
  Caml_state->young_ptr = (value *) CONTEXT_YOUNG_PTR;
  Caml_state->bottom_of_stack = (char *) CONTEXT_SP;
  Caml_state->last_return_address = (uintnat) CONTEXT_PC;
  caml_array_bound_error();
}
#endif

/* Machine- and OS-dependent handling of stack overflow */

#ifdef HAS_STACK_OVERFLOW_DETECTION
#ifndef CONTEXT_SP
#error "CONTEXT_SP is required if HAS_STACK_OVERFLOW_DETECTION is defined"
#endif

static char sig_alt_stack[SIGSTKSZ];

/* Code compiled with ocamlopt never accesses more than
   EXTRA_STACK bytes below the stack pointer. */
#define EXTRA_STACK 256

#ifdef RETURN_AFTER_STACK_OVERFLOW
extern void caml_stack_overflow(caml_domain_state*);
#endif

static void disable_segv_handler() {
  struct sigaction act;
  act.sa_handler = SIG_DFL;
  act.sa_flags = 0;
  sigemptyset(&act.sa_mask);
  sigaction(SIGSEGV, &act, NULL);
}
static void handle_stack_overflow(ucontext_t * context) {
#ifdef RETURN_AFTER_STACK_OVERFLOW
#ifndef CONTEXT_PC
#error "CONTEXT_PC must be defined if RETURN_AFTER_STACK_OVERFLOW is"
#endif
  /* Tweak the PC part of the context so that on return from this
      handler, we jump to the asm function [caml_stack_overflow]
      (from $ARCH.S). */
  CONTEXT_C_ARG_1 = (context_reg) Caml_state;
  CONTEXT_PC = (context_reg) &caml_stack_overflow;
#else
  /* Raise a Stack_overflow exception straight from this signal handler */
#if defined(CONTEXT_YOUNG_PTR) && defined(CONTEXT_EXCEPTION_POINTER)
  Caml_state->exception_pointer == (char *) CONTEXT_EXCEPTION_POINTER;
  Caml_state->young_ptr = (value *) CONTEXT_YOUNG_PTR;
#endif
  caml_raise_stack_overflow();
#endif
}

#ifdef NAKED_POINTERS_CHECKER
#ifndef CONTEXT_PC
/* TODO: this error message was wrong */
#error "CONTEXT_PC must be defined if NAKED_POINTERS_CHECKER is"
#endif
static void handle_naked_pointers_checker(ucontext_t * context) {
  CONTEXT_PC = (context_reg)Caml_state->checking_pointer_pc;
}
#endif /* NAKED_POINTERS_CHECKER */

#define MINOR_OVERFLOW
#define CONTEXT_YOUNG_PTR (context->uc_mcontext.gregs[REG_R15])

#ifdef MINOR_OVERFLOW
#ifndef CONTEXT_PC
#error "CONTEXT_PC must be defined if MINOR_OVERFLOW is"
#endif
static void handle_minor_overflow(ucontext_t * context) {
  short* test_pc;
  value gc_regs[13];
  short allocsz;

  test_pc = (short*)CONTEXT_PC;
  CONTEXT_PC = CONTEXT_PC + 3;
  /*
    subq $0, %r15; 49 83 ef 00
    subq $127, %r15; 49 83 ef 7f
    subq $128, %r15; 49 81 ef 80 00 00 00
    subq $256, %r15; 49 81 ef 00 01 00 00
  */
  allocsz = test_pc[-1];
  if (allocsz == 0) {
    allocsz = test_pc[-2];
  } else {
    allocsz = allocsz >> 8;
  }
  // TODO: is this -1 correct?
  allocsz = (allocsz >> 3) - 1;

  // printf("%d\n", allocsz);
  // printf("minor overflow\n");

  // TODO: this
  Caml_state->young_ptr = (value*)CONTEXT_YOUNG_PTR;
  Caml_state->last_return_address = CONTEXT_PC;
  Caml_state->bottom_of_stack = (char*)CONTEXT_SP;
  Caml_state->gc_regs = gc_regs;

  #define STORE_CONTEXT(NAME, n) \
    (gc_regs[n] = ((value)(context->uc_mcontext.gregs[REG_##NAME])))
  STORE_CONTEXT(RBP, 12);
  STORE_CONTEXT(R11, 11);
  STORE_CONTEXT(R10, 10);
  STORE_CONTEXT(R13, 9);
  STORE_CONTEXT(R12, 8);
  STORE_CONTEXT(R9, 7);
  STORE_CONTEXT(R8, 6);
  STORE_CONTEXT(RCX, 5);
  STORE_CONTEXT(RDX, 4);
  STORE_CONTEXT(RSI, 3);
  STORE_CONTEXT(RDI, 2);
  STORE_CONTEXT(RBX, 1);
  STORE_CONTEXT(RAX, 0);
  #undef CONTEXT
  

  // printf("%p\n", Caml_state->last_return_address);

  caml_alloc_small_dispatch(allocsz, CAML_DO_TRACK | CAML_FROM_CAML, 0, NULL);
  #define LOAD_REG(NAME, n) \
    context->uc_mcontext.gregs[REG_##NAME] = (intnat)gc_regs[n]
  LOAD_REG(RBP, 12);
  LOAD_REG(R11, 11);
  LOAD_REG(R10, 10);
  LOAD_REG(R13, 9);
  LOAD_REG(R12, 8);
  LOAD_REG(R9, 7);
  LOAD_REG(R8, 6);
  LOAD_REG(RCX, 5);
  LOAD_REG(RDX, 4);
  LOAD_REG(RSI, 3);
  LOAD_REG(RDI, 2);
  LOAD_REG(RBX, 1);
  LOAD_REG(RAX, 0);
  #undef LOAD_REG
  // printf(
  //   "base: %p start:%p end: %p\n",
  //   Caml_state->young_base,
  //   Caml_state->young_alloc_start,
  //   Caml_state->young_alloc_end);
  // printf("%p\n", (void*)CONTEXT_YOUNG_PTR);
  CONTEXT_YOUNG_PTR = (uintnat)Caml_state->young_ptr;
  // printf("%p\n", (void*)CONTEXT_YOUNG_PTR);
  #undef PRINT
}
#endif

/* Address sanitizer is confused when running the stack overflow
   handler in an alternate stack. We deactivate it for all the
   functions used by the stack overflow handler. */
CAMLno_asan
DECLARE_SIGNAL_HANDLER(segv_handler)
{
  char * fault_addr;
  intnat is_stack_overflow;
  #ifdef MINOR_OVERFLOW
  intnat is_minor_overflow;
  #endif

  fault_addr = CONTEXT_FAULTING_ADDRESS;
  // printf("segfault %p\n", fault_addr);

  // faulting address is on the stack, or within EXTRA_STACK of it
  is_stack_overflow =
    fault_addr < Caml_state->top_of_stack &&
    (uintnat)fault_addr >= CONTEXT_SP - EXTRA_STACK;

  #ifdef MINOR_OVERFLOW
  // faulting address is on the disabled zone of the heap
  is_minor_overflow =
    (void*)fault_addr > Caml_state->young_base &&
    (value*)fault_addr < Caml_state->young_start;
  #endif

  /* Sanity checks:
     - faulting address is word-aligned
     - is a stack overflow or is a minor overflow
     - we are in OCaml code */
  if (((uintnat) fault_addr & (sizeof(intnat) - 1)) == 0
#ifdef MINOR_OVERFLOW
      && (is_stack_overflow || is_minor_overflow)
#else
      && is_stack_overflow
#endif
#ifdef CONTEXT_PC
      && caml_find_code_fragment_by_pc((char *) CONTEXT_PC) != NULL
#endif
      ) {
    if (is_stack_overflow) {
      handle_stack_overflow(context);
    } else {
      handle_minor_overflow(context);
    };
#ifdef NAKED_POINTERS_CHECKER
  } else if (Caml_state->checking_pointer_pc) {
      handle_naked_pointers_checker(context);
#endif /* NAKED_POINTERS_CHECKER */
  } else {
    /* Otherwise, deactivate our exception handler and return,
       causing fatal signal to be generated at point of error. */
    disable_segv_handler();
  }
}

#endif

/* Initialization of signal stuff */

void caml_init_signals(void)
{
  /* Bound-check trap handling */

#if defined(TARGET_power)
  { struct sigaction act;
    sigemptyset(&act.sa_mask);
    SET_SIGACT(act, trap_handler);
#if !defined(SYS_rhapsody)
    act.sa_flags |= SA_NODEFER;
#endif
    sigaction(SIGTRAP, &act, NULL);
  }
#endif

#if defined(TARGET_s390x)
  { struct sigaction act;
    sigemptyset(&act.sa_mask);
    SET_SIGACT(act, trap_handler);
    sigaction(SIGFPE, &act, NULL);
  }
#endif

#ifdef HAS_STACK_OVERFLOW_DETECTION
  {
    stack_t stk;
    struct sigaction act;
    stk.ss_sp = sig_alt_stack;
    stk.ss_size = SIGSTKSZ;
    stk.ss_flags = 0;
    SET_SIGACT(act, segv_handler);
    act.sa_flags |= SA_ONSTACK | SA_NODEFER;
    sigemptyset(&act.sa_mask);
    if (sigaltstack(&stk, NULL) == 0) { sigaction(SIGSEGV, &act, NULL); }
  }
#endif
}

CAMLexport void caml_setup_stack_overflow_detection(void)
{
#ifdef HAS_STACK_OVERFLOW_DETECTION
  stack_t stk;
  stk.ss_sp = malloc(SIGSTKSZ);
  stk.ss_size = SIGSTKSZ;
  stk.ss_flags = 0;
  if (stk.ss_sp)
    sigaltstack(&stk, NULL);
#endif
}
