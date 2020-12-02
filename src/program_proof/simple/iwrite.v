From RecordUpdate Require Import RecordSet.
Import RecordSetNotations.

From Perennial.algebra Require Import deletable_heap liftable auth_map.
From Perennial.Helpers Require Import Transitions.
From Perennial.program_proof Require Import proof_prelude.

From Goose.github_com.mit_pdos.goose_nfsd Require Import simple.
From Perennial.program_proof Require Import txn.txn_proof marshal_proof addr_proof crash_lockmap_proof addr.addr_proof buf.buf_proof.
From Perennial.program_proof Require Import buftxn.sep_buftxn_proof.
From Perennial.program_proof Require Import proof_prelude.
From Perennial.program_proof Require Import disk_lib.
From Perennial.Helpers Require Import NamedProps Map List range_set.
From Perennial.algebra Require Import log_heap.
From Perennial.program_logic Require Import spec_assert.
From Perennial.goose_lang.lib Require Import slice.typed_slice into_val.
From Perennial.program_proof Require Import simple.spec simple.invariant simple.common.

Section heap.
Context `{!buftxnG Σ}.
Context `{!ghost_varG Σ (gmap u64 (list u8))}.
Context `{!mapG Σ u64 (list u8)}.
Implicit Types (stk:stuckness) (E: coPset).

Theorem wp_Inode__WriteInode γ γtxn (inum : u64) len len' blk (l : loc) (btxn : loc) dinit γdurable :
  {{{ is_buftxn_mem Nbuftxn btxn γ.(simple_buftxn) dinit γtxn γdurable ∗
      is_inode_enc inum len blk (buftxn_maps_to γtxn) ∗
      is_inode_mem l inum len' blk ∗
      ⌜ inum ∈ covered_inodes ⌝
  }}}
    Inode__WriteInode #l #btxn
  {{{ RET #();
      is_buftxn_mem Nbuftxn btxn γ.(simple_buftxn) dinit γtxn γdurable ∗
      is_inode_enc inum len' blk (buftxn_maps_to γtxn) ∗
      is_inode_mem l inum len' blk }}}.
Proof.
  iIntros (Φ) "(Hbuftxn & Henc & Hmem & %Hcovered) HΦ".
  wp_call.
  iNamed "Hmem".
  wp_call.
  wp_apply wp_new_enc. iIntros (enc) "He".
  wp_loadField.
  wp_apply (wp_Enc__PutInt with "He"); first by word. iIntros "He".
  wp_loadField.
  wp_apply (wp_Enc__PutInt with "He"); first by word. iIntros "He".
  wp_apply (wp_Enc__Finish with "He"). iIntros (s data) "(%Hdata & %Hlen & Hs)".
  wp_loadField.
  wp_apply wp_inum2Addr.
  {
    iPureIntro.
    rewrite /covered_inodes in Hcovered.
    eapply rangeSet_lookup in Hcovered; try lia.
    rewrite /NumInodes /InodeSz. simpl. lia.
  }
  iNamed "Henc".
  iDestruct (is_slice_to_small with "Hs") as "Hs".
  wp_apply (wp_BufTxn__OverWrite
    _ _ _ _ _ _ _ _ _ _ _ (existT KindInode (bufInode (list_to_inode_buf data))) with "[$Hbuftxn $Hinode_enc_mapsto $Hs]").
  { eauto. }
  { rewrite /data_has_obj /=. apply list_to_inode_buf_to_list.
    rewrite /inode_bytes. word. }
  { eauto. }
  iIntros "[Hbuftxn Hinode_enc_mapsto]".
  wp_apply util_proof.wp_DPrintf.
  iApply "HΦ". iFrame.
  iExists _. iFrame. iPureIntro.
  rewrite /encodes_inode.
  rewrite list_to_inode_buf_to_list. 2: { rewrite /inode_bytes; word. }
  eapply Hdata.
Qed.

Lemma length_1_singleton {T} (l : list T) :
  length l = 1 -> ∃ v, l = [v].
Proof.
  destruct l; simpl in *; intros; try lia.
  destruct l; simpl in *; intros; try lia.
  eexists; eauto.
Qed.

Theorem wp_Inode__Write γ γtxn ip inum len blk (btxn : loc) (offset : u64) (count : u64) dataslice databuf γdurable dinit contents :
  {{{ is_buftxn_mem Nbuftxn btxn γ.(simple_buftxn) dinit γtxn γdurable ∗
      is_inode_mem ip inum len blk ∗
      is_inode_enc inum len blk (buftxn_maps_to γtxn) ∗
      is_inode_data len blk contents (buftxn_maps_to γtxn) ∗
      is_slice_small dataslice u8T 1 databuf ∗
      ⌜ int.nat count = length databuf ⌝ ∗
      ⌜ inum ∈ covered_inodes ⌝
  }}}
    Inode__Write #ip #btxn #offset #count (slice_val dataslice)
  {{{ (wcount: u64) (ok: bool), RET (#wcount, #ok);
      is_buftxn_mem Nbuftxn btxn γ.(simple_buftxn) dinit γtxn γdurable ∗
      ( ( let contents' := ((firstn (int.nat offset) contents) ++
                          (firstn (int.nat count) databuf) ++
                          (skipn (int.nat offset + int.nat count) contents))%list in
        let len' := U64 (Z.max (int.Z len) (int.Z offset + int.Z count)) in
        is_inode_mem ip inum len' blk ∗
        is_inode_enc inum len' blk (buftxn_maps_to γtxn) ∗
        is_inode_data len' blk contents' (buftxn_maps_to γtxn) ∗
        ⌜ wcount = count ∧ ok = true ∧
          (int.Z offset + length databuf < 2^64)%Z ∧
          (int.Z offset ≤ int.Z len)%Z ⌝ ) ∨
      ( is_inode_mem ip inum len blk ∗
        is_inode_enc inum len blk (buftxn_maps_to γtxn) ∗
        is_inode_data len blk contents (buftxn_maps_to γtxn) ∗
        ⌜ int.Z wcount = 0 ∧ ok = false ⌝ ) )
  }}}.
Proof.
  iIntros (Φ) "(Hbuftxn & Hmem & Hienc & Hdata & Hdatabuf & %Hcount & %Hcovered) HΦ".
  wp_call.
  wp_apply util_proof.wp_DPrintf.
  wp_apply wp_slice_len.
  wp_if_destruct.
  { wp_pures. iApply "HΦ". iFrame. iRight. iFrame. done. }
  wp_apply util_proof.wp_SumOverflows.
  iIntros (ok) "%Hok". subst.
  wp_if_destruct.
  { wp_pures. iApply "HΦ". iFrame "Hbuftxn". iRight. iFrame. done. }
  wp_if_destruct.
  { wp_pures. iApply "HΦ". iFrame "Hbuftxn". iRight. iFrame. done. }
  iNamed "Hmem".
  wp_loadField.
  wp_if_destruct.
  { wp_pures. iApply "HΦ". iFrame "Hbuftxn". iRight. iFrame. done. }

  iNamed "Hdata".
  wp_loadField.
  wp_apply wp_block2addr.
  wp_apply (wp_BufTxn__ReadBuf with "[$Hbuftxn $Hdiskblk]"); first by eauto.
  iIntros (dirty bufptr) "[Hbuf Hbufdone]".

  wp_apply wp_ref_to; first by val_ty.
  iIntros (count) "Hcount".

  wp_apply (wp_forUpto (λ i,
    ∃ bbuf',
      "Hdatabuf" ∷ is_slice_small dataslice byteT 1 databuf ∗
      "Hbuf" ∷ is_buf bufptr (blk2addr blk) {|
             bufKind := objKind (existT KindBlock (bufBlock bbuf'));
             bufData := objData (existT KindBlock (bufBlock bbuf'));
             bufDirty := dirty |} ∗
      "%Hbbuf" ∷ ⌜ vec_to_list bbuf' = ((firstn (int.nat offset) (vec_to_list bbuf)) ++
                                       (firstn (int.nat i) databuf) ++
                                       (skipn (int.nat offset + int.nat i) (vec_to_list bbuf)))%list ⌝
    )%I with "[] [$Hcount Hdatabuf Hbuf]").
  { word. }
  {
    iIntros (count').
    iIntros (Φ') "!>".
    iIntros "(HI & Hcount & %Hbound) HΦ'".
    iNamed "HI".
    wp_load.
    destruct (databuf !! int.nat count') eqn:He.
    2: {
      iDestruct (is_slice_small_sz with "Hdatabuf") as "%Hlen".
      eapply lookup_ge_None_1 in He. word.
    }
    wp_apply (wp_SliceGet (V:=u8) with "[$Hdatabuf]"); eauto.
    iIntros "Hdatabuf".
    wp_load.
    wp_apply (wp_buf_loadField_data with "Hbuf").
    iIntros (bufslice) "[Hbufdata Hbufnodata]".
    assert (is_Some (vec_to_list bbuf' !! int.nat (word.add offset count'))).
    { eapply lookup_lt_is_Some_2. rewrite vec_to_list_length /block_bytes.
      revert Heqb0. word. }
    wp_apply (wp_SliceSet (V:=u8) with "[$Hbufdata]"); eauto.
    iIntros "Hbufdata".
    wp_pures.
    iApply "HΦ'". iFrame.

    assert ((int.nat (word.add offset count')) < block_bytes) as fin.
    {
      rewrite /is_Some in H.
      destruct H.
      apply lookup_lt_Some in H.
      rewrite vec_to_list_length /block_bytes in H.
      rewrite /block_bytes; lia.
    }
    iExists (vinsert (nat_to_fin fin) u bbuf'). iSplit.
    { iApply is_buf_return_data. iFrame.
      iExactEq "Hbufdata".
      rewrite /= /Block_to_vals vec_to_list_insert.
      rewrite /is_slice_small. f_equal.
      rewrite /list.untype /to_val /u8_IntoVal /b2val. f_equal. f_equal.
      erewrite fin_to_nat_to_fin. reflexivity.
    }
    iPureIntro.
    rewrite vec_to_list_insert Hbbuf.
    erewrite fin_to_nat_to_fin.
    replace (int.nat (word.add offset count')) with ((int.nat offset)+(int.nat count')).
    2: { word. }
    assert ((int.nat offset) = (length (take (int.nat offset) bbuf))) as Hoff.
    1: {
      rewrite take_length.
      rewrite vec_to_list_length.
      revert fin. word_cleanup.
    }
    rewrite -> Hoff at 1.
    rewrite insert_app_r.
    f_equal.
    replace (int.nat count') with (length (take (int.nat count') databuf) + 0) at 1.
    2: {
      rewrite take_length_le; first by lia. word.
    }
    rewrite insert_app_r.
    replace (int.nat (word.add count' 1%Z)) with (S (int.nat count')) at 1 by word.
    erewrite take_S_r; eauto.
    rewrite -app_assoc. f_equal.
    erewrite <- drop_take_drop.
    1: rewrite insert_app_l.
    1: f_equal.
    3: word.
    2: {
      rewrite drop_length.
      rewrite firstn_length_le.
      2: { rewrite vec_to_list_length. revert fin. word. }
      revert fin. word.
    }
    replace (int.nat (word.add count' 1%Z)) with (int.nat count' + 1) by word.
    rewrite plus_assoc.
    rewrite skipn_firstn_comm.
    replace (int.nat offset + int.nat count' + 1 - (int.nat offset + int.nat count')) with 1 by word.
    edestruct (length_1_singleton (T:=u8) (take 1 (drop (int.nat offset + int.nat count') bbuf))) as [x Hx].
    2: { rewrite Hx. done. }
    rewrite firstn_length_le; eauto.
    rewrite drop_length.
    rewrite vec_to_list_length.
    revert fin. word.
  }
  {
    iExists _. iFrame.
    iPureIntro.
    replace (int.nat (U64 0)) with 0 by reflexivity.
    rewrite take_0. rewrite app_nil_l.
    replace (int.nat offset + 0) with (int.nat offset) by lia.
    rewrite take_drop. done.
  }

  iIntros "(HI & Hcount)".
  iNamed "HI".
  wp_apply (wp_Buf__SetDirty with "Hbuf"). iIntros "Hbuf".

  iMod ("Hbufdone" with "Hbuf []") as "[Hbuftxn Hdiskblk]".
  { iLeft. done. }

  wp_apply util_proof.wp_DPrintf.
  wp_loadField.

  assert (take (int.nat offset) contents =
          take (int.nat offset) bbuf) as Hcontents0.
  { rewrite -Hdiskdata.
    rewrite take_take. f_equal. lia. }

  assert (drop (int.nat offset + int.nat dataslice.(Slice.sz)) contents =
          drop (int.nat offset + int.nat dataslice.(Slice.sz)) (take (length contents) bbuf))
    as Hcontents1.
  { congruence. }

  assert ( (drop (int.nat offset + int.nat dataslice.(Slice.sz)) bbuf) =
           (drop (int.nat offset + int.nat dataslice.(Slice.sz))
                 (take (length contents) bbuf ++ (drop (length contents) bbuf))))
     as Hbuf.
  { rewrite take_drop; done. }

  assert (length contents ≤ length bbuf) as Hlencontents.
  { eapply (f_equal length) in Hdiskdata.
    rewrite take_length in Hdiskdata. lia. }

  wp_if_destruct.
  { wp_storeField.
    wp_apply (wp_Inode__WriteInode with "[$Hbuftxn Hinum Hisize Hidata $Hienc]").
    { iFrame. iFrame "%". }
    iIntros "(Hbuftxn & Hienc & Hmem)".
    wp_pures.
    iApply "HΦ". iFrame "Hbuftxn". iLeft.
    rewrite Z.max_r.
    2: { revert Heqb2. word. }
    iFrame.
    iSplit.
    2: {
      iPureIntro. intuition eauto.
      { rewrite -Hcount; word. }
      lia.
    }
    iExists _. iFrame. iPureIntro.
    rewrite Hbbuf. rewrite Hcontents0 Hcontents1.
    rewrite !app_length.
    rewrite drop_length.
    rewrite take_length_le; last by ( rewrite vec_to_list_length /block_bytes; word ).
    rewrite take_length_le; last by ( rewrite Hcount; lia ).
    rewrite take_length_le; last by ( rewrite vec_to_list_length /block_bytes; word ).
    replace (length contents) with (int.nat len) by word.
    split. 2: { revert Heqb2. word. }
    rewrite app_assoc. rewrite take_app_le.
    2: {
      rewrite !app_length.
      rewrite take_length_le. 2: rewrite vec_to_list_length /block_bytes; word.
      rewrite take_length_le. 2: rewrite Hcount; lia.
      revert Heqb2. word.
    }
    rewrite firstn_all2.
    2: {
      rewrite !app_length.
      rewrite take_length_le. 2: rewrite vec_to_list_length /block_bytes; word.
      rewrite take_length_le. 2: rewrite Hcount; lia.
      revert Heqb2. word.
    }
    f_equal. rewrite drop_ge. 1: rewrite app_nil_r; eauto.
    rewrite take_length_le. 2: rewrite vec_to_list_length /block_bytes; word.
    rewrite Hcount. revert Heqb2. word.
  }
  { wp_pures.
    iApply "HΦ". iFrame "Hbuftxn". iLeft.
    rewrite Z.max_l.
    2: { revert Heqb2. word. }
    replace (U64 (int.Z len)) with (len) by word.
    iFrame.
    iSplit.
    2: {
      iPureIntro. intuition eauto.
      { rewrite -Hcount; word. }
      lia.
    }
    iExists _. iFrame. iPureIntro.
    rewrite Hbbuf. rewrite Hcontents0 Hcontents1 Hbuf.
    rewrite !app_length.
    rewrite drop_length.
    rewrite take_length_le. 2: { rewrite vec_to_list_length /block_bytes. revert Heqb0; word. }
    rewrite take_length_le. 2: { rewrite Hcount; lia. }
    rewrite take_length_le. 2: { lia. }
    replace (length contents) with (int.nat len) by word.
    split. 2: { revert Heqb2. word. }
    rewrite drop_app_le.
    2: {
      rewrite take_length_le. 2: lia.
      revert Heqb2. word.
    }
    rewrite app_assoc. rewrite app_assoc. rewrite take_app_le.
    2: {
      rewrite !app_length.
      rewrite drop_length.
      rewrite take_length_le. 2: lia.
      rewrite take_length_le. 2: rewrite Hcount; lia.
      rewrite take_length_le. 2: lia.
      revert Heqb2. word.
    }
    rewrite firstn_all2.
    1: { rewrite app_assoc; eauto. }

    rewrite !app_length.
    rewrite drop_length.
    rewrite take_length_le. 2: lia.
    rewrite take_length_le. 2: rewrite Hcount; lia.
    rewrite take_length_le. 2: lia.
    revert Heqb2. word.
  }
Qed.

End heap.