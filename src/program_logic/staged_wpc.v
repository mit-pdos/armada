From iris.proofmode Require Import base tactics classes.
From Perennial.Helpers Require Import ipm.
From iris.algebra Require Import excl numbers.
From iris.base_logic Require Export invariants.
From iris.program_logic Require Export weakestpre.
From Perennial.program_logic Require Import staged_invariant crash_weakestpre.
Set Default Proof Using "Type".
Import uPred.

Section staged_inv_wpc.
Context `{!irisG Λ Σ}.
Context `{!stagedG Σ}.
Context `{!crashG Σ}.
Context `{inG Σ (exclR unitO)}.
Implicit Types s : stuckness.
Implicit Types P : iProp Σ.
Implicit Types Φ : val Λ → iProp Σ.
Implicit Types Φc : iProp Σ.
Implicit Types v : val Λ.
Implicit Types e : expr Λ.

Lemma staged_inv_init_cfupd' γ k k' N1 N2 E1 P:
  k' ≤ k →
  N1 ## N2 →
  ↑N1 ⊆ E1 →
  ↑N2 ⊆ E1 →
  staged_inv (S k') N1 N2 (E1 ∖ ↑N1 ∖ ↑N2) γ P ∗
  staged_pending 1%Qp γ -∗
  (<disc> |C={E1, ∅}_(S k)=> P).
Proof.
  iIntros (Hle Hdisj Hin1 Hin2)  "(#Hinv&Hpending)".
  iModIntro. iIntros "HC".
  iPoseProof (staged_inv_weak_open E1 k' N1 N2 (E1 ∖ ↑N1 ∖ ↑N2) with "[Hinv $Hpending $HC]") as "H"; auto.
  iMod (fupd_level_le with "H") as "HP"; first by lia.
  do 2 iModIntro. auto.
Qed.

Lemma wpc_staged_inv_init' γ s k k' N1 N2 E1 E2 e Φ Φc P:
  k' ≤ k →
  N1 ## N2 →
  ↑N1 ⊆ E1 →
  ↑N2 ⊆ E1 →
  staged_inv (S k') N1 N2 (E1 ∖ ↑N1 ∖ ↑N2) γ P ∗
  staged_pending 1%Qp γ ∗
  WPC e @ s; (S k); E1; E2 {{ Φ }} {{ Φc }} ⊢
  WPC e @ s; (S k); E1; E2 {{ Φ }} {{ Φc ∗ P }}.
Proof.
  iIntros (Hle ?? Hin) "(#Hinv&Hpending&H)".
  iApply (wpc_strong_crash_frame s s _ _ E1 _ _ with "H"); try auto.
  iApply (staged_inv_init_cfupd'); eauto.
Qed.

(* Like staged value, except that it can be opened without getting a later, because
   it says that ▷ of what's stored implies Q *)
Definition staged_value_later k1 k2 N1 N2 E E' γ Q Q' P : iProp Σ :=
  ∃ Q0, (▷ Q0-∗ ◇ Q) ∗
      □ (▷ Q0 -∗ ▷ C -∗ |k2={E' ∖ ↑N1 ∖ ↑N2}=> |k2={∅, ∅}=> ▷ P ∗ ▷ Q') ∗
      staged_value k1 N1 N2 E γ Q0 Q' P.

(* XXX what about stripping the later off Qr? maybe we put one later in the definition of wpc after the viewshifts in the crash condition? *)
(*
Lemma staged_inv_later_open E k k2 N1 N2 E1 γ P Q Qr:
  N1 ## N2 →
  ↑N1 ⊆ E →
  ↑N2 ⊆ E →
  staged_value_later (S k) k2 N1 N2 E1 γ Q Qr P -∗ |(S k)={E,E∖↑N1}=>
  (Q ∗ (∀ Q' Qr' Q0, ▷ Q0 ∗ (▷ Q0-∗ ◇ Q') ∗
   □ (▷ Q0 -∗ |C={E1, ∅}_k=> ▷ P ∗ ▷ Qr') -∗ |(S k)={E∖↑N1,E}=> staged_value_later (S k) k2 N1 N2 E1 γ Q' Qr' P)) ∨
  (▷ Qr ∗ C ∗ |(S k)={E∖↑N1, E}=> staged_value_later (S k) k2 N1 N2 E1 γ Q True P).
Proof.
  iIntros (???) "Hinv".
  iDestruct "Hinv" as (Q0) "(Hwand&Hinv)".
  iMod (staged_inv_open_modify with "Hinv") as "[HQ0|Hcrash]"; auto.
  - iDestruct "HQ0" as "(HQ0&Hclo)".
    iMod ("Hwand" with "HQ0") as "HQ".
    iModIntro. iLeft. iFrame "HQ".
    iIntros (Q' Qr' Q0'). iIntros "(HQ0'&Hwand'&#Hwand'')".
    iMod ("Hclo" $! Q0' Qr' with "[$HQ0' $Hwand'']").
    iModIntro. iExists Q0'; iFrame.
  - iRight. iModIntro. iDestruct "Hcrash" as "($&$&Hfinish)".
    iMod "Hfinish". iModIntro. iExists Q0. by iFrame "# ∗".
Qed.
*)

(* WPC without the other most fupd *)
Definition wpc_no_fupd s k E1 E2 e1 Φ Φc :=
  ((match to_val e1 with
   | Some v => NC -∗ |={E1}=> Φ v ∗ NC
   | None => ∀ σ1 κ κs n,
      state_interp σ1 (κ ++ κs) n -∗ NC -∗ |={E1,∅}=> (
        (⌜if s is NotStuck then reducible e1 σ1 else True⌝ ∗
        ∀ e2 σ2 efs, ⌜prim_step e1 σ1 κ e2 σ2 efs⌝ -∗ |={∅,∅}=> ▷ |={∅,E1}=>
          (state_interp σ2 κs (length efs + n) ∗
          wpc s k E1 E2 e2 Φ Φc ∗
          ([∗ list] i ↦ ef ∈ efs, wpc s k ⊤ E2 ef fork_post True) ∗
          NC)))
   end ∧
   (<disc> |C={E1,E2}_ k => Φc)))%I.

Lemma staged_inv_later_open' E k k2 N1 N2 E1 E2 γ P Q Qr:
  N1 ## N2 →
  ↑N1 ⊆ E →
  ↑N2 ⊆ E →
  staged_value_later (S k) k2 N1 N2 E1 E2 γ Q Qr P -∗ |(S k)={E,E∖↑N1}=>
  (Q ∗ (∀ Q' Qr', ▷ Q' ∗
   □ (▷ Q' -∗ |C={E1, ∅}_k=> P ∗ Qr') -∗ |(S k)={E∖↑N1,E}=> staged_value (S k) N1 N2 E1 γ Q' Qr' P)) ∨
  (▷ Qr ∗ C ∗ |(S k)={E∖↑N1, E}=> staged_value_later (S k) k2 N1 N2 E1 E2 γ Q True P).
Proof.
  iIntros (???) "Hinv".
  iDestruct "Hinv" as (Q0) "(Hwand1&#Hwand2&Hinv)".
  iMod (staged_inv_open_modify with "Hinv") as "[HQ0|Hcrash]"; auto.
  - iDestruct "HQ0" as "(HQ0&Hclo)".
    iMod ("Hwand1" with "HQ0") as "HQ".
    iModIntro. iLeft. iFrame "HQ". eauto.
  - iRight. iModIntro. iDestruct "Hcrash" as "($&$&Hfinish)".
    iMod "Hfinish". iModIntro. iExists Q0. iFrame "# ∗".
    iModIntro. iIntros.
    iMod ("Hwand2" with "[$] [$]") as "H".
    iModIntro.
    iMod ("H") as "($&_)". auto.
Qed.

Lemma wpc_staged_inv_open_aux' γ s k k' k'' E1 E1' E2 e Φ Φc P Q N1 N2 :
  E1 ⊆ E1' →
  N1 ## N2 →
  ↑N1 ⊆ E1 →
  ↑N2 ⊆ E1 →
  (* The level we move to (k'') must be < (S k'), the level of the staged invariant.
     However, it may be the same as (S k), the wpc we were originally proving. Thus,
     no "fuel" is lost except what is needed to be "below" the invariant's universe level *)
  k'' ≤ k' →
  k'' ≤ (S k) →
  NC ∗
  staged_value_later (S k') k'' N1 N2 (E1' ∖ ↑N1 ∖ ↑N2) E1 γ
               (wpc_no_fupd NotStuck k'' (E1 ∖ ↑N1 ∖ ↑N2) ∅ e
                   (λ v, ▷ Q v ∗ ▷ □ (Q v -∗ P) ∗ (staged_value (S k') N1 N2 (E1' ∖ ↑N1 ∖ ↑N2) γ
                                                                (Q v) True (P) -∗ <disc> ▷ Φc ∧ Φ v))%I
                   (Φc ∗ P))
                Φc
                (P)%I
  ⊢ |={E1}=> WPC e @ s; (S k); E1; E2 {{ v, Φ v }} {{Φc}} ∗ NC.
Proof.
  iIntros (???? Hle1 Hle2) "(HNC&Hwp)".
  iLöb as "IH" forall (e).
  destruct (to_val e) as [v|] eqn:Hval.
  {
    iPoseProof (staged_inv_later_open' E1 with "[$]") as "H"; try auto.
    iMod (fupd_level_fupd with "H") as "[(H&Hclo')|Hcrash]"; last first.
    {
      iDestruct "Hcrash" as "(HΦc&HC&Hclo')".
      iDestruct (NC_C with "[$] [$]") as "[]".
    }
    {
      rewrite /wpc_no_fupd.
      rewrite wpc_unfold /wpc_pre.
      rewrite Hval.
      iDestruct "H" as "(H&_)".
      iMod (fupd_intro_mask' _ (E1 ∖ ↑N1 ∖ ↑N2)) as "Hclo"; first by set_solver+.
      iMod ("H" with "[$]") as "((HQ&#HQP&HΦ)&HNC)".
      iMod "Hclo".
      iSpecialize ("Hclo'" $! (Q v)%I True%I with "[HQ]").
      { iFrame. iIntros "!> HQ". iModIntro. iSplitR ""; last done.
        iNext. iApply "HQP"; eauto. }
      iMod (fupd_level_fupd with "Hclo'") as "Hval".
      iModIntro. iSplitR "HNC"; last by iFrame.
      iModIntro.
      iSplit.
      - iIntros "HNC". iDestruct ("HΦ" with "[$]") as "(_&?)". iModIntro. iFrame.
      - iDestruct ("HΦ" with "[$]") as "(HΦ&_)".
        do 2 iModIntro. auto.
    }
  }
  iModIntro.
  iEval (rewrite wpc_unfold /wpc_pre). rewrite Hval.
  iSplitR "HNC"; last by auto.
  iModIntro.
  iSplit; last first.
  {
    rewrite /staged_value_later.
    iDestruct "Hwp" as (?) "(?&#Hwand0&Hwp)".
    iDestruct (staged_value_into_disc with "Hwp") as "Hwp".
    iModIntro. iIntros "HC".
    iMod (staged_inv_disc_open_crash with "[] Hwp HC"); try assumption.
    {
      iModIntro. iIntros "HQC >HC".
      iDestruct ("Hwand0" with "[$] [$]") as "Hwp".
      iMod (fupd_level_intro_mask' _ (E1 ∖ ↑N1 ∖ ↑N2)) as "Hclo"; first by set_solver+.
      iMod (fupd_level_le with "Hwp") as "Hwp"; first lia.
      iMod (fupd_level_intro_mask' _ ∅) as "Hclo'"; first by set_solver+.
      iMod (fupd_level_le with "Hwp") as "(HΦ&HP)"; first lia.
      iMod "Hclo'" as "_".
      iMod "Hclo". do 2 iModIntro. by iFrame.
    }
    iModIntro. iApply (fupd_level_mask_weaken); auto. set_solver.
  }
  iIntros.
  iPoseProof (staged_inv_later_open' E1 with "[$]") as "H"; try assumption.
  iMod (fupd_level_fupd with "H") as "[(Hwp&Hclo')|Hcrash]"; last first.
  {
    iDestruct "Hcrash" as "(HΦc&HC&Hclo')".
    iDestruct (NC_C with "[$] [$]") as "[]".
  }
  iDestruct "Hwp" as "(H&_)".
  rewrite Hval.
  iMod (fupd_intro_mask' _ (E1 ∖ ↑N1 ∖ ↑N2)) as "Hclo"; first by set_solver+.
  iMod ("H" with "[$] [$]") as "(%&H)".
  iSplitL "".
  { by destruct s; auto. }
  iModIntro.
  iIntros. iMod ("H" with "[//]") as "H".
  iModIntro. iNext.
  iMod "H" as "(Hσ&H&Hefs&HNC)".
  iEval (rewrite wpc_unfold /wpc_pre) in "H". iMod "H".
  iDestruct (own_discrete_elim_conj with "H") as (Q_keep Q_inv) "(HQ_keep&HQ_inv&#Hwand1&#Hwand2)".
  iSpecialize ("Hclo'" $! Q_inv Φc with "[HQ_inv]").
  {
    iFrame.
    iIntros "!> HQ". iSpecialize ("Hwand1" with "[$]").
    iMod "Hwand1". iIntros "HC". iSpecialize ("Hwand1" with "[$]").
    iMod (fupd_level_intro_mask' _ (E1 ∖ ↑N1 ∖ ↑N2)) as "Hclo"; first by set_solver.
    iMod (fupd_level_le with "Hwand1") as "Hwand1"; first by lia.
    iMod (fupd_level_intro_mask' _ ∅) as "Hclo'"; first by set_solver.
    iMod (fupd_level_le with "Hwand1") as "(HΦc&HP)"; first by lia.
    iMod "Hclo'". iMod "Hclo". do 2 iModIntro. by iFrame.
  }
  iMod "Hclo" as "_".
  iMod (fupd_level_fupd with "Hclo'") as "H".
  iMod ("IH" with "HNC [H HQ_keep]") as "(Hwp&HNC)".
  { iExists _. iFrame "H".  iSplitL "HQ_keep".
    - iIntros "HQ". iApply "Hwand2"; iFrame.
    - iModIntro. iIntros "HQ >HC". iMod ("Hwand1" with "[$]") as "H".
      iSpecialize ("H" with "[$]").
      iMod "H". iModIntro.
      iMod "H" as "($&$)". eauto.
  }
  iFrame. iModIntro.
  iApply (big_sepL_mono with "Hefs").
  iIntros. iApply (wpc_strong_mono' with "[$]"); eauto.
  { set_solver+. }
  iSplit; first auto. iIntros "!> ?"; eauto.
  iApply fupd_level_mask_weaken; eauto. set_solver+.
Qed.

Lemma wpc_staged_inv_open' γ s k k' k'' E1 E1' E2 e Φ Φc Q Qrest Qnew P N1 N2 :
  E1 ⊆ E1' →
  N1 ## N2 →
  ↑N1 ⊆ E1 →
  ↑N2 ⊆ E1 →
  k'' ≤ k' →
  k'' ≤ (S k) →
  staged_value (S k') N1 N2 (E1' ∖ ↑ N1 ∖ ↑N2) γ Q Qrest P ∗
  (<disc> ▷ Φc ∧
  (▷ Q -∗
   WPC e @ NotStuck; k''; (E1 ∖ ↑N1 ∖ ↑N2); ∅
      {{λ v, ▷ Qnew v ∗
             ▷ □ (Qnew v -∗ P) ∗
            (staged_value (S k') N1 N2 (E1' ∖ ↑ N1 ∖ ↑N2) γ (Qnew v) True P -∗  (<disc> ▷ Φc ∧ Φ v))}}
      {{ Φc ∗ P }}))
  ⊢
  WPC e @ s; (S k); E1; E2 {{ Φ }} {{ Φc }}.
Proof.
  iIntros (??????) "(Hval&Hwp)".
  destruct (to_val e) as [v|] eqn:Hval.
  {
    iPoseProof (staged_inv_open_modify E1 with "Hval") as "H"; try auto.
    rewrite wpc_unfold /wpc_pre. iModIntro.
    rewrite Hval.
    iSplit.
    - iIntros "HNC". iMod (fupd_level_fupd with "H") as "[(H&Hclo')|Hcrash]"; last first.
      {
        iDestruct "Hcrash" as "(HΦc&HC&Hclo')".
        iDestruct (NC_C with "[$] [$]") as "[]".
      }
      iDestruct "Hwp" as "(_&Hwp)".
      iMod (fupd_intro_mask' _ (E1 ∖ ↑N1 ∖ ↑N2)) as "Hclo"; first by set_solver+.
      rewrite wpc_unfold /wpc_pre.
      rewrite Hval.
      iMod ("Hwp" with "[$]") as "(H&_)".
      iMod ("H" with "[$]") as "((HQ&#HQP&Hwand)&$)".
      iMod "Hclo".
      iSpecialize ("Hclo'" $! (Qnew v)%I True%I with "[HQ]").
      { iFrame. iIntros "!> HQ". iModIntro. iSplitR ""; last done.
        iNext. iApply "HQP"; eauto. }
      iMod (fupd_level_fupd with "Hclo'") as "Hval".
      iModIntro. iDestruct ("Hwand" with "[$]") as "(_&$)".
    - iDestruct "Hwp" as "(Hwp&_)". iModIntro. iModIntro. eauto.
    }
  rewrite !wpc_unfold /wpc_pre.
  iModIntro.
  iSplit; last first.
  {
    iDestruct "Hwp" as "(Hwp&_)". do 2 iModIntro. auto.
  }
  rewrite Hval.
  iIntros (????) "Hstate HNC".
  iPoseProof (staged_inv_open_modify with "[$]") as "H"; try eassumption.
  iMod (fupd_level_fupd with "H") as "[(H&Hclo)|Hfalse]"; last first.
  { iDestruct "Hfalse" as "(_&HC&_)".
    iDestruct (NC_C with "[$] [$]") as "[]".
  }
  iDestruct ("Hwp") as "(_&Hwp)".
  iMod (fupd_intro_mask' (E1 ∖ ↑N1) (E1 ∖ ↑N1 ∖ ↑N2)) as "Hclo0"; first by set_solver+.
  iMod ("Hwp" with "[$] [$] [$]") as ">(%&H)".
  iSplitL "".
  { destruct s; eauto. }
  iModIntro. iIntros.
  iMod ("H" with "[//]") as "H".
  iModIntro. iNext.
  iMod "H" as "(Hσ&H&Hefs&HNC)".
  iEval (rewrite wpc_unfold /wpc_pre) in "H". iMod "H".
  iDestruct (own_discrete_elim_conj with "H") as (Q_keep Q_inv) "(HQ_keep&HQ_inv&#Hwand1&#Hwand2)".
  iSpecialize ("Hclo" $! Q_inv Φc with "[HQ_inv]").
  {
    iFrame.
    iIntros "!> HQ". iSpecialize ("Hwand1" with "[$]").
    iMod "Hwand1". iIntros "HC". iSpecialize ("Hwand1" with "[$]").
    iMod (fupd_level_intro_mask' _ (E1 ∖ ↑N1 ∖ ↑N2)) as "Hclo"; first by set_solver.
    iMod (fupd_level_le with "Hwand1") as "Hwand1"; first by lia.
    iMod (fupd_level_intro_mask' _ ∅) as "Hclo'"; first by set_solver.
    iMod (fupd_level_le with "Hwand1") as "(HΦc&HP)"; first by lia.
    iMod "Hclo'". iMod "Hclo". do 2 iModIntro. by iFrame.
  }
  iMod "Hclo0" as "_".
  iMod (fupd_level_fupd with "Hclo") as "H".
  iPoseProof (wpc_staged_inv_open_aux' γ s k k' k'' E1 E1'
                _ e2 Φ Φc P Qnew N1 N2 with "[H HQ_keep HNC]") as "H"; try assumption.
  { iFrame. iExists _. iFrame "H".  iSplitL "HQ_keep".
    - iIntros "HQ". iMod ("Hwand2" with "[$]") as "H". iExact "H".
    - iModIntro. iIntros "HQ >HC". iMod ("Hwand1" with "[$]") as "H".
      iSpecialize ("H" with "[$]").
      iMod "H". iModIntro.
      iMod "H" as "($&$)". eauto.
  }
  iMod "H" as "($&$)".
  iModIntro. iFrame.
  iApply (big_sepL_mono with "Hefs").
  iIntros. iApply (wpc_strong_mono' with "[$]"); eauto.
  - set_solver+.
  - iSplit; first auto. iModIntro. iIntros "H". iApply fupd_level_mask_weaken; eauto; set_solver.
Qed.

(*
Lemma cfupd_big_sepS `{Countable A} (σ: gset A)(P: A → iProp Σ) k E1  :
  ([∗ set] a ∈ σ, |C={E1, ∅}_(LVL k)=> P a) -∗
  |C={E1, ∅}_(LVL (size σ + k))=> ([∗ set] a ∈ σ, P a).
Proof.
  iIntros "H".
  iInduction σ as [| x σ ?] "IH" using set_ind_L.
  - iModIntro. iNext.
    rewrite big_sepS_empty //.
  - rewrite -> !big_sepS_union by set_solver.
    rewrite !big_sepS_singleton.
    iDestruct "H" as "(Hx & Hrest)".
    rewrite size_union; last by set_solver.
    rewrite size_singleton.
    iMod "Hx".
    { simpl.
      rewrite LVL_Sk.
      pose proof (LVL_gt (size σ+k)).
      rewrite LVL_sum_split.
      abstract_pow4. }
    iFrame "Hx".
    iMod ("IH" with "Hrest") as "Hrest".
    { change (1 + size σ + k) with (S (size σ + k)).
      rewrite LVL_Sk.
      pose proof (LVL_gt (size σ + k)).
      pose proof (LVL_le k (size σ + k)).
      nia. }
    iModIntro. iModIntro.
    iFrame.
Qed.

Lemma cfupd_big_sepL_aux {A} (l: list A) (Φ: nat → A → iProp Σ) n k E1 :
  ([∗ list] i↦a ∈ l, |C={E1, ∅}_(LVL k)=> Φ (n + i) a) -∗
  |C={E1, ∅}_(LVL (length l + k))=> ([∗ list] i↦a ∈ l, Φ (n + i) a).
Proof.
  iIntros "H".
  (iInduction l as [| x l] "IH" forall (n)).
  - iModIntro. iNext.
    simpl; auto.
  - rewrite -> !big_sepL_cons by set_solver.
    simpl.
    iDestruct "H" as "(Hx & Hrest)".
    iMod "Hx".
    { simpl.
      rewrite LVL_Sk.
      pose proof (LVL_gt (length l+k)).
      rewrite LVL_sum_split.
      abstract_pow4. }
    iFrame "Hx".
    assert (forall k, n + S k = S n + k) as Harith by lia.
    setoid_rewrite Harith.
    iMod ("IH" with "Hrest") as "Hrest".
    { rewrite LVL_Sk.
      pose proof (LVL_gt (length l + k)).
      pose proof (LVL_le k (length l + k)).
      nia. }
    iModIntro. iModIntro.
    iFrame.
Qed.

Lemma cfupd_big_sepL {A} (l: list A) (Φ: nat → A → iProp Σ) k E1 :
  ([∗ list] i↦a ∈ l, |C={E1, ∅}_(LVL k)=> Φ i a) -∗
  |C={E1, ∅}_(LVL (length l + k))=> ([∗ list] i↦a ∈ l, Φ i a).
Proof. iApply (cfupd_big_sepL_aux _ _ 0). Qed.

Lemma wpc_crash_frame_big_sepS_wand `{Countable A} (σ: gset A)(P: A → iProp Σ) k s E2 e Φ Φc  :
  ([∗ set] a ∈ σ, ∃ k', ⌜ k' ≤ k ⌝ ∗ |C={⊤, ∅}_(LVL k')=> P a) -∗
  WPC e @ s; LVL k; ⊤; E2 {{ Φ }} {{ ([∗ set] a ∈ σ, P a) -∗ Φc }} -∗
  WPC e @ s; LVL (S k + size σ); ⊤; E2 {{ Φ }} {{ Φc }}.
Proof.
  iIntros "Hs Hwpc".
  iDestruct (cfupd_big_sepS with "[Hs]") as "Hs".
  { iApply (big_sepS_mono with "Hs").
    iIntros (x ?) "H".
    iDestruct "H" as (k') "[% H]".
    iApply (cfupd_weaken_all _ (LVL k) with "H"); auto.
    apply LVL_le; auto. }
  simpl.
  iMod "Hs" as "_".
  { lia. }
  iApply (wpc_idx_mono with "Hwpc").
  apply LVL_le; lia.
Qed.

Lemma wpc_staged_inv_init Γ s k k' N E1 E2 e Φ Φc P i :
  k' < k →
  ↑N ⊆ E1 →
  staged_inv Γ N (LVL k') (E1 ∖ ↑N) (E1 ∖ ↑N) ∗
  staged_crash_pending Γ P i ∗
  WPC e @ s; LVL k; E1; E2 {{ Φ }} {{ Φc }} ⊢
  WPC e @ s; LVL (S k); E1; E2 {{ Φ }} {{ Φc ∗ P }}.
Proof.
  rewrite /LVL. iIntros (??) "(?&?&?)".
  replace (base ^ (S (S (S k)))) with (base * (base ^ ((S (S k))))) by auto.
  iApply (wpc_idx_mono _ (2 * base ^ (S (S k)))).
  {  lia. }
  iApply wpc_staged_inv_init''; last first. iFrame; auto.
  - eauto.
  - transitivity (base)%nat; first by auto. replace base with (base^1) by auto. apply Nat.pow_lt_mono_r_iff; eauto => //=. lia.
    lia.
  - apply (lt_le_trans _ (base * (base ^ (S (S k'))))).
    cut (1 < base ^ (S (S k'))); try lia.
    { replace 1 with (base^0) by auto. apply Nat.pow_lt_mono_r_iff; lia. }
    rewrite -PeanoNat.Nat.pow_succ_r'. apply Nat.pow_le_mono_r_iff; lia.
Qed.

Lemma wpc_staged_inv_init_wand Γ s k k' N E1 E2 e Φ Φc P i :
  k' < k →
  ↑N ⊆ E1 →
  staged_inv Γ N (LVL k') (E1 ∖ ↑N) (E1 ∖ ↑N) ∗
  staged_crash_pending Γ P i ∗
  WPC e @ s; LVL k; E1; E2 {{ Φ }} {{ P -∗ Φc }} ⊢
  WPC e @ s; LVL (S k); E1; E2 {{ Φ }} {{ Φc }}.
Proof.
  iIntros (??) "(Hstaged&Hcrash&Hwp)".
  iAssert (WPC e @ s; LVL (S k); E1; E2 {{ Φ }} {{ (P -∗ Φc) ∗ P }})%I with "[-]" as "Hwp"; last first.
  { iApply (wpc_mono with "Hwp"); auto. rewrite wand_elim_l //. }
  by iApply (wpc_staged_inv_init with "[$]").
Qed.

Lemma wpc_staged_inv_open Γ s k k' E1 E1' E2 e Φ Φc Q Qrest Qnew P N b bset :
  E1 ⊆ E1' →
  ↑N ⊆ E1 →
  S k < k' →
  to_val e = None →
  staged_inv Γ N (LVL k') (E1' ∖ ↑N) (E1' ∖ ↑N) ∗
  staged_bundle Γ Q Qrest b bset ∗
  staged_crash Γ P bset ∗
  (Φc ∧ ((Q) -∗ WPC e @ NotStuck; (LVL k); (E1 ∖ ↑N); ∅ {{λ v, ▷ Qnew v ∗ ▷ □ (Qnew v -∗ P) ∗ (staged_bundle Γ (Qnew v) True false bset -∗  (Φc ∧ Φ v))}} {{ Φc ∗ ▷ P }})) ⊢
  WPC e @ s; LVL ((S k)); E1; E2 {{ Φ }} {{ Φc }}.
Proof.
  rewrite /LVL. iIntros (????) "(?&?&?)".
  assert (Hpow: base ^ (S (S (S k))) =  4 * base ^ (S (S k))).
  { rewrite //=. }
  rewrite Hpow.
  iApply (wpc_idx_mono _ (4 * base ^ (S (S k)))).
  { lia. }
  iApply (wpc_staged_inv_open'' with "[$]"); eauto.
  { transitivity (4 * base ^ (S (S k))); first by lia. rewrite -Hpow. apply Nat.pow_le_mono_r_iff; eauto. lia. }
  { transitivity (base)%nat; first lia. replace base with (base^1) at 1; last by auto.
    apply Nat.pow_lt_mono_r_iff; eauto. lia. }
Qed.

Lemma wpc_later' s k E1 E2 e Φ Φc :
  to_val e = None →
  ▷ ▷ WPC e @ s; (LVL k); E1 ; E2 {{ Φ }} {{ Φc }} -∗
  WPC e @ s; (LVL (S k)); E1 ; E2 {{ Φ }} {{ Φc }}.
Proof.
  iIntros (?) "Hwp".
  pose proof (SS_LVL k).
  iApply (wpc_idx_mono with "[Hwp]"); first by eassumption.
  iApply (wpc_later with "[Hwp]"); eauto.
  iNext.
  iApply (wpc_later with "[Hwp]"); eauto.
Qed.

Lemma wpc_later_crash' s k E1 E2 e Φ Φc :
  WPC e @ s; (LVL k); E1 ; E2 {{ Φ }} {{ ▷ ▷ Φc }} -∗
  WPC e @ s; (LVL (S k)); E1 ; E2 {{ Φ }} {{ Φc }}.
Proof.
  iIntros "Hwp".
  pose proof (SS_LVL k).
  iApply (wpc_idx_mono with "[Hwp]"); first by eassumption.
  iApply (wpc_later_crash with "[Hwp]"); eauto.
  iApply (wpc_later_crash with "[Hwp]"); eauto.
Qed.

Lemma wpc_step_fupd' s k E1 E2 e Φ Φc :
  to_val e = None →
  (|={E1}[∅]▷=> WPC e @ s; (LVL k); E1 ; E2 {{ Φ }} {{ Φc }}) -∗
  WPC e @ s; (LVL (S k)); E1 ; E2 {{ Φ }} {{ Φc }}.
Proof.
  iIntros (?) "Hwp".
  specialize (SS_LVL k) => Hlvl.
  assert (S (LVL k) ≤ LVL (S k)) by lia.
  clear Hlvl.
  iApply (wpc_idx_mono with "[Hwp]"); first by eassumption.
  iApply (wpc_step_fupd with "[Hwp]"); eauto.
Qed.

Lemma wpc_step_fupdN_inner3 s k E1 E2 e Φ Φc :
  to_val e = None →
  (|={E1,E1}_3=> WPC e @ s; (LVL k); E1 ; E2 {{ Φ }} {{ Φc }}) -∗
  WPC e @ s; (LVL (S k)); E1 ; E2 {{ Φ }} {{ Φc }}.
Proof.
  iIntros (?) "Hwp".
  specialize (SSS_LVL k) => Hlvl.
  iApply (wpc_idx_mono with "[Hwp]"); first by eassumption.
  replace (S (S (S (LVL k)))) with (3 + LVL k) by lia.
  iApply (wpc_step_fupdN_inner with "[Hwp]"); eauto.
Qed.

Lemma wpc_step_fupdN_inner3_NC s k E1 E2 e Φ Φc :
  to_val e = None →
  Φc ∧ (NC -∗ |={E1,E1}_3=> NC ∗ WPC e @ s; (LVL k); E1 ; E2 {{ Φ }} {{ Φc }}) -∗
  WPC e @ s; (LVL (S k)); E1 ; E2 {{ Φ }} {{ Φc }}.
Proof.
  iIntros (?) "Hwp".
  specialize (SSS_LVL k) => Hlvl.
  iApply (wpc_idx_mono with "[Hwp]"); first by eassumption.
  replace (S (S (S (LVL k)))) with (3 + LVL k) by lia.
  iApply (wpc_step_fupdN_inner_NC with "[Hwp]"); eauto.
  iApply (and_mono with "Hwp"); auto.
  iIntros. by iApply intro_cfupd.
Qed.

Lemma wpc_fupd_crash_shift_empty' s k E1 e Φ Φc :
  WPC e @ s; (LVL k) ; E1 ; ∅ {{ Φ }} {{ |={E1}=> Φc }} ⊢ WPC e @ s; LVL (S k); E1 ; ∅ {{ Φ }} {{ Φc }}.
Proof.
  iApply wpc_fupd_crash_shift_empty.
  rewrite /LVL.
  cut (2 * base ^ (S (S k)) + 1 ≤ base ^ (S (S (S k)))); first lia.
  assert (Hpow: base ^ ((S (S (S k)))) =  base * base ^ (S (S k))).
  { rewrite //=. }
  rewrite Hpow.
  cut (1 ≤ base ^ (S (S k))); first lia.
  replace 1 with (base^0) by auto. apply Nat.pow_le_mono_r_iff; eauto. lia.
Qed.
*)

End staged_inv_wpc.
