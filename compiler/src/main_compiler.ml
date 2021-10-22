open Utils
open Prog
open Glob_options

(* -------------------------------------------------------------------- *)
exception UsageError

let parse () =
  let error () = raise UsageError in
  let set_in s =
    if !infile <> "" then error();
    infile := s  in
  Arg.parse options set_in usage_msg;
  let c =
    match !color with
    | Auto -> Unix.isatty (Unix.descr_of_out_channel stderr)
    | Always -> true
    | Never -> false
  in
  if c then enable_colors ();
  if !infile = "" && (not !help_intrinsics) && (!safety_makeconfigdoc = None)
  then error()

(*--------------------------------------------------------------------- *)

let saved_extra_free_registers : (L.i_loc -> var option) ref = ref (fun _ -> None)

(* -------------------------------------------------------------------- *)
let rec warn_extra_i i = 
  match i.i_desc with
  | Cassgn (_, tag, _, _) | Copn (_, tag, _, _) ->
    begin match tag with
    | AT_rename ->
      warning ExtraAssignment i.i_loc
        "@[<v>extra assignment introduced:@;<0 2>%a@]"
        (Printer.pp_instr ~debug:false) i
    | AT_inline ->
      hierror ~loc:(Lmore i.i_loc) ~kind:"compilation error" ~internal:true
        "@[<v>AT_inline flag remains in instruction:@;<0 2>@[%a@]@]"
        (Printer.pp_instr ~debug:false) i
    | _ -> ()
    end
  | Cif(_, c1, c2) | Cwhile(_,c1,_,c2) ->
    List.iter warn_extra_i c1;
    List.iter warn_extra_i c2;
  | Cfor _ ->
    hierror ~loc:(Lmore i.i_loc) ~kind:"compilation error" ~internal:true
      "for loop remains"
  | Ccall _ -> ()

let warn_extra_fd (_, fd) =
  List.iter warn_extra_i fd.f_body
 
let check_safety_p s p source_p =
  let () = if SafetyConfig.sc_print_program () then
      let s1,s2 = Glob_options.print_strings s in
      Format.eprintf "@[<v>At compilation pass: %s@;%s@;@;\
                      %a@;@]@."
        s1 s2
        (Printer.pp_prog ~debug:true) p
  in

  let () = SafetyConfig.pp_current_config_diff () in
  
  let () =
    List.iter (fun f_decl ->
        if f_decl.f_cc = Export then
          let () = Format.eprintf "@[<v>Analyzing function %s@]@."
              f_decl.f_name.fn_name in

          let source_f_decl = List.find (fun source_f_decl ->
              f_decl.f_name.fn_name = source_f_decl.f_name.fn_name
            ) (snd source_p) in
          let module AbsInt = SafetyInterpreter.AbsAnalyzer(struct
              let main_source = source_f_decl
              let main = f_decl
              let prog = p
            end) in

          AbsInt.analyze ())
      (List.rev (snd p)) in
  exit 0 

(* -------------------------------------------------------------------- *)
let main () =
  try
    parse();

    if !safety_makeconfigdoc <> None
    then (
      let dir = oget !safety_makeconfigdoc in
      SafetyConfig.mk_config_doc dir;
      exit 0);

    if !help_intrinsics
    then (Help.show_intrinsics (); exit 0);

    let () = if !check_safety then
        match !safety_config with
        | Some conf -> SafetyConfig.load_config conf
        | None -> () in

    let fname = !infile in
    let env, pprog, ast =
      try Pretyping.tt_program Pretyping.Env.empty fname
      with
      | Pretyping.TyError (loc, code) -> hierror ~loc:(Lone loc) ~kind:"typing error" "%a" Pretyping.pp_tyerror code
      | Syntax.ParseError (loc, msg) ->
          let msg =
            match msg with
            | None -> "unexpected token" (* default message *)
            | Some msg -> msg
          in
          hierror ~loc:(Lone loc) ~kind:"parse error" "%s" msg
    in
 
    if !latexfile <> "" then begin
      let out = open_out !latexfile in
      let fmt = Format.formatter_of_out_channel out in
      Format.fprintf fmt "%a@." Latex_printer.pp_prog ast;
      close_out out;
      if !debug then Format.eprintf "Pretty printed to LATEX@."
    end;
  
    eprint Compiler.Typing Printer.pp_pprog pprog;

    let prog = Subst.remove_params pprog in
    eprint Compiler.ParamsExpansion (Printer.pp_prog ~debug:true) prog;

    begin try
      Typing.check_prog prog
    with Typing.TyError(loc, code) ->
      hierror ~loc:(Lmore loc) ~kind:"typing error" "%s" code
    end;
    
    (* The source program, before any compilation pass. *)
    let source_prog = prog in
    
    if SafetyConfig.sc_comp_pass () = Compiler.ParamsExpansion &&
       !check_safety
    then check_safety_p Compiler.ParamsExpansion prog source_prog
    else
            
    if !ec_list <> [] then begin
      let fmt, close =
        if !ecfile = "" then Format.std_formatter, fun () -> ()
        else
          let out = open_out !ecfile in
          let fmt = Format.formatter_of_out_channel out in
          fmt, fun () -> close_out out in
      begin try
        BatPervasives.finally
          (fun () -> close ())
          (fun () -> ToEC.extract fmt !model prog !ec_list)
          ()
      with e ->
        BatPervasives.ignore_exceptions
          (fun () -> if !ecfile <> "" then Unix.unlink !ecfile) ();
        raise e end;
      exit 0
    end;

    (* FIXME: why this is not certified *)
    let prog = Inline_array_copy.doit prog in

    (* Now call the coq compiler *)
    let all_vars = Prog.rip :: Regalloc.X64.all_registers in
    let tbl, cprog = Conv.cuprog_of_prog all_vars () prog in

    if !debug then Printf.eprintf "translated to coq \n%!";

    let to_exec = Pretyping.Env.Exec.get env in
    if to_exec <> [] then begin
        let exec (f, m) =
          try
            let pp_range fmt (ptr, sz) =
              Format.fprintf fmt "%a:%a" B.pp_print ptr B.pp_print sz in
            Format.printf "Evaluation of %s (@[<h>%a@]):@." f.fn_name
              (pp_list ",@ " pp_range) m;
            let _m, vs =
              (** TODO: allow to configure the initial stack pointer *)
              let live = List.map (fun (ptr, sz) -> Conv.int64_of_bi ptr, Conv.z_of_bi sz) m in
              (match Low_memory.Memory.coq_M.init live (Conv.int64_of_bi (Bigint.of_string "1024")) with Utils0.Ok m -> m | Utils0.Error err -> raise (Evaluator.Eval_error (Coq_xH, err))) |>
              Evaluator.exec (Expr.to_uprog cprog) (Conv.cfun_of_fun tbl f) in
            Format.printf "@[<v>%a@]@."
              (pp_list "@ " Evaluator.pp_val) vs
          with Evaluator.Eval_error (ii,err) ->
            let (i_loc, _) = Conv.get_iinfo tbl ii in
            hierror ~loc:(Lmore i_loc) ~kind:"evaluation error" "%a" Evaluator.pp_error err
        in
        List.iter exec to_exec
      end;


    let lowering_vars = Lowering.(
        let f ty n = 
          let v = V.mk n (Reg Direct) ty L._dummy in
          Conv.cvar_of_var tbl v in
        let b = f tbool in
        { fresh_OF = (b "OF").vname
        ; fresh_CF = (b "CF").vname
        ; fresh_SF = (b "SF").vname
        ; fresh_PF = (b "PF").vname
        ; fresh_ZF = (b "ZF").vname
        ; fresh_multiplicand = (fun sz -> (f (Bty (U sz)) "multiplicand").vname)
        }) in

    let fdef_of_cufdef fn cfd = Conv.fdef_of_cufdef tbl (fn,cfd) in
    let cufdef_of_fdef fd = snd (Conv.cufdef_of_fdef tbl fd) in

    let apply msg trans fn cfd =
      if !debug then Format.eprintf "START %s@." msg;
      let fd = fdef_of_cufdef fn cfd in
      if !debug then Format.eprintf "back to ocaml@.";
      let fd = trans fd in
      cufdef_of_fdef fd in

    let translate_var = Conv.var_of_cvar tbl in
    
    let memory_analysis up : Compiler.stack_alloc_oracles =
      StackAlloc.memory_analysis (Printer.pp_err ~debug:!debug) ~debug:!debug tbl up
     in

    let global_regalloc fds =
      if !debug then Format.eprintf "START regalloc@.";
      let fds = List.map (Conv.fdef_of_csfdef tbl) fds in
      (* TODO: move *)
      (* Check the stacksize, stackallocsize & stackalign annotations, if any *)
      List.iter (fun ({ Expr.sf_stk_sz ; Expr.sf_stk_extra_sz ; Expr.sf_align }, { f_loc ; f_annot ; f_name }) ->
          let hierror fmt =
            hierror ~loc:(Lone f_loc) ~funname:f_name.fn_name
              ~kind:"compilation error" ~sub_kind:"stack allocation" fmt
          in
          begin match f_annot.stack_size with
          | None -> ()
          | Some expected ->
             let actual = Conv.bi_of_z sf_stk_sz in
             if B.equal actual expected
             then (if !debug then Format.eprintf "INFO: %s has the expected stack size (%a)@." f_name.fn_name B.pp_print expected)
             else hierror "the stack has size %a (expected: %a)" B.pp_print actual B.pp_print expected
          end;
          begin match f_annot.stack_allocation_size with
          | None -> ()
          | Some expected ->
             let actual = Conv.bi_of_z (Memory_model.round_ws sf_align (BinInt.Z.add sf_stk_sz sf_stk_extra_sz)) in
             if B.equal actual expected
             then (if !debug then Format.eprintf "INFO: %s has the expected stack size (%a)@." f_name.fn_name B.pp_print expected)
             else hierror "the stack has size %a (expected: %a)" B.pp_print actual B.pp_print expected
          end;
          begin match f_annot.stack_align with
          | None -> ()
          | Some expected ->
             let actual = sf_align in
             if actual = expected
             then (if !debug then Format.eprintf "INFO: %s has the expected stack alignment (%s)@." f_name.fn_name (string_of_ws expected))
             else hierror "the stack has alignment %s (expected: %s)" (string_of_ws actual) (string_of_ws expected)
          end
        ) fds;

      let fds, extra_free_registers =
        Regalloc.alloc_prog translate_var (fun _fd extra ->
            match extra.Expr.sf_save_stack with
            | Expr.SavedStackReg _ | Expr.SavedStackStk _ -> true
            | Expr.SavedStackNone -> false) fds in
      saved_extra_free_registers := extra_free_registers;
      let fds = List.map (fun (y,_,x) -> y, x) fds in
      let fds = List.map (Conv.csfdef_of_fdef tbl) fds in
      fds in

    let is_var_in_memory cv : bool =
      let v = Conv.vari_of_cvari tbl cv |> L.unloc in
      is_stack_kind v.v_kind in


     (* TODO: update *)
    (* (\* Check safety and calls exit(_). *\)
     * let check_safety_cp s cp =
     *   let p = Conv.prog_of_cprog tbl cp in
     *   check_safety_p s p source_prog in
     * 
     * let pp_cprog s cp =
     *   if s = SafetyConfig.sc_comp_pass () && !check_safety then
     *     check_safety_cp s cp
     *   else
     *     eprint s (fun fmt cp ->
     *         let p = Conv.prog_of_cprog tbl cp in
     *         Printer.pp_prog ~debug:true fmt p) cp in *)

    let pp_cuprog fmt cp =
      let p = Conv.prog_of_cuprog tbl cp in
      Printer.pp_prog ~debug:true fmt p in

    let pp_csprog fmt cp =
      let p = Conv.prog_of_csprog tbl cp in
      Printer.pp_sprog ~debug:true tbl fmt p in

    let pp_linear fmt lp =
      PrintLinear.pp_prog tbl fmt lp in

    let rename_fd ii fn cfd =
      let ii,_ = Conv.get_iinfo tbl ii in
      let doit fd =
        let fd = Subst.clone_func fd in
        Subst.extend_iinfo ii fd in
      apply "rename_fd" doit fn cfd in

    let expand_fd fn cfd = 
      let fd = Conv.fdef_of_cufdef tbl (fn, cfd) in
      let vars, harrs = Array_expand.init_tbl fd in
      let cvar = Conv.cvar_of_var tbl in
      let vars = List.map cvar (Sv.elements vars) in
      let arrs = ref [] in
      let doarr x (ws, xs) = 
        arrs := 
          Array_expansion.{ 
            vi_v = cvar x;
            vi_s = ws;
            vi_n = List.map (fun x -> (cvar x).Var0.Var.vname) (Array.to_list xs); } :: !arrs in
      Hv.iter doarr harrs;
      { Array_expansion.vars = vars; arrs = !arrs } in

    let warning ii msg =
      if not !Glob_options.lea then begin
          let loc,_ = Conv.get_iinfo tbl ii in
          warning UseLea loc "%a" Printer.pp_warning_msg msg
        end;
      ii in

    let inline_var x =
      let x = Conv.var_of_cvar tbl x in
      x.v_kind = Inline in

   
    let is_glob x =
      let x = Conv.var_of_cvar tbl x in
      x.v_kind = Global in

    let fresh_id _gd x =
      let x = Conv.var_of_cvar tbl x in
      let x' = Prog.V.clone x in
      let cx = Conv.cvar_of_var tbl x' in
      cx.Var0.Var.vname in

    let var_alloc_fd fd = Regalloc.split_live_ranges fd in

    let removereturn sp = 
      let (fds,_data) = Conv.prog_of_csprog tbl sp in
      let tokeep = RemoveUnusedResults.analyse  fds in 
      let tokeep fn = tokeep (Conv.fun_of_cfun tbl fn) in
      tokeep in

    let is_reg_ptr x = 
      let x = Conv.var_of_cvar tbl x in
      is_reg_ptr_kind x.v_kind in

    let is_ptr x = 
      let x = Conv.var_of_cvar tbl x in
      is_ptr x.v_kind in

    let is_reg_array x =
      is_reg_arr (Conv.var_of_cvar tbl x)
    in

    let warn_extra s p =
      if s = Compiler.DeadCode_RegAllocation then
        let (fds, _) = Conv.prog_of_csprog tbl p in
        List.iter warn_extra_fd fds in


    let cparams = {
      Compiler.rename_fd    = rename_fd;
      Compiler.expand_fd    = expand_fd;
      Compiler.var_alloc_fd = apply "var alloc" var_alloc_fd;
      Compiler.stack_register_symbol = Var0.Var.vname (Conv.cvar_of_var tbl Prog.rsp);
      Compiler.global_static_data_symbol = Var0.Var.vname (Conv.cvar_of_var tbl Prog.rip);
      Compiler.stackalloc    = memory_analysis;
      Compiler.removereturn  = removereturn;
      Compiler.regalloc      = global_regalloc;
      Compiler.extra_free_registers = (fun ii ->
        let loc, _ = Conv.get_iinfo tbl ii in
        !saved_extra_free_registers loc |> omap (Conv.cvar_of_var tbl)
      );
      Compiler.lowering_vars = lowering_vars;
      Compiler.is_var_in_memory = is_var_in_memory;
      Compiler.print_uprog  = (fun s p -> eprint s pp_cuprog p; p);
      Compiler.print_sprog  = (fun s p -> warn_extra s p;
                                          eprint s pp_csprog p; p);
      Compiler.print_linear = (fun s p -> eprint s pp_linear p; p);
      Compiler.warning      = warning;
      Compiler.inline_var   = inline_var;
      Compiler.lowering_opt = Lowering.{ use_lea = !Glob_options.lea;
                                         use_set0 = !Glob_options.set0; };
      Compiler.is_glob     = is_glob;
      Compiler.fresh_id    = fresh_id;
      Compiler.is_reg_ptr  = is_reg_ptr;
      Compiler.is_ptr      = is_ptr;
      Compiler.is_reg_array = is_reg_array;
    } in

    let export_functions, subroutines =
      let conv fd = Conv.cfun_of_fun tbl fd.f_name in
      List.fold_right
        (fun fd ((e, i) as acc) ->
          match fd.f_cc with
          | Export -> (conv fd :: e, i)
          | Internal -> acc
          | Subroutine _ -> (e, conv fd :: i)
        )
        (snd prog)
        ([], []) in

    begin match
      Compiler.compile_prog_to_x86 cparams export_functions subroutines (Expr.to_uprog cprog) with
    | Utils0.Error e ->
      let e = Conv.error_of_cerror (Printer.pp_err ~debug:!debug tbl) tbl e in
      raise (HiError e)
    | Utils0.Ok asm ->
      if !outfile <> "" then begin
        BatFile.with_file_out !outfile (fun out ->
          let fmt = BatFormat.formatter_of_out_channel out in
          Format.fprintf fmt "%a%!" (Ppasm.pp_prog tbl) asm);
          if !debug then Format.eprintf "assembly listing written@."
      end else if List.mem Compiler.Assembly !print_list then
          Format.printf "%a%!" (Ppasm.pp_prog tbl) asm
    end
  with
  | Utils.HiError e ->
    Format.eprintf "%a@." pp_hierror e;
    exit 1

  | UsageError ->
    Arg.usage options usage_msg;
    exit 1

(* -------------------------------------------------------------------- *)
let () = main ()
