(module
  (import "js" "print" (func $print (param i32)))
  (memory 8192)
  (func $sieve (export "sieve") (param $n i32) (result i32)
    (local $i i32)
    (local $j i32)
    (local $last i32)

    (set_local $i (i32.const 0))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.ge_s (get_local $i) (get_local $n)))
        (i32.store8 (get_local $i) (i32.const 1))
        (set_local $i (i32.add (get_local $i) (i32.const 1)))
        (br $loop)))

    (set_local $i (i32.const 2))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.ge_s (i32.mul (get_local $i) (get_local $i)) 
                                  (get_local $n)))
        (if (i32.eq (i32.load8_s (get_local $i)) (i32.const 1))
          (then
            (set_local $j (i32.mul (get_local $i) (get_local $i)))
            (block $endInnerLoop
              (loop $innerLoop
                (i32.store8 (get_local $j) (i32.const 0))
                (set_local $j (i32.add (get_local $j) (get_local $i)))
                (br_if $endInnerLoop (i32.ge_s (get_local $j) (get_local $n)))
                (br $innerLoop)))))
        (set_local $i (i32.add (get_local $i) (i32.const 1)))
        (br $loop)))

    (set_local $i (i32.const 2))
    (block $endLoop
      (loop $loop
        (if (i32.eq (i32.load8_s (get_local $i)) (i32.const 1))
          (then
            ;; (call $print (get_local $i))
            (set_local $last (get_local $i))))
        (set_local $i (i32.add (get_local $i) (i32.const 1)))
        (br_if $endLoop (i32.ge_s (get_local $i) (get_local $n)))
        (br $loop)))
    
    (return (get_local $last))))
