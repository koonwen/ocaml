(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(* Generation of bytecode from lambda terms *)

open Lambda
open Instruct

val handle_comp_expr: (
  compilation_env -> lambda -> int ->
  before:instruction list ->
  after:instruction list ->
  instruction list
) ref

val compile_implementation: string -> lambda -> instruction list
val compile_phrase: lambda -> instruction list * instruction list
val reset: unit -> unit

val merge_events:
  Instruct.debug_event -> Instruct.debug_event -> Instruct.debug_event
