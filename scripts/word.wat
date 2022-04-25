;; Template for defining 'word' modules
;; Used to 'reverse engineer' the binary code to emit from the compiler
(module $quadruple
  (import "env" "table" (table 4 anyfunc))
  (import "env" "memory" (memory 1))

  (type $void (func (param i32) (result i32)))
  (type $push (func (param i32) (param i32) (result i32)))
  (type $pop (func (param i32) (result i32) (result i32)))

  (func $word (param $tos i32) (param $n i32) (result i32)
    (local $index1 i32)
    (local $end1 i32)
    (local $incr1 i32)

    (local.get $tos)  

    ;; Push
    (local.set $tos)
    (i32.store (local.get $tos) (i32.const 43))
    (i32.add (local.get $tos) (i32.const 4))

    ;; Word call
    (call_indirect (type $push) (i32.const 10) (i32.const 9))

    ;; Pop   
    (tee_local $tos (i32.sub (i32.const 4)))
    (local.get $tos)
    (i32.load)
    (drop)

    ;; Conditional
    (if (param i32) (result i32) (i32.ne (call_indirect (type $pop) (i32.const 2)) (i32.const 0))
      (then
        (call_indirect (type $push) (i32.const 10) (i32.const 9))
        (nop)
        (nop))
      (else
        (nop)
        (nop)
        (nop)))

    ;; do loop
    (local.set $index1 (call_indirect (type $pop) (i32.const 2)))
    (local.set $end1 (call_indirect (type $pop) (i32.const 2)))
    (local.set $incr1 (i32.ge_s (local.get $end1) (local.get $index1)))
    (block $endDoLoop
      (loop $doLoop
        (nop)
        (local.set $index1 (i32.add (local.get $index1) (i32.const 1)))
        (if (i32.eqz (local.get $incr1))
          (then (br_if $endDoLoop (i32.le_s (local.get $index1) (local.get $end1))))
          (else (br_if $endDoLoop (i32.ge_s (local.get $index1) (local.get $end1)))))
        (br $doLoop)))

    ;; repeat loop
    (block $endRepeatLoop (param i32) (result i32)
      (loop $repeatLoop (param i32) (result i32)
        (nop)
        (br_if $endRepeatLoop (i32.eqz (call_indirect (type $pop) (i32.const 2))))
        (nop)
        (br $repeatLoop)))

    ;; repeat loop with fallthrough
    (loop $repeatLoop (param i32) (result i32)
      (nop)
      (br_if $repeatLoop (i32.eqz (call_indirect (type $pop) (i32.const 2))))
      (nop))

    
    (call $word (local.get $n)))

  (elem (i32.const 44) $word))
