From mathcomp Require Import all_ssreflect all_algebra.
Require Import low_memory x86_sem x86_decl compiler_util.
Import Utf8 String.
Import all_ssreflect.
Import xseq expr.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

(* -------------------------------------------------------------------- *)
Definition reg_of_string (s : string) : option register :=
  assoc strings s.

(* -------------------------------------------------------------------- *)
Definition xmm_reg_of_string (s : string) : option xmm_register :=
  assoc strings s.

(* -------------------------------------------------------------------- *)
Definition rflag_of_string (s : string) : option rflag :=
  assoc strings s.

(* -------------------------------------------------------------------- *)
Lemma rflag_of_stringK : pcancel to_string rflag_of_string.
Proof.
  move=> r /=; rewrite /rflag_of_string /=.
  apply /assocP.
  + rewrite -map_comp map_inj_uniq; first by apply enum_uniq.
    by apply (@inj_to_string _ _ x86_rflag_toS).
  apply /mapP; exists r => //.
  by rewrite mem_enum.
Qed.

Lemma reg_of_stringK : pcancel to_string reg_of_string.
Proof.
  move=> r /=; rewrite /rflag_of_string /=.
  apply /assocP.
  + rewrite -map_comp map_inj_uniq; first by apply enum_uniq.
    by apply (@inj_to_string _ _ x86_reg_toS).
  apply /mapP; exists r => //.
  by rewrite mem_enum.
Qed.

Lemma xmm_reg_of_stringK : pcancel to_string xmm_reg_of_string.
Proof.
  move=> r /=; rewrite /rflag_of_string /=.
  apply /assocP.
  + rewrite -map_comp map_inj_uniq; first by apply enum_uniq.
    by apply (@inj_to_string _ _ x86_xreg_toS).
  apply /mapP; exists r => //.
  by rewrite mem_enum.
Qed.

(* other proof: to_string_inj ! *)
Lemma inj_string_of_rflag : injective (@to_string _ _ x86_rflag_toS).
Proof. by apply: (pcan_inj rflag_of_stringK). Qed.

Lemma inj_string_of_register : injective (@to_string _ _ x86_reg_toS).
Proof. by apply: (pcan_inj reg_of_stringK). Qed.

Lemma inj_string_of_xmm_register : injective (@to_string _ _ x86_xreg_toS).
Proof. by apply: (pcan_inj xmm_reg_of_stringK). Qed.

(* -------------------------------------------------------------------- *)
Lemma inj_reg_of_string s1 s2 r :
     reg_of_string s1 = Some r
  -> reg_of_string s2 = Some r
  -> s1 = s2.
Proof. by rewrite /reg_of_string; apply: inj_assoc; apply enum_uniq. Qed.

(* -------------------------------------------------------------------- *)
Lemma xmm_reg_of_stringI s r :
  xmm_reg_of_string s = Some r →
  to_string r = s.
Proof.
  have := xmm_reg_of_stringK r.
  move => /assoc_inj. apply.
  rewrite /= -map_comp map_inj_uniq //.
  by apply enum_uniq.
Qed.

(* -------------------------------------------------------------------- *)
Lemma inj_xmm_reg_of_string s1 s2 r :
     xmm_reg_of_string s1 = Some r
  -> xmm_reg_of_string s2 = Some r
  -> s1 = s2.
Proof. by rewrite /xmm_reg_of_string; apply: inj_assoc; apply enum_uniq. Qed.

(* -------------------------------------------------------------------- *)
Lemma inj_rflag_of_string s1 s2 rf :
     rflag_of_string s1 = Some rf
  -> rflag_of_string s2 = Some rf
  -> s1 = s2.
Proof. by rewrite /rflag_of_string; apply: inj_assoc; apply enum_uniq. Qed.

(* -------------------------------------------------------------------- *)

Definition var_of_register (r:register) :=
  {| vtype := sword64 ; vname := to_string r |}.

Definition var_of_xmm_register (r:xmm_register) :=
  {| vtype := sword256 ; vname := to_string r |}.

Definition var_of_flag (f:rflag) :=
  {| vtype := sbool; vname := to_string f |}.

Lemma var_of_register_inj x y :
  var_of_register x = var_of_register y →
  x = y.
Proof. by move=> [];apply inj_string_of_register. Qed.

Lemma var_of_flag_inj x y :
  var_of_flag x = var_of_flag y →
  x = y.
Proof. by move=> [];apply inj_string_of_rflag. Qed.

Lemma var_of_register_var_of_flag r f :
  ¬ var_of_register r = var_of_flag f.
Proof. by case: r;case: f. Qed.

Definition register_of_var (v:var) : option register :=
  if v.(vtype) == sword64 then reg_of_string v.(vname)
  else None.

Lemma var_of_register_of_var v r :
  register_of_var v = Some r →
  var_of_register r = v.
Proof.
  rewrite /register_of_var /var_of_register;case:ifP => //.
  case: v => [vt vn] /= /eqP -> H;apply f_equal.
  by apply: inj_reg_of_string H; apply reg_of_stringK.
Qed.

Lemma register_of_var_of_register r :
  register_of_var (var_of_register r) = Some r.
Proof. exact: reg_of_stringK. Qed.

Definition flag_of_var (v: var) : option rflag :=
  if v.(vtype) == sbool then rflag_of_string v.(vname)
  else None.

Lemma var_of_flag_of_var v f :
  flag_of_var v = Some f →
  var_of_flag f = v.
Proof.
  rewrite /flag_of_var /var_of_flag;case:ifP => //.
  case: v => [vt vn] /= /eqP -> H; apply f_equal.
  by apply: inj_rflag_of_string H; apply rflag_of_stringK.
Qed.

Lemma flag_of_var_of_flag r :
  flag_of_var (var_of_flag r) = Some r.
Proof.
  rewrite /flag_of_var /var_of_flag /=.
  by apply rflag_of_stringK.
Qed.

Definition xmm_register_of_var (v:var) : option xmm_register :=
  if v.(vtype) == sword256 then xmm_reg_of_string v.(vname)
  else None.

Lemma xmm_register_of_varI v r :
  xmm_register_of_var v = Some r →
  var_of_xmm_register r = v.
Proof.
  by rewrite /xmm_register_of_var /var_of_xmm_register; case: eqP => // /= <- /xmm_reg_of_stringI /= ->; case: v.
Qed.

Lemma xmm_register_of_var_of_xmm_register xr :
  xmm_register_of_var (var_of_xmm_register xr) = Some xr.
Proof. exact: xmm_reg_of_stringK. Qed.

(* -------------------------------------------------------------------- *)
Variant compiled_variable :=
| LRegister of register
| LXRegister of xmm_register
| LRFlag of rflag
.

Scheme Equality for compiled_variable.

Definition compiled_variable_eqMixin := comparableMixin compiled_variable_eq_dec.

Canonical compiled_variable_eqType := EqType compiled_variable compiled_variable_eqMixin.

Definition compile_var (v: var) : option compiled_variable :=
  match register_of_var v with
  | Some r => Some (LRegister r)
  | None =>
  match xmm_register_of_var v with
  | Some r => Some (LXRegister r)
  | None =>
  match flag_of_var v with
  | Some f => Some (LRFlag f)
  | None => None
  end end end.

Lemma xmm_register_of_var_compile_var x r :
  xmm_register_of_var x = Some r →
  compile_var x = Some (LXRegister r).
Proof.
  move => h; rewrite /compile_var h.
  case: (register_of_var x) (@var_of_register_of_var x) => //.
  move => r' /(_ _ erefl) ?; subst x.
  have {h} := xmm_register_of_varI h.
  by destruct r, r'.
Qed.

Lemma compile_varI x cv :
  compile_var x = Some cv →
  match cv with
  | LRegister r => var_of_register r = x
  | LXRegister r => var_of_xmm_register r = x
  | LRFlag f => var_of_flag f = x
  end.
Proof.
  rewrite /compile_var.
  case: (register_of_var x) (@var_of_register_of_var x).
  + by move => r /(_ _ erefl) <- {x} [<-]{cv}.
  move => _.
  case: (xmm_register_of_var x) (@xmm_register_of_varI x).
  + by move => r /(_ _ erefl) <- {x} [<-]{cv}.
  move => _.
  case: (flag_of_var x) (@var_of_flag_of_var x) => //.
  by move => r /(_ _ erefl) <- {x} [<-]{cv}.
Qed.

(* -------------------------------------------------------------------- *)
(* Compilation of pexprs *)
(* -------------------------------------------------------------------- *)
Import compiler_util.

Module E.

Definition pass_name := "asmgen"%string.

Definition gen_error (internal:bool) (ii:option instr_info) (vi: option var_info) (msg:pp_error) := 
  {| pel_msg      := msg
   ; pel_fn       := None
   ; pel_fi       := None
   ; pel_ii       := ii
   ; pel_vi       := vi
   ; pel_pass     := Some pass_name
   ; pel_internal := internal
  |}.

Definition internal_error ii msg := 
  gen_error true (Some ii) None (pp_s msg).

Definition error ii msg := 
  gen_error false (Some ii) None msg.

Definition verror internal msg ii (v:var_i) := 
  gen_error internal (Some ii) (Some v.(v_info)) (pp_box [:: pp_s msg; pp_s ":"; pp_var v]).


Definition invalid_rflag ii (v:var_i) :=
   verror true "Invalid rflag name" ii v.

Definition invalid_rflag_ty ii (v:var_i) :=
  verror true "Invalid rflag type" ii v.

Definition invalid_register ii (v:var_i) :=
   verror true "Invalid register name" ii v.

Definition invalid_register_ty ii (v:var_i) :=
  verror true "Invalid register type" ii v.

Definition berror ii e msg := 
  gen_error false (Some ii) None (pp_vbox [::pp_box [:: pp_s "not able to compile the condition"; pp_e e];
                                             pp_s msg]).

Definition werror ii e msg := 
  gen_error false (Some ii) None (pp_vbox [::pp_box [:: pp_s "invalid pexpr for oprd"; pp_e e];
                                             pp_s msg]).

End E.

(* -------------------------------------------------------------------- *)
Definition rflag_of_var ii (vi: var_i) :=
  let v := vi.(v_var) in
  Let _ := assert (v.(vtype) == sbool) (E.invalid_rflag_ty ii vi) in
  match rflag_of_string v.(vname) with
  | Some r => ok r
  | None => Error (E.invalid_rflag ii vi) 
  end.

(* -------------------------------------------------------------------- *)

Definition not_condt (c:condt) := 
  match c with
  | O_ct  => NO_ct
  | NO_ct => O_ct
  | B_ct  => NB_ct 
  | NB_ct => B_ct
  | E_ct  => NE_ct 
  | NE_ct => E_ct 
  | BE_ct => NBE_ct 
  | NBE_ct => BE_ct 
  | S_ct   => NS_ct 
  | NS_ct  => S_ct 
  | P_ct   => NP_ct 
  | NP_ct  => P_ct 
  | L_ct   => NL_ct 
  | NL_ct  => L_ct 
  | LE_ct  => NLE_ct 
  | NLE_ct => LE_ct
  end.

Definition or_condt ii e c1 c2 : cexec condt := 
  match c1, c2 with
  | L_ct, E_ct | E_ct, L_ct => ok LE_ct
  | B_ct, E_ct | E_ct, B_ct => ok BE_ct 
  | _, _ => Error (E.berror ii e "Invalid condition (OR)")
  end.

Definition and_condt ii e c1 c2 := 
  match c1, c2 with
  | NB_ct, NE_ct | NE_ct, NB_ct => ok NBE_ct
  | NE_ct, NL_ct | NL_ct, NE_ct => ok NLE_ct 
  | _, _ => Error (E.berror ii e "Invalid condition (AND)")
  end.

Fixpoint assemble_cond_r ii (e: pexpr) : cexec condt := 
  match e with
  | Pvar v =>
    Let r := rflag_of_var ii v.(gv) in
    match r with
    | OF => ok O_ct
    | CF => ok B_ct
    | ZF => ok E_ct
    | SF => ok S_ct
    | PF => ok P_ct
    | DF => Error (E.berror ii e "Cannot branch on DF")
    end
  | Papp1 Onot e => 
    Let c := assemble_cond_r ii e in
    ok (not_condt c)

  | Papp2 Oor e1 e2 =>
    Let c1 := assemble_cond_r ii e1 in
    Let c2 := assemble_cond_r ii e2 in
    or_condt ii e c1 c2
  
  | Papp2 Oand e1 e2 =>
    Let c1 := assemble_cond_r ii e1 in
    Let c2 := assemble_cond_r ii e2 in
    and_condt ii e c1 c2
    
  | Papp2 Obeq (Pvar x1) (Pvar x2) =>
    Let r1 := rflag_of_var ii x1.(gv) in
    Let r2 := rflag_of_var ii x2.(gv) in
    if (r1 == SF) && (r2 == OF) || (r1 == OF) && (r2 == SF) then ok NL_ct
    else Error (E.berror ii e "Invalid condition (NL)")
  
  (* We keep this by compatibility but it will be nice to remove it *)
  | Pif _ (Pvar v1) (Papp1 Onot (Pvar vn2)) (Pvar v2) =>
    Let r1 := rflag_of_var ii v1.(gv) in
    Let rn2 := rflag_of_var ii vn2.(gv) in
    Let r2 := rflag_of_var ii v2.(gv) in
    if [&& r1 == SF, rn2 == OF & r2 == OF] ||
       [&& r1 == OF, rn2 == SF & r2 == SF] then
      ok L_ct
    else Error (E.berror ii e "Invalid condition (L)")

  | Pif _ (Pvar v1) (Pvar v2) (Papp1 Onot (Pvar vn2)) =>
    Let r1 := rflag_of_var ii v1.(gv) in
    Let r2 := rflag_of_var ii v2.(gv) in
    Let rn2 := rflag_of_var ii vn2.(gv) in
    if [&& r1 == SF, rn2 == OF & r2 == OF] ||
       [&& r1 == OF, rn2 == SF & r2 == SF] then
      ok NL_ct
    else  Error (E.berror ii e "Invalid condition (NL)")
  
  | _ => Error (E.berror ii e "don't known how to compile the condition")

  end.

Definition assemble_cond ii (e: pexpr) : cexec condt :=
  assemble_cond_r ii e.

(* -------------------------------------------------------------------- *)

Definition reg_of_var ii (vi: var_i) :=
  let v := vi.(v_var) in
  Let _ := assert (v.(vtype) == sword U64) (E.invalid_register_ty ii vi) in
  match reg_of_string v.(vname) with
  | Some r => ok r 
  | None => Error (E.invalid_register ii vi)
  end.

Definition reg_of_vars ii (vs: seq var_i) :=
  mapM (reg_of_var ii) vs.

Lemma reg_of_var_register_of_var ii x r :
  reg_of_var ii x = ok r →
  register_of_var x = Some r.
Proof.
 rewrite /reg_of_var /register_of_var; case: x => -[] ty s vi /=; t_xrbindP => _ /assertP /eqP ->.
 by case: reg_of_string => // r' [->]; rewrite eqxx.
Qed.

(* -------------------------------------------------------------------- *)
Definition scale_of_z' ii (z:pointer) :=
  match wunsigned z with
  | 1 => ok 0%nat
  | 2 => ok 1%nat
  | 4 => ok 2%nat
  | 8 => ok 3%nat
  | _ => Error (E.error ii (pp_s "invalid scale"))
  end%Z.

Definition reg_of_ovar ii (x:option var_i) := 
  match x with 
  | Some x => 
    Let r := reg_of_var ii x in
    ok (Some r)
  | None =>
    ok None
  end.

Definition xreg_of_var ii (x: var_i) : cexec asm_arg :=
  if xmm_register_of_var x is Some r then ok (XReg r)
  else if register_of_var x is Some r then ok (Reg r)
  else Error (E.verror false "Not a (x)register" ii x).

Lemma var_of_xmm_register_inj x y :
  var_of_xmm_register x = var_of_xmm_register y →
  x = y.
Proof. by move=> [];apply inj_string_of_xmm_register. Qed.

(* TODO: change def of reg_of_var *)
Lemma var_of_reg_of_var ii v r: reg_of_var ii v = ok r → var_of_register r = v.
Proof.
  rewrite /reg_of_var /var_of_register; case: v => -[] ty vn vi /=; t_xrbindP => _ /assertP /eqP ->.
  case heq : reg_of_string => [r' | ] => // -[<-]; apply f_equal.
  by apply: inj_reg_of_string heq; apply reg_of_stringK.
Qed.
