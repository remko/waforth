
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
(define !stateBase #x104)
(define !inBase #x108)
(define !wordBase #x200)
(define !inputBufferBase #x300)
;; Compiled modules are limited to 4096 bytes until Chrome refuses to load
;; them synchronously
(define !moduleHeaderBase #x1000) 
(define !preludeDataBase #x2000)
(define !returnStackBase #x4000)
(define !stackBase #x10000)
(define !dictionaryBase #x20000)
(define !memorySize (* 100 1024 1024))

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

    "\u0002" "\u002B" ;; Import section
      "\u0003" ;; #Entries
      "\u0003\u0065\u006E\u0076" "\u0005\u0074\u0061\u0062\u006C\u0065" ;; 'env' . 'table'
        "\u0001" "\u0070" "\u0000" "\u00FB\u0000\u0000\u0000" ;; table, anyfunc, flags, initial size
      "\u0003\u0065\u006E\u0076" "\u0006\u006d\u0065\u006d\u006f\u0072\u0079" ;; 'env' . 'memory'
        "\u0002" "\u0000" "\u0001" ;; memory
      "\u0003\u0065\u006E\u0076" "\u0003\u0074\u006f\u0073" ;; 'env' . 'tos'
        "\u0003" "\u007F" "\u0000" ;; global, i32, immutable

    
    "\u0003" "\u0002" ;; Function section
      "\u0001" ;; #Entries
      "\u0000" ;; Type 0
      
    "\u0009" "\u000a" ;; Element section
      "\u0001" ;; #Entries
      "\u0000" ;; Table 0
      "\u0041\u00FC\u0000\u0000\u0000\u000B" ;; i32.const ..., end
      "\u0001" ;; #elements
        "\u0000" ;; function 0

    "\u000A" "\u00FF\u0000\u0000\u0000" ;; Code section (padded length)
    "\u0001" ;; #Bodies
      "\u00FE\u0000\u0000\u0000" ;; Body size (padded)
      "\u0001" ;; #locals
        "\u00FD\u0000\u0000\u0000\u007F")) ;; # #i32 locals (padded)

(define !moduleHeaderSize (string-length !moduleHeader))
(define !moduleHeaderCodeSizeOffset (char-index (string->list !moduleHeader) #\u00FF 0))
(define !moduleHeaderBodySizeOffset (char-index (string->list !moduleHeader) #\u00FE 0))
(define !moduleHeaderLocalCountOffset (char-index (string->list !moduleHeader) #\u00FD 0))
(define !moduleHeaderTableIndexOffset (char-index (string->list !moduleHeader) #\u00FC 0))
(define !moduleHeaderTableInitialSizeOffset (char-index (string->list !moduleHeader) #\u00FB 0))

(define !moduleBodyBase (+ !moduleHeaderBase !moduleHeaderSize))
(define !moduleHeaderCodeSizeBase (+ !moduleHeaderBase !moduleHeaderCodeSizeOffset))
(define !moduleHeaderBodySizeBase (+ !moduleHeaderBase !moduleHeaderBodySizeOffset))
(define !moduleHeaderLocalCountBase (+ !moduleHeaderBase !moduleHeaderLocalCountOffset))
(define !moduleHeaderTableIndexBase (+ !moduleHeaderBase !moduleHeaderTableIndexOffset))
(define !moduleHeaderTableInitialSizeBase (+ !moduleHeaderBase !moduleHeaderTableInitialSizeOffset))


(define !fNone #x0)
(define !fImmediate #x80)
(define !fData #x40)
(define !fHidden #x20)
(define !lengthMask #x1F)

;; Predefined table indices
(define !pushIndex 1)
(define !popIndex 2)
(define !typeIndex 3)
(define !pushDataAddressIndex 4)
(define !pushDataValueIndex 5)
(define !tableStartIndex 6)

(define !dictionaryLatest 0)
(define !dictionaryTop !dictionaryBase)

(define (!def_word name f (flags 0) (idx !tableStartIndex))
  (let* ((base !dictionaryTop) 
         (previous !dictionaryLatest)
         (name-entry-length (* (ceiling (/ (+ (string-length name) 1) 4)) 4))
         (size (+ 8 name-entry-length)))
    (cond ((= idx !tableStartIndex)
           (set! !tableStartIndex (+ !tableStartIndex 1))
           (set! !dictionaryLatest !dictionaryTop)))
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
  (import "shell" "load" (func $shell_load (param i32 i32 i32)))
  (import "shell" "debug" (func $shell_debug (param i32)))

  (memory (export "memory") (!/ !memorySize 65536))

  (type $word (func))
  (type $dataWord (func (param i32)))

  (global $tos (mut i32) (i32.const !stackBase))
  (global $tors (mut i32) (i32.const !returnStackBase))
  (global $inputBufferSize (mut i32) (i32.const 0))
  (global $sourceID (mut i32) (i32.const 0))

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

  ;; 6.1.0070
  (func $tick
    (call $word)
    (if (i32.eqz (i32.load (i32.const !wordBase))) (then (unreachable)))
    (call $find)
    (drop (call $pop)))
  (!def_word "'" "$tick")

  ;; 6.1.0090
  (func $star
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.mul (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (!def_word "*" "$star")

  ;; 6.1.0100
  (func $*/
    (local $bbtos i32)
    (local $bbbtos i32)
    (i32.store (tee_local $bbbtos (i32.sub (get_global $tos) (i32.const 12)))
               (i32.wrap/i64
                  (i64.div_s
                      (i64.mul (i64.extend_s/i32 (i32.load (get_local $bbbtos)))
                               (i64.extend_s/i32 (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))))
                      (i64.extend_s/i32 (i32.load (i32.sub (get_global $tos) (i32.const 4)))))))
    (set_global $tos (get_local $bbtos)))
  (!def_word "*/" "$*/")

  ;; 6.1.0110
  (func $*/MOD
    (local $btos i32)
    (local $bbtos i32)
    (local $bbbtos i32)
    (local $x1 i64)
    (local $x2 i64)
    (i32.store (tee_local $bbbtos (i32.sub (get_global $tos) (i32.const 12)))
               (i32.wrap/i64
                  (i64.rem_s
                      (tee_local $x1 (i64.mul (i64.extend_s/i32 (i32.load (get_local $bbbtos)))
                                              (i64.extend_s/i32 (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))))))
                      (tee_local $x2 (i64.extend_s/i32 (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))))))
    (i32.store (get_local $bbtos) (i32.wrap/i64 (i64.div_s (get_local $x1) (get_local $x2))))
    (set_global $tos (get_local $btos)))
  (!def_word "*/MOD" "$*/MOD")

  ;; 6.1.0120
  (func $plus
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.add (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (!def_word "+" "$plus")

  ;; 6.1.0130
  (func $+!
    (local $addr i32)
    (local $bbtos i32)
    (i32.store (tee_local $addr (i32.load (i32.sub (get_global $tos) (i32.const 4))))
               (i32.add (i32.load (get_local $addr))
                        (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))))
    (set_global $tos (get_local $bbtos)))
  (!def_word "+!" "$+!")

  ;; 6.1.0140
  (func $plus-loop
    (call $ensureCompiling)
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
    (call $emitICall (i32.const 0) (i32.const !typeIndex)))
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

  ;; 6.1.0320
  (func $2*
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.shl (i32.load (get_local $btos)) (i32.const 1))))
  (!def_word "2*" "$2*")

  ;; 6.1.0330
  (func $2/
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.shr_s (i32.load (get_local $btos)) (i32.const 1))))
  (!def_word "2/" "$2/")


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

  ;; 6.1.0400
  (func $2OVER
    (i32.store (get_global $tos)
               (i32.load (i32.sub (get_global $tos) (i32.const 16))))
    (i32.store (i32.add (get_global $tos) (i32.const 4))
               (i32.load (i32.sub (get_global $tos) (i32.const 12))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 8))))
  (!def_word "2OVER" "$2OVER")

  ;; 6.1.0430
  (func $2SWAP
    (local $x1 i32)
    (local $x2 i32)
    (set_local $x1 (i32.load (i32.sub (get_global $tos) (i32.const 16))))
    (set_local $x2 (i32.load (i32.sub (get_global $tos) (i32.const 12))))
    (i32.store (i32.sub (get_global $tos) (i32.const 16))
               (i32.load (i32.sub (get_global $tos) (i32.const 8))))
    (i32.store (i32.sub (get_global $tos) (i32.const 12))
               (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (i32.store (i32.sub (get_global $tos) (i32.const 8))
               (get_local $x1))
    (i32.store (i32.sub (get_global $tos) (i32.const 4))
               (get_local $x2)))
  (!def_word "2SWAP" "$2SWAP")

  ;; 6.1.0450
  (func $colon
    (call $create)
    (call $hidden)
    (set_global $cp (i32.const !moduleBodyBase))
    (set_global $currentLocal (i32.const -1))
    (set_global $lastLocal (i32.const -1))
    (call $right-bracket))
  (!def_word ":" "$colon")

  ;; 6.1.0460
  (func $semicolon
    (local $bodySize i32)
    (local $nameLength i32)

    (call $emitEnd)

    ;; Update code size
    (set_local $bodySize (i32.sub (get_global $cp) (i32.const !moduleHeaderBase))) 
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

    ;; Update #locals
    (i32.store 
      (i32.const !moduleHeaderLocalCountBase)
      (call $leb128-4p (i32.add (get_global $lastLocal) (i32.const 1))))

    ;; Update table offset
    (i32.store 
      (i32.const !moduleHeaderTableIndexBase)
      (call $leb128-4p (get_global $nextTableIndex)))
    ;; Also store the initial table size to satisfy other tools (e.g. wasm-as)
    (i32.store 
      (i32.const !moduleHeaderTableInitialSizeBase)
      (call $leb128-4p (i32.add (get_global $nextTableIndex) (i32.const 1))))

    ;; Write a name section
    (set_local $nameLength (i32.and (i32.load8_u (i32.add (get_global $latest) (i32.const 4)))
                                    (i32.const !lengthMask)))
    (i32.store8 (get_global $cp) (i32.const 0))
    (i32.store8 (i32.add (get_global $cp) (i32.const 1)) 
                (i32.add (i32.const 13) (i32.mul (i32.const 2) (get_local $nameLength))))
    (i32.store8 (i32.add (get_global $cp) (i32.const 2)) (i32.const 0x04))
    (i32.store8 (i32.add (get_global $cp) (i32.const 3)) (i32.const 0x6e))
    (i32.store8 (i32.add (get_global $cp) (i32.const 4)) (i32.const 0x61))
    (i32.store8 (i32.add (get_global $cp) (i32.const 5)) (i32.const 0x6d))
    (i32.store8 (i32.add (get_global $cp) (i32.const 6)) (i32.const 0x65))
    (set_global $cp (i32.add (get_global $cp) (i32.const 7)))

    (i32.store8 (get_global $cp) (i32.const 0x00))
    (i32.store8 (i32.add (get_global $cp) (i32.const 1)) 
                (i32.add (i32.const 1) (get_local $nameLength)))
    (i32.store8 (i32.add (get_global $cp) (i32.const 2)) (get_local $nameLength)) 
    (set_global $cp (i32.add (get_global $cp) (i32.const 3)))
    (call $memmove (get_global $cp)
                  (i32.add (get_global $latest) (i32.const 5))
                  (get_local $nameLength))
    (set_global $cp (i32.add (get_global $cp) (get_local $nameLength)))

    (i32.store8 (get_global $cp) (i32.const 0x01))
    (i32.store8 (i32.add (get_global $cp) (i32.const 1)) 
                (i32.add (i32.const 3) (get_local $nameLength)))
    (i32.store8 (i32.add (get_global $cp) (i32.const 2)) (i32.const 0x01))
    (i32.store8 (i32.add (get_global $cp) (i32.const 3)) (i32.const 0x00))
    (i32.store8 (i32.add (get_global $cp) (i32.const 4)) (get_local $nameLength))
    (set_global $cp (i32.add (get_global $cp) (i32.const 5)))
    (call $memmove (get_global $cp)
                  (i32.add (get_global $latest) (i32.const 5))
                  (get_local $nameLength))
    (set_global $cp (i32.add (get_global $cp) (get_local $nameLength)))

    ;; Load the code and store the index
    (call $shell_load (i32.const !moduleHeaderBase) 
                      (i32.sub (get_global $cp) (i32.const !moduleHeaderBase))
                      (get_global $nextTableIndex))
    (i32.store (call $body (get_global $latest)) (get_global $nextTableIndex))
    (set_global $nextTableIndex (i32.add (get_global $nextTableIndex) (i32.const 1)))

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

  ;; 6.1.0530
  (func $=
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.eq (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
      (then (i32.store (get_local $bbtos) (i32.const -1)))
      (else (i32.store (get_local $bbtos) (i32.const 0))))
    (set_global $tos (get_local $btos)))
  (!def_word "=" "$=")

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

  ;; 6.1.0550
  (func $>BODY
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.add (call $body (i32.load (get_local $btos)))
                        (i32.const 4))))
  (!def_word ">BODY" "$>BODY")

  ;; 6.1.0560
  (func $>IN
    (i32.store (get_global $tos) (i32.const !inBase))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word ">IN" "$>IN")

  ;; 6.1.0580
  (func $>R
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4)))
    (i32.store (get_global $tors) (i32.load (get_global $tos)))
    (set_global $tors (i32.add (get_global $tors) (i32.const 4))))
  (!def_word ">R" "$>R")

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

  ;; 6.1.0690
  (func $ABS
    (local $btos i32)
    (local $v i32)
    (local $y i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.sub (i32.xor (tee_local $v (i32.load (get_local $btos)))
                                 (tee_local $y (i32.shr_s (get_local $v) (i32.const 31))))
                        (get_local $y))))
  (!def_word "ABS" "$ABS")

  ;; 6.1.0710
  (func $ALLOT
    (set_global $here (i32.add (get_global $here) (call $pop))))
  (!def_word "ALLOT" "$ALLOT")

  ;; 6.1.0720
  (func $AND
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.and (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (!def_word "AND" "$AND")

  ;; 6.1.0705
  (func $ALIGN
    (set_global $here (i32.and
                        (i32.add (get_global $here) (i32.const 3))
                        (i32.const -4 #| ~3 |#))))
  (!def_word "ALIGN" "$ALIGN")

  ;; 6.1.0706
  (func $ALIGNED
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.and (i32.add (i32.load (get_local $btos)) (i32.const 3))
                        (i32.const -4 #| ~3 |#))))
  (!def_word "ALIGNED" "$ALIGNED")

  ;; 6.1.0750 
  (func $BASE
   (i32.store (get_global $tos) (i32.const !baseBase))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "BASE" "$BASE")
  
  ;; 6.1.0760 
  (func $begin
    (call $ensureCompiling)
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

  ;; 6.1.0860
  (func $c-comma
    (i32.store8 (get_global $here)
                (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $here (i32.add (get_global $here) (i32.const 1)))
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4))))
  (!def_word "C," "$c-comma")

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

  ;; 6.1.0950
  (func $CONSTANT
    (call $create)
    (i32.store (call $body (get_global $latest)) (i32.const !pushDataValueIndex))
    (i32.store (get_global $here) (call $pop))
    (call $setFlag (i32.const !fData))
    (set_global $here (i32.add (get_global $here) (i32.const 4))))
  (!def_word "CONSTANT" "$CONSTANT")

  ;; 6.1.0980
  (func $COUNT
    (local $btos i32)
    (local $addr i32)
    (i32.store (get_global $tos)
               (i32.load (tee_local $addr (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                                              (i32.const 4)))))))
    (i32.store (get_local $btos) (i32.add (get_local $addr) (i32.const 4)))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "COUNT" "$COUNT")

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

    (call $memmove (get_global $here) (i32.const (!+ !wordBase 4)) (get_local $length))

    (set_global $here (i32.add (get_global $here) (get_local $length)))

    (call $ALIGN)

    ;; Leave space for the code pointer
    (i32.store (get_global $here) (i32.const 0))
    (set_global $here (i32.add (get_global $here) (i32.const 4))))
  (!def_word "CREATE" "$create")

  ;; 6.1.1200
  (func $DEPTH
   (i32.store (get_global $tos)
              (i32.shr_u (i32.sub (get_global $tos) (i32.const !stackBase)) (i32.const 2)))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "DEPTH" "$DEPTH")


  ;; 6.1.1240
  (func $do
    (call $ensureCompiling)
    (call $compileDo))
  (!def_word "DO" "$do" !fImmediate)

  ;; 6.1.1250
  ; (func $DOES>)
  ; (!def_word "DOES>" "$DOES>")

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
    (call $ensureCompiling)
    (call $compileElse))
  (!def_word "ELSE" "$else" !fImmediate)

  ;; 6.1.1320
  (func $emit
    (call $shell_emit (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4))))
  (!def_word "EMIT" "$emit")

  ;; 6.1.1370
  (func $EXECUTE
    (local $xt i32)
    (local $body i32)
    (set_local $body (call $body (tee_local $xt (call $pop))))
    (if (i32.and (i32.load (i32.add (get_local $xt) (i32.const 4)))
                 (i32.const !fData))
      (then
        (call_indirect (type $dataWord) (i32.add (get_local $body) (i32.const 4))
                                        (i32.load (get_local $body))))
      (else
        (call_indirect (type $word) (i32.load (get_local $body))))))
  (!def_word "EXECUTE" "$EXECUTE")

  ;; 6.1.1360
  (func $EVALUATE
    (local $bbtos i32)
    (local $inputSize i32)
    (set_global $sourceID (i32.const -1))
    (call $memmove (i32.const !inputBufferBase)
                   (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                   (tee_local $inputSize (i32.load (i32.sub (get_global $tos) (i32.const 4)))))
    (set_global $inputBufferSize (get_local $inputSize))
    (i32.store (i32.const !inBase) (i32.const 0))
    (set_global $tos (get_local $bbtos))
    (if (i32.ne (call $interpret) (i32.const 0))
      ;; TODO: ABORT
      (unreachable)))
  (!def_word "EVALUATE" "$EVALUATE")

  ;; 6.1.1380
  (func $EXIT
    (call $emitReturn))
  (!def_word "EXIT" "$EXIT" !fImmediate)

  ;; 6.1.1540
  (func $FILL
    (local $bbbtos i32)
    (call $memset (i32.load (tee_local $bbbtos (i32.sub (get_global $tos) (i32.const 12))))
                  (i32.load (i32.sub (get_global $tos) (i32.const 4)))
                  (i32.load (i32.sub (get_global $tos) (i32.const 8))))
    (set_global $tos (get_local $bbbtos)))
  (!def_word "FILL" "$FILL")

  ;; 6.1.1550
  (func $find
    (local $entryP i32)
    (local $entryNameP i32)
    (local $entryLF i32)
    (local $wordP i32)
    (local $wordStart i32)
    (local $wordLength i32)
    (local $wordEnd i32)

    (set_local $wordLength 
               (i32.load (tee_local $wordStart (i32.load (i32.sub (get_global $tos) 
                                                                  (i32.const 4))))))
    (set_local $wordStart (i32.add (get_local $wordStart) (i32.const 4)))
    (set_local $wordEnd (i32.add (get_local $wordStart) (get_local $wordLength)))

    (set_local $entryP (get_global $latest))
    (block $endLoop
      (loop $loop
        (set_local $entryLF (i32.load (i32.add (get_local $entryP) (i32.const 4))))
        (block $endCompare
          (if (i32.and 
                (i32.eq (i32.and (get_local $entryLF) (i32.const !fHidden)) (i32.const 0))
                (i32.eq (i32.and (get_local $entryLF) (i32.const !lengthMask))
                        (get_local $wordLength)))
            (then
              (set_local $wordP (get_local $wordStart))
              (set_local $entryNameP (i32.add (get_local $entryP) (i32.const 5)))
              (block $endCompareLoop
                (loop $compareLoop
                  (br_if $endCompare (i32.ne (i32.load8_s (get_local $entryNameP))
                                             (i32.load8_s (get_local $wordP))))
                  (set_local $entryNameP (i32.add (get_local $entryNameP) (i32.const 1)))
                  (set_local $wordP (i32.add (get_local $wordP) (i32.const 1)))
                  (br_if $endCompareLoop (i32.eq (get_local $wordP)
                                                 (get_local $wordEnd)))
                  (br $compareLoop)))
              (i32.store (i32.sub (get_global $tos) (i32.const 4))
                         (get_local $entryP))
              (if (i32.eq (i32.and (get_local $entryLF) (i32.const !fImmediate)) (i32.const 0))
                (then
                  (call $push (i32.const -1)))
                (else
                  (call $push (i32.const 1))))
              (return))))
        (set_local $entryP (i32.load (get_local $entryP)))
        (br_if $endLoop (i32.eqz (get_local $entryP)))
        (br $loop)))
    (call $push (i32.const 0)))
  (!def_word "FIND" "$find")

  ;; 6.1.1650
  (func $here
   (i32.store (get_global $tos) (get_global $here))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "HERE" "$here")

  ;; 6.1.1680
  (func $i
    (call $ensureCompiling)
    (call $compilePushLocal (i32.sub (get_global $currentLocal) (i32.const 1))))
  (!def_word "I" "$i" !fImmediate)

  ;; 6.1.1700
  (func $if
    (call $ensureCompiling)
    (call $compileIf))
  (!def_word "IF" "$if" !fImmediate)

  ;; 6.1.1710
  (func $immediate
    (call $setFlag (i32.const !fImmediate)))
  (!def_word "IMMEDIATE" "$immediate")

  ;; 6.1.1720
  (func $INVERT
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.xor (i32.load (get_local $btos)) (i32.const -1))))
  (!def_word "INVERT" "$INVERT")

  ;; 6.1.1730
  (func $j
    (call $ensureCompiling)
    (call $compilePushLocal (i32.sub (get_global $currentLocal) (i32.const 3))))
  (!def_word "J" "$j" !fImmediate)

  ;; 6.1.1750
  (func $key
    (i32.store (get_global $tos) (call $readChar))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "KEY" "$key")

  ;; 6.1.1760
  (func $LEAVE
    (call $ensureCompiling)
    (call $compileLeave))
  (!def_word "LEAVE" "$LEAVE" !fImmediate)


  ;; 6.1.1780
  (func $literal
    (call $compilePushConst (call $pop)))
  (!def_word "LITERAL" "$literal" !fImmediate)

  ;; 6.1.1800
  (func $loop
    (call $ensureCompiling)
    (call $compileLoop))
  (!def_word "LOOP" "$loop" !fImmediate)

  ;; 6.1.1805
  (func $LSHIFT
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.shl (i32.load (get_local $bbtos))
                        (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (!def_word "LSHIFT" "$LSHIFT")

  ;; 6.1.1870
  (func $MAX
    (local $btos i32)
    (local $bbtos i32)
    (local $v i32)
    (if (i32.lt_s (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (tee_local $v (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                                    (i32.const 4))))))
      (then
        (i32.store (get_local $bbtos) (get_local $v))))
    (set_global $tos (get_local $btos)))
  (!def_word "MAX" "$MAX")

  ;; 6.1.1880
  (func $MIN
    (local $btos i32)
    (local $bbtos i32)
    (local $v i32)
    (if (i32.gt_s (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (tee_local $v (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                                    (i32.const 4))))))
      (then
        (i32.store (get_local $bbtos) (get_local $v))))
    (set_global $tos (get_local $btos)))
  (!def_word "MIN" "$MIN")

  ;; 6.1.1880
  (func $MOD
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.rem_s (i32.load (get_local $bbtos))
                          (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (!def_word "MOD" "$MOD")

  ;; 6.1.1900
  (func $MOVE
    (local $bbbtos i32)
    (call $memmove (i32.load (i32.sub (get_global $tos) (i32.const 8)))
                   (i32.load (tee_local $bbbtos (i32.sub (get_global $tos) (i32.const 12))))
                   (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $tos (get_local $bbbtos)))
  (!def_word "MOVE" "$MOVE")

  ;; 6.1.1910
  (func $negate
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.sub (i32.const 0) (i32.load (get_local $btos)))))
  (!def_word "NEGATE" "$negate")

  ;; 6.1.1980
  (func $OR
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.or (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (!def_word "OR" "$OR")

  ;; 6.1.1990
  (func $over
    (i32.store (get_global $tos)
               (i32.load (i32.sub (get_global $tos) (i32.const 8))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "OVER" "$over")

  ;; 6.1.2060
  (func $R>
    (set_global $tors (i32.sub (get_global $tors) (i32.const 4)))
    (i32.store (get_global $tos) (i32.load (get_global $tors)))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "R>" "$R>")

  ;; 6.1.2070
  (func $R@
    (i32.store (get_global $tos) (i32.load (i32.sub (get_global $tors) (i32.const 4))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "R@" "$R@")

  ;; 6.1.2120 
  (func $RECURSE 
    (call $compileRecurse))
  (!def_word "RECURSE" "$RECURSE" !fImmediate)


  ;; 6.1.2140
  (func $repeat
    (call $ensureCompiling)
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

  ;; 6.1.2162
  (func $RSHIFT
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.shr_u (i32.load (get_local $bbtos))
                          (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (!def_word "RSHIFT" "$RSHIFT")

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
    (call $compilePushConst (get_local $start))
    (call $compilePushConst (i32.sub (get_global $here) (get_local $start)))
    (call $ALIGN))
  (!def_word "S\"" "$Sq" !fImmediate)

  ;; 6.1.2216
  (func $SOURCE 
    (call $push (i32.const !inputBufferBase))
    (call $push (get_global $inputBufferSize)))
  (!def_word "SOURCE" "$SOURCE")

  ;; 6.1.2220
  (func $space (call $bl) (call $emit))
  (!def_word "SPACE" "$space")

  ;; 6.1.2250
  (func $STATE
    (i32.store (get_global $tos) (i32.const !stateBase))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (!def_word "STATE" "$STATE")

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
    (call $ensureCompiling)
    (call $compileThen))
  (!def_word "THEN" "$then" !fImmediate)

  ;; 6.2.2295
  (func $TO
    (call $word)
    (if (i32.eqz (i32.load (i32.const !wordBase))) (then (unreachable)))
    (call $find)
    (if (i32.eqz (call $pop)) (unreachable))
    (i32.store (i32.add (call $body (call $pop)) (i32.const 4)) (call $pop)))
  (!def_word "TO" "$TO")

  ;; 6.1.2340
  (func $U<
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_u (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
      (then (i32.store (get_local $bbtos) (i32.const -1)))
      (else (i32.store (get_local $bbtos) (i32.const 0))))
    (set_global $tos (get_local $btos)))
  (!def_word "U<" "$U<")

  ;; 6.1.2380
  (func $UNLOOP)
  (!def_word "UNLOOP" "$UNLOOP" !fImmediate)

  ;; 6.1.2390
  (func $UNTIL
    (call $ensureCompiling)
    (call $compileUntil))
  (!def_word "UNTIL" "$UNTIL" !fImmediate)

  ;; 6.2.2405
  (!def_word "VALUE" "$CONSTANT")

  ;; 6.1.2410
  (func $VARIABLE
    (call $create)
    (i32.store (call $body (get_global $latest)) (i32.const !pushDataAddressIndex))
    (i32.store (get_global $here) (i32.const 0))
    (call $setFlag (i32.const !fData))
    (set_global $here (i32.add (get_global $here) (i32.const 4))))
  (!def_word "VARIABLE" "$VARIABLE")

  ;; 6.1.2430
  (func $while
    (call $ensureCompiling)
    (call $compileWhile))
  (!def_word "WHILE" "$while" !fImmediate)

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

  ;; 6.1.2490
  (func $XOR
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.xor (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (!def_word "XOR" "$XOR")

  ;; 6.1.2500
  (func $left-bracket
    (i32.store (i32.const !stateBase) (i32.const 0)))
  (!def_word "[" "$left-bracket" !fImmediate)

  ;; 6.1.2540
  (func $right-bracket
    (i32.store (i32.const !stateBase) (i32.const 1)))
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

  ;; 6.2.2030
  (func $PICK
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.load (i32.sub (get_global $tos) 
                                  (i32.shl (i32.add (i32.load (get_local $btos))
                                                    (i32.const 2))
                                           (i32.const 2))))))
  (!def_word "PICK" "$PICK")

  ;; 6.1.2395
  (func $UNUSED
    (call $push (i32.shr_s (i32.sub (i32.const !memorySize) (get_global $here)) (i32.const 2))))
  (!def_word "UNUSED" "$UNUSED")

  ;; 6.1.2250
  (func $SOURCE-ID
    (call $push (get_global $sourceID)))
  (!def_word "SOURCE-ID" "$SOURCE-ID")

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
    : '\n' 10 ;
    : 'A' [ CHAR A ] LITERAL ;
    : '0' [ CHAR 0 ] LITERAL ;
    : '(' [ CHAR ( ] LITERAL ;
    : ')' [ CHAR ) ] LITERAL ;

    : ( 
      1
      BEGIN
        KEY
        DUP '(' = IF
          DROP
          1+
        ELSE
          ')' = IF 1- THEN
        THEN
      DUP 0= UNTIL
      DROP
    ; IMMEDIATE
    

    \ 6.1.1170 
    : DECIMAL 10 BASE ! ;

    \ 6.2.1660
    : HEX ( -- ) 16 BASE ! ;

    \ 6.2.2298
    : TRUE -1 ;

    \ 6.2.1485
    : FALSE 0 ;

    \ 6.2.1930
    : NIP ( x y -- y ) SWAP DROP ;

    \ 6.2.2300
    : TUCK ( x y -- y x y ) SWAP OVER ;

    \ 6.1.0897
    : CHAR+ 1+ ;

    \ 6.1.0898
    : CHARS ;

    \ 6.1.0880
    : CELL+ 4 + ;
    
    \ 6.1.0890
    : CELLS 4 * ;

    \ 6.1.0350
    : 2@ DUP CELL+ @ SWAP @ ;

    \ 6.1.0310
    : 2! SWAP OVER ! CELL+ ! ;

    : UWIDTH BASE @ / ?DUP IF RECURSE 1+ ELSE 1 THEN ;

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
    (local $n i32)

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
        (set_local $char (i32.const 48 #| '0' |# )))
      (else 
        (set_local $sign (i32.const 1))))

    ;; Read all characters
    (set_local $value (i32.const 0))
    (block $endLoop
      (loop $loop
        (if (i32.lt_s (get_local $char) (i32.const 48 #| '0' |# ))
          (return (i32.const -1)))

        (if (i32.le_s (get_local $char) (i32.const 57 #| '9' |# ))
          (then
            (set_local $n (i32.sub (get_local $char) (i32.const 48))))
          (else
            (if (i32.lt_s (get_local $char) (i32.const 65 #| 'A' |# ))
              (return (i32.const -1)))
            (set_local $n (i32.sub (get_local $char) (i32.const 55)))
            (if (i32.ge_s (get_local $n) (get_local $base))
              (return (i32.const -1)))))

        (set_local $value (i32.add (i32.mul (get_local $value) (get_local $base))
                                   (get_local $n)))
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
    (local $body i32)
    (local $error i32)
    (set_local $error (i32.const 0))
    (set_global $tors (i32.const !returnStackBase))
    (i32.store (i32.const !inBase) (i32.const 0))
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
                (if (i32.ne (i32.load (i32.const !stateBase)) (i32.const 0))
                  (then
                    ;; We're compiling. Pop it off the stack and 
                    ;; add it to the compiled list
                    (call $compilePushConst (call $pop)))))
                  ;; We're not compiling. Leave the number on the stack.
              (else ;; It's not a number.
                ;; TODO: Give error
                (set_local $error (i32.const -1))
                (br $endLoop))))
          (else ;; Found the word. 
            (set_local $body (call $body (get_local $findToken)))
            ;; Are we compiling or is it immediate?
            (if (i32.or (i32.eqz (i32.load (i32.const !stateBase)))
                        (i32.eq (get_local $findResult) (i32.const 1)))
              (then
                (call $push (get_local $findToken))
                (call $EXECUTE))
              (else
                ;; We're compiling a non-immediate
                (if (i32.and (i32.load (i32.add (get_local $findToken) (i32.const 4)))
                             (i32.const !fData))
                  (then
                    (call $emitConst (i32.add (get_local $body) (i32.const 4)))
                    (call $emitICall 
                          (i32.const 1) 
                          (i32.load (get_local $body))))
                  (else
                    (call $emitICall 
                          (i32.const 0) 
                          (i32.load (get_local $body)))))))))
          (br $loop)))
    ;; 'WORD' left the address on the stack
    (drop (call $pop))
    (if (i32.eqz (get_local $error))
      (then
        (return (i32.load (i32.const !stateBase))))
      (else
        (return (get_local $error))))
    (unreachable))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Compiler functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $compilePushConst (param $n i32)
    (call $emitConst (get_local $n))
    (call $emitICall (i32.const 1) (i32.const !pushIndex)))

  (func $compilePushLocal (param $n i32)
    (call $emitGetLocal (get_local $n))
    (call $emitICall (i32.const 1) (i32.const !pushIndex)))

  (func $compileIf
    (call $compilePop)
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
    (set_global $currentLocal (i32.add (get_global $currentLocal) (i32.const 2)))
    (if (i32.gt_s (get_global $currentLocal) (get_global $lastLocal))
      (then
        (set_global $lastLocal (get_global $currentLocal))))
    (call $compilePop)
    (call $emitSetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $compilePop)
    (call $emitSetLocal (get_global $currentLocal))
    (call $emitBlock)
    (call $emitLoop))
  
  (func $compileLoop 
    (call $emitConst (i32.const 1))
    (call $compileLoopEnd))

  (func $compilePlusLoop 
    (call $compilePop)
    (call $compileLoopEnd))

  ;; Assumes increment is on the operand stack
  (func $compileLoopEnd
    (call $emitGetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $emitAdd)
    (call $emitSetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $emitGetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $emitGetLocal (get_global $currentLocal))
    (call $emitGreaterEqualSigned)
    (call $emitBrIf (i32.const 1))
    (call $emitBr (i32.const 0))
    (call $emitEnd)
    (call $emitEnd)
    (set_global $currentLocal (i32.sub (get_global $currentLocal) (i32.const 2))))

  (func $compileLeave
    (call $emitBr (i32.const 1)))

  (func $compileBegin
    (call $emitBlock)
    (call $emitLoop))

  (func $compileWhile
    (call $compilePop)
    (call $emitEqualsZero)
    (call $emitBrIf (i32.const 1)))

  (func $compileRepeat
    (call $emitBr (i32.const 0))
    (call $emitEnd)
    (call $emitEnd))

  (func $compileUntil
    (call $compilePop)
    (call $emitEqualsZero)
    (call $emitBrIf (i32.const 0))
    (call $emitBr (i32.const 1))
    (call $emitEnd)
    (call $emitEnd))

  (func $compileRecurse
    ;; call 0
    (i32.store8 (get_global $cp) (i32.const 0x10))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (i32.const 0x00))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $compilePop
    (call $emitICall (i32.const 2) (i32.const !popIndex)))

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

  (func $emitSetLocal (param $n i32)
    (i32.store8 (get_global $cp) (i32.const 0x21))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (set_global $cp (call $leb128 (get_global $cp) (get_local $n))))

  (func $emitGetLocal (param $n i32)
    (i32.store8 (get_global $cp) (i32.const 0x20))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (set_global $cp (call $leb128 (get_global $cp) (get_local $n))))

  (func $emitAdd
    (i32.store8 (get_global $cp) (i32.const 0x6a))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitEqualsZero
    (i32.store8 (get_global $cp) (i32.const 0x45))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitGreaterEqualSigned
    (i32.store8 (get_global $cp) (i32.const 0x4e))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitReturn
    (i32.store8 (get_global $cp) (i32.const 0x0f))
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

  (func $TYPE
    (local $p i32)
    (local $end i32)
    (set_local $end (i32.add (call $pop) (tee_local $p (call $pop))))
    (block $endLoop
     (loop $loop
       (br_if $endLoop (i32.eq (get_local $p) (get_local $end)))
       (call $shell_emit (i32.load8_u (get_local $p)))
       (set_local $p (i32.add (get_local $p) (i32.const 1)))
       (br $loop))))
  (!def_word "TYPE" "$TYPE" !fNone !typeIndex)

  (func $pushDataAddress (param $d i32)
    (call $push (get_local $d)))
  (elem (i32.const !pushDataAddressIndex) $pushDataAddress)

  (func $pushDataValue (param $d i32)
    (call $push (i32.load (get_local $d))))
  (elem (i32.const !pushDataValueIndex) $pushDataValue)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Helper functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $setFlag (param $v i32)
    (i32.store 
      (i32.add (get_global $latest) (i32.const 4))
      (i32.or 
        (i32.load (i32.add (get_global $latest) (i32.const 4)))
        (get_local $v))))

  (func $ensureCompiling
    (if (i32.eqz (i32.load (i32.const !stateBase)))
      (then
        (unreachable))))

  ;; Toggle the hidden flag
  (func $hidden
    (i32.store 
      (i32.add (get_global $latest) (i32.const 4))
      (i32.xor 
        (i32.load (i32.add (get_global $latest) (i32.const 4)))
        (i32.const !fHidden))))

  (func $memmove (param $dst i32) (param $src i32) (param $n i32)
    (local $end i32)
    (if (i32.gt_u (get_local $dst) (get_local $src))
      (then
        (set_local $end (get_local $src))
        (set_local $src (i32.sub (i32.add (get_local $src) (get_local $n)) (i32.const 1)))
        (set_local $dst (i32.sub (i32.add (get_local $dst) (get_local $n)) (i32.const 1)))
        (block $endLoop
        (loop $loop
          (br_if $endLoop (i32.lt_u (get_local $src) (get_local $end)))
          (i32.store8 (get_local $dst) (i32.load8_u (get_local $src)))
          (set_local $src (i32.sub (get_local $src) (i32.const 1)))
          (set_local $dst (i32.sub (get_local $dst) (i32.const 1)))
          (br $loop))))
      (else
        (set_local $end (i32.add (get_local $src) (get_local $n)))
        (block $endLoop
          (loop $loop
            (br_if $endLoop (i32.eq (get_local $src) (get_local $end)))
            (i32.store8 (get_local $dst) (i32.load8_u (get_local $src)))
            (set_local $src (i32.add (get_local $src) (i32.const 1)))
            (set_local $dst (i32.add (get_local $dst) (i32.const 1)))
            (br $loop))))))

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
    (local $in i32)
    (loop $loop
      (if (i32.ge_u (tee_local $in (i32.load (i32.const !inBase)))
                    (get_global $inputBufferSize))
        (then
          (if (i32.eqz (get_global $sourceID))
            (then
              (return (i32.const -1)))
            (else
              (set_global $sourceID (i32.const 0))
              (br $loop))))
        (else
          (set_local $n (i32.load8_s (i32.add (i32.const !inputBufferBase) (get_local $in))))
          (i32.store (i32.const !inBase) (i32.add (get_local $in) (i32.const 1)))
          (return (get_local $n)))))
    (unreachable))

  (func $readInput
    (local $char i32)
    (set_global $inputBufferSize (i32.const 0))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eq (tee_local $char (call $shell_key)) (i32.const -1)))
        (i32.store8 (i32.add (i32.const !inputBufferBase) (get_global $inputBufferSize)) 
                   (get_local $char))
        (set_global $inputBufferSize (i32.add (get_global $inputBufferSize) (i32.const 1)))
        (br $loop))))

  (func $loadPrelude (export "loadPrelude")
    (set_global $sourceID (i32.const -1))
    (call $push (i32.const !preludeDataBase))
    (call $push (i32.const (!+ (string-length !preludeData) 0)))
    (call $EVALUATE))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; A sieve with direct calls. Only here for benchmarking
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $sieve_prime
    (call $here) (call $plus) 
    (call $c-fetch) (call $zero-equals))

  (func $sieve_composite
    (call $here)
    (call $plus)
    (i32.store (get_global $tos) (i32.const 1))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4)))
    (call $swap)
    (call $c-store))
;
  (func $sieve
    (local $i i32)
    (local $end i32)
    (call $here) 
    (call $over) 
    (call $erase)
    (call $push (i32.const 2))
    (block $endLoop1
      (loop $loop1
        (call $two-dupe) 
        (call $dupe) 
        (call $star) 
        (call $greater-than)
        (br_if $endLoop1 (i32.eqz (call $pop)))
        (call $dupe) 
        (call $sieve_prime)
        (if (i32.ne (call $pop) (i32.const 0))
          (block
            (call $two-dupe) 
            (call $dupe) 
            (call $star)
            (set_local $i (call $pop))
            (set_local $end (call $pop))
            (block $endLoop2
              (loop $loop2
                (call $push (get_local $i))
                (call $sieve_composite) 
                (call $dupe)
                (set_local $i (i32.add (call $pop) (get_local $i)))
                (br_if $endLoop2 (i32.ge_s (get_local $i) (get_local $end)))
                (br $loop2)))))
        (call $one-plus)
        (br $loop1)))
    (call $drop) 
    (call $push (i32.const 1))
    (call $swap) 
    (call $push (i32.const 2))
    (set_local $i (call $pop))
    (set_local $end (call $pop))
    (block $endLoop3
      (loop $loop3
        (call $push (get_local $i))
        (call $sieve_prime) 
        (if (i32.ne (call $pop) (i32.const 0))
        (block
          (call $drop)
          (call $push (get_local $i))))
        (set_local $i (i32.add (i32.const 1) (get_local $i)))
        (br_if $endLoop3 (i32.ge_s (get_local $i) (get_local $end)))
        (br $loop3))))
  (!def_word "sieve_direct" "$sieve")
    
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Data
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (data (i32.const !baseBase) "\u000A\u0000\u0000\u0000")
  (data (i32.const !stateBase) "\u0000\u0000\u0000\u0000")
  (data (i32.const !inBase) "\u0000\u0000\u0000\u0000")
  (data (i32.const !moduleHeaderBase) !moduleHeader)
  (data (i32.const !preludeDataBase)  !preludeData)

  (func (export "tos") (result i32)
    (get_global $tos))

  (func (export "interpret") (result i32)
    (local $result i32)
    (call $readInput)
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
  (global $nextTableIndex (mut i32) (i32.const !tableStartIndex))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Compilation state
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (global $currentLocal (mut i32) (i32.const 0))
  (global $lastLocal (mut i32) (i32.const -1))

  ;; Compilation pointer
  (global $cp (mut i32) (i32.const !moduleBodyBase)))
