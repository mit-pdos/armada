(* autogenerated from grove_common *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.

Module RawRPCRequest.
  Definition S := struct.decl [
    "RpcId" :: uint64T;
    "Data" :: slice.T byteT
  ].
End RawRPCRequest.

Module RawRPCReply.
  Definition S := struct.decl [
    "Data" :: slice.T byteT
  ].
End RawRPCReply.

Definition RawRpcFunc: ty := (slice.T byteT -> refT (slice.T byteT) -> unitT)%ht.

Module RPCVals.
  Definition S := struct.decl [
    "U64_1" :: uint64T;
    "U64_2" :: uint64T
  ].
End RPCVals.

Module RPCRequest.
  Definition S := struct.decl [
    "CID" :: uint64T;
    "Seq" :: uint64T;
    "Args" :: struct.t RPCVals.S
  ].
End RPCRequest.

Module RPCReply.
  Definition S := struct.decl [
    "Stale" :: boolT;
    "Ret" :: uint64T
  ].
End RPCReply.

Definition RpcFunc: ty := (struct.ptrT RPCRequest.S -> struct.ptrT RPCReply.S -> unitT)%ht.
