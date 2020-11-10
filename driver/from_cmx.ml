open Printf
open Cmx_format

let get_cmx_infos filename =
  printf "File %s\n" filename;
  let ic = open_in_bin filename in
  let len_magic_number = String.length Config.cmo_magic_number in
  let _ = really_input_string ic len_magic_number in
  let ui = (input_value ic : unit_infos) in
  close_in ic;
  ui

let get_cmm filename =
  let ui = get_cmx_infos filename in
  let export_info =
    match ui.ui_export_info with
    | Clambda _ -> assert false
    | Flambda export -> export
  in
  export_info.Export_info.cmm |> Option.get

let main () = 
  let filename = Sys.argv.(1) in
  let cmm = get_cmm filename in
  Compilenv.reset "Tuturu";
  Asmgen.compile_cmm
    ~toplevel:(fun _ -> false)
    ~prefixname:"generated"
    ~ppf_dump:Format.std_formatter
    cmm
let () = main ()
