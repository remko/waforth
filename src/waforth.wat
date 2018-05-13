
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Assembler Macros
;;
;; This is not part of the WebAssembly spec, but uses some custom assembler
;; infrastructure.
;;
;; Although you can go crazy wild with macro programming, I tried to keep this
;; as simple as possible.
;;
;; Variables and functions in the WebAssembly module definition starting with 
;; ! are processed by the assembler, and defined in this section.
;; The assembler also fixes the order of "table" in the module  (which needs to come
;; before "elem"s, but due to our assembly macros building up the table need to come
;; last in our definition.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(require "tools/assembler.rkt")

(define (char-index cs char pos)
  (cond ((null? cs) #f)
        ((char=? char (car cs)) pos)
        (else (char-index (cdr cs) char (add1 pos)))))

(define !baseBase #x100)
(define !wordBase #x200)
;; Compiled modules are limited to 4096 bytes until Chrome refuses to load
;; them synchronously
(define !moduleHeaderBase #x1000) 
(define !preludeDataBase #x2000)
(define !returnStackBase #x4000)
(define !stackBase #x10000)
(define !dictionaryBase #x20000)
(define !memorySize (* 1 1024 1024))

(define !moduleHeader 
  (string-append
    "\u0000\u0061\u0073\u006D" ;; Header
    "\u0001\u0000\u0000\u0000" ;; Version

    "\u0001" "\u0011" ;; Type section
      "\u0004" ;; #Entries
        "\u0060\u0000\u0000" ;; (func)
        "\u0060\u0001\u007F\u0000" ;; (func (param i32))
        "\u0060\u0000\u0001\u007F" ;; (func (result i32))
        "\u0060\u0001\u007f\u0001\u007F" ;; (func (param i32) (result i32))

    "\u0002" "\u0020" ;; Import section
      "\u0002" ;; #Entries
      "\u0003\u0065\u006E\u0076" "\u0005\u0074\u0061\u0062\u006C\u0065" ;; 'env' . 'table'
        "\u0001" "\u0070" "\u0000" "\u0004" ;; table, anyfunc, flags, initial size
      "\u0003\u0065\u006E\u0076" "\u0009\u0074\u0061\u0062\u006C\u0065\u0042\u0061\u0073\u0065" ;; 'env' . 'tableBase
        "\u0003" "\u007F" "\u0000" ;; global, i32, immutable
    
    "\u0003" "\u0002" ;; Function section
      "\u0001" ;; #Entries
      "\u0000" ;; Type 0
      
    "\u0009" "\u0007" ;; Element section
      "\u0001" ;; #Entries
      "\u0000" ;; Table 0
      "\u0023\u0000\u000B" ;; get_global 0, end
      "\u0001" ;; #elements
        "\u0000" ;; function 0

    "\u000A" "\u00FF\u0000\u0000\u0000" ;; Code section (padded length)
    "\u0001" ;; #Bodies
      "\u00FE\u0000\u0000\u0000" ;; Body size (padded)
      "\u0000")) ;; #locals
(define !moduleHeaderSize (string-length !moduleHeader))
(define !moduleHeaderCodeSizeOffset (char-index (string->list !moduleHeader) #\u00FF 0))
(define !moduleHeaderBodySizeOffset (char-index (string->list !moduleHeader) #\u00FE 0))

(define !moduleBodyBase (+ !moduleHeaderBase !moduleHeaderSize))
(define !moduleHeaderCodeSizeBase (+ !moduleHeaderBase !moduleHeaderCodeSizeOffset))
(define !moduleHeaderBodySizeBase (+ !moduleHeaderBase !moduleHeaderBodySizeOffset))


(define !fNone #x0)
(define !fImmediate #x80)
(define !fHidden #x20)
(define !lengthMask #x1F)

;; Predefined table indices
(define !pushIndex 1)
(define !popIndex 2)
(define !beginDoIndex 3)
(define !endDoIndex 4)
(define !displayIndex 5)
(define !tableStartIndex 6)

(define !dictionaryLatest 0)
(define !dictionaryTop !dictionaryBase)

(define (!def_word name f (flags 0))
  (let* ((idx !tableStartIndex) 
         (base !dictionaryTop) 
         (previous !dictionaryLatest)
         (name-entry-length (* (ceiling (/ (+ (string-length name) 1) 4)) 4))
         (size (+ 8 name-entry-length)))
    (set! !tableStartIndex (+ !tableStartIndex 1))
    (set! !dictionaryLatest !dictionaryTop)
    (set! !dictionaryTop (+ !dictionaryTop size))
    `((elem (i32.const ,(eval idx)) ,(string->symbol f))
      (data 
        (i32.const ,(eval base))
        ,(integer->integer-bytes previous 4 #f #f) 
        ,(integer->integer-bytes (bitwise-ior (string-length name) flags) 1 #f #f)
        ,(eval name)
        ,(make-bytes (- name-entry-length (string-length name) 1) 0)
        ,(integer->integer-bytes idx 4 #f #f)))))

(define (!+ x y) (list (+ x y)))
(define (!/ x y) (list (ceiling (/ x y))))

(define !preludeData "")
(define (!prelude c) 
  (set! !preludeData 
    (regexp-replace* #px"[ ]?\n[ ]?" 
      (regexp-replace* #px"[ ]+" 
        (regexp-replace* #px"[\n]+" (string-append !preludeData "\n" c) "\n")
        " ")
      "\n"))
  (list))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; WebAssembly module definition
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(module
  (import "shell" "emit" (func $shell_emit (param i32)))
  (import "shell" "key" (func $shell_key (result i32)))
  (import "shell" "load" (func $shell_load (param i32 i32) (result i32)))
  (import "shell" "debug" (func $shell_debug (param i32)))

  (import "tmp" "find" (func $tmpFind (param i32 i32)))

  (memory (export "memory") (!/ !memorySize 65536))

  (type $void (func))

  (global $tos (mut i32) (i32.const !stackBase))
  (global $tors (mut i32) (i32.const !returnStackBase))
  (global $state (mut i32) (i32.const 0))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Built-in words
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; 6.1.0010 ! 
  (func $!
    (local $bbtos i32)
    (i32.store (i32.load (i32.sub (get_global $tos) (i32.const 4)))
               (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))))
    (set_global $tos (get_local $bbtos)))
  (!def_word "!" "$!")

  ;; 6.1.0090
  (func $star
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.mul (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (!def_word "*" "$star")

  ;; 6.1.0120
  (func $plus
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.add (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (!def_word "+" "$plus")

  ;; 6.1.0140
  (func $plus-loop
    (if (i32.eqz (get_global $state)) (unreachable))
    (call $compilePlusLoop))
  (!def_word "+LOOP" "$plus-loop" !fImmediate)

  ;; 6.1.0150
  (func $comma
    (i32.store
      (get_global $here)
      (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $here (i32.add (get_global $here) (i32.const 4)))
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4))))
  (!def_word "," "$comma")

  ;; 6.1.0160
  (func $minus
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.sub (i32.load (get_local $bbtos))
                        (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (!def_word "-" "$minus")

  ;; 6.1.0180
  (func $.q
    (call $Sq)
    (call $emitICall (i32.const 0) (i32.const !displayIndex)))
  (!def_word ".\"" "$.q" !fImmediate)

  ;; 6.1.0230
  (func $/
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.div_s (i32.load (get_local $bbtos))
                          (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (!def_word "/" "$/")

  ;; 6.1.0240
  (func $/MOD
    (local $btos i32)
    (local $bbtos i32)
    (local $n1 i32)
    (local $n2 i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.rem_s (tee_local $n1 (i32.load (get_local $bbtos)))
                          (tee_local $n2 (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                                             (i32.const 4)))))))
    (i32.store (get_local $btos) (i32.div_s (get_local $n1) (get_local $n2))))
  (!def_word "/MOD" "$/MOD")

  ;; 6.1.0250
  (func $0<
    (local $btos i32)
    (if (i32.lt_s (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                     (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (get_local $btos) (i32.const -1)))
      (else (i32.store (get_local $btos) (i32.const 0)))))
  (!def_word "0<" "$0<")


  ;; 6.1.0270
  (func $zero-equals
    (local $btos i32)
    (if (i32.eqz (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                     (i32.const 4)))))
      (then (i32.store (get_local $btos) (i32.const -1)))
      (else (i32.store (get_local $btos) (i32.const 0)))))
  (!def_word "0=" "$zero-equals")

  ;; 6.1.0290
  (func $one-plus
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.add (i32.load (get_local $btos)) (i32.const 1))))
  (!def_word "1+" "$one-plus")

  ;; 6.1.0300
  (func $one-minus
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.sub (i32.load (get_local $btos)) (i32.const 1))))
  (!def_word "1-" "$one-minus")

  ;; 6.1.0370 
  (func $two-drop
    (set_global $tos (i32.sub (get_global $tos) (i32.const 8))))
  (!def_word "2DROP" "$two-drop")

  ;; 6.1.0380
  (func $two-dupe
    (i32.store (get_global $tos)
               (i32.load (i32.sub (get_global $tos) (i32.const 8))))
    (i32.store (i32.add (get_global $tos) (i32.const 4))
               (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 8))))
  (!def_word "2DUP" "$two-dupe")

  ;; 6.1.0450
  (func $colon
    (call $create)
    (call $hidden)
    (set_global $cp (i32.const !moduleBodyBase))
    (call $right-bracket))
  (!def_word ":" "$colon")

  ;; 6.1.0460
  (func $semicolon
    (local $bodySize i32)

    (call $emitEnd)

    (set_local $bodySize (i32.sub (get_global $cp) (i32.const !moduleHeaderBase))) 
    
    ;; Update code size
    (i32.store 
      (i32.const !moduleHeaderCodeSizeBase)
      (call $leb128-4p
         (i32.sub (get_local $bodySize) 
                  (i32.const (!+ !moduleHeaderCodeSizeOffset 4)))))

    ;; Update body size
    (i32.store 
      (i32.const !moduleHeaderBodySizeBase)
      (call $leb128-4p
         (i32.sub (get_local $bodySize) 
                  (i32.const (!+ !moduleHeaderBodySizeOffset 4)))))

    ;; Load the code and store the index
    (i32.store
      (call $body (get_global $latest))
      (call $shell_load (i32.const !moduleHeaderBase) (get_local $bodySize)))

    (call $hidden)
    (call $left-bracket))
  (!def_word ";" "$semicolon" !fImmediate)

  ;; 6.1.0480
  (func $less-than
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_s (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
      (then (i32.store (get_local $bbtos) (i32.const -1)))
      (else (i32.store (get_local $bbtos) (i32.const 0))))
    (set_global $tos (get_local $btos)))
  (!def_word "<" "$less-than")

  ;; 6.1.0540
  (func $greater-than
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.gt_s (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
      (then (i32.store (get_local $bbtos) (i32.const -1)))
      (else (i32.store (get_local $bbtos) (i32.const 0))))
    (set_global $tos (get_local $btos)))
  (!def_word ">" "$greater-than")

  ;; 6.1.0630 
  (func $?DUP
    (local $btos i32)
    (if (i32.ne (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                (i32.const 0))
      (then
        (i32.store (get_global $tos)
                   (i32.load (get_local $btos)))
        (set_global $tos (i32.add (get_global $tos) (i32.const 4))))))
  (!def_word "?DUP" "$?DUP")

  ;; 6.1.0650
  (func $@
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.load (i32.load (get_local $btos)))))
  (!def_word "@" "$@")

  ;; 6.1.0705
  (func $ALIGN
    (set_global $here (i32.and
                        (i32.add (get_global $here) (i32.const 3))
                        (i32.const -4 #| ~3 |#))))
  (!def_word "ALIGN" "$ALIGN")

  ;; 6.1.0750 
  (func $BASE 
   (i32.store (get_global $tos) (i32.const !baseBase))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "BASE" "$BASE")
  
  ;; 6.1.0760 
  (func $begin
    (if (i32.eqz (get_global $state)) (unreachable))
    (call $compileBegin))
  (!def_word "BEGIN" "$begin" !fImmediate)

  ;; 6.1.0770
  (func $bl (call $push (i32.const 32)))
  (!def_word "BL" "$bl")

  ;; 6.1.0850
  (func $c-store
    (local $bbtos i32)
    (i32.store8 (i32.load (i32.sub (get_global $tos) (i32.const 4)))
                (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))))
    (set_global $tos (get_local $bbtos)))
  (!def_word "C!" "$c-store")

  ;; 6.1.0870
  (func $c-fetch
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.load8_u (i32.load (get_local $btos)))))
  (!def_word "C@" "$c-fetch")

  ;; 6.1.0895
  (func $CHAR
    (call $word)
    (i32.store (i32.sub (get_global $tos) (i32.const 4))
               (i32.load8_u (i32.const (!+ !wordBase 4)))))
  (!def_word "CHAR" "$CHAR")

  ;; 6.1.1000
  (func $create
    (local $length i32)

    (i32.store (get_global $here) (get_global $latest))
    (set_global $latest (get_global $here))
    (set_global $here (i32.add (get_global $here) (i32.const 4)))

    (call $word)
    (drop (call $pop))
    (i32.store8 (get_global $here) (tee_local $length (i32.load (i32.const !wordBase))))
    (set_global $here (i32.add (get_global $here) (i32.const 1)))

    (call $memcpy (get_global $here) (i32.const (!+ !wordBase 4)) (get_local $length))

    (set_global $here (i32.add (get_global $here) (get_local $length)))

    (call $ALIGN)

    ;; Leave space for the code pointer
    (i32.store (get_global $here) (i32.const 0))
    (set_global $here (i32.add (get_global $here) (i32.const 4))))
  (!def_word "CREATE" "$create")

  ;; 6.1.1240
  (func $do
    (if (i32.eqz (get_global $state)) (unreachable))
    (call $compileDo))
  (!def_word "DO" "$do" !fImmediate)

  ;; 6.1.1260
  (func $drop
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4))))
  (!def_word "DROP" "$drop")

  ;; 6.1.1290
  (func $dupe
   (i32.store
    (get_global $tos)
    (i32.load (i32.sub (get_global $tos) (i32.const 4))))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "DUP" "$dupe")

  ;; 6.1.1310
  (func $else
    (if (i32.eqz (get_global $state)) (unreachable))
    (call $compileElse))
  (!def_word "ELSE" "$else" !fImmediate)

  ;; 6.1.1320
  (func $emit
   (call $shell_emit (i32.load (i32.sub (get_global $tos) (i32.const 4))))
   (set_global $tos (i32.sub (get_global $tos) (i32.const 4))))
  (!def_word "EMIT" "$emit")

  ;; 6.1.1550
  (func $find (export "FIND")
    (call $tmpFind (get_global $latest) (get_global $tos))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "FIND" "$find")

  ;; 6.1.1650
  (func $here
   (i32.store (get_global $tos) (get_global $here))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "HERE" "$here")

  ;; 6.1.1680
  (func $i
    (i32.store (get_global $tos) (i32.load (i32.sub (get_global $tors) (i32.const 4))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "I" "$i")

  ;; 6.1.1700
  (func $if
    (if (i32.eqz (get_global $state)) (unreachable))
    (call $compileIf))
  (!def_word "IF" "$if" !fImmediate)

  ;; 6.1.1710
  (func $immediate
    (i32.store 
      (i32.add (get_global $latest) (i32.const 4))
      (i32.or 
        (i32.load (i32.add (get_global $latest) (i32.const 4)))
        (i32.const !fImmediate))))
  (!def_word "IMMEDIATE" "$immediate")

  ;; 6.1.1730
  (func $j
    (i32.store (get_global $tos) (i32.load (i32.sub (get_global $tors) (i32.const 12))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "J" "$j")

  ;; 6.1.1750
  (func $key
   (i32.store (get_global $tos) (call $readChar))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "KEY" "$key")

  ;; 6.1.1780
  (func $literal
    (call $compilePush (call $pop)))
  (!def_word "LITERAL" "$literal" !fImmediate)

  ;; 6.1.1800
  (func $loop
    (if (i32.eqz (get_global $state)) (unreachable))
    (call $compileLoop))
  (!def_word "LOOP" "$loop" !fImmediate)

  ;; 6.1.1910
  (func $negate
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.sub (i32.const 0) (i32.load (get_local $btos)))))
  (!def_word "NEGATE" "$negate")

  ;; 6.1.1990
  (func $over
    (i32.store (get_global $tos)
               (i32.load (i32.sub (get_global $tos) (i32.const 8))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "OVER" "$over")

  ;; 6.1.2120 
  (func $RECURSE 
    (call $compileRecurse))
  (!def_word "RECURSE" "$RECURSE" !fImmediate)


  ;; 6.1.2140
  (func $repeat
    (if (i32.eqz (get_global $state)) (unreachable))
    (call $compileRepeat))
  (!def_word "REPEAT" "$repeat" !fImmediate)

  ;; 6.1.2160 ROT 
  (func $ROT
    (local $tmp i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $bbbtos i32)
    (set_local $tmp (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
    (i32.store (get_local $btos) 
               (i32.load (tee_local $bbbtos (i32.sub (get_global $tos) (i32.const 12)))))
    (i32.store (get_local $bbbtos) 
               (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))))
    (i32.store (get_local $bbtos) 
               (get_local $tmp)))
  (!def_word "ROT" "$ROT")

  ;; 6.1.2165
  (func $Sq
    (local $c i32)
    (local $start i32)
    (set_local $start (get_global $here))
    (block $endLoop
      (loop $loop
        (if (i32.eqz (tee_local $c (call $readChar)))
          (then
            (unreachable)))
        (br_if $endLoop (i32.eq (get_local $c) (i32.const 0x22)))
        (i32.store8 (get_global $here) (get_local $c))
        (set_global $here (i32.add (get_global $here) (i32.const 1)))
        (br $loop)))
    (call $compilePush (get_local $start))
    (call $compilePush (i32.sub (get_global $here) (get_local $start)))
    (call $ALIGN))
  (!def_word "S\"" "$Sq" !fImmediate)

  ;; 6.1.2220
  (func $space (call $bl) (call $emit))
  (!def_word "SPACE" "$space")


  ;; 6.1.2260
  (func $swap
    (local $btos i32)
    (local $bbtos i32)
    (local $tmp i32)
    (set_local $tmp (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))))
    (i32.store (get_local $bbtos) 
               (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
    (i32.store (get_local $btos) (get_local $tmp)))
  (!def_word "SWAP" "$swap")

  ;; 6.1.2270
  (func $then
    (if (i32.eqz (get_global $state)) (unreachable))
    (call $compileThen))
  (!def_word "THEN" "$then" !fImmediate)

  ;; 6.1.2430
  (func $while
    (if (i32.eqz (get_global $state)) (unreachable))
    (call $compileWhile))
  (!def_word "WHILE" "$while" !fImmediate)

  ;; 6.1.2450
  (func $word (export "WORD") 
    (local $char i32)
    (local $stringPtr i32)

    ;; Search for first non-blank character
    (block $endSkipBlanks
     (loop $skipBlanks
       (set_local $char (call $readChar))
       
       ;; Skip comments (if necessary)
       (if (i32.eq (get_local $char) (i32.const 0x5C #| '\' |#))
         (then 
          (loop $skipComments
            (set_local $char (call $readChar))
            (br_if $skipBlanks (i32.eq (get_local $char) (i32.const 0x0a #| '\n' |#)))
            (br_if $endSkipBlanks (i32.eq (get_local $char) (i32.const -1)))
            (br $skipComments))))

       (br_if $skipBlanks (i32.eq (get_local $char) (i32.const 0x20 #| ' ' |#)))
       (br_if $skipBlanks (i32.eq (get_local $char) (i32.const 0x0a #| ' ' |#)))
       (br $endSkipBlanks)))

    (if (i32.ne (get_local $char) (i32.const -1)) 
      (then 
        ;; Search for first blank character
        (i32.store8 (i32.const (!+ !wordBase 4)) (get_local $char))
        (set_local $stringPtr (i32.const (!+ !wordBase 5)))
        (block $endReadChars
         (loop $readChars
           (set_local $char (call $readChar))
           (br_if $endReadChars (i32.eq (get_local $char) (i32.const 0x20 #| ' ' |#)))
           (br_if $endReadChars (i32.eq (get_local $char) (i32.const 0x0a #| ' ' |#)))
           (br_if $endReadChars (i32.eq (get_local $char) (i32.const -1)))
           (i32.store8 (get_local $stringPtr) (get_local $char))
           (set_local $stringPtr (i32.add (get_local $stringPtr) (i32.const 0x1)))
           (br $readChars))))
      (else
        ;; Reached end of input
        (set_local $stringPtr (i32.const (!+ !wordBase 4)))))

     ;; Write word length
     (i32.store (i32.const !wordBase) 
       (i32.sub (get_local $stringPtr) (i32.const (!+ !wordBase 4))))
     
     (call $push (i32.const !wordBase)))
  (!def_word "WORD" "$word")

  ;; 6.1.2500
  (func $left-bracket
    (set_global $state (i32.const 0)))
  (!def_word "[" "$left-bracket" !fImmediate)

  ;; 6.1.2540
  (func $right-bracket
    (set_global $state (i32.const 1)))
  (!def_word "]" "$right-bracket")

  ;; 6.2.0280
  (func $zero-greater
    (local $btos i32)
    (if (i32.gt_s (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                     (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (get_local $btos) (i32.const -1)))
      (else (i32.store (get_local $btos) (i32.const 0)))))
  (!def_word "0>" "$zero-greater")

  ;; 6.2.1350
  (func $erase
    (local $bbtos i32)
    (call $memset (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (i32.const 0)
                  (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $tos (get_local $bbtos)))
  (!def_word "ERASE" "$erase")

  (func $dspFetch
    (i32.store
     (get_global $tos)
     (get_global $tos))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "DSP@" "$dspFetch")

  (func $S0
    (call $push (i32.const !stackBase)))
  (!def_word "S0" "$S0")

  (func $latest
   (i32.store (get_global $tos) (get_global $latest))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "LATEST" "$latest")

  ;; High-level words
  (!prelude #<<EOF

    : UWIDTH BASE @ / ?DUP IF RECURSE 1+ ELSE 1 THEN ;

    : '\n' 10 ;
    \ : 'A' [ CHAR A ] LITERAL ;
    \ : '0' [ CHAR 0 ] LITERAL ;
    
    \ 6.1.0990
    : CR '\n' EMIT ;

    \ 6.1.2230
    : SPACES BEGIN DUP 0> WHILE SPACE 1- REPEAT DROP ;

    \ 6.1.2320
    : U.
      BASE @ /MOD
      ?DUP IF RECURSE THEN
      DUP 10 < IF 48 ELSE 10 - 65 THEN
      +
      EMIT
    ;

    \ 15.6.1.0220
    : .S
      DSP@ S0 
      BEGIN
        2DUP >
      WHILE
        DUP @ U.
        SPACE
        4 +
      REPEAT
      2DROP
    ;

    \ 6.2.0210
    : .R
      SWAP
      DUP 0< IF NEGATE 1 SWAP ROT 1- ELSE 0 SWAP ROT THEN
      SWAP DUP UWIDTH ROT SWAP -
      SPACES SWAP
      IF 45 EMIT THEN
      U.
    ;

    \ 6.1.0180
    : . 0 .R SPACE ;
EOF
)

  ;; Reads a number from the word buffer, and puts it on the stack. 
  ;; Returns -1 if an error occurred.
  ;; TODO: Support other bases
  (func $number (result i32)
    (local $sign i32)
    (local $length i32)
    (local $char i32)
    (local $value i32)
    (local $base i32)
    (local $p i32)
    (local $end i32)

    (if (i32.eqz (tee_local $length (i32.load (i32.const !wordBase))))
      (return (i32.const -1)))

    (set_local $p (i32.const (!+ !wordBase 4)))
    (set_local $end (i32.add (i32.const (!+ !wordBase 4)) (get_local $length)))
    (set_local $base (i32.load (i32.const !baseBase)))

    ;; Read first character
    (if (i32.eq (tee_local $char (i32.load8_u (i32.const (!+ !wordBase 4))))
                (i32.const 0x2d #| '-' |#))
      (then 
        (set_local $sign (i32.const -1))
        (set_local $char (i32.const 48)))
      (else (set_local $sign (i32.const 1))))

    ;; Read all characters
    (set_local $value (i32.const 0))
    (block $endLoop
      (loop $loop
        (if (i32.or (i32.lt_s (get_local $char) (i32.const 48 #| '0' |# ))
                    (i32.gt_s (get_local $char) (i32.const 57 #| '9' |# )))
          (then (return (i32.const -1))))
        (set_local $value (i32.add (i32.mul (get_local $value) (get_local $base))
                                   (i32.sub (get_local $char)
                                            (i32.const 48))))
        (set_local $p (i32.add (get_local $p) (i32.const 1)))
        (br_if $endLoop (i32.eq (get_local $p) (get_local $end)))
        (set_local $char (i32.load8_s (get_local $p)))
        (br $loop)))
    (call $push (i32.mul (get_local $sign) (get_local $value)))
    (return (i32.const 0)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Interpreter
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; Interprets the string in the input, until the end of string is reached.
  ;; Returns 0 if processed, 1 if still compiling, -1 if a word was not found.
  (func $interpret (result i32)
    (local $findResult i32)
    (local $findToken i32)
    (block $endLoop
      (loop $loop
        (call $word)
        (br_if $endLoop (i32.eqz (i32.load (i32.const !wordBase))))
        (call $find)
        (set_local $findResult (call $pop))
        (set_local $findToken (call $pop))
        (if (i32.eqz (get_local $findResult))
          (then ;; Not in the dictionary. Is it a number?
            (if (i32.eqz (call $number))
              (then ;; It's a number. Are we compiling?
                (if (i32.ne (get_global $state) (i32.const 0))
                  (then
                    ;; We're compiling. Pop it off the stack and 
                    ;; add it to the compiled list
                    (call $compilePush (call $pop)))))
                  ;; We're not compiling. Leave the number on the stack.
              (else ;; It's not a number.
                (drop (call $pop))
                ;; TODO: Give error
                (return (i32.const -1)))))
          (else ;; Found the word. Are we compiling?
            (if (i32.eqz (get_global $state))
              (then
                ;; We're not compiling. Execute the word.
                (call_indirect (type $void) (i32.load (call $body (get_local $findToken)))))
              (else
                ;; We're compiling. Is it immediate?
                (if (i32.eq (get_local $findResult) (i32.const 1))
                  (then ;; Immediate. Execute the word.
                    (call_indirect (type $void) (i32.load (call $body (get_local $findToken)))))
                  (else ;; Not Immediate. Compile the word call.
                    (call $emitICall 
                          (i32.const 0)
                          (i32.load (call $body (get_local $findToken))))))))))
          (br $loop)))
    ;; 'WORD' left the address on the stack
    (drop (call $pop))
    (return (get_global $state)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Compiler functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $compilePush (param $n i32)
    (call $emitConst (get_local $n))
    (call $emitICall (i32.const 1) (i32.const !pushIndex)))

  (func $compileIf
    (call $emitICall (i32.const 2) (i32.const !popIndex))
    (call $emitConst (i32.const 0))

    ;; ne
    (i32.store8 (get_global $cp) (i32.const 0x47))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))

    ;; if (empty block)
    (i32.store8 (get_global $cp) (i32.const 0x04))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (i32.const 0x40))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $compileElse
    (i32.store8 (get_global $cp) (i32.const 0x05))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $compileThen (call $emitEnd))

  (func $compileDo
    (call $emitICall (i32.const 0) (i32.const !beginDoIndex))
    (call $emitBlock)
    (call $emitLoop))
  
  (func $compileLoop 
    (call $emitConst (i32.const 1))
    (call $compileLoopEnd))

  (func $compilePlusLoop 
    (call $emitICall (i32.const 2) (i32.const !popIndex))
    (call $compileLoopEnd))

  ;; Assumes increment is on the operand stack
  (func $compileLoopEnd
    (call $emitICall (i32.const 3) (i32.const !endDoIndex))
    (call $emitBrIf (i32.const 1))
    (call $emitBr (i32.const 0))
    (call $emitEnd)
    (call $emitEnd))

  (func $compileBegin
    (call $emitBlock)
    (call $emitLoop))

  (func $compileWhile
    (call $emitICall (i32.const 2) (i32.const !popIndex))

    ;; eqz
    (i32.store8 (get_global $cp) (i32.const 0x45))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))

    (call $emitBrIf (i32.const 1)))

  (func $compileRepeat
    (call $emitBr (i32.const 0))
    (call $emitEnd)
    (call $emitEnd))

  (func $compileRecurse
    ;; call 0
    (i32.store8 (get_global $cp) (i32.const 0x10))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (i32.const 0x00))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitICall (param $type i32) (param $n i32)
    (call $emitConst (get_local $n))

    (i32.store8 (get_global $cp) (i32.const 0x11))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (get_local $type))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (i32.const 0x00))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitBlock
    (i32.store8 (get_global $cp) (i32.const 0x02))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (i32.const 0x40))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitLoop
    (i32.store8 (get_global $cp) (i32.const 0x03))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (i32.const 0x40))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitConst (param $n i32)
    (i32.store8 (get_global $cp) (i32.const 0x41))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (set_global $cp (call $leb128 (get_global $cp) (get_local $n))))

  (func $emitEnd
    (i32.store8 (get_global $cp) (i32.const 0x0b))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitBr (param $n i32)
    (i32.store8 (get_global $cp) (i32.const 0x0c))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (get_local $n))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitBrIf (param $n i32)
    (i32.store8 (get_global $cp) (i32.const 0x0d))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (get_local $n))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Word helper function
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $push (export "push") (param $v i32)
    (i32.store (get_global $tos) (get_local $v))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (elem (i32.const !pushIndex) $push)

  (func $pop (export "pop") (result i32)
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4)))
    (i32.load (get_global $tos)))
  (elem (i32.const !popIndex) $pop)

  (func $beginDo
    (i32.store (i32.add (get_global $tors) (i32.const 4)) (call $pop))
    (i32.store (get_global $tors) (call $pop))
    (set_global $tors (i32.add (get_global $tors) (i32.const 8))))
  (elem (i32.const !beginDoIndex) $beginDo)

  (func $endDo (param $incr i32) (result i32)
    (local $i i32)
    (local $bbtors i32)
    (local $btors i32)
    (if (i32.ge_s (tee_local $i (i32.add (i32.load (tee_local $btors (i32.sub (get_global $tors) 
                                                                            (i32.const 4))))
                                       (get_local $incr)))
                (i32.load (tee_local $bbtors (i32.sub (get_global $tors) (i32.const 8)))))
      (then
        (set_global $tors (get_local $bbtors))
        (return (i32.const 1)))
      (else
        (i32.store (get_local $btors) (get_local $i))
        (return (i32.const 0))))
    (unreachable))
  (elem (i32.const !endDoIndex) $endDo)

  (func $display
    (local $p i32)
    (local $end i32)
    (set_local $end (i32.add (call $pop) (tee_local $p (call $pop))))
    (block $endLoop
     (loop $loop
       (br_if $endLoop (i32.eq (get_local $p) (get_local $end)))
       (call $shell_emit (i32.load8_u (get_local $p)))
       (set_local $p (i32.add (get_local $p) (i32.const 1)))
       (br $loop))))
  (elem (i32.const !displayIndex) $display)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Helper functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; Toggle the hidden flag
  (func $hidden
    (i32.store 
      (i32.add (get_global $latest) (i32.const 4))
      (i32.xor 
        (i32.load (i32.add (get_global $latest) (i32.const 4)))
        (i32.const !fHidden))))

  (func $memcpy (param $dst i32) (param $src i32) (param $n i32)
    (local $end i32)
    (set_local $end (i32.add (get_local $src) (get_local $n)))
    (block $endLoop
     (loop $loop
       (br_if $endLoop (i32.eq (get_local $src) (get_local $end)))
       (i32.store (get_local $dst) (i32.load (get_local $src)))
       (set_local $src (i32.add (get_local $src) (i32.const 1)))
       (set_local $dst (i32.add (get_local $dst) (i32.const 1)))
       (br $loop))))

   (func $memset (param $dst i32) (param $c i32) (param $n i32)
    (local $end i32)
    (set_local $end (i32.add (get_local $dst) (get_local $n)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eq (get_local $dst) (get_local $end)))
        (i32.store8 (get_local $dst) (get_local $c))
        (set_local $dst (i32.add (get_local $dst) (i32.const 1)))
        (br $loop))))

  ;; LEB128 with fixed 4 bytes (with padding bytes)
  ;; This means we can only represent 28 bits, which should be plenty.
  (func $leb128-4p (export "leb128_4p") (param $n i32) (result i32)
    (i32.or
      (i32.or 
        (i32.or
          (i32.or
            (i32.and (get_local $n) (i32.const 0x7F))
            (i32.shl
              (i32.and
                (get_local $n)
                (i32.const 0x3F80))
              (i32.const 1)))
          (i32.shl
            (i32.and
              (get_local $n)
              (i32.const 0x1FC000))
            (i32.const 2)))
        (i32.shl
          (i32.and
            (get_local $n)
            (i32.const 0xFE00000))
          (i32.const 3)))
      (i32.const 0x808080)))

  ;; Encodes `value` as leb128 to `p`, and returns the address pointing after the data
  (func $leb128 (export "leb128") (param $p i32) (param $value i32) (result i32)
    (local $more i32)
    (local $byte i32)
    (set_local $more (i32.const 1))
    (block $endLoop
      (loop $loop
        (set_local $byte (i32.and (i32.const 0x7F) (get_local $value)))
        (set_local $value (i32.shr_s (get_local $value) (i32.const 7)))
        (if (i32.or (i32.and (i32.eqz (get_local $value)) 
                             (i32.eq (i32.and (get_local $byte) (i32.const 0x40))
                                     (i32.const 0)))
                    (i32.and (i32.eq (get_local $value) (i32.const -1))
                             (i32.eq (i32.and (get_local $byte) (i32.const 0x40))
                                     (i32.const 0x40))))
          (then
            (set_local $more (i32.const 0)))
          (else
            (set_local $byte (i32.or (get_local $byte) (i32.const 0x80)))))
        (i32.store8 (get_local $p) (get_local $byte))
        (set_local $p (i32.add (get_local $p) (i32.const 1)))
        (br_if $loop (get_local $more))
        (br $endLoop)))
    (get_local $p))

  (func $body (param $xt i32) (result i32)
    (i32.and
      (i32.add
        (i32.add 
          (get_local $xt)
          (i32.and
            (i32.load8_u (i32.add (get_local $xt) (i32.const 4)))
            (i32.const !lengthMask)))
        (i32.const 8 #| 4 + 1 + 3 |#))
      (i32.const -4)))

  (func $readChar (result i32)
    (local $n i32)
    (if (i32.eq (get_global $preludeDataP) (get_global $preludeDataEnd))
      (then 
        (return (call $shell_key)))
      (else
        (set_local $n (i32.load8_s (get_global $preludeDataP)))
        (set_global $preludeDataP (i32.add (get_global $preludeDataP) (i32.const 1)))
        (return (get_local $n))))
    (unreachable))

  (func $loadPrelude (export "loadPrelude")
    (set_global $preludeDataP (i32.const !preludeDataBase))
    (if (i32.ne (call $interpret) (i32.const 0))
      (unreachable)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Data
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (data (i32.const !baseBase) "\u000A\u0000\u0000\u0000")
  (data (i32.const !moduleHeaderBase) !moduleHeader)

  (data (i32.const !preludeDataBase)  !preludeData)
  (global $preludeDataEnd i32 (i32.const (!+ !preludeDataBase (string-length !preludeData))))
  (global $preludeDataP (mut i32) (i32.const (!+ !preludeDataBase (string-length !preludeData))))

  (func (export "tos") (result i32)
    (get_global $tos))

  (func (export "interpret") (result i32)
    (local $result i32)
    (if (i32.ge_s (tee_local $result (call $interpret)) (i32.const 0))
      (then
        ;; Write ok
        (call $shell_emit (i32.const 111))
        (call $shell_emit (i32.const 107)))
      (else
        ;; Write error
        (call $shell_emit (i32.const 101))
        (call $shell_emit (i32.const 114))
        (call $shell_emit (i32.const 114))
        (call $shell_emit (i32.const 111))
        (call $shell_emit (i32.const 114))))
    (call $shell_emit (i32.const 10))
    (get_local $result))

  (table (export "table") !tableStartIndex anyfunc)
  (global $latest (mut i32) (i32.const !dictionaryLatest))
  (global $here (mut i32) (i32.const !dictionaryTop))

  ;; Compilation pointer
  (global $cp (mut i32) (i32.const !moduleBodyBase)))
