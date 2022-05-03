(module $sieve-raw
  (memory 8192)
  (func $sieve (export "sieve") (param $n i32) (result i32)
    (local $i i32)
    (local $j i32)
    (local $last i32)

    (local.set $i (i32.const 0))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.ge_s (local.get $i) (local.get $n)))
        (i32.store8 (local.get $i) (i32.const 1))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)))

    (local.set $i (i32.const 2))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.ge_s (i32.mul (local.get $i) (local.get $i)) (local.get $n)))
        (if (i32.eq (i32.load8_s (local.get $i)) (i32.const 1))
          (then
            (local.set $j (i32.mul (local.get $i) (local.get $i)))
            (loop $innerLoop
              (i32.store8 (local.get $j) (i32.const 0))
              (local.set $j (i32.add (local.get $j) (local.get $i)))
              (br_if $innerLoop (i32.lt_s (local.get $j) (local.get $n))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)))

    (local.set $i (i32.const 2))
    (loop $loop
      (if (i32.eq (i32.load8_s (local.get $i)) (i32.const 1))
        (then
          (local.set $last (local.get $i))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $loop (i32.lt_s (local.get $i) (local.get $n))))
    
    (return (local.get $last))))
