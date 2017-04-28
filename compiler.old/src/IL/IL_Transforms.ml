(* * License
 * -----------------------------------------------------------------------
 * Copyright 2016--2017 IMDEA Software Institute
 * Copyright 2016--2017 Inria
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 * ----------------------------------------------------------------------- *)

(* * Apply transformations to IL *)

(* ** Imports *)
open Core_kernel.Std
open Util
open IL_Lang
open IL_Pprint
open IL_Compile
open IL_Expand
open IL_Utils
open Arith

module Cert = CIL_Conv

(* ** Apply transformations in sequence.
 * ------------------------------------------------------------------------ *)

type asm_lang = X64

type pprint_opt = {
  pp_fname : Fname.t option;
  pp_info  : bool;
  pp_num   : bool;
  pp_types : bool;
}

let mk_pprint_opt ofn = {
  pp_fname = ofn;
  pp_info  = false;
  pp_num   = false;
  pp_types = false;
}

type cert = NonCert | Cert

type transform =
  | MergeBlocks of Fname.t option
  | MacroExpand of Fname.t * value Pname.Table.t
  | ParamsExpand 
  | ArrayAssignExpand of Fname.t
  | ArrayExpand of Fname.t
  | LocalSSA of Fname.t
  | RegisterAlloc of Fname.t * int
  | InlineCalls of cert * Fname.t
  | UnrollCert of Fname.t
  | ConstPropCert of Fname.t
  | DeadCodeCert of Fname.t
  | UnrollLoopCert of Fname.t
  | RegisterLiveness of Fname.t
  | RemoveEqConstrs of Fname.t
  | RenumberIdents of renumber_opt
  | PrintCoq of string
  | Asm of asm_lang
  (* debugging *)
  | Type
  | CargoTest
  | Print of string * pprint_opt
  | Save  of string * pprint_opt
  | TestConversion of Fname.t
  | StripComments of Fname.t

let ptrafo =
  let open MP in
  let ident =
    many1 (MParser.none_of "]=,") >>= fun l -> return (String.of_char_list l)
  in
  let asm_lang = choice [ string "x86-64" >>$ X64 ] in
  let enclosed p pstart pend = pstart >> p >>= fun x -> pend >>$ x in
  let bracketed p = enclosed p (char '[') (char ']') in
  let u64 = many1 digit >>= fun s -> return (Arith.parse_big_int (String.of_char_list s)) in
  let int = many1 digit >>= fun s -> return (int_of_string (String.of_char_list s)) in
  let _value () =
    choice
      [ (u64 >>= fun u -> return (Value.mk_Vu 64 u))
      ; (char '[' >>= fun _ ->
        (sep_by u64 (char ',')) >>= fun vs ->
        char ']' >>= fun _ ->
        let vs = U64.Map.of_alist_exn (List.mapi vs ~f:(fun i v -> (U64.of_int i, v))) in
        return (Value.mk_Varr 64 vs)) ]
  in
  let pmapping =
    ident >>= fun s -> char '=' >> u64 >>= fun u -> return (Pname.mk s,Value.mk_Vu 64 u)
  in
  let register_num = bracketed int in
  let mappings p mc =
    bracketed (sep_by p (char ',') >>= fun l -> return (mc l))
  in
  let fname = bracketed (ident >>= fun s -> return @@ Fname.mk s) in
  let pmap = mappings pmapping (fun l -> Pname.Table.of_alist_exn l) in
  let pprint_opt =
    choice
      [ (string "info" >>$ `Info)
      ; (string "num" >>$ `Num)
      ; (string "types" >>$ `Types)
      ; (string "fun=" >> ident >>= fun s -> return (`Fun (Fname.mk s)))
      ]
  in
  let pprint_opts =
    bracketed (sep_by pprint_opt (char ',')) >>= fun upds -> return @@
    List.fold ~init:(mk_pprint_opt None)
      ~f:(fun ppo opt ->
            match opt with
            | `Info   -> { ppo with pp_info  = true }
            | `Num    -> { ppo with pp_num   = true }
            | `Types  -> { ppo with pp_types = true }
            | `Fun fn -> { ppo with pp_fname = Some(fn) })
      upds
  in
  let get_pp_opts = get_opt (mk_pprint_opt None) in
  choice
    [ (string "typecheck" >>$ Type)
    ; (string "cargo_test" >>$ CargoTest)
    ; (string "renumber_fun_unique" >>$ RenumberIdents(UniqueNumFun))
    ; (string "renumber_module_unique" >>$ RenumberIdents(UniqueNumModule))
    ; (string "renumber_reuse"  >>$ RenumberIdents(ReuseNum))
    ; (string "merge_blocks" >> option fname >>= fun ofn ->
       return (MergeBlocks ofn))
    ; (string "array_assign_expand" >> fname >>= fun fn ->
       return (ArrayAssignExpand fn))
    ; (string "array_expand" >> fname >>= fun fn ->
       return (ArrayExpand fn))
    ; (string "local_ssa" >> fname >>= fun fn ->
       return (LocalSSA fn))
    ; (string "strip_comments" >> fname >>= fun fn ->
       return (StripComments(fn)))
    ; (string "print" >> (bracketed ident) >>= fun name ->
       (option pprint_opts) >>= fun pp_opts -> return (Print(name,get_pp_opts pp_opts)))
    ; (string "save"  >> (bracketed ident) >>= fun name ->
       (option pprint_opts) >>= fun pp_opts -> return (Save(name,get_pp_opts pp_opts)))
    ; (string "register_liveness" >> fname >>= fun fn ->
       return (RegisterLiveness fn))
    ; (string "remove_eq_constrs" >> fname >>= fun fn ->
       return (RemoveEqConstrs(fn)))
    ; (string "test_conv" >> fname >>= fun fn ->
       return (TestConversion fn))
    ; (string "register_allocate" >> fname >>= fun fn ->
       register_num >>= fun l ->
       return (RegisterAlloc(fn,l)))
    ; string "asm" >> char '[' >> asm_lang >>= (fun l -> char ']' >>$ (Asm(l)))
    ; (string "coq" >> (bracketed ident) >>= fun filename -> return (PrintCoq filename))

    ; (string "expand" >> fname >>= fun fname ->
       pmap >>= fun pm -> return (MacroExpand(fname,pm)))
    ; (string "params_expand" >>$ ParamsExpand)
    ; (string "cert_inline" >> fname >>= fun fname -> return (InlineCalls(Cert,fname)))
    ; (string "cert_unroll_loop" >> fname >>= fun fname -> return (UnrollLoopCert(fname)))
    ; (string "cert_unroll" >> fname >>= fun fname -> return (UnrollCert(fname)))
    ; (string "cert_const_prop" >> fname >>= fun fname -> return (ConstPropCert(fname)))
    ; (string "cert_dead_code" >> fname >>= fun fname -> return (DeadCodeCert(fname)))
    ; (string "inline" >> fname >>= fun fname -> return (InlineCalls(NonCert,fname))) ]

let parse_trafo s =
  let open MP in
  match parse_string (sep_by ptrafo (char ',') >>= fun x -> eof >>$ x) s () with
  | Success t ->
    begin match List.rev t with
    | Asm(l)::rest ->
      if List.exists ~f:(function Asm(_) -> true | _ -> false) rest then (
        eprintf "asm[_] transformation must be last transformation";
        exit 1
      );
      (List.rev rest,Some l)
    | _ -> (t,None)
    end
  | Failed(s,_) ->
    eprintf "parsing transformation string failed: %s.\n%!" s;
    exit 1

type modules =
  | Um of unit modul
  | Lm of LV.t modul

type map_mod = {
  f : 'a. 'a modul -> 'a modul
}

let map_module (m : modules) (mf : map_mod) =
  match m with
  | Lm m -> Lm(mf.f m)
  | Um m -> Um(mf.f m)

let apply_transform trafos (modul0 : unit modul) =
  let total = ref 0. in
  let filter_fn m ofname =
    match ofname with
    | Some fn -> { m with mod_funcs=List.filter ~f:(fun nf -> nf.nf_name = fn) m.mod_funcs }
    | None    -> m
  in
  let all_fn = Fname.mk "all" in
  let notify s fn ~f =
    let start = Unix.gettimeofday () in
    F.printf "%s in %s function(s)\n%!" s
      (if Fname.equal fn all_fn then "all" else "``"^Fname.to_string fn^"''");
    let res = f () in
    let stop = Unix.gettimeofday () in
    let d = (stop -. start) *. 1000. in
    F.printf "   %fms\n%!" d;
    total := d +. !total;
    res
  in
  let pp_stats fmt li =
      if IS.is_empty li.LV.var_ue && IS.is_empty li.LV.var_kill && IS.is_empty li.LV.live_out then (
        pp_string fmt ""
      ) else (
        let lout_killed = Set.inter li.LV.live_out li.LV.var_kill in
        let lout_nkilled = Set.diff li.LV.live_out li.LV.var_kill in
        F.fprintf fmt
          ("%a@\n//   var_ue[%i]=%a@\n//   var_kill[%i]=%a"
           ^^"@\n//   live-out[%i/%i]=%a killed/%a not killed")
          (fun fmt () -> match li.LV.phi with
          | None -> pp_string fmt ""
          | Some phi ->
            F.fprintf fmt "@\n//   phi: %a" LV.pp_phi phi) ()
          (IS.length li.LV.var_ue)
          pp_set_vn li.LV.var_ue
          (IS.length li.LV.var_kill)
          pp_set_vn li.LV.var_kill
          (IS.length lout_killed)
          (IS.length lout_nkilled)
          pp_set_vn lout_killed
          pp_set_vn lout_nkilled
      )
  in
  let pp_info_lv tg =
    match tg with
    | BlockStart -> fun fmt info ->
      let li = (Option.value ~default:(LV.mk ()) info).LV.enter in
      F.fprintf fmt "// STARTBLOCK:%a" pp_stats li
    | BlockEnd -> fun fmt info ->
      let li = (Option.value ~default:(LV.mk ()) info).LV.leave in
      F.fprintf fmt "// ENDBLOCK:%a" pp_stats li
  in
  let pp_info_u = function
    | BlockStart -> fun fmt _info -> pp_string fmt "// STARTBLOCK"
    | BlockEnd   -> fun fmt _info -> pp_string fmt "// ENDBLOCK"
  in

  let app_trafo modul trafo =
    let inline fn m =
      notify "inlining all calls" fn
        ~f:(fun () -> inline_calls_modul m fn)
    in
    let inline_cert fn m =
      notify "inlining all calls (certified)" fn
        ~f:(fun () -> Cert.inline_calls_modul fn m)
    in
    let unroll_cert fn m =
      notify "unroll loops once (certified)" fn
        ~f:(fun () -> Cert.unroll_modul fn m)
    in
    let const_prop_cert fn m =
      notify "propagating constants (certified)" fn
        ~f:(fun () -> Cert.const_prop_modul fn m)
    in
    let dead_code_cert fn m =
      notify "removing dead code (certified)" fn
        ~f:(fun () -> Cert.dead_code_modul fn m)
    in
    let unroll_loop_cert fn m =
      notify "unroll loops until finding a fixpoint (certified)" fn
        ~f:(fun () -> Cert.unroll_loop_modul fn m)
    in
    let arr_exp fn m =
      notify "expanding register arrays" fn
        ~f:(fun () -> array_expand_modul m fn)
    in
    let save fn ppo m =
      let m = map_module m { f = fun m -> filter_fn m ppo.pp_fname } in
      let go m pp = Out_channel.write_all fn ~data:(fsprintf "%a" pp m) in
      let ppm ppi =
        IL_Pprint.pp_modul ?pp_info:ppi ~pp_types:ppo.pp_types
      in
      match m, ppo.pp_info with
      | Um m, true  -> go m (ppm (Some(pp_info_u)))
      | Um m, false -> go m (ppm None)
      | Lm m, true  -> go m (ppm (Some(pp_info_lv)))
      | Lm m, false -> go m (ppm None)
    in
    let print n ppo m =
      let m = map_module m { f = fun m -> filter_fn m ppo.pp_fname } in
      let ppm ppi =
        IL_Pprint.pp_modul ?pp_info:ppi ~pp_types:ppo.pp_types
      in
      let go m ppi =
        F.printf ">> %s:@\n%a@\n@\n" n (ppm ppi) m
      in
      match m, ppo.pp_info with
      | Um m, true  -> go m (Some(pp_info_u))
      | Um m, false -> go m None
      | Lm m, true  -> go m (Some(pp_info_lv))
      | Lm m, false -> go m None
    in
    let print_coq fn m =
      notify ("printing to “" ^ fn ^ "” in Coq concrete syntax") all_fn
        ~f:(fun () -> Cert.print_coq_modul fn m)
    in
    let test_conversion fn m0 =
      let open CIL_Conv in
      let m0 = match m0 with Um m0 -> m0 | Lm _ -> assert false in
      notify "testing conversion" fn
        ~f:(fun () ->
         let cvi = CVI.mk () in
         let conv func =
           { func with
             f_body = stmt_of_cmd cvi (cmd_of_stmt cvi false func.f_body); }
         in
         let m1 = map_func m0 fn ~f:conv in
         if not (equal_modul m0 m1) then (
           F.printf "test_conversion: roundtrip for function %s failed@\n"
             (Fname.to_string fn)
         );
         Um m1)
    in
    let array_expand_modul fn m =
      notify "expanding array assignments" fn
        ~f:(fun () -> array_assign_expand_modul m fn)
    in
    let remove_eq_constrs fn _m =
      notify "removing equality constraints" fn
        ~f:(fun () -> undefined () (*remove_eq_constrs_modul m fn *))
    in
    let strip_comments fn m =
      notify "stripping comments" fn
        ~f:(fun () -> strip_comments_modul m fn)
    in
    let typecheck m =
      notify "type checking module" all_fn
        ~f:(fun () -> IL_Typing.typecheck_modul m; m)
    in
    let p_expand m = 
      notify "expanding params" all_fn ~f:(fun () -> IL_Map.psubst_modul m)
    in

    let register_alloc fn _n _m =
      notify "performing register allocation" fn
        ~f:(fun () -> undefined () (*reg_alloc_modul (min 15 n) m fn*))
    in
    let register_liveness fn m =
      notify "adding register liveness information" fn
        ~f:(fun () ->
              match m with
              | Um m -> Lm (add_liveness_modul (reset_info_modul m) fn)
              | Lm m -> Lm (add_liveness_modul (reset_info_modul m) fn))
    in
    let local_ssa fn m =
      notify "transforming into local SSA form" fn
        ~f:(fun () ->
              match m with
              | Um _ -> assert false
              | Lm m -> Lm (local_ssa_modul m fn))
    in
    let macro_expand fn map m =
      notify "expanding macros" fn
        ~f:(fun () -> macro_expand_modul map m fn)
    in
      
    let merge_blocks ofn m =
      match ofn with
      | None     ->
        notify "merging basic blocks" all_fn ~f:(fun () -> merge_blocks_modul_all m)
      | Some(fn) ->
        notify "merging basic blocks" fn ~f:(fun () -> merge_blocks_modul m fn)
    in
    let renumber_idents rno m =
      notify "renumbering identifiers" all_fn
        ~f:(fun () -> renumber_vars_modul_all rno m)
    in
    match trafo with
    | InlineCalls(NonCert,fn)   -> map_module modul {f = fun m -> inline fn m}
    | InlineCalls(Cert,fn)      -> map_module modul {f = fun m -> inline_cert fn m}
    | UnrollCert(fn)            -> map_module modul {f = fun m -> unroll_cert fn m}
    | ConstPropCert(fn)         -> map_module modul {f = fun m -> const_prop_cert fn m}
    | DeadCodeCert(fn)          -> map_module modul {f = fun m -> dead_code_cert fn m}
    | UnrollLoopCert(fn)        -> map_module modul {f = fun m -> unroll_loop_cert fn m}
    | ArrayExpand(fn)           -> map_module modul {f = fun m -> arr_exp fn m}
    | ArrayAssignExpand(fn)     -> map_module modul {f = fun m -> array_expand_modul fn m}
    | StripComments(fn)         -> map_module modul {f = fun m -> strip_comments fn m}
    | RemoveEqConstrs(fn)       -> map_module modul {f = fun m -> remove_eq_constrs fn m}
    | RegisterAlloc(fn,n)       -> map_module modul {f = fun m -> register_alloc fn n m}
    | MacroExpand(fn,map)       -> map_module modul {f = fun m -> macro_expand fn map m}    
    | Type                      -> map_module modul {f = fun m -> typecheck m}
    | ParamsExpand              -> map_module modul {f = fun m -> p_expand m}
    | RenumberIdents(rno)       -> map_module modul {f = fun m -> renumber_idents rno m}
    | MergeBlocks(ofn)          -> map_module modul {f = fun m -> merge_blocks ofn m}
    | RegisterLiveness(fn)      -> register_liveness fn modul
    | TestConversion(fn)        -> test_conversion fn modul
    | LocalSSA(fn)              -> local_ssa fn modul
    | Print(n,ppo)              -> print n ppo modul; modul
    | Save(fn,ppo)              -> save fn ppo modul; modul
    | CargoTest                 ->
      save "tests/build/test_jasmin.rs" (mk_pprint_opt None) modul;
      ignore (Sys.command "cd tests/build/ && cargo test"); (* FIXME: don't use system, don't hardcode path *)
      modul
    | Asm(_)                    -> assert false
    | PrintCoq(fn) -> map_module modul { f = fun m -> print_coq fn m }
  in
  let start = Unix.gettimeofday () in
  let res = List.fold_left trafos ~init:(Um modul0) ~f:app_trafo in
  let stop = Unix.gettimeofday () in
  let d = (stop -. start) *. 1000. in
  F.printf "\ntotal transformation time: %fms\n%!" !total;
  F.printf "\ntotal time (with save/print): %fms\n%!" d;
  res


let apply_transform_asm strafo modul =
  let (trafo,mlang) = parse_trafo strafo in
  let modul = apply_transform trafo modul in
  match mlang with
  | None     -> `IL (match modul with Um m -> m | Lm m -> reset_info_modul m)
  | Some X64 -> assert false (* `Asm_X64 (List.map ~f:to_asm_x64 modul) *)