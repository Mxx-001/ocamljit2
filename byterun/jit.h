/***********************************************************************/
/*                                                                     */
/*                           Objective Caml                            */
/*                                                                     */
/*            Benedikt Meurer, University of Siegen                    */
/*                                                                     */
/*  Copyright 2010 Department of Compiler Construction and Software    */
/*  Analysis, University of Siegen.  All rights reserved.  This file   */
/*  is distributed under the terms of the GNU Library General Public   */
/*  License, with the special exception on linking described in file   */
/*  ../LICENSE.                                                        */
/*                                                                     */
/***********************************************************************/

/* $Id$ */

#ifndef CAML_JIT_H
#define CAML_JIT_H

#ifdef CAML_JIT

#include <stddef.h>
#include <stdlib.h>

/* Assertions */
#if defined(DEBUG)
# include <assert.h>
# define caml_jit_assert               assert
# define caml_jit_assert_not_reached() assert(0)
#else
# define caml_jit_assert(x)            ((void) 0)
# define caml_jit_assert_not_reached() ((void) 0)
#endif

/* GNU CC detection */
#if defined(__GNUC__) && defined(__GNUC_MINOR__)
# define CAML_JIT_GNUC_PREREQ(major, minor) ((__GNUC__ << 16) + __GNUC_MINOR__ >= ((major) << 16) + (minor))
#else
# define CAML_JIT_GNUC_PREREQ(major, minor) (0)
#endif

/* Internal functions/variables */
#if defined(DEBUG)
# define CAML_JIT_INTERNAL extern
#else
# define CAML_JIT_INTERNAL extern CAML_JIT_GNUC_HIDDEN
#endif

/* GNU CC symbol attributes */
#if CAML_JIT_GNUC_PREREQ(3,0)
# define CAML_JIT_GNUC_HIDDEN __attribute__((visibility("hidden")))
#else
# define CAML_JIT_GNUC_HIDDEN
#endif
#if CAML_JIT_GNUC_PREREQ(2,96)
# define CAML_JIT_GNUC_MALLOC __attribute__((__malloc__)) CAML_JIT_GNUC_WARN_UNUSED_RESULT
#else
# define CAML_JIT_GNUC_MALLOC
#endif
#if CAML_JIT_GNUC_PREREQ(2,8)
# define CAML_JIT_GNUC_NOINLINE __attribute__((noinline))
#else
# define CAML_JIT_GNUC_NOINLINE
#endif
#if CAML_JIT_GNUC_PREREQ(2,8)
# define CAML_JIT_GNUC_UNUSED __attribute__((unused))
#else
# define CAML_JIT_GNUC_UNUSED
#endif
#if CAML_JIT_GNUC_PREREQ(3,4)
# define CAML_JIT_GNUC_WARN_UNUSED_RESULT __attribute__((warn_unused_result))
#else
# define CAML_JIT_GNUC_WARN_UNUSED_RESULT
#endif

/* GNU CC features */
#if CAML_JIT_GNUC_PREREQ(3,0)
# define CAML_JIT_GNUC_LIKELY(x)   __builtin_expect(!!(x), 1)
# define CAML_JIT_GNUC_UNLIKELY(x) __builtin_expect(!!(x), 0)
#else
# define CAML_JIT_GNUC_LIKELY(x)   (x)
# define CAML_JIT_GNUC_UNLIKELY(x) (x)
#endif


/* maximum native code size */
#define CAML_JIT_CODE_SIZE (128 * 1024 * 1024)


//
// TODO
//

CAML_JIT_INTERNAL void caml_jit_init();

CAML_JIT_INTERNAL unsigned char *caml_jit_code_base;
CAML_JIT_INTERNAL unsigned char *caml_jit_code_end;
CAML_JIT_INTERNAL unsigned char *caml_jit_code_ptr;
CAML_JIT_INTERNAL opcode_t       caml_jit_callback_return;
CAML_JIT_INTERNAL unsigned       caml_jit_enabled;

/* Caml byte-code segments */
typedef struct caml_jit_segment_t caml_jit_segment_t;
struct caml_jit_segment_t
{
  code_t              segment_prog;
  code_t              segment_pend;
  caml_jit_segment_t *segment_next;
};

#else

#define caml_jit_enabled (0)

#endif /* CAML_JIT */

#endif /* !CAML_JIT_H */
