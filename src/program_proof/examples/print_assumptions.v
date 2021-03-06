(** Print any assumptions made by top-level theorems *)
(* importing the prelude ensures notations are in scope for these lemma
statements *)
From Perennial.program_proof Require Import disk_prelude.
From Perennial.program_proof.examples Require
     replicated_block_proof (* single_inode_proof *) dir_proof toy_proof.

Definition toy_theorems :=
  @toy_proof.wpc_TransferEvenBlock.

Definition replicated_block_theorems :=
  (@replicated_block_proof.init_zero_cinv,  (* not used by [OpenRead] *)
   @replicated_block_proof.OpenRead_adequate).
(*
Definition single_inode_theorems :=
  (@single_inode_proof.init_single_inode,
   @single_inode_proof.wpc_Open,
   @single_inode_proof.is_single_inode_alloc,
   @single_inode_proof.wpc_Read,
   @single_inode_proof.wpc_Append).
*)
Definition dir_theorems :=
  (@dir_proof.init_dir,
   @dir_proof.wpc_Open,
   @dir_proof.is_dir_alloc,
   @dir_proof.wpc_Dir__Read,
   @dir_proof.wpc_Dir__Size,
   @dir_proof.wpc_Dir__Append,
   @dir_proof.wpr_Open).

Goal True.

idtac "toy even block:".
Print Assumptions toy_theorems.

idtac "".
idtac "replicated block:".
Print Assumptions replicated_block_theorems.
(*
idtac "".
idtac "single inode:".
Print Assumptions single_inode_theorems.
*)
idtac "".
idtac "directory:".
Print Assumptions dir_theorems.

Abort. (* leave [Goal] *)
