From Perennial.go_lang Require Export lang notation.
From Perennial.go_lang Require Import struct typing.

(** * Slice library

    Intended to model Go slices. We don't track slice capacity because our model
    soundly approximates slices as never having extra capacity.
 *)

Open Scope heap_types.

Module slice.
  Definition sliceS := mkStruct ["p"; "len"].
  Definition T t := prodT (refT t) intT.
  Section fields.
    Context {ext:ext_op}.
    Definition ptr := structF! sliceS "p".
    Definition len: val := structF! sliceS "len".
    Theorem ptr_t t Γ : Γ ⊢ ptr : (T t -> refT t).
    Proof.
      typecheck.
    Qed.
    Theorem len_t t Γ : Γ ⊢ len : (T t -> intT).
    Proof.
      typecheck.
    Qed.
  End fields.
End slice.

Hint Resolve slice.ptr_t slice.len_t : types.

(*
Eval compute in get_field sliceS "p".
Eval compute in get_field sliceS "len".
*)
Section go_lang.
  Context `{ffi_sem: ext_semantics}.

  Definition Var' s : @expr ext := Var s.
  Local Coercion Var' : string >-> expr.

Definition NewByteSlice: val :=
  λ: (annot "sz" intT),
  let: "p" := AllocN "sz" #(LitByte 0) in
  ("p", "sz").

Theorem NewByteSlice_t Γ : Γ ⊢ NewByteSlice : (intT -> slice.T byteT).
Proof.
  typecheck.
Qed.

Definition MemCpy: val :=
  λ: "dst" "src" (annot "n" intT),
    for: "i" < "n" :=
    ("dst" +ₗ "i") <- !("src" +ₗ "i").

Theorem MemCpy_t Γ t : Γ ⊢ MemCpy : (refT t -> refT t -> intT -> unitT).
Proof.
  typecheck.
Qed.

(* explicitly recursive version of MemCpy *)
Definition MemCpy_rec: val :=
  rec: "memcpy" "dst" "src" "n" :=
    if: "n" = #0
    then #()
    else "dst" <- !"src";;
         "memcpy" ("dst" +ₗ #1) ("src" +ₗ #1) ("n" - #1).

Theorem MemCpy_rec_t Γ t : Γ ⊢ MemCpy_rec : (refT t -> refT t -> intT -> unitT).
Proof.
  typecheck.
Qed.

Definition SliceSkip: val :=
  λ: "s" "n", (slice.ptr "s" +ₗ "n", slice.len "s" - "n").

Theorem SliceSkip_t Γ t : Γ ⊢ SliceSkip : (slice.T t -> intT -> slice.T t).
Proof.
  typecheck.
Qed.

Definition SliceTake: val :=
  λ: "s" "n", if: slice.len "s" < "n"
              then #() (* TODO: this should be Panic *)
              else (slice.ptr "s", "n").

Definition SliceGet: val :=
  λ: "s" "i",
  !(slice.ptr "s" +ₗ "i").

Theorem SliceGet_t Γ t : Γ ⊢ SliceGet : (slice.T t -> intT -> t).
Proof.
  typecheck.
Qed.

Definition SliceAppend: val :=
  λ: "s1" "s2",
  let: "p" := AllocN (slice.len "s1" + slice.len "s2") #() in
  MemCpy "p" (slice.ptr "s1");;
  MemCpy ("p" +ₗ slice.len "s2") (slice.ptr "s2");;
  (* TODO: unsound, need to de-allocate s1.p *)
  ("p", slice.len "s1" + slice.len "s2").

(* doesn't work since initial value is of wrong type
Theorem SliceAppend_t Γ t : Γ ⊢ SliceAppend : (slice.T t -> slice.T t -> slice.T t).
Proof.
  typecheck.
Qed. *)

Definition UInt64Put: val :=
  λ: "p" "n",
  EncodeInt "n" (slice.ptr "p").

Definition UInt64Get: val :=
  λ: "p",
  DecodeInt (slice.ptr "p").

End go_lang.
