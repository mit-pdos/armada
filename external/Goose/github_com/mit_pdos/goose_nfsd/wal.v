(* autogenerated from github.com/mit-pdos/goose-nfsd/wal *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.

From Goose Require github_com.mit_pdos.goose_nfsd.common.
From Goose Require github_com.mit_pdos.goose_nfsd.util.
From Goose Require github_com.tchajed.marshal.

(* 00walconst.go *)

(*  wal implements write-ahead logging

    The layout of log:
    [ installed writes | logged writes | in-memory/logged | unstable in-memory ]
     ^                   ^               ^                  ^
     0                   memStart        diskEnd            nextDiskEnd

    Blocks in the range [diskEnd, nextDiskEnd) are in the process of
    being logged.  Blocks in unstable are unstably committed (i.e.,
    written by NFS Write with the unstable flag and they can be lost
    on crash). Later transactions may absorb them (e.g., a later NFS
    write may update the same inode or indirect block).  The code
    implements a policy of postponing writing unstable blocks to disk
    as long as possible to maximize the chance of absorption (i.e.,
    commitWait or log is full).  It may better to start logging
    earlier. *)

(* space for the end position *)
Definition HDRMETA : expr := #8.

Definition HDRADDRS : expr := (disk.BlockSize - HDRMETA) `quot` #8.

Definition LOGSZ : expr := HDRADDRS.

(* 2 for log header *)
Definition LOGDISKBLOCKS : expr := HDRADDRS + #2.

Definition LOGHDR : expr := #0.

Definition LOGHDR2 : expr := #1.

Definition LOGSTART : expr := #2.

(* 0circular.go *)

Definition LogPosition: ty := uint64T.

Module Update.
  Definition S := struct.decl [
    "Addr" :: uint64T;
    "Block" :: disk.blockT
  ].
End Update.

Definition MkBlockData: val :=
  rec: "MkBlockData" "bn" "blk" :=
    let: "b" := struct.mk Update.S [
      "Addr" ::= "bn";
      "Block" ::= "blk"
    ] in
    "b".

Module circularAppender.
  Definition S := struct.decl [
    "diskAddrs" :: slice.T uint64T
  ].
End circularAppender.

(* initCircular takes ownership of the circular log, which is the first
   LOGDISKBLOCKS of the disk. *)
Definition initCircular: val :=
  rec: "initCircular" "d" :=
    let: "b0" := NewSlice byteT disk.BlockSize in
    disk.Write LOGHDR "b0";;
    disk.Write LOGHDR2 "b0";;
    let: "addrs" := NewSlice uint64T HDRADDRS in
    struct.new circularAppender.S [
      "diskAddrs" ::= "addrs"
    ].

(* decodeHdr1 decodes (end, start) from hdr1 *)
Definition decodeHdr1: val :=
  rec: "decodeHdr1" "hdr1" :=
    let: "dec1" := marshal.NewDec "hdr1" in
    let: "end" := marshal.Dec__GetInt "dec1" in
    let: "addrs" := marshal.Dec__GetInts "dec1" HDRADDRS in
    ("end", "addrs").

(* decodeHdr2 reads start from hdr2 *)
Definition decodeHdr2: val :=
  rec: "decodeHdr2" "hdr2" :=
    let: "dec2" := marshal.NewDec "hdr2" in
    let: "start" := marshal.Dec__GetInt "dec2" in
    "start".

Definition recoverCircular: val :=
  rec: "recoverCircular" "d" :=
    let: "hdr1" := disk.Read LOGHDR in
    let: "hdr2" := disk.Read LOGHDR2 in
    let: ("end", "addrs") := decodeHdr1 "hdr1" in
    let: "start" := decodeHdr2 "hdr2" in
    let: "bufs" := ref (zero_val (slice.T (struct.t Update.S))) in
    let: "pos" := ref_to uint64T "start" in
    (for: (λ: <>, ![uint64T] "pos" < "end"); (λ: <>, "pos" <-[uint64T] ![uint64T] "pos" + #1) := λ: <>,
      let: "addr" := SliceGet uint64T "addrs" ((![uint64T] "pos") `rem` LOGSZ) in
      let: "b" := disk.Read (LOGSTART + (![uint64T] "pos") `rem` LOGSZ) in
      "bufs" <-[slice.T (struct.t Update.S)] SliceAppend (struct.t Update.S) (![slice.T (struct.t Update.S)] "bufs") (struct.mk Update.S [
        "Addr" ::= "addr";
        "Block" ::= "b"
      ]);;
      Continue);;
    (struct.new circularAppender.S [
       "diskAddrs" ::= "addrs"
     ], "start", "end", ![slice.T (struct.t Update.S)] "bufs").

Definition circularAppender__hdr1: val :=
  rec: "circularAppender__hdr1" "c" "end" :=
    let: "enc" := marshal.NewEnc disk.BlockSize in
    marshal.Enc__PutInt "enc" "end";;
    marshal.Enc__PutInts "enc" (struct.loadF circularAppender.S "diskAddrs" "c");;
    marshal.Enc__Finish "enc".

Definition hdr2: val :=
  rec: "hdr2" "start" :=
    let: "enc" := marshal.NewEnc disk.BlockSize in
    marshal.Enc__PutInt "enc" "start";;
    marshal.Enc__Finish "enc".

Definition circularAppender__logBlocks: val :=
  rec: "circularAppender__logBlocks" "c" "d" "end" "bufs" :=
    ForSlice (struct.t Update.S) "i" "buf" "bufs"
      (let: "pos" := "end" + "i" in
      let: "blk" := struct.get Update.S "Block" "buf" in
      let: "blkno" := struct.get Update.S "Addr" "buf" in
      util.DPrintf #5 (#(str"logBlocks: %d to log block %d
      ")) #();;
      disk.Write (LOGSTART + "pos" `rem` LOGSZ) "blk";;
      SliceSet uint64T (struct.loadF circularAppender.S "diskAddrs" "c") ("pos" `rem` LOGSZ) "blkno").

Definition circularAppender__Append: val :=
  rec: "circularAppender__Append" "c" "d" "end" "bufs" :=
    circularAppender__logBlocks "c" "d" "end" "bufs";;
    let: "newEnd" := "end" + slice.len "bufs" in
    let: "b" := circularAppender__hdr1 "c" "newEnd" in
    disk.Write LOGHDR "b";;
    disk.Barrier #().

Definition Advance: val :=
  rec: "Advance" "d" "newStart" :=
    let: "b" := hdr2 "newStart" in
    disk.Write LOGHDR2 "b";;
    disk.Barrier #().

(* 0waldefs.go *)

(*  wal implements write-ahead logging

    The layout of log:
    [ installed writes | logged writes | in-memory/logged | unstable in-memory ]
     ^                   ^               ^                  ^
     0                   memStart        diskEnd            nextDiskEnd

    Blocks in the range [diskEnd, nextDiskEnd) are in the process of
    being logged.  Blocks in unstable are unstably committed (i.e.,
    written by NFS Write with the unstable flag and they can be lost
    on crash). Later transactions may absorb them (e.g., a later NFS
    write may update the same inode or indirect block).  The code
    implements a policy of postponing writing unstable blocks to disk
    as long as possible to maximize the chance of absorption (i.e.,
    commitWait or log is full).  It may better to start logging
    earlier. *)

Module WalogState.
  Definition S := struct.decl [
    "memLog" :: slice.T (struct.t Update.S);
    "memStart" :: LogPosition;
    "diskEnd" :: LogPosition;
    "nextDiskEnd" :: LogPosition;
    "memLogMap" :: mapT LogPosition;
    "shutdown" :: boolT;
    "nthread" :: uint64T
  ].
End WalogState.

Module Walog.
  Definition S := struct.decl [
    "memLock" :: lockRefT;
    "d" :: disk.Disk;
    "circ" :: struct.ptrT circularAppender.S;
    "st" :: struct.ptrT WalogState.S;
    "condLogger" :: condvarRefT;
    "condInstall" :: condvarRefT;
    "condShut" :: condvarRefT
  ].
End Walog.

Definition Walog__LogSz: val :=
  rec: "Walog__LogSz" "l" :=
    common.HDRADDRS.

(* installer.go *)

(* cutMemLog deletes from the memLog through installEnd, after these blocks have
   been installed. This transitions from a state where the on-disk install point
   is already at installEnd, but memStart < installEnd.

   Assumes caller holds memLock *)
Definition WalogState__cutMemLog: val :=
  rec: "WalogState__cutMemLog" "st" "installEnd" :=
    ForSlice (struct.t Update.S) "i" "blk" (SliceTake (struct.loadF WalogState.S "memLog" "st") ("installEnd" - struct.loadF WalogState.S "memStart" "st"))
      (let: "pos" := struct.loadF WalogState.S "memStart" "st" + "i" in
      let: "blkno" := struct.get Update.S "Addr" "blk" in
      let: ("oldPos", "ok") := MapGet (struct.loadF WalogState.S "memLogMap" "st") "blkno" in
      (if: "ok" && ("oldPos" ≤ "pos")
      then
        util.DPrintf #5 (#(str"memLogMap: del %d %d
        ")) #();;
        MapDelete (struct.loadF WalogState.S "memLogMap" "st") "blkno"
      else #()));;
    struct.storeF WalogState.S "memLog" "st" (SliceSkip (struct.t Update.S) (struct.loadF WalogState.S "memLog" "st") ("installEnd" - struct.loadF WalogState.S "memStart" "st"));;
    struct.storeF WalogState.S "memStart" "st" "installEnd".

(* installBlocks installs the updates in bufs to the data region

   Does not hold the memLock, but expects exclusive ownership of the data
   region. *)
Definition installBlocks: val :=
  rec: "installBlocks" "d" "bufs" :=
    ForSlice (struct.t Update.S) "i" "buf" "bufs"
      (let: "blkno" := struct.get Update.S "Addr" "buf" in
      let: "blk" := struct.get Update.S "Block" "buf" in
      util.DPrintf #5 (#(str"installBlocks: write log block %d to %d
      ")) #();;
      disk.Write "blkno" "blk").

(* logInstall installs one on-disk transaction from the disk log to the data
   region.

   Returns (blkCount, installEnd)

   blkCount is the number of blocks installed (only used for liveness)

   installEnd is the new last position installed to the data region (only used
   for debugging)

   Installer holds memLock *)
Definition Walog__logInstall: val :=
  rec: "Walog__logInstall" "l" :=
    let: "installEnd" := struct.loadF WalogState.S "diskEnd" (struct.loadF Walog.S "st" "l") in
    let: "bufs" := SliceTake (struct.loadF WalogState.S "memLog" (struct.loadF Walog.S "st" "l")) ("installEnd" - struct.loadF WalogState.S "memStart" (struct.loadF Walog.S "st" "l")) in
    (if: (slice.len "bufs" = #0)
    then (#0, "installEnd")
    else
      lock.release (struct.loadF Walog.S "memLock" "l");;
      util.DPrintf #5 (#(str"logInstall up to %d
      ")) #();;
      installBlocks (struct.loadF Walog.S "d" "l") "bufs";;
      Advance (struct.loadF Walog.S "d" "l") "installEnd";;
      lock.acquire (struct.loadF Walog.S "memLock" "l");;
      WalogState__cutMemLog (struct.loadF Walog.S "st" "l") "installEnd";;
      lock.condBroadcast (struct.loadF Walog.S "condInstall" "l");;
      (slice.len "bufs", "installEnd")).

(* installer installs blocks from the on-disk log to their home location. *)
Definition Walog__installer: val :=
  rec: "Walog__installer" "l" :=
    lock.acquire (struct.loadF Walog.S "memLock" "l");;
    struct.storeF WalogState.S "nthread" (struct.loadF Walog.S "st" "l") (struct.loadF WalogState.S "nthread" (struct.loadF Walog.S "st" "l") + #1);;
    Skip;;
    (for: (λ: <>, ~ (struct.loadF WalogState.S "shutdown" (struct.loadF Walog.S "st" "l"))); (λ: <>, Skip) := λ: <>,
      let: ("blkcount", "txn") := Walog__logInstall "l" in
      (if: "blkcount" > #0
      then
        util.DPrintf #5 (#(str"Installed till txn %d
        ")) #()
      else lock.condWait (struct.loadF Walog.S "condInstall" "l"));;
      Continue);;
    util.DPrintf #1 (#(str"installer: shutdown
    ")) #();;
    struct.storeF WalogState.S "nthread" (struct.loadF Walog.S "st" "l") (struct.loadF WalogState.S "nthread" (struct.loadF Walog.S "st" "l") - #1);;
    lock.condSignal (struct.loadF Walog.S "condShut" "l");;
    lock.release (struct.loadF Walog.S "memLock" "l").

(* logger.go *)

(* logAppend appends to the log, if it can find transactions to append.

   It grabs the new writes in memory and not on disk through l.nextDiskEnd; if
   there are any such writes, it commits them atomically.

   assumes caller holds memLock

   Returns true if it made progress (for liveness, not important for
   correctness). *)
Definition Walog__logAppend: val :=
  rec: "Walog__logAppend" "l" :=
    Skip;;
    (for: (λ: <>, slice.len (struct.loadF WalogState.S "memLog" (struct.loadF Walog.S "st" "l")) > LOGSZ); (λ: <>, Skip) := λ: <>,
      lock.condWait (struct.loadF Walog.S "condInstall" "l");;
      Continue);;
    let: "memstart" := struct.loadF WalogState.S "memStart" (struct.loadF Walog.S "st" "l") in
    let: "memlog" := struct.loadF WalogState.S "memLog" (struct.loadF Walog.S "st" "l") in
    let: "newDiskEnd" := struct.loadF WalogState.S "nextDiskEnd" (struct.loadF Walog.S "st" "l") in
    let: "diskEnd" := struct.loadF WalogState.S "diskEnd" (struct.loadF Walog.S "st" "l") in
    let: "newbufs" := SliceSubslice (struct.t Update.S) "memlog" ("diskEnd" - "memstart") ("newDiskEnd" - "memstart") in
    (if: (slice.len "newbufs" = #0)
    then #false
    else
      lock.release (struct.loadF Walog.S "memLock" "l");;
      circularAppender__Append (struct.loadF Walog.S "circ" "l") (struct.loadF Walog.S "d" "l") "diskEnd" "newbufs";;
      lock.acquire (struct.loadF Walog.S "memLock" "l");;
      struct.storeF WalogState.S "diskEnd" (struct.loadF Walog.S "st" "l") "newDiskEnd";;
      lock.condBroadcast (struct.loadF Walog.S "condLogger" "l");;
      lock.condBroadcast (struct.loadF Walog.S "condInstall" "l");;
      #true).

(* logger writes blocks from the in-memory log to the on-disk log

   Operates by continuously polling for in-memory transactions, driven by
   condLogger for scheduling *)
Definition Walog__logger: val :=
  rec: "Walog__logger" "l" :=
    lock.acquire (struct.loadF Walog.S "memLock" "l");;
    struct.storeF WalogState.S "nthread" (struct.loadF Walog.S "st" "l") (struct.loadF WalogState.S "nthread" (struct.loadF Walog.S "st" "l") + #1);;
    Skip;;
    (for: (λ: <>, ~ (struct.loadF WalogState.S "shutdown" (struct.loadF Walog.S "st" "l"))); (λ: <>, Skip) := λ: <>,
      let: "progress" := Walog__logAppend "l" in
      (if: ~ "progress"
      then lock.condWait (struct.loadF Walog.S "condLogger" "l")
      else #());;
      Continue);;
    util.DPrintf #1 (#(str"logger: shutdown
    ")) #();;
    struct.storeF WalogState.S "nthread" (struct.loadF Walog.S "st" "l") (struct.loadF WalogState.S "nthread" (struct.loadF Walog.S "st" "l") - #1);;
    lock.condSignal (struct.loadF Walog.S "condShut" "l");;
    lock.release (struct.loadF Walog.S "memLock" "l").

(* wal.go *)

Definition Walog__recover: val :=
  rec: "Walog__recover" "l" :=
    util.DPrintf #1 (#(str"recover %d %d
    ")) #();;
    ForSlice (struct.t Update.S) "i" "buf" (struct.loadF WalogState.S "memLog" (struct.loadF Walog.S "st" "l"))
      (MapInsert (struct.loadF WalogState.S "memLogMap" (struct.loadF Walog.S "st" "l")) (struct.get Update.S "Addr" "buf") (struct.loadF WalogState.S "memStart" (struct.loadF Walog.S "st" "l") + "i")).

Definition mkLog: val :=
  rec: "mkLog" "disk" :=
    let: ("circ", ("start", ("end", "memLog"))) := recoverCircular "disk" in
    let: "ml" := lock.new #() in
    let: "st" := struct.new WalogState.S [
      "memLog" ::= "memLog";
      "memStart" ::= "start";
      "diskEnd" ::= "end";
      "nextDiskEnd" ::= "end";
      "memLogMap" ::= NewMap LogPosition;
      "shutdown" ::= #false;
      "nthread" ::= #0
    ] in
    let: "l" := struct.new Walog.S [
      "d" ::= "disk";
      "circ" ::= "circ";
      "memLock" ::= "ml";
      "st" ::= "st";
      "condLogger" ::= lock.newCond "ml";
      "condInstall" ::= lock.newCond "ml";
      "condShut" ::= lock.newCond "ml"
    ] in
    util.DPrintf #1 (#(str"mkLog: size %d
    ")) #();;
    Walog__recover "l";;
    "l".

Definition Walog__startBackgroundThreads: val :=
  rec: "Walog__startBackgroundThreads" "l" :=
    Fork (Walog__logger "l");;
    Fork (Walog__installer "l").

Definition MkLog: val :=
  rec: "MkLog" "disk" :=
    let: "l" := mkLog "disk" in
    Walog__startBackgroundThreads "l";;
    "l".

(* memWrite writes out bufs to the in-memory log

   Absorbs writes in in-memory transactions (avoiding those that might be in
   the process of being logged or installed).

   Assumes caller holds memLock *)
Definition WalogState__memWrite: val :=
  rec: "WalogState__memWrite" "st" "bufs" :=
    let: "pos" := ref_to LogPosition (struct.loadF WalogState.S "memStart" "st" + slice.len (struct.loadF WalogState.S "memLog" "st")) in
    ForSlice (struct.t Update.S) <> "buf" "bufs"
      (let: ("oldpos", "ok") := MapGet (struct.loadF WalogState.S "memLogMap" "st") (struct.get Update.S "Addr" "buf") in
      (if: "ok" && ("oldpos" ≥ struct.loadF WalogState.S "nextDiskEnd" "st")
      then
        util.DPrintf #5 (#(str"memWrite: absorb %d pos %d old %d
        ")) #();;
        SliceSet (struct.t Update.S) (struct.loadF WalogState.S "memLog" "st") ("oldpos" - struct.loadF WalogState.S "memStart" "st") "buf"
      else
        (if: "ok"
        then
          util.DPrintf #5 (#(str"memLogMap: replace %d pos %d old %d
          ")) #()
        else
          util.DPrintf #5 (#(str"memLogMap: add %d pos %d
          ")) #());;
        struct.storeF WalogState.S "memLog" "st" (SliceAppend (struct.t Update.S) (struct.loadF WalogState.S "memLog" "st") "buf");;
        MapInsert (struct.loadF WalogState.S "memLogMap" "st") (struct.get Update.S "Addr" "buf") (![LogPosition] "pos");;
        "pos" <-[LogPosition] ![LogPosition] "pos" + #1)).

(* Assumes caller holds memLock *)
Definition WalogState__doMemAppend: val :=
  rec: "WalogState__doMemAppend" "st" "bufs" :=
    WalogState__memWrite "st" "bufs";;
    let: "txn" := struct.loadF WalogState.S "memStart" "st" + slice.len (struct.loadF WalogState.S "memLog" "st") in
    "txn".

(* Grab all of the current transactions and record them for the next group commit (when the logger gets around to it).

   This is a separate function purely for verification purposes; the code isn't complicated but we have to manipulate
   some ghost state and justify this value of nextDiskEnd.

   Assumes caller holds memLock. *)
Definition WalogState__endGroupTxn: val :=
  rec: "WalogState__endGroupTxn" "st" :=
    struct.storeF WalogState.S "nextDiskEnd" "st" (struct.loadF WalogState.S "memStart" "st" + slice.len (struct.loadF WalogState.S "memLog" "st")).

Definition copyUpdateBlock: val :=
  rec: "copyUpdateBlock" "u" :=
    let: "blk" := NewSlice byteT disk.BlockSize in
    SliceCopy byteT "blk" (struct.get Update.S "Block" "u");;
    "blk".

(* readMem implements ReadMem, assuming memLock is held *)
Definition WalogState__readMem: val :=
  rec: "WalogState__readMem" "st" "blkno" :=
    let: ("pos", "ok") := MapGet (struct.loadF WalogState.S "memLogMap" "st") "blkno" in
    (if: "ok"
    then
      util.DPrintf #5 (#(str"read memLogMap: read %d pos %d
      ")) #();;
      let: "u" := SliceGet (struct.t Update.S) (struct.loadF WalogState.S "memLog" "st") ("pos" - struct.loadF WalogState.S "memStart" "st") in
      let: "blk" := copyUpdateBlock "u" in
      ("blk", #true)
    else (slice.nil, #false)).

(* Read from only the in-memory cached state (the unstable and logged parts of
   the wal). *)
Definition Walog__ReadMem: val :=
  rec: "Walog__ReadMem" "l" "blkno" :=
    lock.acquire (struct.loadF Walog.S "memLock" "l");;
    let: ("blk", "ok") := WalogState__readMem (struct.loadF Walog.S "st" "l") "blkno" in
    Linearize;;
    lock.release (struct.loadF Walog.S "memLock" "l");;
    ("blk", "ok").

(* Read from only the installed state (a subset of durable state). *)
Definition Walog__ReadInstalled: val :=
  rec: "Walog__ReadInstalled" "l" "blkno" :=
    disk.Read "blkno".

(* Read reads from the latest memory state, but does so in a
   difficult-to-linearize way (specifically, it is future-dependent when to
   linearize between the l.memLog.Unlock() and the eventual disk read, due to
   potential concurrent cache or disk writes). *)
Definition Walog__Read: val :=
  rec: "Walog__Read" "l" "blkno" :=
    let: ("blk", "ok") := Walog__ReadMem "l" "blkno" in
    (if: "ok"
    then "blk"
    else Walog__ReadInstalled "l" "blkno").

(* Append to in-memory log.

   On success returns the pos for this append.

   On failure guaranteed to be idempotent (failure can only occur in principle,
   due overflowing 2^64 writes) *)
Definition Walog__MemAppend: val :=
  rec: "Walog__MemAppend" "l" "bufs" :=
    (if: slice.len "bufs" > LOGSZ
    then (#0, #false)
    else
      let: "txn" := ref_to LogPosition #0 in
      let: "ok" := ref_to boolT #true in
      lock.acquire (struct.loadF Walog.S "memLock" "l");;
      Skip;;
      (for: (λ: <>, #true); (λ: <>, Skip) := λ: <>,
        (if: util.SumOverflows (struct.loadF WalogState.S "memStart" (struct.loadF Walog.S "st" "l")) (slice.len "bufs")
        then
          "ok" <-[boolT] #false;;
          Break
        else
          let: "memEnd" := struct.loadF WalogState.S "memStart" (struct.loadF Walog.S "st" "l") + slice.len (struct.loadF WalogState.S "memLog" (struct.loadF Walog.S "st" "l")) in
          let: "memSize" := "memEnd" - struct.loadF WalogState.S "diskEnd" (struct.loadF Walog.S "st" "l") in
          (if: "memSize" + slice.len "bufs" > LOGSZ
          then
            util.DPrintf #5 (#(str"memAppend: log is full; try again")) #();;
            WalogState__endGroupTxn (struct.loadF Walog.S "st" "l");;
            lock.condBroadcast (struct.loadF Walog.S "condLogger" "l");;
            lock.condWait (struct.loadF Walog.S "condLogger" "l");;
            Continue
          else
            "txn" <-[LogPosition] WalogState__doMemAppend (struct.loadF Walog.S "st" "l") "bufs";;
            Break)));;
      lock.release (struct.loadF Walog.S "memLock" "l");;
      (![LogPosition] "txn", ![boolT] "ok")).

(* Flush flushes a transaction pos (and all preceding transactions)

   The implementation waits until the logger has appended in-memory log up to
   txn to on-disk log. *)
Definition Walog__Flush: val :=
  rec: "Walog__Flush" "l" "pos" :=
    util.DPrintf #1 (#(str"Flush: commit till txn %d
    ")) #();;
    lock.acquire (struct.loadF Walog.S "memLock" "l");;
    lock.condBroadcast (struct.loadF Walog.S "condLogger" "l");;
    (if: "pos" > struct.loadF WalogState.S "nextDiskEnd" (struct.loadF Walog.S "st" "l")
    then
      WalogState__endGroupTxn (struct.loadF Walog.S "st" "l");;
      #()
    else #());;
    Skip;;
    (for: (λ: <>, ~ ("pos" ≤ struct.loadF WalogState.S "diskEnd" (struct.loadF Walog.S "st" "l"))); (λ: <>, Skip) := λ: <>,
      lock.condWait (struct.loadF Walog.S "condLogger" "l");;
      Continue);;
    Linearize;;
    lock.release (struct.loadF Walog.S "memLock" "l").

(* Shutdown logger and installer *)
Definition Walog__Shutdown: val :=
  rec: "Walog__Shutdown" "l" :=
    util.DPrintf #1 (#(str"shutdown wal
    ")) #();;
    lock.acquire (struct.loadF Walog.S "memLock" "l");;
    struct.storeF WalogState.S "shutdown" (struct.loadF Walog.S "st" "l") #true;;
    lock.condBroadcast (struct.loadF Walog.S "condLogger" "l");;
    lock.condBroadcast (struct.loadF Walog.S "condInstall" "l");;
    Skip;;
    (for: (λ: <>, struct.loadF WalogState.S "nthread" (struct.loadF Walog.S "st" "l") > #0); (λ: <>, Skip) := λ: <>,
      util.DPrintf #1 (#(str"wait for logger/installer")) #();;
      lock.condWait (struct.loadF Walog.S "condShut" "l");;
      Continue);;
    lock.release (struct.loadF Walog.S "memLock" "l");;
    util.DPrintf #1 (#(str"wal done
    ")) #().
