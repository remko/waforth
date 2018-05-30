;; Template for defining 'word' modules
;; Used to 'reverse engineer' the binary code to emit from the compiler
(module $quadruple
  (import "env" "table" (table 4 anyfunc))
  (import "env" "memory" (memory 1))
  (import "env" "tos" (global $tos (mut i32)))

  (type $void (func))
  (type $push (func (param i32)))
  (type $pop (func (result i32)))
  (type $endLoop (func (param i32) (result i32)))

  (func $word (param $n i32)
    (local $index1 i32)
    (local $end1 i32)
    (local $incr1 i32)

    ;; Push
    (i32.store (get_global $tos) (i32.const 43))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4)))

    ;; Word call
    (call_indirect (type $push) (i32.const 10) (i32.const 9))

    ;; Conditional
    (i32.load (get_global $tos))
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4)))
    (if (i32.ne (i32.const 0))
      (then
        (nop)
        (nop))
      (else
        (nop)
        (nop)
        (nop)))

    ;; do loop
    (set_local $index1 (call_indirect (type $pop) (i32.const 2)))
    (set_local $end1 (call_indirect (type $pop) (i32.const 2)))
    (set_local $incr1 (i32.ge_s (get_local $end1) (get_local $index1)))
    (block $endDoLoop
      (loop $doLoop
        (nop)
        (set_local $index1 (i32.add (get_local $index1) (i32.const 1)))
        (if (i32.eqz (get_local $incr1))
          (then (br_if $endDoLoop (i32.le_s (get_local $index1) (get_local $end1))))
          (else (br_if $endDoLoop (i32.ge_s (get_local $index1) (get_local $end1)))))
        (br $doLoop)))

    ;; repeat loop
    (block $endRepeatLoop
      (loop $repeatLoop
        (nop)
        (br_if $endRepeatLoop (i32.eqz (call_indirect (type $pop) (i32.const 2))))
        (nop)
        (br $repeatLoop)))
    
    (call $word (get_local $n)))

  (elem (i32.const 44) $word))
