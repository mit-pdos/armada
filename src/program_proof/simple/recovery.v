From RecordUpdate Require Import RecordSet.
Import RecordSetNotations.

From Perennial.algebra Require Import deletable_heap liftable auth_map.
From Perennial.Helpers Require Import Transitions.
From Perennial.program_proof Require Import proof_prelude.

From Goose.github_com.mit_pdos.goose_nfsd Require Import simple.
From Perennial.program_proof Require Import txn.txn_proof marshal_proof addr_proof crash_lockmap_proof addr.addr_proof buf.buf_proof.
From Perennial.program_proof Require Import buftxn.sep_buftxn_proof buftxn.sep_buftxn_recovery_proof.
From Perennial.program_proof Require Import proof_prelude.
From Perennial.program_proof Require Import disk_lib.
From Perennial.Helpers Require Import NamedProps Map List range_set.
From Perennial.algebra Require Import log_heap.
From Perennial.program_logic Require Import spec_assert.
From Perennial.goose_lang.lib Require Import slice.typed_slice into_val.
From Perennial.program_proof.simple Require Import spec invariant common.
From Perennial.goose_lang Require Import crash_modality.

Section stable.
Context `{!heapG Σ}.
Context `{!gen_heapPreG u64 bool Σ}.
Context `{!simpleG Σ}.

Global Instance is_inode_stable_set_stable γsrc γ':
    IntoCrash ([∗ set] a ∈ covered_inodes, is_inode_stable γsrc γ' a)
              (λ _, ([∗ set] a ∈ covered_inodes, is_inode_stable γsrc γ' a))%I.
Proof. rewrite /IntoCrash. iApply post_crash_nodep. Qed.

Global Instance is_txn_durable_stable γ dinit logm:
    IntoCrash (is_txn_durable γ dinit logm) (λ _, is_txn_durable γ dinit logm).
Proof.
  rewrite /IntoCrash. iNamed 1.
  iDestruct (post_crash_nodep with "Hlogm") as "Hlogm".
  iDestruct (post_crash_nodep with "Hasync_ctx") as "Hasync_ctx".
  iCrash. rewrite /is_txn_durable. iFrame.
Qed.

Lemma is_source_into_crash P P' γsrc:
  (∀ σ, P σ -∗ post_crash (λ hG, P' hG σ)) -∗
  is_source P γsrc -∗ post_crash (λ hG, is_source (P' hG) γsrc).
Proof.
  iIntros "HPwand Hsrc".
  iNamed "Hsrc".
  iDestruct (post_crash_nodep with "Hnooverflow") as "-#Hnooverflow'".
  iDestruct (post_crash_nodep with "Hsrcheap") as "Hsrcheap".
  iDestruct ("HPwand" with "[$]") as "HP".
  iCrash. iExists _. iFrame. eauto.
Qed.

End stable.

Section heap.
Context `{!heapG Σ}.
Context `{!gen_heapPreG u64 bool Σ}.
Context `{!simpleG Σ}.
Implicit Types (stk:stuckness) (E: coPset).

Context (P1 : SimpleNFS.State → iProp Σ).
Context (P2 : SimpleNFS.State → iProp Σ).

Lemma is_source_later_upd P P' γsrc:
  (∀ σ, ▷ P σ -∗ |C={⊤ ∖ ↑N}_10=> ▷ P σ ∗ ▷ P' σ) -∗
   ▷ is_source P γsrc -∗
   |C={⊤}_10=> ▷ is_source P' γsrc.
Proof.
  iIntros "Hwand H". iDestruct "H" as (?) "(>?&>%&>#?&?)".
  iSpecialize ("Hwand" with "[$]").
  iMod (cfupd_weaken_all with "Hwand") as "(HP1&HP2)"; auto.
  iModIntro.
  iNext. iExists _. iFrame "# ∗ %".
Qed.

Lemma crash_upd_src γsrc γ' src:
  dom (gset u64) src = covered_inodes →
  ("Hlmcrash" ∷ ([∗ set] y ∈ covered_inodes, is_inode_stable γsrc γ' y) ∗
  "Hsrcheap" ∷ map_ctx γsrc 1 src) ==∗
  ∃ γsrc',
  map_ctx γsrc 1 src ∗
  map_ctx γsrc' 1 src ∗
  [∗ set] y ∈ covered_inodes, is_inode_stable γsrc' γ' y.
Proof.
  iIntros (Hdom) "H". iNamed "H".
  iMod (map_init ∅) as (γsrc') "H".
  iMod (map_alloc_many src with "H") as "(Hctx&Hmapsto)".
  { intros. rewrite lookup_empty //=. }
  rewrite right_id_L.
  iModIntro. iExists γsrc'.
  rewrite -Hdom -?big_sepM_dom.
  iFrame "Hctx".
  iCombine "Hmapsto Hlmcrash" as "H".
  rewrite -big_sepM_sep.
  iApply (big_sepM_mono_with_inv with "Hsrcheap H").
  iIntros (k v Hlookup) "(Hctx&src&Hstable)".
  iNamed "Hstable".
  iDestruct (map_valid with "[$] [$]") as %Heq.
  subst. iFrame. iExists _. iFrame. rewrite /named. iExactEq "src". f_equal. congruence.
Qed.

Definition fs_cfupd_cancel dinit P :=
  (<disc> (|C={⊤}_10=>
    ∃ γ γsrc logm',
    is_txn_durable γ dinit logm' ∗
    ▷ is_source P γsrc ∗
    [∗ set] a ∈ covered_inodes, is_inode_stable γsrc γ a))%I.

Theorem wpc_Recover γ γsrc (d : loc) dinit logm :
  {{{
    <disc> (∀ σ, ▷ P1 σ -∗ |C={⊤ ∖ ↑N}_10=> ▷ P1 σ ∗ ▷ P2 σ) ∗
    is_txn_durable γ dinit logm ∗
    ▷ is_source P1 γsrc ∗
    [∗ set] a ∈ covered_inodes, is_inode_stable γsrc γ a
  }}}
    Recover #d @ 10; ⊤
  {{{ γsimp nfs, RET #nfs;
      is_fs P1 γsimp nfs dinit ∗ fs_cfupd_cancel dinit P2 }}}
  {{{
    ∃ γ' γsrc' logm',
    is_txn_durable γ' dinit logm' ∗
    ▷ is_source P2 γsrc' ∗
    [∗ set] a ∈ covered_inodes, is_inode_stable γsrc' γ' a
  }}}.
Proof using All.
  iIntros (Φ Φc) "(Hshift & Htxndurable & Hsrc & Hstable) HΦ".
  iMod (fupd_later_to_disc with "Hsrc") as "Hsrc".
  rewrite /Recover.
  iApply wpc_cfupd.
  wpc_pures.
  { iDestruct "HΦ" as "[HΦc _]". iModIntro.
    iMod (is_source_later_upd P1 P2 with "Hshift Hsrc") as "Hsrc".
    iModIntro. iApply "HΦc".
    iExists _, _, _. iFrame. }

  wpc_apply (wpc_MkTxn Nbuftxn with "Htxndurable").
  { solve_ndisj. }
  { solve_ndisj. }

  iSplit.
  { iDestruct "HΦ" as "[HΦc _]". iModIntro. iIntros "H".
    iDestruct "H" as (γ' logm') "(%Hkinds & Htxndurable)".
    iDestruct "Htxndurable" as "(Hdurable&[%Heq|#Hexch])".
    { subst.
      iMod (is_source_later_upd P1 P2 with "[$] Hsrc") as "Hsrc".
      iModIntro. iApply "HΦc". iExists _, _, _.
      iFrame. }
    iMod (big_sepS_impl_cfupd with "Hstable []") as "Hcrash".
    { iModIntro. iIntros (x Hx) "H".
      iApply (is_inode_stable_crash with "[$] H").
    }
    iMod (is_source_later_upd P1 P2 with "[$] Hsrc") as "Hsrc".
    iModIntro.
    iApply "HΦc".
    iExists _, _, _. iFrame.
  }

  iModIntro.
  iIntros (γ' l) "(#Histxn & #Htxnsys & Hcfupdcancel & #Htxncrash)".

  wpc_pures.
  { iDestruct "HΦ" as "[HΦc _]". iModIntro.
    iMod (big_sepS_impl_cfupd with "Hstable []") as "Hcrash".
    { iModIntro. iIntros (x Hx) "H".
      iMod (is_inode_stable_crash with "Htxncrash H") as "H".
      iModIntro. iExact "H". }
    iMod "Hcfupdcancel" as ">Hcfupdcancel".
    iMod (is_source_later_upd P1 P2 with "[$] Hsrc") as "Hsrc".
    iModIntro.
    iApply "HΦc".
    iDestruct "Hcfupdcancel" as (?) "H".
    iExists _, _, _. iFrame.
  }

  wpc_apply (wpc_MkLockMap _ covered_inodes (is_inode_stable γsrc γ) (is_inode_stable γsrc γ') with "[Hstable]").
  { iApply (big_sepS_impl with "Hstable").
    iModIntro.
    iIntros (a Ha) "H". iFrame.
    iModIntro. iIntros ">Hstable".
    iMod (is_inode_stable_crash with "Htxncrash Hstable") as "Hstable".
    iModIntro. done. }

  iSplit.
  { iDestruct "HΦ" as "[HΦc _]". iModIntro. iIntros "H".
    rewrite -big_sepS_later.
    iDestruct "H" as ">H".
    iMod "Hcfupdcancel" as ">Hcfupdcancel".
    iDestruct "Hcfupdcancel" as (?) "Hcfupdcancel".
    iMod (is_source_later_upd P1 P2 with "[$] Hsrc") as "Hsrc".
    iModIntro.
    iApply "HΦc".
    iExists _, _, _. iFrame.
  }

  iModIntro.
  iIntros (lm ghs) "[#Hlm Hlmcrash]".

  iMod (own_disc_fupd_elim with "Hsrc") as "Hsrc".
  iMod (inv_alloc N with "Hsrc") as "#Hsrc".

  iApply wp_wpc_frame'.
  iSplitL "Hlmcrash Hcfupdcancel HΦ Hsrc Hshift".
  {
    iAssert (fs_cfupd_cancel dinit P2)%I with "[-HΦ]" as "Hcancel".
    { iModIntro.
      rewrite -big_sepS_later.
      iMod "Hlmcrash" as ">Hlmcrash". iMod "Hcfupdcancel" as ">Hcfupdcancel".
      iIntros "#HC".
      iInv "Hsrc" as "Hopen" "Hclose".
      iDestruct "Hopen" as (?) "(>Hsrcheap&>%Hdom&>#Hnooverflow&HP)".
      iMod (crash_upd_src with "[$]") as (γsrc') "(Hsrcheap&Hsrcheap'&Hlmcrash)".
      { eauto. }
      iMod ("Hshift" with "HP HC") as "(HP1&HP2)".
      iMod ("Hclose" with "[HP1 Hsrcheap]") as "_".
      { iNext. iExists _. iFrame "# ∗ %". }
      iDestruct "Hcfupdcancel" as (?) "?".
      iExists γ', γsrc', _. iFrame.
      iModIntro. iNext. iExists _. iFrame "# ∗ %".
    }
    iSplit.
    { iDestruct "HΦ" as "[HΦc _]". iModIntro. iMod ("Hcancel"). iModIntro. by iApply "HΦc". }
    { iNamedAccu. }
  }

  wp_apply wp_allocStruct; first by eauto.
  iIntros (nfs) "Hnfs".

  iDestruct (struct_fields_split with "Hnfs") as "Hnfs". iNamed "Hnfs".
  iMod (readonly_alloc_1 with "t") as "#Ht".
  iMod (readonly_alloc_1 with "l") as "#Hl".

  iAssert (is_fs P1 (Build_simple_names γ γ' γsrc ghs) nfs dinit) with "[]" as "Hfs".
  { iExists _, _. iFrame "Ht Hl Histxn Htxnsys Htxncrash Hlm Hsrc". }
  wp_pures. iNamed 1.
  iRight in "HΦ". iApply "HΦ". iFrame "# ∗".
Qed.

End heap.