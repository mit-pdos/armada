From Goose.github_com.mit_pdos.perennial_examples Require Import alloc.
From Perennial.program_proof Require Import proof_prelude.
From Perennial.goose_lang.lib Require Export typed_slice into_val.
From Perennial.program_proof.examples Require Export range_set.

Instance unit_IntoVal : IntoVal ().
Proof.
  refine {| to_val := λ _, #();
            IntoVal_def := ();
         |}.
  intros [] [] _; auto.
Defined.

Instance unit_IntoValForType : IntoValForType unit_IntoVal (struct.t unit.S).
Proof.
  constructor; auto.
Qed.

Section goose.
Context `{!heapG Σ}.

Implicit Types (m: gmap u64 ()) (addrs: gset u64).

Definition is_addrset (m_ref: loc) addrs: iProp Σ :=
  ∃ m, is_map m_ref m ∗ ⌜dom (gset _) m = addrs⌝.

Lemma rangeSet_append_one:
  ∀ start sz : u64,
    int.val start + int.val sz < 2 ^ 64
    → ∀ i : u64,
      int.val i < int.val (word.add start sz)
      → int.val start ≤ int.val i
      → {[i]} ∪ rangeSet (int.val start) (int.val i - int.val start) =
        rangeSet (int.val start) (int.val i - int.val start + 1).
Proof.
  intros start sz Hbound i Hibound Hilower_bound.
  replace (int.val (word.add start sz)) with (int.val start + int.val sz) in Hibound by word.
  apply gset_eq; intros.
  rewrite elem_of_union.
  rewrite elem_of_singleton.
  rewrite !rangeSet_lookup; try word.
  destruct (decide (x = i)); subst.
  - split; intros; eauto.
    word.
  - intuition; try word.
    right.
    assert (int.val x ≠ int.val i) by (apply not_inj; auto).
    word.
Qed.

Theorem wp_freeRange (start sz: u64) :
  int.val start + int.val sz < 2^64 ->
  {{{ True }}}
    freeRange #start #sz
  {{{ (mref: loc), RET #mref;
      is_addrset mref (rangeSet (int.val start) (int.val sz)) }}}.
Proof.
  iIntros (Hbound Φ) "_ HΦ".
  wp_call.
  wp_apply (wp_NewMap () (t:=struct.t unit.S)).
  iIntros (mref) "Hmap".
  wp_apply wp_ref_to; first by val_ty.
  iIntros (il) "i".
  wp_pures.
  wp_apply (wp_forUpto (λ i, "%Hilower_bound" ∷ ⌜int.val start ≤ int.val i⌝ ∗
                             "*" ∷ ∃ m, "Hmap" ∷ is_map mref m ∗
                                        "%Hmapdom" ∷ ⌜dom (gset _) m = rangeSet (int.val start) (int.val i - int.val start)⌝)%I
            with "[] [Hmap $i]").
  - word.

  - clear Φ.
    iIntros (i).
    iIntros "!>" (Φ) "(HI & i & %Hibound) HΦ"; iNamed "HI".
    wp_pures.
    wp_load.
    wp_apply (wp_MapInsert _ _ _ _ () with "Hmap"); auto.
    iIntros "Hm".
    wp_pures.
    iApply "HΦ".
    iFrame.
    iSplitR.
    { iPureIntro; word. }
    rewrite /named.
    iExists _; iFrame.
    iPureIntro.
    rewrite /map_insert dom_insert_L.
    rewrite Hmapdom.
    replace (int.val (word.add i 1) - int.val start) with ((int.val i - int.val start) + 1) by word.
    eapply rangeSet_append_one; eauto.

  - iSplitR; auto.
    rewrite -> rangeSet_diag by word.
    iExists _; iFrame.
    rewrite dom_empty_L; auto.
  - iIntros "(HI&Hil)"; iNamed "HI".
    wp_pures.
    iApply "HΦ"; iFrame.
    iExists _; iFrame.
    iPureIntro; auto.
    rewrite Hmapdom.
    repeat (f_equal; try word).
Qed.

Lemma big_sepM_lookup_unit (PROP:bi) `{Countable K}
  `{BiAffine PROP} (m: gmap K ()) :
  ⊢@{PROP} [∗ map] k↦_ ∈ m, ⌜m !! k = Some tt⌝.
Proof.
  iDestruct (big_sepM_lookup_holds m) as "Hmap".
  iApply (big_sepM_mono with "Hmap"); simpl; intros.
  destruct x; auto.
Qed.

(* this is superceded by wp_findKey, but that theorem relies in an unproven map
iteration theorem *)
Theorem wp_findKey' mref m :
  {{{ is_map mref m }}}
    findKey #mref
  {{{ (k: u64) (ok: bool), RET (#k, #ok);
      ⌜if ok then m !! k = Some tt else True⌝ ∗ (* TODO: easier if this
      promises to find a key if it exists *)
      is_map mref m
  }}}.
Proof.
  iIntros (Φ) "Hmap HΦ".
  wp_call.
  wp_apply wp_ref_to; first by val_ty.
  iIntros (found_l) "found".
  wp_apply wp_ref_to; first by val_ty.
  iIntros (ok_l) "ok".
  wp_pures.
  wp_apply (wp_MapIter _ _ _ _
                       (∃ (found: u64) (ok: bool),
                           "found" ∷ found_l ↦[uint64T] #found ∗
                           "ok" ∷ ok_l ↦[boolT] #ok ∗
                           "%Hfound_is" ∷ ⌜if ok then m !! found = Some tt else True⌝)
                       (λ k _, ⌜m !! k = Some tt⌝)%I
                       (λ _ _, True)%I
                       with "Hmap [found ok]").
  - iExists _, _; iFrame.
  - iApply big_sepM_lookup_unit.
  - iIntros (k v) "!>".
    clear Φ.
    iIntros (Φ) "[HI %Helem] HΦ"; iNamed "HI".
    wp_pures.
    wp_load.
    wp_pures.
    wp_if_destruct.
    + wp_store. wp_store.
      iApply "HΦ".
      iSplitL; auto.
      iExists _, _; iFrame.
      auto.
    + iApply "HΦ".
      iSplitL; auto.
      iExists _, _; iFrame.
      apply negb_false_iff in Heqb; subst.
      auto.
  - iIntros "(His_map&HI&_HQ)"; iNamed "HI".
    wp_pures.
    wp_load. wp_load.
    wp_pures.
    iApply "HΦ"; iFrame.
    auto.
Qed.

Theorem wp_findKey mref free :
  {{{ is_addrset mref free }}}
    findKey #mref
  {{{ (k: u64) (ok: bool), RET (#k, #ok);
      ⌜if ok then k ∈ free else free = ∅⌝ ∗
      is_addrset mref free
  }}}.
Proof.
  iIntros (Φ) "Hmap HΦ".
  wp_call.
  wp_apply wp_ref_to; first by val_ty.
  iIntros (found_l) "found".
  wp_apply wp_ref_to; first by val_ty.
  iIntros (ok_l) "ok".
  wp_pures.
  iDestruct "Hmap" as (m) "[Hmap %Hmapdom]".
  wp_apply (wp_MapIter_fold _ _ (λ mdone, ∃ (found: u64) (ok: bool),
                           "found" ∷ found_l ↦[uint64T] #found ∗
                           "ok" ∷ ok_l ↦[boolT] #ok ∗
                           "%Hfound_is" ∷ ⌜if ok then m !! found = Some tt else mdone = ∅⌝)%I
           with "Hmap [found ok]").
  - iExists _, _; by iFrame.
  - clear Φ.
    iIntros (mdone k v) "!>".
    iIntros (Φ) "(HI&(%&%)) HΦ"; iNamed "HI".
    wp_pures.
    wp_load.
    wp_pures.
    wp_if_destruct;
      (* TODO: automate this in wp_if_destruct *)
      [ apply negb_true_iff in Heqb | apply negb_false_iff in Heqb ]; subst.
    + wp_store. wp_store.
      iApply "HΦ".
      iExists _, _; iFrame.
      destruct v; auto.
    + iApply "HΦ".
      iExists _, _; iFrame.
      auto.
  - iIntros "[Hm HI]"; iNamed "HI".
    wp_load. wp_load.
    wp_pures.
    iApply "HΦ".
    destruct ok.
    + iSplitR.
      { iPureIntro.
        rewrite -Hmapdom.
        apply elem_of_dom; eauto. }
      iExists _; iFrame "% ∗".
    + iSplitR.
      { iPureIntro.
        rewrite -Hmapdom; subst.
        rewrite dom_empty_L //. }
      iExists _; iFrame "% ∗".
Qed.

Theorem wp_mapRemove m_ref remove_ref free remove :
  {{{ is_addrset m_ref free ∗ is_addrset remove_ref remove }}}
    mapRemove #m_ref #remove_ref
  {{{ RET #(); is_addrset m_ref (free ∖ remove) ∗ is_addrset remove_ref remove }}}.
Proof.
  iIntros (Φ) "[His_free His_remove] HΦ".
  rewrite /mapRemove.
  wp_pures.
  iDestruct "His_remove" as (m) "[His_remove %Hdom]".
  wp_apply (wp_MapIter_2 _ _ _ _
                         (λ mtodo mdone, is_addrset m_ref (free ∖ dom (gset _) mdone))
              with "His_remove [His_free] [] [HΦ]").
  - rewrite dom_empty_L.
    rewrite difference_empty_L.
    iFrame.

  - clear Hdom m Φ.
    iIntros (k [] mtodo mdone) "!>".
    iIntros (Φ) "[His_free %Hin] HΦ".
    wp_call.
    iDestruct "His_free" as (m) "[His_free %Hdom]".
    wp_apply (wp_MapDelete with "His_free").
    iIntros "Hm".
    iApply "HΦ".
    iExists _; iFrame.
    iPureIntro.
    rewrite /map_del dom_delete_L.
    set_solver.
  - iIntros "[Hremove Hfree]".
    iApply "HΦ".
    rewrite Hdom.
    iFrame.
    iExists _; iFrame "% ∗".
Qed.

Theorem wp_SetAdd mref used addr_s q (addrs: list u64) :
  {{{ is_addrset mref used ∗ is_slice_small addr_s uint64T q addrs }}}
    SetAdd #mref (slice_val addr_s)
  {{{ RET #(); is_addrset mref (used ∪ list_to_set addrs) ∗
               is_slice_small addr_s uint64T q addrs }}}.
Proof.
  iIntros (Φ) "(Hused&Haddrs) HΦ".
  rewrite /SetAdd; wp_pures.
  wp_apply (wp_forSlicePrefix (λ done todo, is_addrset mref (used ∪ list_to_set done))
                              with "[] [Hused $Haddrs]").

  - clear Φ.
    iIntros (i a done _) "!>".
    iIntros (Φ) "Hused HΦ".
    wp_pures.
    iDestruct "Hused" as (m) "[Hused %Hdom]".
    wp_apply (wp_MapInsert _ _ _ _ () with "Hused").
    { auto. }
    iIntros "Hm".
    iApply "HΦ".
    iExists _; iFrame.
    iPureIntro.
    rewrite /map_insert dom_insert_L.
    set_solver.
  - simpl.
    iExactEq "Hused".
    f_equal.
    set_solver.
  - iIntros "[Hs Haddrs]".
    iApply "HΦ"; iFrame.
Qed.

End goose.