(* ** License
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

(* * Prove properties about semantics of dmasm input language *)

(* ** Imports and settings *)
Require Import ZArith.
From mathcomp Require Import all_ssreflect all_algebra.
Require Import sem allocation compiler_util.
Require Export inline.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Local Open Scope vmap.
Local Open Scope seq_scope.

Section INLINE.

Context (inline_var: var -> bool).
Variable rename_fd : instr_info -> funname -> fundef -> fundef.

Lemma get_funP p ii f fd : 
  get_fun p ii f = ok fd -> get_fundef p f = Some fd.
Proof. by rewrite /get_fun;case:get_fundef => // ? [->]. Qed.

Local Notation inline_i' := (inline_i inline_var rename_fd).
Local Notation inline_fd' := (inline_fd inline_var rename_fd).
Local Notation inline_prog' := (inline_prog inline_var rename_fd).

Section INCL.

  Variable p p': prog.  

  Hypothesis Incl : forall f fd, 
    get_fundef p f = Some fd -> get_fundef p' f = Some fd.

  Let Pi i := forall X1 c' X2,
    inline_i' p  i X2 = ok (X1, c') ->
    inline_i' p' i X2 = ok (X1, c').

  Let Pr i := forall ii, Pi (MkI ii i).

  Let Pc c :=  forall X1 c' X2, 
    inline_c (inline_i' p)  c X2 = ok (X1, c') ->
    inline_c (inline_i' p') c X2 = ok (X1, c').
 
  Lemma inline_c_incl c : Pc c.
  Proof.
    apply (@cmd_rect Pr Pi Pc) => // {c}.
    + move=> i c Hi Hc X1 c' X2 /=.
      apply:rbindP => -[Xc cc] /Hc -> /=.
      by apply:rbindP => -[Xi ci] /Hi ->.
    + by move=> * ?. 
    + by move=> * ?.
    + move=> e c1 c2 Hc1 Hc2 ii X1 c' X2 /=.
      apply: rbindP => -[Xc1 c1'] /Hc1 -> /=.
      by apply: rbindP => -[Xc2 c2'] /Hc2 -> /= [] <- <-.
    + move=> i dir lo hi c Hc ii X1 c0 X2 /=.
      by apply: rbindP => -[Xc c'] /Hc -> /=.     
    + move=> c e c' Hc Hc' ii X1 c0 X2 /=.
      apply: rbindP => -[Xc1 c1] /Hc -> /=.
      by apply: rbindP => -[Xc1' c1'] /Hc' -> /=.
    move=> i xs f es ii X1 c' X2 /=.
    case: i => //;apply: rbindP => fd /get_funP -/Incl.
    by rewrite /get_fun => ->.
  Qed.

  Lemma inline_incl fd fd' :
    inline_fd' p fd = ok fd' ->
    inline_fd' p' fd = ok fd'.
  Proof.
    by case: fd => fi fp fb fr /=;apply: rbindP => -[??] /inline_c_incl -> [<-].
  Qed.

End INCL. 

Lemma inline_prog_fst p p' :
  inline_prog' p = ok p' ->
  [seq x.1 | x <- p] = [seq x.1 | x <- p'].
Proof.
  elim: p p' => [ ?[<-] | [f fd] p Hrec p'] //=. 
  by apply: rbindP => ? /Hrec -> /=;apply:rbindP => ?? [] <-.
Qed.

Lemma inline_progP p p' f fd' :
  uniq [seq x.1 | x <- p] ->
  inline_prog' p = ok p' ->
  get_fundef p' f = Some fd' ->
  exists fd, get_fundef p f = Some fd /\ inline_fd' p' fd = ok fd'.
Proof.
  elim: p p' => [ | [f1 fd1] p Hrec] p' /=. 
  + by move=> _ [<-].
  move=> /andP [] Hf1 Huniq.
  apply: rbindP => p1 Hp1 /=.
  apply: rbindP => fd1';apply: add_finfoP => Hinl [] <-.
  rewrite !get_fundef_cons /=;case: eqP => [? [?]| Hne].
  + subst f1 fd';exists fd1;split=>//.
    apply: inline_incl Hinl => f0 fd0;rewrite get_fundef_cons /=.
    case: eqP => // -> H; have := (get_fundef_in H)=> {H}H.
    by move: Hf1;rewrite (inline_prog_fst Hp1) H.
  move=> /(Hrec   _ Huniq Hp1) [fd [? H]];exists fd;split=>//.
  apply: inline_incl H => f0 fd0;rewrite get_fundef_cons /=.
  case: eqP => // -> H; have := (get_fundef_in H)=> {H}H.
  by move: Hf1;rewrite (inline_prog_fst Hp1) H.
Qed.

Lemma inline_progP' p p' f fd :
  uniq [seq x.1 | x <- p] ->
  inline_prog' p = ok p' ->
  get_fundef p f = Some fd ->
  exists fd', get_fundef p' f = Some fd' /\ inline_fd' p' fd = ok fd'.
Proof.
  elim: p p' => [ | [f1 fd1] p Hrec] p' //. 
  rewrite /= => /andP [] Hf1 Huniq.
  apply: rbindP => p1 Hp1.
  apply: rbindP => fd1';apply: add_finfoP => Hinl [] <-.
  rewrite !get_fundef_cons /=;case: eqP => [? [?]| Hne].
  + subst f1 fd1;exists fd1';split=>//.
    apply: inline_incl Hinl => f0 fd0;rewrite get_fundef_cons /=.
    case: eqP => // -> H; have := (get_fundef_in H)=> {H}H.
    by move: Hf1;rewrite (inline_prog_fst Hp1) H.
  move=> /(Hrec   _ Huniq Hp1) [fd' [? H]];exists fd';split=>//.
  apply: inline_incl H => f0 fd0;rewrite get_fundef_cons /=.
  case: eqP => // -> H; have := (get_fundef_in H)=> {H}H.
  by move: Hf1;rewrite (inline_prog_fst Hp1) H.
Qed.

Section SUBSET.

  Variable p : prog.  

  Let Pi i := forall X2 Xc,
    inline_i' p i X2 = ok Xc -> Sv.Equal Xc.1 (Sv.union (read_I i) X2).

  Let Pr i := forall ii, Pi (MkI ii i).

  Let Pc c := 
    forall X2 Xc,
      inline_c (inline_i' p) c X2 = ok Xc -> Sv.Equal Xc.1 (Sv.union (read_c c) X2).

  Local Lemma Smk    : forall i ii, Pr i -> Pi (MkI ii i).
  Proof. done. Qed.

  Local Lemma Snil   : Pc [::].
  Proof. by move=> X2 Xc [<-]. Qed.

  Local Lemma Scons  : forall i c, Pi i -> Pc c -> Pc (i::c).
  Proof. 
    move=> i c Hi Hc X2 Xc /=.
    apply:rbindP=> Xc' /Hc ?;apply:rbindP => Xi /Hi ? [<-] /=.
    rewrite read_c_cons;SvD.fsetdec.
  Qed.

  Local Lemma Sasgn  : forall x t e, Pr (Cassgn x t e).
  Proof. by move=> ??? ii X2 Xc /= [<-]. Qed.

  Local Lemma Sopn   : forall xs o es, Pr (Copn xs o es).
  Proof. by move=> ??? ii X2 Xc /= [<-]. Qed.

  Local Lemma Sif    : forall e c1 c2, Pc c1 -> Pc c2 -> Pr (Cif e c1 c2).
  Proof. 
    move=> e c1 c2 Hc1 Hc2 ii X2 Xc /=.
    apply: rbindP => Xc1 /Hc1 ?;apply:rbindP=> Xc2 /Hc2 ? [<-] /=.
    rewrite read_Ii read_i_if read_eE;SvD.fsetdec.
  Qed.

  Local Lemma Sfor   : forall v dir lo hi c, Pc c -> Pr (Cfor v (dir,lo,hi) c).
  Proof. by move=> i d lo hi c Hc ii X2 Xc;apply:rbindP => Xc' /Hc ? [<-]. Qed.

  Local Lemma Swhile : forall c e c', Pc c -> Pc c' -> Pr (Cwhile c e c').
  Proof.
    move=> c e c' Hc Hc' ii X2 Xc;apply:rbindP=> Xc' /Hc ?.
    by apply: rbindP=> Hc'' /Hc' ? [<-].
  Qed.

  Local Lemma Scall  : forall i xs f es, Pr (Ccall i xs f es).
  Proof. 
    move=> i xs f es ii X2 Xc /=;case: i => [ | [<-] //].
    by apply:rbindP => fd _;apply: rbindP => ?? [<-].
  Qed. 

  Lemma inline_c_subset c : Pc c.
  Proof.
    by apply (@cmd_rect Pr Pi Pc Smk Snil Scons Sasgn Sopn Sif Sfor Swhile Scall).
  Qed.

  Lemma inline_i_subset i : Pr i.
  Proof.
    by apply (@instr_r_Rect Pr Pi Pc Smk Snil Scons Sasgn Sopn Sif Sfor Swhile Scall).
  Qed.
  
  Lemma inline_i'_subset i : Pi i.
  Proof.
    by apply (@instr_Rect Pr Pi Pc Smk Snil Scons Sasgn Sopn Sif Sfor Swhile Scall).
  Qed.
  
End SUBSET.

Lemma assgn_tuple_Lvar p gd ii (xs:seq var_i) flag es vs s s' :
  let xs := map Lvar xs in
  disjoint (vrvs xs) (read_es es) ->  
  sem_pexprs gd s es = ok vs ->
  write_lvals gd s xs vs = ok s' ->
  sem p gd s (assgn_tuple inline_var ii xs flag es) s'.
Proof.
  rewrite /disjoint /assgn_tuple /is_true Sv.is_empty_spec.
  elim: xs es vs s s' => [ | x xs Hrec] [ | e es] [ | v vs] s s' //=.
  + by move=> _ _ [<-];constructor.
  + by move=> _;apply: rbindP => ??;apply:rbindP.
  rewrite vrvs_cons vrv_var read_es_cons=> Hempty.
  apply: rbindP => ve Hse;apply:rbindP => vz Hses [??]; subst ve vz.
  apply: rbindP => s1 Hw Hws. 
  apply Eseq with s1;first by constructor;constructor;rewrite Hse.
  apply : Hrec Hws;first by SvD.fsetdec.
  apply:rbindP Hw => vm;apply: on_vuP.
  + move=> z ? <- [<-] /=.
    rewrite -Hses=> {Hse Hses};case:s => sm svm /=. 
    apply read_es_eq_on with Sv.empty.
    by rewrite read_esE => y Hy;rewrite Fv.setP_neq //;apply/eqP;SvD.fsetdec.
  case:ifP => //= _ ? [<-] [<-] /=.
  rewrite -Hses=> {Hse Hses};case:s => sm svm /=. 
  apply read_es_eq_on with Sv.empty.
  by rewrite read_esE => y Hy;rewrite Fv.setP_neq //;apply/eqP;SvD.fsetdec.
Qed.

Lemma assgn_tuple_Pvar p gd ii xs flag rxs vs s s' :
  let es := map Pvar rxs in
  disjoint (vrvs xs) (read_es es) -> 
  mapM (fun x : var_i => get_var (evm s) x) rxs = ok vs ->
  write_lvals gd s xs vs = ok s' ->
  sem p gd s (assgn_tuple inline_var ii xs flag es) s'.
Proof.
  rewrite /disjoint /assgn_tuple /is_true Sv.is_empty_spec.
  have : evm s = evm s [\vrvs xs] by done.
  have : Sv.Subset (vrvs xs) (vrvs xs) by done.
  move: {1 3}s => s0;move: {2 3 4}(vrvs xs) => X.
  elim: xs rxs vs s s' => [ | x xs Hrec] [ | rx rxs] [ | v vs] s s' //=.
  + by move=> _ _ _ _ [<-];constructor.
  + by move=> _ _ _;apply: rbindP => ??;apply:rbindP.
  rewrite vrvs_cons read_es_cons read_e_var => Hsub Heqe Hempty.
  apply: rbindP => ve Hse;apply:rbindP => vz Hses [??]; subst ve vz.
  apply: rbindP => s1 Hw Hws; apply Eseq with s1. 
  + constructor;constructor;rewrite /=.
    have /get_var_eq_on: evm s0 =[Sv.singleton rx] evm s. 
      move=> y ?;apply: Heqe;SvD.fsetdec.
    by move=> <-;[rewrite Hse | SvD.fsetdec].
  apply: Hrec Hses Hws;[SvD.fsetdec| |SvD.fsetdec].
  by move=> y Hy;rewrite Heqe //;apply (vrvP Hw);SvD.fsetdec.
Qed.

(* FIXME : MOVE THIS, this should be an invariant in vmap *)
Section WF.

  Definition wf_vm (vm:vmap) := 
    forall x,
      match vm.[x], vtype x with
      | Ok _   , _      => True
      | Error ErrAddrUndef, sarr _ => False
      | Error ErrAddrUndef, _ => True
      | _, _ => false
      end.

  Lemma wf_set_var x ve vm1 vm2 :
    wf_vm vm1 -> set_var vm1 x ve = ok vm2 -> wf_vm vm2.
  Proof.
    move=> Hwf;apply: set_varP => [v | _ ] ? <- /= z.
    + case: (x =P z) => [ <- | /eqP Hne];first by rewrite Fv.setP_eq.
      by rewrite Fv.setP_neq //;apply (Hwf z).
    case: (x =P z) => [ <- | /eqP Hne].
    + by rewrite Fv.setP_eq; case (vtype x).
    by rewrite Fv.setP_neq //;apply (Hwf z).
  Qed.
  
  Lemma wf_write_var x ve s1 s2 :
    wf_vm (evm s1) -> write_var x ve s1 = ok s2 -> wf_vm (evm s2).
  Proof. 
    by move=> HWf; apply: rbindP => vm Hset [<-] /=;apply: wf_set_var Hset. 
  Qed.
 
  Lemma wf_write_vars x ve s1 s2 :
    wf_vm (evm s1) -> write_vars x ve s1 = ok s2 -> wf_vm (evm s2).
  Proof. 
    elim: x ve s1 s2=> [ | x xs Hrec] [ | e es] //= s1 s2.
    + by move=> ? [<-].
    by move=> Hwf; apply: rbindP => vm /(wf_write_var Hwf) -/Hrec H/H.
  Qed.
  
  Lemma wf_write_lval gd x ve s1 s2 :
    wf_vm (evm s1) -> write_lval gd x ve s1 = ok s2 -> wf_vm (evm s2).
  Proof.
    case: x => [vi t|v|v e|v e] /= Hwf.
    + by move=> /write_noneP [->]. + by apply wf_write_var. + by t_rbindP => -[<-].
    apply: on_arr_varP => n t ? ?.   
    apply:rbindP => ??;apply:rbindP => ??;apply:rbindP => ??.
    by apply:rbindP=>? Hset [<-] /=;apply: wf_set_var Hset.
  Qed.
  
  Lemma wf_write_lvals gd xs vs s1 s2 :
    wf_vm (evm s1) -> write_lvals gd s1 xs vs = ok s2 -> wf_vm (evm s2).
  Proof.
    elim: xs vs s1 => [ | x xs Hrec] [ | v vs] s1 //= Hwf => [[<-]//| ].
    apply: rbindP => s1' /(wf_write_lval Hwf);apply Hrec.
  Qed.

  Lemma wf_sem p gd s1 c s2 :
    sem p gd s1 c s2 -> wf_vm (evm s1) -> wf_vm (evm s2).
  Proof.
    apply (@cmd_rect 
             (fun i => forall s1 s2, sem_i p gd s1 i s2 -> wf_vm (evm s1) -> wf_vm (evm s2))
             (fun i => forall s1 s2, sem_I p gd s1 i s2 -> wf_vm (evm s1) -> wf_vm (evm s2))
             (fun c => forall s1 s2, sem   p gd s1 c s2 -> wf_vm (evm s1) -> wf_vm (evm s2)))=>
      {s1 s2 c}.
    + by move=> i ii Hrec s1 s2 H;sinversion H;apply Hrec.
    + by move=> s1 s2 H;sinversion H.
    + by move=> i c Hi Hc s1 s2 H;sinversion H => /(Hi _ _ H3);apply Hc.
    + move=> x t e s1 s2 H;sinversion H.
      by apply:rbindP H5 => v ? Hw ?; apply: wf_write_lval Hw.
    + move=> xs o es s1 s2 H;sinversion H. 
      by apply:rbindP H5 => ?? Hw ?;apply: wf_write_lvals Hw.
    + by move=> e c1 c2 Hc1 Hc2 s1 s2 H;sinversion H;[apply Hc1 | apply Hc2].
    + move=> i dir lo hi c Hc s1 s2 H;sinversion H.
      elim: H9 Hc => // ???? ???? Hw Hsc Hsf Hrec Hc.
      by move=> /wf_write_var -/(_ _ _ _ Hw) -/(Hc _ _ Hsc);apply: Hrec Hc.
    + move=> c e c' Hc Hc' s1 s2 H.
      move: {1 2}(Cwhile c e c') H (refl_equal (Cwhile c e c'))=> i;elim=> //=.
      move=> ??????? Hsc ? Hsc' Hsw Hrec [???];subst.
      move=> /(Hc _ _ Hsc).
      by move=> /(Hc' _ _ Hsc'); apply Hrec.
    + move=> ????? Hsc ? [???];subst.
      exact: (Hc _ _ Hsc).
    move=> i xs f es s1 s2 H;sinversion H=> Hwf.
    by apply: wf_write_lvals H8.
  Qed. 

  Lemma wf_vm_uincl vm : wf_vm vm -> vm_uincl vmap0 vm.
  Proof.
    move=> Hwf x;have := Hwf x;rewrite /vmap0 Fv.get0.
    case: vm.[x] => [a _ | ];first by apply eval_uincl_undef.
    move=> [] //=;case:(vtype x) => //=.
  Qed.
  
  Lemma wf_vmap0 : wf_vm vmap0.
  Proof. by move=> x;rewrite /vmap0 Fv.get0;case:vtype. Qed.

End WF.
  
Section PROOF.

  Variable p p' : prog.
  Context (gd: glob_defs).

  Hypothesis uniq_funname : uniq [seq x.1 | x <- p].

  Hypothesis Hp : inline_prog' p = ok p'.

  Let Pi_r s1 (i:instr_r) s2:= 
    forall ii X1 X2 c', inline_i' p' (MkI ii i) X2 = ok (X1, c') ->
    forall vm1, wf_vm vm1 -> evm s1 =[X1] vm1 -> 
    exists vm2, [/\ wf_vm vm2, evm s2 =[X2] vm2 &
       sem p' gd (Estate (emem s1) vm1) c' (Estate (emem s2) vm2)].

  Let Pi s1 (i:instr) s2:= 
    forall X1 X2 c', inline_i' p' i X2 = ok (X1, c') ->
    forall vm1, wf_vm vm1 -> evm s1 =[X1] vm1 -> 
    exists vm2, [/\ wf_vm vm2, evm s2 =[X2] vm2 &
      sem p' gd (Estate (emem s1) vm1) c' (Estate (emem s2) vm2)].

  Let Pc s1 (c:cmd) s2:= 
    forall X1 X2 c', inline_c (inline_i' p') c X2 = ok (X1, c') ->
    forall vm1, wf_vm vm1 -> evm s1 =[X1] vm1 -> 
    exists vm2, [/\ wf_vm vm2, evm s2 =[X2] vm2 &
      sem p' gd (Estate (emem s1) vm1) c' (Estate (emem s2) vm2)].

  Let Pfor (i:var_i) vs s1 c s2 :=
    forall X1 X2 c', 
    inline_c (inline_i' p') c X2 = ok (X1, c') ->
    Sv.Equal X1 X2 ->
    forall vm1, wf_vm vm1 -> evm s1 =[X1] vm1 -> 
    exists vm2, [/\ wf_vm vm2, evm s2 =[X2] vm2 &
      sem_for p' gd i vs (Estate (emem s1) vm1) c' (Estate (emem s2) vm2)].

  Let Pfun (mem:Memory.mem) fn vargs (mem':Memory.mem) vres :=
    sem_call p' gd mem fn vargs mem' vres.

  Local Lemma Hskip s: Pc s [::] s.
  Proof. move=> X1 X2 c' [<- <-] vm1 Hwf Hvm1;exists vm1;split=>//;constructor. Qed.

  Local Lemma Hcons s1 s2 s3 i c :
    sem_I p gd s1 i s2 ->
    Pi s1 i s2 -> sem p gd s2 c s3 -> Pc s2 c s3 -> Pc s1 (i :: c) s3.
  Proof.
    move=> _ Hi _ Hc X1 X2 c0 /=;apply: rbindP => -[Xc c'] /Hc Hic.
    apply:rbindP => -[Xi i'] /Hi Hii [<- <-] vm1 /Hii H/H{H} [vm2 []].
    move=> /Hic H/H{H} [vm3 [Hwf3 Hvm3 Hsc']] ?.
    by exists vm3;split=> //;apply: sem_app Hsc'.
  Qed.

  Local Lemma HmkI ii i s1 s2 :
    sem_i p gd s1 i s2 -> Pi_r s1 i s2 -> Pi s1 (MkI ii i) s2.
  Proof. by move=> _ Hi ??? /Hi. Qed.

  Local Lemma Hassgn s1 s2 x tag e :
    Let v := sem_pexpr gd s1 e in write_lval gd x v s1 = Ok error s2 ->
    Pi_r s1 (Cassgn x tag e) s2.
  Proof.
    case: s1 s2 => sm1 svm1 [sm2 svm2].
    apply: rbindP => ve Hse Hw ii X1 X2 c' [] <- <- vm1.
    rewrite read_i_assgn => Hwf Hvm.
    have /read_e_eq_on H: svm1 =[read_e e] vm1 by apply: eq_onI Hvm;SvD.fsetdec.
    rewrite H in Hse.
    have [ | vm2 [/=Hvm2 Hw']]:= write_lval_eq_on _ Hw Hvm; first by SvD.fsetdec.
    have /(_ Hwf):= wf_write_lval _ Hw'.
    exists vm2;split=>//; first by apply: eq_onI Hvm2;SvD.fsetdec.   
    by apply: sem_seq1;constructor;constructor;rewrite Hse.
  Qed.

  Local Lemma Hopn s1 s2 o xs es : 
    Let x := Let x := sem_pexprs gd s1 es in sem_sopn o x
    in write_lvals gd s1 xs x = Ok error s2 -> Pi_r s1 (Copn xs o es) s2.
  Proof.
    case: s1 s2 => sm1 svm1 [sm2 svm2].
    apply: rbindP => ve Hse Hw ii X1 X2 c' [] <- <- vm1.
    rewrite read_i_opn => Hwf Hvm.
    have /read_es_eq_on H: svm1 =[read_es es] vm1 by apply: eq_onI Hvm;SvD.fsetdec.
    rewrite H in Hse.
    have [ | vm2 [Hvm2 Hw']]:= write_lvals_eq_on _ Hw Hvm; first by SvD.fsetdec.
    have /(_ Hwf):= wf_write_lvals _ Hw'.
    exists vm2;split=>//; first by apply: eq_onI Hvm2;SvD.fsetdec.   
    by apply: sem_seq1;constructor;constructor;rewrite Hse.
  Qed.

  Local Lemma Hif_true s1 s2 e c1 c2 :
    Let x := sem_pexpr gd s1 e in to_bool x = Ok error true ->
    sem p gd s1 c1 s2 -> Pc s1 c1 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    case: s1 => sm1 svm1.
    apply: rbindP => ve Hse Hto _ Hc ii X1 X2 c'.
    apply: rbindP => -[Xc1 c1'] /Hc Hc1;apply: rbindP => -[Xc2 c2'] ? [<- <-] vm1.
    rewrite read_eE=> Hwf Hvm1.
    case: (Hc1 vm1 _)=>//;first by apply: eq_onI Hvm1;SvD.fsetdec.
    move=> vm2 [Hvm2 Hc1'];exists vm2;split=>//.
    apply sem_seq1;constructor;apply Eif_true => //.
    have /read_e_eq_on <-: svm1 =[read_e e] vm1 by apply: eq_onI Hvm1;SvD.fsetdec.
    by rewrite Hse.
  Qed.

  Local Lemma Hif_false s1 s2 e c1 c2 :
    Let x := sem_pexpr gd s1 e in to_bool x = Ok error false ->
    sem p gd s1 c2 s2 -> Pc s1 c2 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    case: s1 => sm1 svm1.
    apply: rbindP => ve Hse Hto _ Hc ii X1 X2 c'.
    apply: rbindP => -[Xc1 c1'] ?;apply: rbindP => -[Xc2 c2'] /Hc Hc2 [<- <-] vm1.
    rewrite read_eE=> Hwf Hvm1.
    case: (Hc2 vm1 _)=>//;first by apply: eq_onI Hvm1;SvD.fsetdec.
    move=> vm2 [Hvm2 Hc1'];exists vm2;split=>//.
    apply sem_seq1;constructor;apply Eif_false => //.
    have /read_e_eq_on <-: svm1 =[read_e e] vm1 by apply: eq_onI Hvm1;SvD.fsetdec.
    by rewrite Hse.
  Qed.
    
  Local Lemma Hwhile_true s1 s2 s3 s4 c e c':
    sem p gd s1 c s2 -> Pc s1 c s2 ->
    Let x := sem_pexpr gd s2 e in to_bool x = Ok error true ->
    sem p gd s2 c' s3 -> Pc s2 c' s3 ->
    sem_i p gd s3 (Cwhile c e c') s4 -> Pi_r s3 (Cwhile c e c') s4 ->
    Pi_r s1 (Cwhile c e c') s4.
  Proof.
    case: s1 => sm1 svm1 Hsc Hc Hse Hsc' Hc' _ Hw ii X1 X2 cw Hi.
    move: (Hi) => /=;set X3 := Sv.union _ _;apply: rbindP => -[Xc c1] Hc1.
    apply: rbindP => -[Xc' c1'] Hc1' [] ??;subst X1 cw => vm1 Hwf Hvm1.
    case : (Hc _ _ _ Hc1 _ Hwf) => [| vm2 [Hwf2 Hvm2 Hsc1]].
    + apply: eq_onI Hvm1; have /= -> := inline_c_subset Hc1.
      by rewrite /X3 read_i_while;SvD.fsetdec.
    case : (Hc' _ _ _ Hc1' _ Hwf2) => [| vm3 [Hwf3 Hvm3 Hsc2]].
    + apply: eq_onI Hvm2; have /= -> := inline_c_subset Hc1'.
      by rewrite /X3 read_i_while;SvD.fsetdec.
    have [vm4 [Hwf4 Hvm4 Hsw]]:= Hw _ _ _ _ Hi _ Hwf3 Hvm3.
    exists vm4;split => //;apply sem_seq1;constructor.
    sinversion Hsw; sinversion H4;sinversion H2.
    apply: (Ewhile_true Hsc1) Hsc2 H4.
    have /read_e_eq_on <- : (evm s2) =[read_e e] vm2. 
    + by apply: eq_onI Hvm2;rewrite /X3 read_i_while;SvD.fsetdec.
    by case: (s2) Hse.
  Qed.

  Local Lemma Hwhile_false s1 s2 c e c':
    sem p gd s1 c s2 -> Pc s1 c s2 ->
    Let x := sem_pexpr gd s2 e in to_bool x = Ok error false ->
    Pi_r s1 (Cwhile c e c') s2.
  Proof.
    case: s1 s2 => sm1 svm1 [sm2 svm2] Hsc Hc Hse ii X1 X2 cw /=.
    set X3 := Sv.union _ _;apply: rbindP => -[Xc c1] Hc1.
    apply: rbindP => -[Xc' c1'] Hc1' [] ??;subst X1 cw => vm1 Hwf Hvm1.
    case : (Hc _ _ _ Hc1 _ Hwf) => [| vm2 [Hwf2 Hvm2 Hsc1]].
    + apply: eq_onI Hvm1; have /= -> := inline_c_subset Hc1.
      by rewrite /X3 read_i_while;SvD.fsetdec.
    exists vm2;split=>//. 
    + by apply: eq_onI Hvm2;rewrite /X3;SvD.fsetdec.
    apply sem_seq1;constructor;apply Ewhile_false => //.
    have /read_e_eq_on <- //: svm2 =[read_e e] vm2.
    apply: eq_onI Hvm2;rewrite /X3 read_i_while;SvD.fsetdec.
  Qed.
 
  Local Lemma Hfor s1 s2 (i:var_i) d lo hi c vlo vhi :
    Let x := sem_pexpr gd s1 lo in to_int x = Ok error vlo ->
    Let x := sem_pexpr gd s1 hi in to_int x = Ok error vhi ->
    sem_for p gd i (wrange d vlo vhi) s1 c s2 ->
    Pfor i (wrange d vlo vhi) s1 c s2 -> Pi_r s1 (Cfor i (d, lo, hi) c) s2.
  Proof.
    case: s1 => sm1 svm1.
    apply: rbindP => zlo Hlo Tlo;apply: rbindP => zhi Hhi Thi _ Hf ii X1 X2 cf Hi.
    apply: rbindP Hi => -[Xc' c'] Hi [??] vm1 Hwf Hvm1;subst.
    have Hxc': Sv.Equal Xc' (Sv.union (read_i (Cfor i (d, lo, hi) c)) X2).
    + by have /= -> := inline_c_subset Hi;rewrite read_i_for;SvD.fsetdec.
    have [ /=| vm2 [Hwf2 Hvm2 Hsf]]:= Hf _ _ _ Hi Hxc' _ Hwf.
    + by apply: eq_onI Hvm1;rewrite Hxc'.
    exists vm2;split=>//;first by apply: eq_onI Hvm2;SvD.fsetdec.
    move: Hvm1;rewrite read_i_for => Hvm1.
    apply sem_seq1;constructor;eapply Efor;eauto=> /=.
    + have /read_e_eq_on <-: svm1 =[read_e lo] vm1 by apply: eq_onI Hvm1; SvD.fsetdec.
      by rewrite Hlo.   
    have /read_e_eq_on <-: svm1 =[read_e hi] vm1 by apply: eq_onI Hvm1; SvD.fsetdec.
    by rewrite Hhi.   
  Qed.

  Local Lemma Hfor_nil s i c: Pfor i [::] s c s.
  Proof.
    move=> X1 X2 c' Hc HX vm1 Hwf Hvm1;exists vm1;split=>//;first by rewrite -HX.
    constructor.
  Qed.

  Local Lemma Hfor_cons s1 s1' s2 s3 (i : var_i) (w:Z) (ws:seq Z) c :
    write_var i w s1 = Ok error s1' ->
    sem p gd s1' c s2 ->
    Pc s1' c s2 ->
    sem_for p gd i ws s2 c s3 -> Pfor i ws s2 c s3 -> Pfor i (w :: ws) s1 c s3.
  Proof.
    move=> Hwi _ Hc _ Hfor X1 X2 c' Hic HX vm1 Hwf Hvm1.
    have [vm1' [Hvm1' Hw]]:= write_var_eq_on Hwi Hvm1.
    have /(_ Hwf)Hwf' := wf_write_var _ Hw.
    have [|vm2 [] ]:= Hc _ _ _ Hic _ Hwf';first by apply: eq_onI Hvm1';SvD.fsetdec.
    rewrite -{1}HX => Hwf2 Hvm2 Hsc'.
    have [vm3 [?? Hsf']] := Hfor _ _ _ Hic HX _ Hwf2 Hvm2.
    by exists vm3;split=>//;apply: EForOne Hsc' Hsf'.
  Qed.

  Lemma array_initP P s ii X : 
    exists vmi, 
      sem P gd s (array_init ii X) {| emem := emem s; evm := vmi |} /\
      forall xt xn,
        let x := {|vtype := xt; vname := xn |} in
        vmi.[x] = 
          if Sv.mem x X then
            match xt return exec (sem_t xt)with
            | sarr n => ok (Array.empty n)
            | t      => (evm s).[{|vtype := t; vname := xn|}]
            end
          else (evm s).[x].
  Proof.
    have [vmi [H1 H2]]: exists vmi, 
      sem P gd s (array_init ii X) {| emem := emem s; evm := vmi |} /\
      forall xt xn,
        let x := {|vtype := xt; vname := xn |} in
        vmi.[x] = 
          if  List.existsb (SvD.F.eqb {| vtype := xt; vname := xn |}) (Sv.elements X) then
            match xt return exec (sem_t xt)with
            | sarr n => ok (Array.empty n)
            | t      => (evm s).[{|vtype := t; vname := xn|}]
            end
          else (evm s).[x];last first.
    + by exists vmi;split=>//= xt xn;rewrite H2 SvD.F.elements_b.    
    case: s => mem;rewrite /array_init Sv.fold_spec.
    set F := (fun (a:cmd) (e:Sv.elt) => _).
    have Hcat : forall l c, List.fold_left F l c = List.fold_left F l [::] ++ c.
    + elim => [ | x l Hrec ] c //=;rewrite Hrec (Hrec (F [::] x)) -catA;f_equal.
      by case: x => [[] ].
    elim: (Sv.elements X) => //=.
    + by move=> vm;exists vm;split;[constructor |].
    move=> x0 l Hrec vm.
    have [vm' [H1 H2]]:= Hrec vm.
    case: x0 => [[||n|] xn0];rewrite /F /=.
    + exists vm';split=> //.
      move=> xt xn';rewrite H2; case: ifP => Hin;first by rewrite orbT.
      rewrite orbF;case:ifPn=> //;rewrite /SvD.F.eqb.
      by case: SvD.F.eq_dec => // -[->].
    + exists vm';split=> //.
      move=> xt xn';rewrite H2; case: ifP => Hin;first by rewrite orbT.
      rewrite orbF;case:ifPn=> //;rewrite /SvD.F.eqb.
      by case: SvD.F.eq_dec => // -[->].
    + exists vm'.[{| vtype := sarr n; vname := xn0 |} <- ok (Array.empty n)];split.
      + rewrite Hcat;apply: (sem_app H1);apply:sem_seq1;constructor;constructor => /=.
        rewrite /write_var /set_var /=;case: CEDecStype.pos_dec (@CEDecStype.pos_dec_r n n) => //=.
        + by move=> a;case a.
        by move=> b /(_ b (refl_equal _)) /eqP.
      rewrite /SvD.F.eqb=> xt xn.
      case:  SvD.F.eq_dec => /= [ [-> ->]| ];first by rewrite Fv.setP_eq.
      by move=> /eqP;rewrite eq_sym => neq;rewrite Fv.setP_neq // H2.
    exists vm';split=> //.
    move=> xt xn';rewrite H2; case: ifP => Hin;first by rewrite orbT.
    rewrite orbF;case:ifPn=> //;rewrite /SvD.F.eqb.
    by case: SvD.F.eq_dec => // -[->].
  Qed.

  Local Lemma Hcall s1 m2 s2 ii xs fn args vargs vs:
    sem_pexprs gd s1 args = Ok error vargs ->
    sem_call p gd (emem s1) fn vargs m2 vs ->
    Pfun (emem s1) fn vargs m2 vs ->
    write_lvals gd {| emem := m2; evm := evm s1 |} xs vs = Ok error s2 ->
    Pi_r s1 (Ccall ii xs fn args) s2.
  Proof.
    case:s1 => sm1 svm1 /= Hes Hsc Hfun Hw ii' X1 X2 c' /=;case:ii;last first.
    + move=> [<- <-] vm1 Hwf1 Hvm1. 
      have [|vm2 /= [Hvm2 Hxs]]:= write_lvals_eq_on _ Hw Hvm1.
      + by rewrite read_i_call;SvD.fsetdec.
      exists vm2;split.
      + by apply: wf_write_lvals Hxs.
      + by apply: eq_onI Hvm2;rewrite read_i_call;SvD.fsetdec.
      apply sem_seq1;constructor;eapply Ecall;eauto.
      symmetry;rewrite -Hes;apply read_es_eq_on with Sv.empty.
      by apply: eq_onI Hvm1;rewrite read_esE read_i_call;SvD.fsetdec.
    apply: rbindP => fd' /get_funP Hfd'.
    have [fd [Hfd Hinline]] := inline_progP uniq_funname Hp Hfd'.
    apply: rbindP => -[];apply:rbindP => -[];apply: add_infunP => Hcheckf.
    sinversion Hfun. move: H;rewrite Hfd' => -[?];subst f.
    have [s1' [vm2' [Hwv Hbody Hvs]]]:= CheckAllocReg.alloc_funP_eq Hcheckf H0 H1 H2 H3. 
    move=> /=;case: ifP => //= Hdisj _ [<- <-] vm1 Hwf1.
    move=> {H0 H1 H2 Hfd' Hfd Hcheckf Hsc Hinline}.
    move: Hdisj;rewrite read_i_call.
    move: Hvs Hwv Hbody;set rfd := rename_fd _ _ => Hvs Hwv Hbody Hdisjoint Hvm1.
    rewrite (write_vars_lvals gd) in Hwv.
    have [||/= vm1' [Wvm1' Uvm1']]:= @writes_uincl gd _ _ vm1 _ vargs vargs _ _ Hwv.
    + by apply wf_vm_uincl. + by apply List_Forall2_refl.
    have [vmi [/=Svmi Evmi]]  := 
      array_initP p' {| emem := emem s1'; evm := vm1' |} ii' (locals (rfd fd')).
    have Uvmi : vm_uincl (evm s1') vmi.
    + move=> [zt zn];rewrite Evmi;case:ifPn => // /Sv_memP.
      rewrite /locals /locals_p !vrvs_recE;have := Uvm1' {| vtype := zt; vname := zn |}.
      by case: zt => //= n _ Hin; rewrite -(vrvsP Hwv) //; SvD.fsetdec.
    have [/=vm3 [Hsem' Uvm3]]:= sem_uincl Uvmi Hbody.
    have [/=vs' [Hvs' /(is_full_array_uincls H3) Uvs]]:= get_vars_uincl Uvm3 Hvs;subst vs'.
    move=> {Hvs Hbody Hwv}.
    have Heqvm : svm1 =[Sv.union (read_rvs xs) X2] vm3.
    + apply eq_onT with vm1;first by apply: eq_onI Hvm1;SvD.fsetdec.
      apply eq_onT with vm1'.
      + apply: disjoint_eq_ons Wvm1'.
        move: Hdisjoint;rewrite /disjoint /is_true !Sv.is_empty_spec. 
        by rewrite /locals_p vrvs_recE;SvD.fsetdec.
      apply eq_onT with vmi.
      + move=> [zt zn] Hin;rewrite Evmi;case:ifP => // /Sv_memP.
        move: Hdisjoint;rewrite /disjoint /locals /is_true !Sv.is_empty_spec => Hdisjoint Zin.
        by SvD.fsetdec.
      move=> z Hz;apply (writeP Hsem').
      move: Hdisjoint;rewrite /disjoint /is_true /locals /locals_p !Sv.is_empty_spec.
      by rewrite vrvs_recE read_cE write_c_recE ;SvD.fsetdec.
    have [|vm4 [/= Hvm4 Hw']]:= write_lvals_eq_on _ Hw Heqvm;first by SvD.fsetdec.
    exists vm4;split.
    + apply: wf_write_lvals Hw';apply: (wf_sem Hsem') => -[xt xn].
      have /(_ Hwf1 {|vtype := xt; vname := xn |}) /=:= wf_write_lvals _ Wvm1'.
      by rewrite Evmi;case:ifPn => //;case: xt.
    + by apply: eq_onI Hvm4;SvD.fsetdec.
    apply sem_app with {| emem := emem s1'; evm := vm1' |}.
    + apply: assgn_tuple_Lvar Wvm1'.
      + by move: Hdisjoint;rewrite /disjoint /is_true !Sv.is_empty_spec /locals /locals_p vrvs_recE;SvD.fsetdec.
      have /read_es_eq_on -/(_ gd sm1) <- // : svm1 =[read_es args] vm1.
      by apply: eq_onI Hvm1;SvD.fsetdec.
    apply: (sem_app Svmi); apply: (sem_app Hsem');apply: assgn_tuple_Pvar Hw' => //.
    move: Hdisjoint;rewrite /disjoint /is_true !Sv.is_empty_spec.
    by rewrite /locals /locals_p vrvs_recE read_cE write_c_recE;SvD.fsetdec.
  Qed.

  Local Lemma Hproc m1 m2 fn fd vargs s1 vm2 vres: 
    get_fundef p fn = Some fd ->
    write_vars (f_params fd) vargs {| emem := m1; evm := vmap0 |} = ok s1 ->
    sem p gd s1 (f_body fd) {| emem := m2; evm := vm2 |} ->
    Pc s1 (f_body fd) {| emem := m2; evm := vm2 |} ->
    mapM (fun x : var_i => get_var vm2 x) (f_res fd) = ok vres ->
    List.Forall is_full_array vres -> 
    Pfun m1 fn vargs m2 vres.
  Proof.
    move=> Hget Hw Hsem Hc Hres Hfull.
    have [fd' [Hfd]{Hget}] := inline_progP' uniq_funname Hp Hget.
    case: fd Hw Hsem Hc Hres => /= fi fx fc fxr Hw Hsem Hc Hres.
    apply: rbindP => -[X fc'] /Hc{Hc} -/(_ (evm s1)) [] => //.
    + by apply: wf_write_vars Hw;apply wf_vmap0.
    move=> vm1 /= [Hwf1 Heq Hsem'] [?];subst fd'=> {Hsem}.
    case: s1 Hw Hsem' => /= sm1 svm1 Hw Hsem'.
    apply: (EcallRun Hfd Hw Hsem')=>//=.
    have /= <- := @sem_pexprs_get_var gd (Estate m2 vm1).
    have <- := @read_es_eq_on gd _ Sv.empty m2 _ _ Heq.
    by rewrite sem_pexprs_get_var.
  Qed.

  Lemma inline_callP f mem mem' va vr:
    sem_call p gd mem f va mem' vr ->
    sem_call p' gd mem f va mem' vr.
  Proof.
    apply (@sem_call_Ind p gd Pc Pi_r Pi Pfor Pfun Hskip Hcons HmkI Hassgn Hopn
             Hif_true Hif_false Hwhile_true Hwhile_false Hfor Hfor_nil Hfor_cons Hcall Hproc).
  Qed.

End PROOF.

Lemma inline_call_errP p p' gd f mem mem' va vr:
  inline_prog_err inline_var rename_fd p = ok p' ->
  sem_call p gd mem f va mem' vr ->
  sem_call p' gd mem f va mem' vr.
Proof.
  rewrite /inline_prog_err;case:ifP => //= Hu Hi.
  apply: (inline_callP Hu Hi).
Qed.

End INLINE.

Section REMOVE_INIT.

  Variable p : prog.
  Variable gd : glob_defs.

  Definition p' := remove_init_prog p.

  Let Pi s1 (i:instr) s2 :=  
    forall vm1,
      vm_uincl (evm s1) vm1 -> wf_vm vm1 ->
      exists vm2, 
       [/\ sem p' gd (Estate (emem s1) vm1) (remove_init_i i) (Estate (emem s2) vm2),
           vm_uincl (evm s2) vm2 &
           wf_vm vm2].

  Let Pi_r s1 (i:instr_r) s2 := forall ii, Pi s1 (MkI ii i) s2.

  Let Pc s1 (c:cmd) s2 :=  
    forall vm1,
      vm_uincl (evm s1) vm1 -> wf_vm vm1 ->
      exists vm2, 
        [/\ sem p' gd (Estate (emem s1) vm1) (remove_init_c c) (Estate (emem s2) vm2),
            vm_uincl (evm s2) vm2 & 
            wf_vm vm2].

  Let Pfor (i:var_i) vs s1 c s2 :=
    forall vm1,
      vm_uincl (evm s1) vm1 -> wf_vm vm1 ->
      exists vm2, 
        [/\ sem_for p' gd i vs (Estate (emem s1) vm1) (remove_init_c c) (Estate (emem s2) vm2),
            vm_uincl (evm s2) vm2 & 
             wf_vm vm2].

  Let Pfun (mem:Memory.mem) fn vargs (mem':Memory.mem) vres :=
    forall vargs',
    List.Forall2 value_uincl vargs vargs' ->
    sem_call p' gd mem fn vargs' mem' vres.

  Local Lemma Rnil s : @Pc s [::] s.
  Proof. by move=> vm1 Hvm1;exists vm1;split=> //;constructor. Qed.
  
  Local Lemma Rcons s1 s2 s3 i c :
    sem_I p gd s1 i s2 -> Pi s1 i s2 ->
    sem p gd s2 c s3 -> Pc s2 c s3 -> Pc s1 (i :: c) s3.
  Proof.
    move=> _ Hi _ Hc vm1 Hvm1 /(Hi _ Hvm1)  [vm2 []] Hsi Hvm2 /(Hc _ Hvm2) [vm3 []] Hsc ??.
    by exists vm3;split=>//=; apply: sem_app Hsc.
  Qed.
  
  Local Lemma RmkI ii i s1 s2 : sem_i p gd s1 i s2 -> Pi_r s1 i s2 -> Pi s1 (MkI ii i) s2.
  Proof. by move=> _ Hi vm1 Hvm1 /(Hi ii _ Hvm1) [vm2 []] Hsi ??;exists vm2. Qed.
  
  Lemma is_array_initP e : is_array_init e -> exists e1, e = Papp1 Oarr_init e1.
  Proof. by case e => // -[] //= e1 _;exists e1. Qed.

  Local Lemma Rasgn s1 s2 x tag e :
    Let v := sem_pexpr gd s1 e in write_lval gd x v s1 = ok s2 ->
    Pi_r s1 (Cassgn x tag e) s2.
  Proof.
    move=> Hs2 ii vm1 Hvm1;apply:rbindP Hs2 => z /=. 
    case: ifP.
    + move=> /is_array_initP => -[e1 ?];subst e => /=.
      apply: rbindP => v1 He1; apply: rbindP => -[ | n | ] //=.
      move=> Hn [?];subst z; case: x => [vi t | [[xt xn] xi] | x e | x e] /=.
      + by move=> /write_noneP [->];exists vm1;split=> //;constructor.
      + apply: rbindP => vm1';apply: on_vuP => //=.
        + case: xt => //= p0 t;case: CEDecStype.pos_dec => // heq;case heq => /= -[] ?? [] ? Wf1;subst t vm1' s2 p0.
          exists vm1;split => //=;first by constructor.
          move=> z;have := Hvm1 z.
          case: ({| vtype := sarr n; vname := xn |} =P z) => [<- _ | /eqP neq].
          + rewrite Fv.setP_eq;have := Wf1 {| vtype := sarr n; vname := xn |}.
            case: (vm1.[_]) => //= [a _ i v | []//].
            by move=> H; have := Array.getP_empty H.
          by rewrite Fv.setP_neq.
        by rewrite /of_val;case:xt => //= ?; case: CEDecStype.pos_dec.
      + by t_xrbindP.
      by apply: on_arr_varP => ????; t_xrbindP.
    move=> _ /(sem_pexpr_uincl Hvm1) [] z' [] Hz' Hz /= /(write_uincl Hvm1 Hz) [vm2 []] Hw ?;exists vm2;split=> //.
    + by apply sem_seq1;constructor;constructor;rewrite Hz' /= Hw.
    by apply: wf_write_lval Hw.
  Qed.
  
  Local Lemma Ropn s1 s2 o xs es:
    Let x := Let x := sem_pexprs gd s1 es in sem_sopn o x in
    write_lvals gd s1 xs x = ok s2 -> Pi_r s1 (Copn xs o es) s2.
  Proof.
    move=> H ii vm1 Hvm1; move: H;t_xrbindP => rs vs.
    move=> /(sem_pexprs_uincl Hvm1) [] vs' [] H1 H2.
    move=> /(vuincl_sem_opn H2) [] rs' [] H3 H4.
    move=> /(writes_uincl Hvm1 H4) [] vm2 [] Hw ?. 
    exists vm2;split => //=;last by apply: wf_write_lvals Hw.
    by apply sem_seq1;constructor;constructor;rewrite H1 /= H3.
  Qed.
  
  Local Lemma Rif_true s1 s2 e c1 c2 :
    Let x := sem_pexpr gd s1 e in to_bool x = ok true ->
    sem p gd s1 c1 s2 -> Pc s1 c1 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    move=> H _ Hc ii vm1 Hvm1;apply: rbindP H => v.
    move=> /(sem_pexpr_uincl Hvm1) [] v' [] H1 H2.
    move=> /(value_uincl_bool H2) [] ?? Hwf;subst.
    have [vm2 [??]]:= Hc _ Hvm1 Hwf;exists vm2;split=>//.
    by apply sem_seq1;constructor;apply Eif_true;rewrite // H1.
  Qed.
  
  Local Lemma Rif_false s1 s2 e c1 c2 :
    Let x := sem_pexpr gd s1 e in to_bool x = ok false ->
    sem p gd s1 c2 s2 -> Pc s1 c2 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    move=> H _ Hc ii vm1 Hvm1;apply: rbindP H => v.
    move=> /(sem_pexpr_uincl Hvm1) [] v' [] H1 H2.
    move=> /(value_uincl_bool H2) [] ?? Hwf;subst.
    have [vm2 [??]]:= Hc _ Hvm1 Hwf;exists vm2;split=>//.
    by apply sem_seq1;constructor;apply Eif_false;rewrite // H1.
  Qed.
  
  Local Lemma Rwhile_true s1 s2 s3 s4 c e c' :
    sem p gd s1 c s2 -> Pc s1 c s2 ->
    Let x := sem_pexpr gd s2 e in to_bool x = ok true ->
    sem p gd s2 c' s3 -> Pc s2 c' s3 ->
    sem_i p gd s3 (Cwhile c e c') s4 -> Pi_r s3 (Cwhile c e c') s4 -> Pi_r s1 (Cwhile c e c') s4.
  Proof.
    move=> _ Hc H _ Hc' _ Hw ii vm1 Hvm1 Hwf;apply: rbindP H => v.
    have [vm2 [Hs2 Hvm2 Hwf2]] := Hc _ Hvm1 Hwf.
    move=> /(sem_pexpr_uincl Hvm2) [] v' [] H1 H2.
    move=> /(value_uincl_bool H2) [] ??;subst.
    have [vm3 [H4 Hvm3 ]]:= Hc' _ Hvm2 Hwf2.
    move=> /(Hw ii _ Hvm3)  [vm4 [Hsem ??]]; exists vm4;split => //=.
    apply sem_seq1;constructor;eapply Ewhile_true;eauto;first by rewrite H1.
    by move: Hsem => /= H;sinversion H;sinversion H8;sinversion H6.
  Qed.
  
  Local Lemma Rwhile_false s1 s2 c e c' :
    sem p gd s1 c s2 -> Pc s1 c s2 ->
    Let x := sem_pexpr gd s2 e in to_bool x = ok false ->
    Pi_r s1 (Cwhile c e c') s2.
  Proof.
    move=> _ Hc H ii vm1 Hvm1 Hwf; apply: rbindP H => v.
    have [vm2 [Hs2 Hvm2 Hwf2]] := Hc _ Hvm1 Hwf.
    move=> /(sem_pexpr_uincl Hvm2) [] v' [] H1 H2.
    move=> /(value_uincl_bool H2) [] ??;subst.
    by exists vm2;split=> //=;apply sem_seq1;constructor;apply: Ewhile_false=> //;rewrite H1.
  Qed.
  
  Local Lemma Rfor s1 s2 (i : var_i) d lo hi c (vlo vhi : Z) :
    Let x := sem_pexpr gd s1 lo in to_int x = ok vlo ->
    Let x := sem_pexpr gd s1 hi in to_int x = ok vhi ->
    sem_for p gd i (wrange d vlo vhi) s1 c s2 ->
    Pfor i (wrange d vlo vhi) s1 c s2 ->
    Pi_r s1 (Cfor i (d, lo, hi) c) s2.
  Proof.
    move=> H H' _ Hfor ii vm1 Hvm1 Hwf;apply: rbindP H => ?.
    move=> /(sem_pexpr_uincl Hvm1) [] ? [] H1 H2.
    move=> /(value_uincl_int H2) [] ??;subst.
    apply: rbindP H' => ?.
    move=> /(sem_pexpr_uincl Hvm1) [] ? [] H3 H4.
    move=> /(value_uincl_int H4) [] ??;subst.
    have [vm2 []???]:= Hfor _ Hvm1 Hwf; exists vm2;split=>//=.
    by apply sem_seq1;constructor; econstructor;eauto;rewrite ?H1 ?H3.
  Qed.
  
  Local Lemma Rfor_nil s i c : Pfor i [::] s c s.
  Proof. by move=> vm1 Hvm1;exists vm1;split=> //;constructor. Qed.
  
  Local Lemma Rfor_cons s1 s1' s2 s3 (i : var_i) (w : Z) (ws : seq Z) c :
    write_var i w s1 = ok s1' ->
    sem p gd s1' c s2 -> Pc s1' c s2 ->
    sem_for p gd i ws s2 c s3 -> Pfor i ws s2 c s3 -> Pfor i (w :: ws) s1 c s3.
  Proof.
    move=> Hi _ Hc _ Hf vm1 Hvm1 Hwf.
    have [vm1' [Hi' /Hc]] := write_var_uincl Hvm1 (value_uincl_refl _) Hi.
    have /(_ Hwf) /= Hwf' := wf_write_var _ Hi'.
    move=> /(_ Hwf') [vm2 [Hsc /Hf H /H]] [vm3 [Hsf Hvm3]];exists vm3;split => //.
    by econstructor;eauto.
  Qed.
  
  Local Lemma Rcall s1 m2 s2 ii xs fn args vargs vs :
    sem_pexprs gd s1 args = ok vargs ->
    sem_call p gd (emem s1) fn vargs m2 vs ->
    Pfun (emem s1) fn vargs m2 vs ->
    write_lvals gd {| emem := m2; evm := evm s1 |} xs vs = ok s2 ->
    Pi_r s1 (Ccall ii xs fn args) s2.
  Proof.
    move=> Hargs Hcall Hfd Hxs ii' vm1 Hvm1 Hwf.
    have [vargs' [Hsa /Hfd Hc]]:= sem_pexprs_uincl Hvm1 Hargs.
    have Hvm1' : vm_uincl (evm {| emem := m2; evm := evm s1 |}) vm1 by done.
    have [vm2' [Hw ?]]:= writes_uincl Hvm1' (List_Forall2_refl vs value_uincl_refl) Hxs.
    exists vm2';split=>//=. 
    + by apply: sem_seq1;constructor; econstructor;eauto.
    by apply: wf_write_lvals Hw.
  Qed.
  
  Local Lemma Rproc m1 m2 fn fd vargs s1 vm2 vres:
    get_fundef p fn = Some fd ->
    write_vars (f_params fd) vargs {| emem := m1; evm := vmap0 |} = ok s1 ->
    sem p gd s1 (f_body fd) {| emem := m2; evm := vm2 |} ->
    Pc s1 (f_body fd) {| emem := m2; evm := vm2 |} ->
    mapM (fun x : var_i => get_var vm2 x) (f_res fd) = ok vres ->
    List.Forall is_full_array vres ->
    Pfun m1 fn vargs m2 vres.
  Proof.
    move=> Hget Hargs Hsem Hrec Hmap Hfull vargs' Uargs.
    have [vm1 [Hargs' Hvm1]]:= write_vars_uincl (vm_uincl_refl _) Uargs Hargs.
    have /(_ wf_vmap0) /= Hwf1 := wf_write_vars _ Hargs'.
    have [vm2' /= [] Hsem' Uvm2 Hwf2]:= Hrec _ Hvm1 Hwf1.
    have [vs2 [Hvs2]] := get_vars_uincl Uvm2 Hmap.
    move=> /(is_full_array_uincls Hfull) ?;subst.
    eapply EcallRun with (f := remove_init_fd fd);eauto.
    by rewrite /p' /remove_init_prog get_map_prog Hget.
  Qed.
   
  Lemma remove_init_fdP f mem mem' va vr:
    sem_call p gd mem f va mem' vr ->
    sem_call p' gd mem f va mem' vr.
  Proof.
    move=> /(@sem_call_Ind p gd Pc Pi_r Pi Pfor Pfun Rnil Rcons RmkI Rasgn Ropn
             Rif_true Rif_false Rwhile_true Rwhile_false Rfor Rfor_nil Rfor_cons Rcall Rproc) H.
    by apply H;apply List_Forall2_refl.
  Qed.

End REMOVE_INIT.
