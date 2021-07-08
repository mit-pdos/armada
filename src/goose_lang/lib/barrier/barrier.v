From iris.algebra Require Import auth gset.
From Perennial.program_logic Require Export weakestpre crash_weakestpre.
From Perennial.base_logic Require Import invariants lib.saved_prop lib.ghost_map.
From Perennial.goose_lang Require Export lang.
From Perennial.goose_lang Require Export lang typing.
From Perennial.goose_lang Require Import proofmode wpc_proofmode notation crash_borrow.
From Perennial.goose_lang Require Export notation typing.
From Perennial.goose_lang.lib Require Export barrier.impl.
Set Default Proof Using "Type".

(** The CMRAs/functors we need. *)
Class barrierG Σ := BarrierG {
  barrier_inG :> ghost_mapG Σ nat (gname * gname);
  barrier_savedPropG :> savedPropG Σ;
}.
Definition barrierΣ : gFunctors :=
  #[ ghost_mapΣ nat (gname * gname); savedPropΣ ].

Instance subG_barrierΣ {Σ} : subG barrierΣ Σ → barrierG Σ.
Proof. solve_inG. Qed.

(** Now we come to the Iris part of the proof. *)
Section goose_lang.
Context `{ffi_sem: ffi_semantics}.
Context `{!ffi_interp ffi}.
Context {ext_tys: ext_types ext}.

Local Coercion Var' (s:string): expr := Var s.
Section proof.
  Context `{!heapGS Σ}.
  Context `{!stagedG Σ, !barrierG Σ}.

Definition N := nroot.@"mynamespace".
Search crash_borrow.

Lemma crash_borrow_crash_wand P Pc:
  crash_borrow P Pc -∗ □ (P -∗ Pc).
Proof. iDestruct 1 as (??) "($&_)". Qed.

Definition barrier_inv (l : loc) (γ : gname) (P : iProp Σ) (Pc : iProp Σ) : iProp Σ :=
  (∃ (b : bool) (gmm : gmap nat (gname * gname)) (fprop fcprop : gname → iProp Σ),
    l ↦ #b ∗
    ghost_map_auth γ 1 gmm ∗
    ([∗ map] i ↦ γsp ∈ fst <$> gmm, saved_prop_own γsp (fprop γsp)) ∗
    ([∗ map] i ↦ γsp ∈ snd <$> gmm, saved_prop_own γsp (fcprop γsp)) ∗
     (([∗ map] i ↦ γspp ∈ gmm, □ (fprop (fst γspp) -∗ fcprop (snd γspp)))) ∗
    if b then
      crash_borrow ([∗ map] i ↦ γsp ∈ fst <$> gmm, fprop γsp)
                   ([∗ map] i ↦ γsp ∈ snd <$> gmm, fcprop γsp)
    else
      crash_borrow True%I True%I ∗
      □ (P -∗ ([∗ map] i ↦ γsp ∈ fst <$> gmm, fprop γsp)) ∗
      □ (([∗ map] i ↦ γsp ∈ snd <$> gmm, fcprop γsp) -∗ Pc)).


Definition recv (l : loc) (R Rc : iProp Σ) : iProp Σ :=
  (∃ γ i P Pc R' Rc' γsp γspc,
    inv N (barrier_inv l γ P Pc) ∗
    ▷ (R' -∗ R) ∗
    ▷ (Rc -∗ Rc') ∗
    ▷ □ (R -∗ Rc) ∗
    i  ↪[γ] (γsp, γspc) ∗
    saved_prop_own γsp R' ∗
    saved_prop_own γspc Rc')%I.

Definition send (l : loc) (P Pc : iProp Σ) : iProp Σ :=
  (∃ γ, □ (P -∗ Pc) ∗ inv N (barrier_inv l γ P Pc))%I.

(** Setoids *)
Instance barrier_inv_ne l γ : NonExpansive2 (barrier_inv l γ).
Proof. solve_proper. Qed.
Global Instance send_ne l : NonExpansive2 (send l).
Proof. solve_proper. Qed.
Global Instance recv_ne l : NonExpansive2 (recv l).
Proof. solve_proper. Qed.

(** Actual proofs *)
Lemma newbarrier_spec (P Pc : iProp Σ) :
  {{{ □ (P -∗ Pc) }}} barrier.newbarrier #() {{{ l, RET #l; recv l P Pc ∗ send l P Pc }}}.
Proof.
  iIntros (Φ) "#Hwand HΦ". wp_lam.
  iApply wp_fupd.
  iApply (wpc_wp _ 0 _ _ _ True%I).
  iApply (wpc_crash_borrow_init_ctx _ _ _ _ _ True%I True%I id); auto.
  iSplit; first done.
  iIntros "Hc".
  iApply (wpc_crash_mono _ _ _ _ _ _ True%I); first eauto.
  iApply wp_wpc.
  wp_apply wp_alloc_untyped; auto.
  iIntros (l) "Hl". simpl.
  iApply (wpc_crash_mono _ _ _ _ _ _ True%I); first eauto.
  iApply wp_wpc.
  wp_pures.
  iApply ("HΦ" with "[> -]").
  iMod (saved_prop_alloc P) as (γsp) "#Hsp".
  iMod (saved_prop_alloc Pc) as (γspc) "#Hspc".
  iMod (ghost_map_alloc ({[O := (γsp, γspc)]})) as (γ) "[Hauth Hkeys]".
  iMod (inv_alloc N _ (barrier_inv l γ P Pc) with "[Hl Hauth Hc]") as "#Hinv".
  { iExists false,({[O := (γsp, γspc)]}),
            (λ x, if decide (x = γsp) then P else True%I),
            (λ x, if decide (x = γspc) then Pc else True%I).
    iFrame "Hl Hauth Hc".
    iNext.
    iSplit.
    { rewrite big_sepM_fmap big_sepM_singleton. rewrite decide_True //. }
    iSplit.
    { rewrite big_sepM_fmap big_sepM_singleton. rewrite decide_True //. }
    iSplit.
    { rewrite big_sepM_singleton. rewrite ?decide_True //. }
    iSplit.
    { rewrite big_sepM_fmap big_sepM_singleton. rewrite decide_True //. auto. }
    { rewrite big_sepM_fmap big_sepM_singleton. rewrite decide_True //. auto. }
  }
  iModIntro; iSplitL "Hkeys".
  - iExists γ, O, P, Pc, P, Pc, γsp, γspc. iFrame "∗ #".
    rewrite big_sepM_singleton. iFrame.
    iSplitL; eauto.
  - iExists γ. eauto.
Qed.

Lemma signal_spec l P Pc Φ Φc k K `{!LanguageCtx K}:
  send l P Pc -∗
  P -∗
  Φc ∧ (∀ (b: bool), WPC K (of_val #b) @ NotStuck; k; ⊤ {{ Φ }} {{ Φc }}) -∗
  WPC K (barrier.signal #l) @ NotStuck ; k ; ⊤ {{ Φ }} {{ Φc ∗ Pc }}.
Proof.
  iIntros "Hs HP HK".
  iAssert (□ (P -∗ Pc))%I with "[Hs]" as "#Hcwand".
  { iDestruct "Hs" as (?) "($&_)". }
  iApply (wpc_crash_borrow_init_ctx' with "HP"); auto.
  iSplit.
  { by iLeft in "HK". }
  iIntros "Hcb".
  iCache with "HK".
  { by iLeft in "HK". }
  wpc_frame.
  iDestruct "Hs" as (γ) "(_&#Hinv)". wp_lam.
  wp_bind (CmpXchg _ _ _).
  iInv N as ([] gmm fprop fcprop) "(>Hl & H● & Hfprop & Hfcprop & HRs)".
  { wp_cmpxchg_fail. iModIntro. iSplitR "".
    { iExists true, gmm, fprop, fcprop. iFrame. }
    wp_pures. iModIntro. iIntros "(_&HK)". by iApply "HK".
  }
  iDestruct "HRs" as "(#Hcrash&Hcb'&#HP&#HPc)".
  iApply (wpc_wp _ 0 _ _ _ True%I).
  iApply (wpc_crash_borrow_combine _ _ _ _ _
            ([∗ map] _ ↦ γsp ∈ fst <$> gmm, (fprop γsp))
            ([∗ map] _ ↦ γsp ∈ snd <$> gmm, (fcprop γsp))
            with "[$Hcb] [$Hcb'] [] [] []").
  { auto. }
  { iNext. iModIntro. iIntros "H".
    rewrite ?big_sepM_fmap.
    iApply (big_sepM_wand with "H []").
    { simpl. iApply (big_sepM_mono with "Hcrash"). iIntros (???) "H". iApply "H". }
  }
  { iNext. iIntros "H"; iSplit; last done.
    by iApply "HPc".
  }
  { iNext. iIntros "(HP'&HQ')".
    iApply "HP". eauto. }
  iApply wp_wpc.
  wp_cmpxchg_suc.
  iModIntro. iIntros "Hcb". iSplit; first eauto.
  iModIntro.
  iSplitR "".
  { iNext. iExists _, gmm, _, _. iFrame. eauto. }
  wp_pures. iModIntro. iIntros "(_&HK)". iApply "HK".
Qed.

Lemma wait_spec l P Pc:
  {{{ recv l P Pc }}} barrier.wait #l {{{ RET #(); crash_borrow P Pc }}}.
Proof.
  rename P into R.
  rename Pc into Rc.
  iIntros (Φ) "HR HΦ".
  iDestruct "HR" as (γ i P Pc R' Rc' γsp γspc) "(#Hinv & HR & HRc & #HcrashR & H◯ & #Hsp & #Hspc)".
  iLöb as "IH". wp_rec. wp_bind (! _)%E.
  iInv N as ([] gmm fprop fcprop) "(>Hl & >H● & HRs)"; last first.
  {
    iApply (wp_load with "[$]").
    iNext. iIntros "Hl".
    iModIntro. iSplitL "Hl H● HRs".
    { iExists false, gmm, fprop, fcprop. iFrame. }
    wp_pures. by wp_apply ("IH" with "[$] [$] [$] [$]"). }
  iDestruct "HRs" as "(#Hsaved&#Hsavedc&#Hcrash&Hcb)".
  iDestruct (ghost_map_lookup with "[$] [$]") as %Hin.
  iMod (ghost_map_delete with "[$] [$]") as "H●".
  iAssert (▷▷ (fcprop γspc ≡ Rc'))%I as "Hcequiv".
  { iNext.
    iDestruct (big_sepM_delete _ _ i with "Hsavedc") as "[Hthis _]".
    { rewrite lookup_fmap Hin //. }
    iDestruct (saved_prop_agree with "Hthis Hspc") as "Hequiv". eauto. }
  iAssert (▷▷ (fprop γsp ≡ R'))%I as "Hequiv".
  { iNext.
    iDestruct (big_sepM_delete _ _ i with "Hsaved") as "[Hthis _]".
    { rewrite lookup_fmap Hin //. }
    iDestruct (saved_prop_agree with "Hthis Hsp") as "Hequiv". eauto. }

  iApply (wpc_wp _ 0 _ _ _ True%I).
  iApply (wpc_crash_borrow_split' _ _ _ _ _ _ _
            ([∗ map] _ ↦ γsp ∈ fst <$> delete i gmm, (fprop γsp))
            R
            ([∗ map] _ ↦ γsp ∈ snd <$> delete i gmm, (fcprop γsp))
            Rc
            with "[$Hcb] [HR] [] [] [HRc]"); first done.
  { do 2 iNext. iIntros "HRs".
    iDestruct (big_sepM_delete _ _ i with "HRs") as "[HR'' HRs]".
    { rewrite lookup_fmap Hin //. }
    rewrite fmap_delete.
    iFrame. iApply "HR". iRewrite -"Hequiv". eauto. }
  { do 2 iNext. iModIntro.
    rewrite ?big_sepM_fmap.
    iIntros "H".
    iApply (big_sepM_wand with "H []").
    iDestruct (big_sepM_delete _ _ i with "Hcrash") as "[_ Hcrash']"; eauto.
    iApply (big_sepM_mono with "Hcrash'"). iIntros (???) "H". iApply "H".
  }
  { eauto. }
  { do 2 iNext. iIntros "(HRs&HRc')".
    rewrite ?big_sepM_fmap.
    iApply big_sepM_delete; eauto; iFrame.
    simpl. iRewrite "Hcequiv". iApply "HRc". eauto. }

  iApply wp_wpc.
  iApply (wp_load with "[$]").
  iNext. iIntros "Hl (Hcb1&Hcb2)".
  iSplit; first done.
  iModIntro.
  iSplitR "HΦ Hcb2".
  { iNext. iExists true, (delete i gmm), fprop, fcprop. iFrame.
    iDestruct (big_sepM_delete _ _ i with "Hcrash") as "[_ $]"; eauto.
    rewrite ?big_sepM_fmap.
    iDestruct (big_sepM_delete _ _ i with "Hsaved") as "[_ $]"; eauto.
    iDestruct (big_sepM_delete _ _ i with "Hsavedc") as "[_ $]"; eauto.
 }

  wp_pures. iModIntro. iApply "HΦ". eauto.
Qed.

Lemma recv_split E l P1 P2 Pc1 Pc2 :
  ↑N ⊆ E →
  □ (P1 -∗ Pc1) -∗
  □ (P2 -∗ Pc2) -∗
  recv l (P1 ∗ P2) (Pc1 ∗ Pc2) ={E}=∗ recv l P1 Pc1 ∗ recv l P2 Pc2.
Proof.
  rename P1 into R1; rename P2 into R2.
  rename Pc1 into Rc1; rename Pc2 into Rc2.
  iIntros (?) "#Hw1 #Hw2".
  iDestruct 1 as (γ i P Pc R' Rc' γsp γspc) "(#Hinv & HR & HRc & Hcrash & H◯ & #Hsp & #Hspc)".
  iInv N as (b gmm fprop fcprop) "(>Hl & >H● & HRs)".
  iDestruct (ghost_map_lookup with "[$] [$]") as %Hin.
  iMod (ghost_map_delete with "[$] [$]") as "H●".
  iMod (saved_prop_alloc R1) as (γsp1) "#Hsp1".
  iMod (saved_prop_alloc_cofinite ({[ γsp1 ]}) R2)
    as (γsp2 ?%not_elem_of_singleton) "#Hsp2".
  iMod (saved_prop_alloc Rc1) as (γspc1) "#Hspc1".
  iMod (saved_prop_alloc_cofinite ({[ γspc1 ]}) Rc2)
    as (γspc2 ?%not_elem_of_singleton) "#Hspc2".
  assert (∃ i1, i1 ∉ dom (gset _) (delete i gmm)) as (i1&Hnotin1).
  { exists (fresh (dom (gset _) (delete i gmm))). apply is_fresh. }
  assert (∃ i2, i2 ∉ {[i1]} ∪ (dom (gset _) (delete i gmm))) as (i2&Hnotin2).
  { exists (fresh ({[i1]} ∪ (dom (gset _) (delete i gmm)))). apply is_fresh. }
  iMod (ghost_map_insert i1 (γsp1, γspc1) with "[$]") as "(H●&Hkey1)".
  { apply not_elem_of_dom. auto. }
  iMod (ghost_map_insert i2 (γsp2, γspc2) with "[$]") as "(H●&Hkey2)".
  { apply not_elem_of_dom. rewrite dom_insert_L. auto. }
  iModIntro. iSplitL "HR Hl HRs H●".
  { iModIntro.
    iExists b, _, (λ x, if (decide (x = γsp1)) then R1 else
                        if (decide (x = γsp2)) then R2 else
                          fprop x),
                  (λ x, if (decide (x = γspc1)) then Rc1 else
                        if (decide (x = γspc2)) then Rc2 else
                          fcprop x).
    iFrame.
    iDestruct "HRs" as "(#Hs1&#Hs2&#Hc1&HRs)".
    iSplit.
    { iEval (rewrite big_sepM_fmap).
      rewrite big_sepM_insert //=; last first.
      { apply not_elem_of_dom. rewrite dom_insert_L. auto. }
      rewrite big_sepM_insert //=; last first.
      { apply not_elem_of_dom. auto. }
      iSplit.
      { repeat (destruct (decide _)); subst; eauto; try congruence. }
      iSplit.
      { repeat (destruct (decide _)); subst; eauto; try congruence. }
      rewrite big_sepM_fmap.
      iDestruct (big_sepM_delete _ _ i with "Hs1") as "[_ Hs1']"; eauto.
      rewrite ?big_sepM_forall.
      iIntros.
      repeat (destruct (decide _)); subst; eauto; try congruence.
      { iApply "Hs1'". eauto. }
    }
    iSplit.
    { iEval (rewrite big_sepM_fmap).
      rewrite big_sepM_insert //=; last first.
      { apply not_elem_of_dom. rewrite dom_insert_L. auto. }
      rewrite big_sepM_insert //=; last first.
      { apply not_elem_of_dom. auto. }
      iSplit.
      { repeat (destruct (decide _)); subst; eauto; try congruence. }
      iSplit.
      { repeat (destruct (decide _)); subst; eauto; try congruence. }
      rewrite ?big_sepM_fmap.
      iDestruct (big_sepM_delete _ _ i with "Hs2") as "[_ Hs2']"; eauto.
      rewrite ?big_sepM_forall.
      iIntros.
      repeat (destruct (decide _)); subst; eauto; try congruence.
      { iApply "Hs2'". eauto. }
    }
    iSplit.
    {
      rewrite big_sepM_insert //=; last first.
      { apply not_elem_of_dom. rewrite dom_insert_L. auto. }
      rewrite big_sepM_insert //=; last first.
      { apply not_elem_of_dom. auto. }
      iSplit.
      { repeat (destruct (decide _)); subst; eauto; try congruence. }
      iSplit.
      { repeat (destruct (decide _)); subst; eauto; try congruence. }
      rewrite ?big_sepM_fmap.
      iDestruct (big_sepM_delete _ _ i with "Hc1") as "[_ Hc1']"; eauto.
      rewrite ?big_sepM_forall.
      iIntros.
      admit.
      (* Need to pick saved prop names freshly with codomain of gmm *)
      (*
      repeat (destruct (decide _)); subst; eauto; try congruence.
      { admit.  }
      { admit.  }
       *)
    }
    destruct b.
    - iApply (crash_borrow_conseq with "[HR] [] [] HRs").
      { iEval (rewrite ?big_sepM_fmap).
      rewrite ?big_sepM_insert //=; last first.
      { apply not_elem_of_dom. rewrite dom_insert_L. auto. }
      { apply not_elem_of_dom. auto. }
      { apply not_elem_of_dom. rewrite dom_insert_L. auto. }
      { apply not_elem_of_dom. auto. }

      iModIntro.
      repeat (destruct (decide _)); subst; try congruence.
      iIntros "(H2&H1&Hm)".
      iSplitL "H2".
      { iApply "Hw2". eauto. }
      iSplitL "H1".
      { iApply "Hw1". eauto. }
      iApply (big_sepM_mono with "Hm").
      iIntros. simpl.
      (* same issue *)
      admit.
      }
Qed.

Lemma recv_weaken l P1 P2 : (P1 -∗ P2) -∗ recv l P1 -∗ recv l P2.
Proof.
  iIntros "HP". iDestruct 1 as (γ P R' i) "(#Hinv & HR & H◯)".
  iExists γ, P, R', i. iIntros "{$Hinv $H◯} !> HQ". iApply "HP". by iApply "HR".
Qed.

End proof.

End goose_lang.

Typeclasses Opaque send recv.
