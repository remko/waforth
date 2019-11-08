
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

(define !baseBase #x100)
(define !stateBase #x104)
(define !inBase #x108)
(define !wordBase #x200)
(define !wordBasePlus1 #x201)
(define !wordBasePlus2 #x202)
(define !inputBufferBase #x300)
;; Compiled modules are limited to 4096 bytes until Chrome refuses to load
;; them synchronously
(define !moduleHeaderBase #x1000) 
(define !preludeDataBase #x2000)
(define !returnStackBase #x4000)
(define !stackBase #x10000)
(define !dictionaryBase #x21000)
(define !memorySize 104857600) ;; 100*1024*1024
(define !memorySizePages 1600) ;; memorySize / 65536

; (define !moduleHeaderSize (string-length !moduleHeader))
(define !moduleHeaderSize #x68) 
; (define !moduleHeaderCodeSizeOffset (char-index (string->list !moduleHeader) #\u00FF 0))
(define !moduleHeaderCodeSizeOffset #x59) 
(define !moduleHeaderCodeSizeOffsetPlus4 #x5d) 
; (define !moduleHeaderBodySizeOffset (char-index (string->list !moduleHeader) #\u00FE 0))
(define !moduleHeaderBodySizeOffset #x5e) 
(define !moduleHeaderBodySizeOffsetPlus4 #x62) 
; (define !moduleHeaderLocalCountOffset (char-index (string->list !moduleHeader) #\u00FD 0))
(define !moduleHeaderLocalCountOffset #x63) 
; (define !moduleHeaderTableIndexOffset (char-index (string->list !moduleHeader) #\u00FC 0))
(define !moduleHeaderTableIndexOffset #x51) 
; (define !moduleHeaderTableInitialSizeOffset (char-index (string->list !moduleHeader) #\u00FB 0))
(define !moduleHeaderTableInitialSizeOffset #x2b) 
; (define !moduleHeaderFunctionTypeOffset (char-index (string->list !moduleHeader) #\u00FA 0))
(define !moduleHeaderFunctionTypeOffset #x4b) 

(define !moduleBodyBase #x1068) ;; (+ !moduleHeaderBase !moduleHeaderSize))
(define !moduleHeaderCodeSizeBase #x1059) ;; (+ !moduleHeaderBase !moduleHeaderCodeSizeOffset))
(define !moduleHeaderBodySizeBase #x105e) ;; (+ !moduleHeaderBase !moduleHeaderBodySizeOffset))
(define !moduleHeaderLocalCountBase #x1063) ;; (+ !moduleHeaderBase !moduleHeaderLocalCountOffset))
(define !moduleHeaderTableIndexBase #x1051) ;; (+ !moduleHeaderBase !moduleHeaderTableIndexOffset))
(define !moduleHeaderTableInitialSizeBase #x102b) ;; (+ !moduleHeaderBase !moduleHeaderTableInitialSizeOffset))
(define !moduleHeaderFunctionTypeBase #x104b) ;; (+ !moduleHeaderBase !moduleHeaderFunctionTypeOffset))

(define !fNone #x0)
(define !fImmediate #x80)
(define !fData #x40)
(define !fHidden #x20)
(define !lengthMask #x1F)

;; Predefined table indices
(define !pushIndex 1)
(define !popIndex 2)
(define !pushDataAddressIndex 3)
(define !setLatestBodyIndex 4)
(define !compileCallIndex 5)
(define !pushIndirectIndex 6)
(define !typeIndex #x85)
(define !abortIndex #x39)
(define !constantIndex #x4c)

(define !nextTableIndex #xa6)

(define (!+ x y) (list (+ x y)))

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
  (import "shell" "getc" (func $shell_getc (result i32)))
  (import "shell" "key" (func $shell_key (result i32)))
  (import "shell" "accept" (func $shell_accept (param i32) (param i32) (result i32)))
  (import "shell" "load" (func $shell_load (param i32 i32 i32)))
  (import "shell" "debug" (func $shell_debug (param i32)))

  (memory (export "memory") !memorySizePages)

  (type $word (func))
  (type $dataWord (func (param i32)))

  (global $tos (mut i32) (i32.const !stackBase))
  (global $tors (mut i32) (i32.const !returnStackBase))
  (global $inputBufferSize (mut i32) (i32.const 0))
  (global $inputBufferBase (mut i32) (i32.const !inputBufferBase))
  (global $sourceID (mut i32) (i32.const 0))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Constant strings
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (data (i32.const #x20000) "\u000eundefined word")
  (data (i32.const #x20014) "\u000ddivision by 0")
  (data (i32.const #x20028) "\u0010incomplete input")
  (data (i32.const #x2003C) "\u000bmissing ')'")
  (data (i32.const #x2004C) "\u0009missing \u0022")
  (data (i32.const #x2005C) "\u0024word not supported in interpret mode")
  (data (i32.const #x20084) "\u000Fnot implemented")
  
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Built-in words
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; 6.1.0010 ! 
  (func $!
    (local $bbtos i32)
    (i32.store (i32.load (i32.sub (get_global $tos) (i32.const 4)))
               (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))))
    (set_global $tos (get_local $bbtos)))
  (data (i32.const 135168) "\u0000\u0000\u0000\u0000\u0001!\u0000\u0000\u0010\u0000\u0000\u0000")
  (elem (i32.const 0x10) $!)

  (func $# (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135180) "\u0000\u0010\u0002\u0000\u0001#\u0000\u0000\u0011\u0000\u0000\u0000")
  (elem (i32.const 0x11) $#)

  (func $#> (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135192) "\u000c\u0010\u0002\u0000\u0002#>\u0000\u0012\u0000\u0000\u0000")
  (elem (i32.const 0x12) $#>)

  (func $#S (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135204) "\u0018\u0010\u0002\u0000\u0002#S\u0000\u0013\u0000\u0000\u0000")
  (elem (i32.const 0x13) $#S)

  ;; 6.1.0070
  (func $tick
    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const !wordBase))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (call $find)
    (drop (call $pop)))
  (data (i32.const 135216) "$\u0010\u0002\u0000\u0001'\u0000\u0000\u0014\u0000\u0000\u0000")
  (elem (i32.const 0x14) $tick)

  ;; 6.1.0080
  (func $paren
    (local $c i32)
    (block $endLoop
      (loop $loop
        (if (i32.lt_s (tee_local $c (call $readChar)) (i32.const 0)) 
          (call $fail (i32.const 0x2003C))) ;; missing ')'
        (br_if $endLoop (i32.eq (get_local $c) (i32.const 41)))
        (br $loop))))
  (data (i32.const 135228) "0\u0010\u0002\u0000\u0081(\u0000\u0000\u0015\u0000\u0000\u0000")
  (elem (i32.const 0x15) $paren) ;; immediate

  ;; 6.1.0090
  (func $star
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.mul (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 135240) "<\u0010\u0002\u0000\u0001*\u0000\u0000\u0016\u0000\u0000\u0000")
  (elem (i32.const 0x16) $star)

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
  (data (i32.const 135252) "H\u0010\u0002\u0000\u0002*/\u0000\u0017\u0000\u0000\u0000")
  (elem (i32.const 0x17) $*/)

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
  (data (i32.const 135264) "T\u0010\u0002\u0000\u0005*/MOD\u0000\u0000\u0018\u0000\u0000\u0000")
  (elem (i32.const 0x18) $*/MOD)

  ;; 6.1.0120
  (func $plus
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.add (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 135280) "`\u0010\u0002\u0000\u0001+\u0000\u0000\u0019\u0000\u0000\u0000")
  (elem (i32.const 0x19) $plus)

  ;; 6.1.0130
  (func $+!
    (local $addr i32)
    (local $bbtos i32)
    (i32.store (tee_local $addr (i32.load (i32.sub (get_global $tos) (i32.const 4))))
               (i32.add (i32.load (get_local $addr))
                        (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))))
    (set_global $tos (get_local $bbtos)))
  (data (i32.const 135292) "p\u0010\u0002\u0000\u0002+!\u0000\u001a\u0000\u0000\u0000")
  (elem (i32.const 0x1a) $+!)

  ;; 6.1.0140
  (func $plus-loop
    (call $ensureCompiling)
    (call $compilePlusLoop))
  (data (i32.const 135304) "|\u0010\u0002\u0000\u0085+LOOP\u0000\u0000\u001b\u0000\u0000\u0000")
  (elem (i32.const 0x1b) $plus-loop) ;; immediate

  ;; 6.1.0150
  (func $comma
    (i32.store
      (get_global $here)
      (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $here (i32.add (get_global $here) (i32.const 4)))
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4))))
  (data (i32.const 135320) "\u0088\u0010\u0002\u0000\u0001,\u0000\u0000\u001c\u0000\u0000\u0000")
  (elem (i32.const 0x1c) $comma)

  ;; 6.1.0160
  (func $minus
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.sub (i32.load (get_local $bbtos))
                        (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 135332) "\u0098\u0010\u0002\u0000\u0001-\u0000\u0000\u001d\u0000\u0000\u0000")
  (elem (i32.const 0x1d) $minus)

  ;; 6.1.0180
  (func $.q
    (call $ensureCompiling)
    (call $Sq)
    (call $emitICall (i32.const 0) (i32.const !typeIndex))) ;; TYPE
  (data (i32.const 135344) "\u00a4\u0010\u0002\u0000\u0082.\u0022\u0000\u001e\u0000\u0000\u0000")
  (elem (i32.const 0x1e) $.q) ;; immediate

  ;; 6.1.0230
  (func $/
    (local $btos i32)
    (local $bbtos i32)
    (local $divisor i32)
    (if (i32.eqz (tee_local $divisor (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
      (call $fail (i32.const 0x20014))) ;; division by 0
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.div_s (i32.load (get_local $bbtos)) (get_local $divisor)))
    (set_global $tos (get_local $btos)))
  (data (i32.const 135356) "\u00b0\u0010\u0002\u0000\u0001/\u0000\u0000\u001f\u0000\u0000\u0000")
  (elem (i32.const 0x1f) $/)

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
  (data (i32.const 135368) "\u00bc\u0010\u0002\u0000\u0004/MOD\u0000\u0000\u0000 \u0000\u0000\u0000")
  (elem (i32.const 0x20) $/MOD)

  ;; 6.1.0250
  (func $0<
    (local $btos i32)
    (if (i32.lt_s (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                     (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (get_local $btos) (i32.const -1)))
      (else (i32.store (get_local $btos) (i32.const 0)))))
  (data (i32.const 135384) "\u00c8\u0010\u0002\u0000\u00020<\u0000!\u0000\u0000\u0000")
  (elem (i32.const 0x21) $0<)


  ;; 6.1.0270
  (func $zero-equals
    (local $btos i32)
    (if (i32.eqz (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                     (i32.const 4)))))
      (then (i32.store (get_local $btos) (i32.const -1)))
      (else (i32.store (get_local $btos) (i32.const 0)))))
  (data (i32.const 135396) "\u00d8\u0010\u0002\u0000\u00020=\u0000\u0022\u0000\u0000\u0000")
  (elem (i32.const 0x22) $zero-equals)

  ;; 6.1.0290
  (func $one-plus
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.add (i32.load (get_local $btos)) (i32.const 1))))
  (data (i32.const 135408) "\u00e4\u0010\u0002\u0000\u00021+\u0000#\u0000\u0000\u0000")
  (elem (i32.const 0x23) $one-plus)

  ;; 6.1.0300
  (func $one-minus
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.sub (i32.load (get_local $btos)) (i32.const 1))))
  (data (i32.const 135420) "\u00f0\u0010\u0002\u0000\u00021-\u0000$\u0000\u0000\u0000")
  (elem (i32.const 0x24) $one-minus)


  ;; 6.1.0310
  (func $2! 
    (call $SWAP) (call $OVER) (call $!) (call $CELL+) (call $!))
  (data (i32.const 135432) "\u00fc\u0010\u0002\u0000\u00022!\u0000%\u0000\u0000\u0000")
  (elem (i32.const 0x25) $2!)

  ;; 6.1.0320
  (func $2*
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.shl (i32.load (get_local $btos)) (i32.const 1))))
  (data (i32.const 135444) "\u0008\u0011\u0002\u0000\u00022*\u0000&\u0000\u0000\u0000")
  (elem (i32.const 0x26) $2*)

  ;; 6.1.0330
  (func $2/
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.shr_s (i32.load (get_local $btos)) (i32.const 1))))
  (data (i32.const 135456) "\u0014\u0011\u0002\u0000\u00022/\u0000'\u0000\u0000\u0000")
  (elem (i32.const 0x27) $2/)

  ;; 6.1.0350
  (func $2@ 
    (call $DUP)
    (call $CELL+)
    (call $@)
    (call $SWAP)
    (call $@))
  (data (i32.const 135468) " \u0011\u0002\u0000\u00022@\u0000(\u0000\u0000\u0000")
  (elem (i32.const 0x28) $2@)


  ;; 6.1.0370 
  (func $two-drop
    (set_global $tos (i32.sub (get_global $tos) (i32.const 8))))
  (data (i32.const 135480) ",\u0011\u0002\u0000\u00052DROP\u0000\u0000)\u0000\u0000\u0000")
  (elem (i32.const 0x29) $two-drop)

  ;; 6.1.0380
  (func $two-dupe
    (i32.store (get_global $tos)
               (i32.load (i32.sub (get_global $tos) (i32.const 8))))
    (i32.store (i32.add (get_global $tos) (i32.const 4))
               (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 8))))
  (data (i32.const 135496) "8\u0011\u0002\u0000\u00042DUP\u0000\u0000\u0000*\u0000\u0000\u0000")
  (elem (i32.const 0x2a) $two-dupe)

  ;; 6.1.0400
  (func $2OVER
    (i32.store (get_global $tos)
               (i32.load (i32.sub (get_global $tos) (i32.const 16))))
    (i32.store (i32.add (get_global $tos) (i32.const 4))
               (i32.load (i32.sub (get_global $tos) (i32.const 12))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 8))))
  (data (i32.const 135512) "H\u0011\u0002\u0000\u00052OVER\u0000\u0000+\u0000\u0000\u0000")
  (elem (i32.const 0x2b) $2OVER)

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
  (data (i32.const 135528) "X\u0011\u0002\u0000\u00052SWAP\u0000\u0000,\u0000\u0000\u0000")
  (elem (i32.const 0x2c) $2SWAP)

  ;; 6.1.0450
  (func $colon
    (call $CREATE)
    (call $hidden)

    ;; Turn off (default) data flag
    (i32.store 
      (i32.add (get_global $latest) (i32.const 4))
      (i32.xor 
        (i32.load (i32.add (get_global $latest) (i32.const 4)))
        (i32.const !fData)))

    ;; Store the code pointer already
    ;; The code hasn't been loaded yet, but since nothing can affect the next table
    ;; index, we can assume the index will be correct. This allows semicolon to be
    ;; agnostic about whether it is compiling a word or a DOES>.
    (i32.store (call $body (get_global $latest)) (get_global $nextTableIndex))

    (call $startColon (i32.const 0))
    (call $right-bracket))
  (data (i32.const 135544) "h\u0011\u0002\u0000\u0001:\u0000\u0000-\u0000\u0000\u0000")
  (elem (i32.const 0x2d) $colon)

  ;; 6.1.0460
  (func $semicolon
    (call $ensureCompiling)
    (call $endColon)
    (call $hidden)
    (call $left-bracket))
  (data (i32.const 135556) "x\u0011\u0002\u0000\u0081;\u0000\u0000.\u0000\u0000\u0000")
  (elem (i32.const 0x2e) $semicolon) ;; immediate

  ;; 6.1.0480
  (func $less-than
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_s (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
      (then (i32.store (get_local $bbtos) (i32.const -1)))
      (else (i32.store (get_local $bbtos) (i32.const 0))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 135568) "\u0084\u0011\u0002\u0000\u0001<\u0000\u0000/\u0000\u0000\u0000")
  (elem (i32.const 0x2f) $less-than)

  (func $<# (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135580) "\u0090\u0011\u0002\u0000\u0002<#\u00000\u0000\u0000\u0000")
  (elem (i32.const 0x30) $<#)

  ;; 6.1.0530
  (func $=
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.eq (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
      (then (i32.store (get_local $bbtos) (i32.const -1)))
      (else (i32.store (get_local $bbtos) (i32.const 0))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 135592) "\u009c\u0011\u0002\u0000\u0001=\u0000\u00001\u0000\u0000\u0000")
  (elem (i32.const 0x31) $=)

  ;; 6.1.0540
  (func $greater-than
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.gt_s (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
      (then (i32.store (get_local $bbtos) (i32.const -1)))
      (else (i32.store (get_local $bbtos) (i32.const 0))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 135604) "\u00a8\u0011\u0002\u0000\u0001>\u0000\u00002\u0000\u0000\u0000")
  (elem (i32.const 0x32) $greater-than)

  ;; 6.1.0550
  (func $>BODY
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.add (call $body (i32.load (get_local $btos)))
                        (i32.const 4))))
  (data (i32.const 135616) "\u00b4\u0011\u0002\u0000\u0005>BODY\u0000\u00003\u0000\u0000\u0000")
  (elem (i32.const 0x33) $>BODY)

  ;; 6.1.0560
  (func $>IN
    (i32.store (get_global $tos) (i32.const !inBase))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 135632) "\u00c0\u0011\u0002\u0000\u0003>IN4\u0000\u0000\u0000")
  (elem (i32.const 0x34) $>IN)

  (func $>NUMBER (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135644) "\u00d0\u0011\u0002\u0000\u0007>NUMBER5\u0000\u0000\u0000")
  (elem (i32.const 0x35) $>NUMBER)

  ;; 6.1.0580
  (func $>R
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4)))
    (i32.store (get_global $tors) (i32.load (get_global $tos)))
    (set_global $tors (i32.add (get_global $tors) (i32.const 4))))
  (data (i32.const 135660) "\u00dc\u0011\u0002\u0000\u0002>R\u00006\u0000\u0000\u0000")
  (elem (i32.const 0x36) $>R)

  ;; 6.1.0630 
  (func $?DUP
    (local $btos i32)
    (if (i32.ne (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                (i32.const 0))
      (then
        (i32.store (get_global $tos)
                   (i32.load (get_local $btos)))
        (set_global $tos (i32.add (get_global $tos) (i32.const 4))))))
  (data (i32.const 135672) "\u00ec\u0011\u0002\u0000\u0004?DUP\u0000\u0000\u00007\u0000\u0000\u0000")
  (elem (i32.const 0x37) $?DUP)

  ;; 6.1.0650
  (func $@
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.load (i32.load (get_local $btos)))))
  (data (i32.const 135688) "\u00f8\u0011\u0002\u0000\u0001@\u0000\u00008\u0000\u0000\u0000")
  (elem (i32.const 0x38) $@)

  ;; 6.1.0670 ABORT 
  (func $ABORT
    (set_global $tos (i32.const !stackBase))
    (call $QUIT))
  ;; WARNING: If you change this table index, make sure the emitted ICalls are also updated
  (data (i32.const 135700) "\u0008\u0012\u0002\u0000\u0005ABORT\u0000\u00009\u0000\u0000\u0000")
  (elem (i32.const 0x39) $ABORT) ;; none

  ;; 6.1.0680 ABORT"
  (func $ABORT-quote
    (call $compileIf)
    (call $Sq)
    (call $emitICall (i32.const 0) (i32.const !typeIndex)) ;; TYPE
    (call $emitICall (i32.const 0) (i32.const !abortIndex)) ;; ABORT
    (call $compileThen))
  (data (i32.const 135716) "\u0014\u0012\u0002\u0000\u0086ABORT\u0022\u0000:\u0000\u0000\u0000")
  (elem (i32.const 0x3a) $ABORT-quote) ;; immediate

  ;; 6.1.0690
  (func $ABS
    (local $btos i32)
    (local $v i32)
    (local $y i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.sub (i32.xor (tee_local $v (i32.load (get_local $btos)))
                                 (tee_local $y (i32.shr_s (get_local $v) (i32.const 31))))
                        (get_local $y))))
  (data (i32.const 135732) "$\u0012\u0002\u0000\u0003ABS;\u0000\u0000\u0000")
  (elem (i32.const 0x3b) $ABS)

  ;; 6.1.0695
  (func $ACCEPT
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (call $shell_accept (i32.load (get_local $bbtos))
                                   (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 135744) "4\u0012\u0002\u0000\u0006ACCEPT\u0000<\u0000\u0000\u0000")
  (elem (i32.const 0x3c) $ACCEPT)

  ;; 6.1.0705
  (func $ALIGN
    (set_global $here (i32.and
                        (i32.add (get_global $here) (i32.const 3))
                        (i32.const -4 #| ~3 |#))))
  (data (i32.const 135760) "@\u0012\u0002\u0000\u0005ALIGN\u0000\u0000=\u0000\u0000\u0000")
  (elem (i32.const 0x3d) $ALIGN)

  ;; 6.1.0706
  (func $ALIGNED
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.and (i32.add (i32.load (get_local $btos)) (i32.const 3))
                        (i32.const -4 #| ~3 |#))))
  (data (i32.const 135776) "P\u0012\u0002\u0000\u0007ALIGNED>\u0000\u0000\u0000")
  (elem (i32.const 0x3e) $ALIGNED)

  ;; 6.1.0710
  (func $ALLOT
    (set_global $here (i32.add (get_global $here) (call $pop))))
  (data (i32.const 135792) "`\u0012\u0002\u0000\u0005ALLOT\u0000\u0000?\u0000\u0000\u0000")
  (elem (i32.const 0x3f) $ALLOT)

  ;; 6.1.0720
  (func $AND
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.and (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 135808) "p\u0012\u0002\u0000\u0003AND@\u0000\u0000\u0000")
  (elem (i32.const 0x40) $AND)

  ;; 6.1.0750 
  (func $BASE
   (i32.store (get_global $tos) (i32.const !baseBase))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 135820) "\u0080\u0012\u0002\u0000\u0004BASE\u0000\u0000\u0000A\u0000\u0000\u0000")
  (elem (i32.const 0x41) $BASE)
  
  ;; 6.1.0760 
  (func $begin
    (call $ensureCompiling)
    (call $compileBegin))
  (data (i32.const 135836) "\u008c\u0012\u0002\u0000\u0085BEGIN\u0000\u0000B\u0000\u0000\u0000")
  (elem (i32.const 0x42) $begin) ;; immediate

  ;; 6.1.0770
  (func $bl (call $push (i32.const 32)))
  (data (i32.const 135852) "\u009c\u0012\u0002\u0000\u0002BL\u0000C\u0000\u0000\u0000")
  (elem (i32.const 0x43) $bl)

  ;; 6.1.0850
  (func $c-store
    (local $bbtos i32)
    (i32.store8 (i32.load (i32.sub (get_global $tos) (i32.const 4)))
                (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))))
    (set_global $tos (get_local $bbtos)))
  (data (i32.const 135864) "\u00ac\u0012\u0002\u0000\u0002C!\u0000D\u0000\u0000\u0000")
  (elem (i32.const 0x44) $c-store)

  ;; 6.1.0860
  (func $c-comma
    (i32.store8 (get_global $here)
                (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $here (i32.add (get_global $here) (i32.const 1)))
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4))))
  (data (i32.const 135876) "\u00b8\u0012\u0002\u0000\u0002C,\u0000E\u0000\u0000\u0000")
  (elem (i32.const 0x45) $c-comma)

  ;; 6.1.0870
  (func $c-fetch
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.load8_u (i32.load (get_local $btos)))))
  (data (i32.const 135888) "\u00c4\u0012\u0002\u0000\u0002C@\u0000F\u0000\u0000\u0000")
  (elem (i32.const 0x46) $c-fetch)

  (func $CELL+ 
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.add (i32.load (get_local $btos)) (i32.const 4))))
  (data (i32.const 135900) "\u00d0\u0012\u0002\u0000\u0005CELL+\u0000\u0000G\u0000\u0000\u0000")
  (elem (i32.const 0x47) $CELL+)

  (func $CELLS 
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.shl (i32.load (get_local $btos)) (i32.const 2))))
  (data (i32.const 135916) "\u00dc\u0012\u0002\u0000\u0005CELLS\u0000\u0000H\u0000\u0000\u0000")
  (elem (i32.const 0x48) $CELLS)

  ;; 6.1.0895
  (func $CHAR
    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const !wordBase))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (i32.store (i32.sub (get_global $tos) (i32.const 4))
               (i32.load8_u (i32.const !wordBasePlus1))))
  (data (i32.const 135932) "\u00ec\u0012\u0002\u0000\u0004CHAR\u0000\u0000\u0000I\u0000\u0000\u0000")
  (elem (i32.const 0x49) $CHAR)

  (func $CHAR+ (call $one-plus))
  (data (i32.const 135948) "\u00fc\u0012\u0002\u0000\u0005CHAR+\u0000\u0000J\u0000\u0000\u0000")
  (elem (i32.const 0x4a) $CHAR+)

  (func $CHARS)
  (data (i32.const 135964) "\u000c\u0013\u0002\u0000\u0005CHARS\u0000\u0000K\u0000\u0000\u0000")
  (elem (i32.const 0x4b) $CHARS)

  ;; 6.1.0950
  (func $CONSTANT 
    (call $CREATE)
    (i32.store (i32.sub (get_global $here) (i32.const 4)) (i32.const !pushIndirectIndex))
    (i32.store (get_global $here) (call $pop))
    (set_global $here (i32.add (get_global $here) (i32.const 4))))
  (data (i32.const 135980) "\u001c\u0013\u0002\u0000" "\u0008" "CONSTANT\u0000\u0000\u0000" "L\u0000\u0000\u0000")
  (elem (i32.const !constantIndex) $CONSTANT)

  ;; 6.1.0980
  (func $COUNT
    (local $btos i32)
    (local $addr i32)
    (i32.store (get_global $tos)
               (i32.load8_u (tee_local $addr (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                                               (i32.const 4)))))))
    (i32.store (get_local $btos) (i32.add (get_local $addr) (i32.const 1)))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136000) ",\u0013\u0002\u0000\u0005COUNT\u0000\u0000M\u0000\u0000\u0000")
  (elem (i32.const 0x4d) $COUNT)

  (func $CR 
    (call $push (i32.const 10)) (call $EMIT))
  (data (i32.const 136016) "@\u0013\u0002\u0000\u0002CR\u0000N\u0000\u0000\u0000")
  (elem (i32.const 0x4e) $CR)

  ;; 6.1.1000
  (func $CREATE
    (local $length i32)

    (i32.store (get_global $here) (get_global $latest))
    (set_global $latest (get_global $here))
    (set_global $here (i32.add (get_global $here) (i32.const 4)))

    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const !wordBase))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (drop (call $pop))
    (i32.store8 (get_global $here) (tee_local $length (i32.load8_u (i32.const !wordBase))))
    (set_global $here (i32.add (get_global $here) (i32.const 1)))

    (call $memmove (get_global $here) (i32.const !wordBasePlus1) (get_local $length))

    (set_global $here (i32.add (get_global $here) (get_local $length)))

    (call $ALIGN)

    (i32.store (get_global $here) (i32.const !pushDataAddressIndex))
    (set_global $here (i32.add (get_global $here) (i32.const 4)))
    (i32.store (get_global $here) (i32.const 0))

    (call $setFlag (i32.const !fData)))
  (data (i32.const 136028) "P\u0013\u0002\u0000\u0006CREATE\u0000O\u0000\u0000\u0000")
  (elem (i32.const 0x4f) $CREATE)

  (func $DECIMAL 
    (i32.store (i32.const !baseBase) (i32.const 10)))
  (data (i32.const 136044) "\u005c\u0013\u0002\u0000\u0007DECIMALP\u0000\u0000\u0000")
  (elem (i32.const 0x50) $DECIMAL)

  ;; 6.1.1200
  (func $DEPTH
   (i32.store (get_global $tos)
              (i32.shr_u (i32.sub (get_global $tos) (i32.const !stackBase)) (i32.const 2)))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136060) "l\u0013\u0002\u0000\u0005DEPTH\u0000\u0000Q\u0000\u0000\u0000")
  (elem (i32.const 0x51) $DEPTH)


  ;; 6.1.1240
  (func $do
    (call $ensureCompiling)
    (call $compileDo))
  (data (i32.const 136076) "|\u0013\u0002\u0000\u0082DO\u0000R\u0000\u0000\u0000")
  (elem (i32.const 0x52) $do) ;; immediate

  ;; 6.1.1250
  (func $DOES>
    (call $ensureCompiling)
    (call $emitConst (i32.add (get_global $nextTableIndex) (i32.const 1)))
    (call $emitICall (i32.const 1) (i32.const !setLatestBodyIndex))
    (call $endColon)
    (call $startColon (i32.const 1))
    (call $compilePushLocal (i32.const 0)))
  (data (i32.const 136088) "\u008c\u0013\u0002\u0000\u0085DOES>\u0000\u0000S\u0000\u0000\u0000")
  (elem (i32.const 0x53) $DOES>) ;; immediate

  ;; 6.1.1260
  (func $DROP
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4))))
  (data (i32.const 136104) "\u0098\u0013\u0002\u0000\u0004DROP\u0000\u0000\u0000T\u0000\u0000\u0000")
  (elem (i32.const 0x54) $DROP)

  ;; 6.1.1290
  (func $DUP
   (i32.store
    (get_global $tos)
    (i32.load (i32.sub (get_global $tos) (i32.const 4))))
   (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136120) "\u00a8\u0013\u0002\u0000\u0003DUPU\u0000\u0000\u0000")
  (elem (i32.const 0x55) $DUP)

  ;; 6.1.1310
  (func $else
    (call $ensureCompiling)
    (call $emitElse))
  (data (i32.const 136132) "\u00b8\u0013\u0002\u0000\u0084ELSE\u0000\u0000\u0000V\u0000\u0000\u0000")
  (elem (i32.const 0x56) $else) ;; immediate

  ;; 6.1.1320
  (func $EMIT
    (call $shell_emit (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $tos (i32.sub (get_global $tos) (i32.const 4))))
  (data (i32.const 136148) "\u00c4\u0013\u0002\u0000\u0004EMIT\u0000\u0000\u0000W\u0000\u0000\u0000")
  (elem (i32.const 0x57) $EMIT)

  (func $ENVIRONMENT (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136164) "\u00d4\u0013\u0002\u0000\u000bENVIRONMENTX\u0000\u0000\u0000")
  (elem (i32.const 0x58) $ENVIRONMENT)

  ;; 6.1.1360
  (func $EVALUATE
    (local $bbtos i32)
    (local $prevSourceID i32)
    (local $prevIn i32)
    (local $prevInputBufferBase i32)
    (local $prevInputBufferSize i32)

    ;; Save input state
    (set_local $prevSourceID (get_global $sourceID))
    (set_local $prevIn (i32.load (i32.const !inBase)))
    (set_local $prevInputBufferSize (get_global $inputBufferSize))
    (set_local $prevInputBufferBase (get_global $inputBufferBase))

    (set_global $sourceID (i32.const -1))
    (set_global $inputBufferBase (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))))
    (set_global $inputBufferSize (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (i32.store (i32.const !inBase) (i32.const 0))

    (set_global $tos (get_local $bbtos))
    (drop (call $interpret))

    ;; Restore input state
    (set_global $sourceID (get_local $prevSourceID))
    (i32.store (i32.const !inBase) (get_local $prevIn))
    (set_global $inputBufferBase (get_local $prevInputBufferBase))
    (set_global $inputBufferSize (get_local $prevInputBufferSize)))
  (data (i32.const 136184) "\u00e4\u0013\u0002\u0000\u0008EVALUATE\u0000\u0000\u0000Y\u0000\u0000\u0000")
  (elem (i32.const 0x59) $EVALUATE)

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
  (data (i32.const 136204) "\u00f8\u0013\u0002\u0000\u0007EXECUTEZ\u0000\u0000\u0000")
  (elem (i32.const 0x5a) $EXECUTE)

  ;; 6.1.1380
  (func $EXIT
    (call $ensureCompiling)
    (call $emitReturn))
  (data (i32.const 136220) "\u000c\u0014\u0002\u0000\u0084EXIT\u0000\u0000\u0000[\u0000\u0000\u0000")
  (elem (i32.const 0x5b) $EXIT) ;; immediate

  ;; 6.1.1540
  (func $FILL
    (local $bbbtos i32)
    (call $memset (i32.load (tee_local $bbbtos (i32.sub (get_global $tos) (i32.const 12))))
                  (i32.load (i32.sub (get_global $tos) (i32.const 4)))
                  (i32.load (i32.sub (get_global $tos) (i32.const 8))))
    (set_global $tos (get_local $bbbtos)))
  (data (i32.const 136236) "\u001c\u0014\u0002\u0000\u0004FILL\u0000\u0000\u0000\u005c\u0000\u0000\u0000")
  (elem (i32.const 0x5c) $FILL)

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
               (i32.load8_u (tee_local $wordStart (i32.load (i32.sub (get_global $tos) 
                                                                  (i32.const 4))))))
    (set_local $wordStart (i32.add (get_local $wordStart) (i32.const 1)))
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
              (if (i32.eqz (i32.and (get_local $entryLF) (i32.const !fImmediate)))
                (then
                  (call $push (i32.const -1)))
                (else
                  (call $push (i32.const 1))))
              (return))))
        (set_local $entryP (i32.load (get_local $entryP)))
        (br_if $endLoop (i32.eqz (get_local $entryP)))
        (br $loop)))
    (call $push (i32.const 0)))
  (data (i32.const 136252) ",\u0014\u0002\u0000\u0004FIND\u0000\u0000\u0000]\u0000\u0000\u0000")
  (elem (i32.const 0x5d) $find)

  ;; 6.1.1561
  (func $f-m-slash-mod
    (local $btos i32)
    (local $bbbtos i32)
    (local $n1 i64)
    (local $n2 i32)
    (i32.store (tee_local $bbbtos (i32.sub (get_global $tos) (i32.const 12)))
               (i32.wrap/i64 (i64.rem_s (tee_local $n1 (i64.load (get_local $bbbtos)))
                             (i64.extend_s/i32 (tee_local $n2 (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))))))
    (i32.store (i32.sub (get_global $tos) (i32.const 8))
               (i32.wrap/i64 (i64.div_s (get_local $n1) (i64.extend_s/i32 (get_local $n2)))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 136268) "<\u0014\u0002\u0000\u0006FM/MOD\u0000^\u0000\u0000\u0000")
  (elem (i32.const 0x5e) $f-m-slash-mod)

  ;; 6.1.1650
  (func $here
    (i32.store (get_global $tos) (get_global $here))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136284) "L\u0014\u0002\u0000\u0004HERE\u0000\u0000\u0000_\u0000\u0000\u0000")
  (elem (i32.const 0x5f) $here)

  (func $HOLD (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136300) "\u005c\u0014\u0002\u0000\u0004HOLD\u0000\u0000\u0000`\u0000\u0000\u0000")
  (elem (i32.const 0x60) $HOLD)

  ;; 6.1.1680
  (func $i
    (call $ensureCompiling)
    (call $compilePushLocal (i32.sub (get_global $currentLocal) (i32.const 1))))
  (data (i32.const 136316) "l\u0014\u0002\u0000\u0081I\u0000\u0000a\u0000\u0000\u0000")
  (elem (i32.const 0x61) $i) ;; immediate

  ;; 6.1.1700
  (func $if
    (call $ensureCompiling)
    (call $compileIf))
  (data (i32.const 136328) "|\u0014\u0002\u0000\u0082IF\u0000b\u0000\u0000\u0000")
  (elem (i32.const 0x62) $if) ;; immediate

  ;; 6.1.1710
  (func $immediate
    (call $setFlag (i32.const !fImmediate)))
  (data (i32.const 136340) "\u0088\u0014\u0002\u0000\u0009IMMEDIATE\u0000\u0000c\u0000\u0000\u0000")
  (elem (i32.const 0x63) $immediate)

  ;; 6.1.1720
  (func $INVERT
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.xor (i32.load (get_local $btos)) (i32.const -1))))
  (data (i32.const 136360) "\u0094\u0014\u0002\u0000\u0006INVERT\u0000d\u0000\u0000\u0000")
  (elem (i32.const 0x64) $INVERT)

  ;; 6.1.1730
  (func $j
    (call $ensureCompiling)
    (call $compilePushLocal (i32.sub (get_global $currentLocal) (i32.const 4))))
  (data (i32.const 136376) "\u00a8\u0014\u0002\u0000\u0081J\u0000\u0000e\u0000\u0000\u0000")
  (elem (i32.const 0x65) $j) ;; immediate

  ;; 6.1.1750
  (func $key
    (i32.store (get_global $tos) (call $shell_key))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136388) "\u00b8\u0014\u0002\u0000\u0003KEYf\u0000\u0000\u0000")
  (elem (i32.const 0x66) $key)

  ;; 6.1.1760
  (func $LEAVE
    (call $ensureCompiling)
    (call $compileLeave))
  (data (i32.const 136400) "\u00c4\u0014\u0002\u0000\u0085LEAVE\u0000\u0000g\u0000\u0000\u0000")
  (elem (i32.const 0x67) $LEAVE) ;; immediate


  ;; 6.1.1780
  (func $literal
    (call $ensureCompiling)
    (call $compilePushConst (call $pop)))
  (data (i32.const 136416) "\u00d0\u0014\u0002\u0000\u0087LITERALh\u0000\u0000\u0000")
  (elem (i32.const 0x68) $literal) ;; immediate

  ;; 6.1.1800
  (func $loop
    (call $ensureCompiling)
    (call $compileLoop))
  (data (i32.const 136432) "\u00e0\u0014\u0002\u0000\u0084LOOP\u0000\u0000\u0000i\u0000\u0000\u0000")
  (elem (i32.const 0x69) $loop) ;; immediate

  ;; 6.1.1805
  (func $LSHIFT
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.shl (i32.load (get_local $bbtos))
                        (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 136448) "\u00f0\u0014\u0002\u0000\u0006LSHIFT\u0000j\u0000\u0000\u0000")
  (elem (i32.const 0x6a) $LSHIFT)

  ;; 6.1.1810
  (func $m-star
    (local $bbtos i32)
    (i64.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i64.mul (i64.extend_s/i32 (i32.load (get_local $bbtos)))
                        (i64.extend_s/i32 (i32.load (i32.sub (get_global $tos) 
                                                             (i32.const 4)))))))
  (data (i32.const 136464) "\u0000\u0015\u0002\u0000\u0002M*\u0000k\u0000\u0000\u0000")
  (elem (i32.const 0x6b) $m-star)

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
  (data (i32.const 136476) "\u0010\u0015\u0002\u0000\u0003MAXl\u0000\u0000\u0000")
  (elem (i32.const 0x6c) $MAX)

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
  (data (i32.const 136488) "\u001c\u0015\u0002\u0000\u0003MINm\u0000\u0000\u0000")
  (elem (i32.const 0x6d) $MIN)

  ;; 6.1.1890
  (func $MOD
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.rem_s (i32.load (get_local $bbtos))
                          (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 136500) "(\u0015\u0002\u0000\u0003MODn\u0000\u0000\u0000")
  (elem (i32.const 0x6e) $MOD)

  ;; 6.1.1900
  (func $MOVE
    (local $bbbtos i32)
    (call $memmove (i32.load (i32.sub (get_global $tos) (i32.const 8)))
                   (i32.load (tee_local $bbbtos (i32.sub (get_global $tos) (i32.const 12))))
                   (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $tos (get_local $bbbtos)))
  (data (i32.const 136512) "4\u0015\u0002\u0000\u0004MOVE\u0000\u0000\u0000o\u0000\u0000\u0000")
  (elem (i32.const 0x6f) $MOVE)

  ;; 6.1.1910
  (func $negate
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.sub (i32.const 0) (i32.load (get_local $btos)))))
  (data (i32.const 136528) "@\u0015\u0002\u0000\u0006NEGATE\u0000p\u0000\u0000\u0000")
  (elem (i32.const 0x70) $negate)

  ;; 6.1.1980
  (func $OR
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.or (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 136544) "P\u0015\u0002\u0000\u0002OR\u0000q\u0000\u0000\u0000")
  (elem (i32.const 0x71) $OR)

  ;; 6.1.1990
  (func $OVER
    (i32.store (get_global $tos)
               (i32.load (i32.sub (get_global $tos) (i32.const 8))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136556) "`\u0015\u0002\u0000\u0004OVER\u0000\u0000\u0000r\u0000\u0000\u0000")
  (elem (i32.const 0x72) $OVER)

  ;; 6.1.2033
  (func $POSTPONE
    (local $findToken i32)
    (local $findResult i32)
    (call $ensureCompiling)
    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const !wordBase))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (call $find)
    (if (i32.eqz (tee_local $findResult (call  $pop))) (call $fail (i32.const 0x20000))) ;; undefined word
    (set_local $findToken (call $pop))
    (if (i32.eq (get_local $findResult) (i32.const 1))
      (then (call $compileCall (get_local $findToken)))
      (else
        (call $emitConst (get_local $findToken))
        (call $emitICall (i32.const 1) (i32.const !compileCallIndex)))))
  (data (i32.const 136572) "l\u0015\u0002\u0000\u0088POSTPONE\u0000\u0000\u0000s\u0000\u0000\u0000")
  (elem (i32.const 0x73) $POSTPONE) ;; immediate

  ;; 6.1.2050
  (func $QUIT
    (set_global $tors (i32.const !returnStackBase))
    (set_global $sourceID (i32.const 0))
    (unreachable))
  (data (i32.const 136592) "|\u0015\u0002\u0000\u0004QUIT\u0000\u0000\u0000t\u0000\u0000\u0000")
  (elem (i32.const 0x74) $QUIT)

  ;; 6.1.2060
  (func $R>
    (set_global $tors (i32.sub (get_global $tors) (i32.const 4)))
    (i32.store (get_global $tos) (i32.load (get_global $tors)))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136608) "\u0090\u0015\u0002\u0000\u0002R>\u0000u\u0000\u0000\u0000")
  (elem (i32.const 0x75) $R>)

  ;; 6.1.2070
  (func $R@
    (i32.store (get_global $tos) (i32.load (i32.sub (get_global $tors) (i32.const 4))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136620) "\u00a0\u0015\u0002\u0000\u0002R@\u0000v\u0000\u0000\u0000")
  (elem (i32.const 0x76) $R@)

  ;; 6.1.2120 
  (func $RECURSE 
    (call $ensureCompiling)
    (call $compileRecurse))
  (data (i32.const 136632) "\u00ac\u0015\u0002\u0000\u0087RECURSEw\u0000\u0000\u0000")
  (elem (i32.const 0x77) $RECURSE) ;; immediate


  ;; 6.1.2140
  (func $repeat
    (call $ensureCompiling)
    (call $compileRepeat))
  (data (i32.const 136648) "\u00b8\u0015\u0002\u0000\u0086REPEAT\u0000x\u0000\u0000\u0000")
  (elem (i32.const 0x78) $repeat) ;; immediate

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
  (data (i32.const 136664) "\u00c8\u0015\u0002\u0000\u0003ROTy\u0000\u0000\u0000")
  (elem (i32.const 0x79) $ROT)

  ;; 6.1.2162
  (func $RSHIFT
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.shr_u (i32.load (get_local $bbtos))
                          (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 136676) "\u00d8\u0015\u0002\u0000\u0006RSHIFT\u0000z\u0000\u0000\u0000")
  (elem (i32.const 0x7a) $RSHIFT)

  ;; 6.1.2165
  (func $Sq
    (local $c i32)
    (local $start i32)
    (call $ensureCompiling)
    (set_local $start (get_global $here))
    (block $endLoop
      (loop $loop
        (if (i32.lt_s (tee_local $c (call $readChar)) (i32.const 0))
          (call $fail (i32.const 0x2003C))) ;; missing closing quote
        (br_if $endLoop (i32.eq (get_local $c) (i32.const 0x22)))
        (i32.store8 (get_global $here) (get_local $c))
        (set_global $here (i32.add (get_global $here) (i32.const 1)))
        (br $loop)))
    (call $compilePushConst (get_local $start))
    (call $compilePushConst (i32.sub (get_global $here) (get_local $start)))
    (call $ALIGN))
  (data (i32.const 136692) "\u00e4\u0015\u0002\u0000\u0082S\u0022\u0000{\u0000\u0000\u0000")
  (elem (i32.const 0x7b) $Sq) ;; immediate

  ;; 6.1.2170
  (func $s-to-d
    (local $btos i32)
    (i64.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i64.extend_s/i32 (i32.load (get_local $btos))))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136704) "\u00f4\u0015\u0002\u0000\u0003S>D|\u0000\u0000\u0000")
  (elem (i32.const 0x7c) $s-to-d)

  (func $SIGN (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136716) "\u0000\u0016\u0002\u0000\u0004SIGN\u0000\u0000\u0000}\u0000\u0000\u0000")
  (elem (i32.const 0x7d) $SIGN)

  (func $SM/REM (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136732) "\u000c\u0016\u0002\u0000\u0006SM/REM\u0000~\u0000\u0000\u0000")
  (elem (i32.const 0x7e) $SM/REM)

  ;; 6.1.2216
  (func $SOURCE 
    (call $push (get_global $inputBufferBase))
    (call $push (get_global $inputBufferSize)))
  (data (i32.const 136748) "\u001c\u0016\u0002\u0000\u0006SOURCE\u0000\u007f\u0000\u0000\u0000")
  (elem (i32.const 0x7f) $SOURCE)

  ;; 6.1.2220
  (func $space (call $bl) (call $EMIT))
  (data (i32.const 136764) ",\u0016\u0002\u0000\u0005SPACE\u0000\u0000\u0080\u0000\u0000\u0000")
  (elem (i32.const 0x80) $space)

  (func $SPACES 
    (local $i i32)
    (set_local $i (call $pop))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.le_s (get_local $i) (i32.const 0)))
        (call $space)
        (set_local $i (i32.sub (get_local $i) (i32.const 1)))
        (br $loop))))
  (data (i32.const 136780) "<\u0016\u0002\u0000\u0006SPACES\u0000\u0081\u0000\u0000\u0000")
  (elem (i32.const 0x81) $SPACES)

  ;; 6.1.2250
  (func $STATE
    (i32.store (get_global $tos) (i32.const !stateBase))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 136796) "L\u0016\u0002\u0000\u0005STATE\u0000\u0000\u0082\u0000\u0000\u0000")
  (elem (i32.const 0x82) $STATE)

  ;; 6.1.2260
  (func $SWAP
    (local $btos i32)
    (local $bbtos i32)
    (local $tmp i32)
    (set_local $tmp (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))))
    (i32.store (get_local $bbtos) 
               (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
    (i32.store (get_local $btos) (get_local $tmp)))
  (data (i32.const 136812) "\u005c\u0016\u0002\u0000\u0004SWAP\u0000\u0000\u0000\u0083\u0000\u0000\u0000")
  (elem (i32.const 0x83) $SWAP)

  ;; 6.1.2270
  (func $then
    (call $ensureCompiling)
    (call $compileThen))
  (data (i32.const 136828) "l\u0016\u0002\u0000\u0084THEN\u0000\u0000\u0000\u0084\u0000\u0000\u0000")
  (elem (i32.const 0x84) $then) ;; immediate

  ;; 6.1.2310 TYPE 
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
  ;; WARNING: If you change this table index, make sure the emitted ICalls are also updated
  (data (i32.const 136844) "|\u0016\u0002\u0000\u0004TYPE\u0000\u0000\u0000\u0085\u0000\u0000\u0000")
  (elem (i32.const 0x85) $TYPE) ;; none

  (func $U. (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136860) "\u008c\u0016\u0002\u0000\u0002_.\u0000\u0086\u0000\u0000\u0000")
  (elem (i32.const 0x86) $U.) ;; TODO: Rename

  ;; 6.1.2340
  (func $U<
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_u (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))))
      (then (i32.store (get_local $bbtos) (i32.const -1)))
      (else (i32.store (get_local $bbtos) (i32.const 0))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 136872) "\u009c\u0016\u0002\u0000\u0002U<\u0000\u0087\u0000\u0000\u0000")
  (elem (i32.const 0x87) $U<)

  ;; 6.1.2360
  (func $um-star
    (local $bbtos i32)
    (i64.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i64.mul (i64.extend_u/i32 (i32.load (get_local $bbtos)))
                        (i64.extend_u/i32 (i32.load (i32.sub (get_global $tos) 
                                                             (i32.const 4)))))))
  (data (i32.const 136884) "\u00a8\u0016\u0002\u0000\u0003UM*\u0088\u0000\u0000\u0000")
  (elem (i32.const 0x88) $um-star)

  (func $UM/MOD (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136896) "\u00b4\u0016\u0002\u0000\u0006UM/MOD\u0000\u0089\u0000\u0000\u0000")
  (elem (i32.const 0x89) $UM/MOD) ;; TODO: Rename

  ;; 6.1.2380
  (func $UNLOOP
    (call $ensureCompiling))
  (data (i32.const 136912) "\u00c0\u0016\u0002\u0000\u0086UNLOOP\u0000\u008a\u0000\u0000\u0000")
  (elem (i32.const 0x8a) $UNLOOP) ;; immediate

  ;; 6.1.2390
  (func $UNTIL
    (call $ensureCompiling)
    (call $compileUntil))
  (data (i32.const 136928) "\u00d0\u0016\u0002\u0000\u0085UNTIL\u0000\u0000\u008b\u0000\u0000\u0000")
  (elem (i32.const 0x8b) $UNTIL) ;; immediate

  ;; 6.1.2410
  (func $VARIABLE
    (call $CREATE)
    (set_global $here (i32.add (get_global $here) (i32.const 4))))
  (data (i32.const 136944) "\u00e0\u0016\u0002\u0000\u0008VARIABLE\u0000\u0000\u0000\u008c\u0000\u0000\u0000")
  (elem (i32.const 0x8c) $VARIABLE)

  ;; 6.1.2430
  (func $while
    (call $ensureCompiling)
    (call $compileWhile))
  (data (i32.const 136964) "\u00f0\u0016\u0002\u0000\u0085WHILE\u0000\u0000\u008d\u0000\u0000\u0000")
  (elem (i32.const 0x8d) $while) ;; immediate

  ;; 6.1.2450
  (func $word
    (call $readWord (call $pop)))
  (data (i32.const 136980) "\u0004\u0017\u0002\u0000\u0004WORD\u0000\u0000\u0000\u008e\u0000\u0000\u0000")
  (elem (i32.const 0x8e) $word)

  ;; 6.1.2490
  (func $XOR
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8)))
               (i32.xor (i32.load (tee_local $btos (i32.sub (get_global $tos) (i32.const 4))))
                        (i32.load (get_local $bbtos))))
    (set_global $tos (get_local $btos)))
  (data (i32.const 136996) "\u0014\u0017\u0002\u0000\u0003XOR\u008f\u0000\u0000\u0000")
  (elem (i32.const 0x8f) $XOR)

  ;; 6.1.2500
  (func $left-bracket
    (call $ensureCompiling)
    (i32.store (i32.const !stateBase) (i32.const 0)))
  (data (i32.const 137008) "$\u0017\u0002\u0000\u0081[\u0000\u0000\u0090\u0000\u0000\u0000")
  (elem (i32.const 0x90) $left-bracket) ;; immediate

  ;; 6.1.2510
  (func $bracket-tick
    (call $ensureCompiling)
    (call $tick)
    (call $compilePushConst (call $pop)))
  (data (i32.const 137020) "0\u0017\u0002\u0000\u0083[']\u0091\u0000\u0000\u0000")
  (elem (i32.const 0x91) $bracket-tick) ;; immediate

  ;; 6.1.2520
  (func $bracket-char
    (call $ensureCompiling)
    (call $CHAR)
    (call $compilePushConst (call $pop)))
  (data (i32.const 137032) "<\u0017\u0002\u0000\u0086[CHAR]\u0000\u0092\u0000\u0000\u0000")
  (elem (i32.const 0x92) $bracket-char) ;; immediate

  ;; 6.1.2540
  (func $right-bracket
    (i32.store (i32.const !stateBase) (i32.const 1)))
  (data (i32.const 137048) "H\u0017\u0002\u0000\u0001]\u0000\u0000\u0093\u0000\u0000\u0000")
  (elem (i32.const 0x93) $right-bracket)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; 6.2.0280
  (func $zero-greater
    (local $btos i32)
    (if (i32.gt_s (i32.load (tee_local $btos (i32.sub (get_global $tos) 
                                                     (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (get_local $btos) (i32.const -1)))
      (else (i32.store (get_local $btos) (i32.const 0)))))
  (data (i32.const 137060) "X\u0017\u0002\u0000\u00020>\u0000\u0094\u0000\u0000\u0000")
  (elem (i32.const 0x94) $zero-greater)

  ;; 6.2.1350
  (func $erase
    (local $bbtos i32)
    (call $memset (i32.load (tee_local $bbtos (i32.sub (get_global $tos) (i32.const 8))))
                  (i32.const 0)
                  (i32.load (i32.sub (get_global $tos) (i32.const 4))))
    (set_global $tos (get_local $bbtos)))
  (data (i32.const 137072) "d\u0017\u0002\u0000\u0005ERASE\u0000\u0000\u0095\u0000\u0000\u0000")
  (elem (i32.const 0x95) $erase)

  ;; 6.2.2030
  (func $PICK
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (get_global $tos) (i32.const 4)))
               (i32.load (i32.sub (get_global $tos) 
                                  (i32.shl (i32.add (i32.load (get_local $btos))
                                                    (i32.const 2))
                                           (i32.const 2))))))
  (data (i32.const 137088) "p\u0017\u0002\u0000\u0004PICK\u0000\u0000\u0000\u0096\u0000\u0000\u0000")
  (elem (i32.const 0x96) $PICK)

  ;; 6.2.2125
  (func $refill
    (local $char i32)
    (set_global $inputBufferSize (i32.const 0))
    (if (i32.eq (get_global $sourceID) (i32.const -1))
      (then
        (call $push (i32.const -1))
        (return)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eq (tee_local $char (call $shell_getc)) (i32.const -1)))
        (i32.store8 (i32.add (i32.const !inputBufferBase) (get_global $inputBufferSize)) 
                   (get_local $char))
        (set_global $inputBufferSize (i32.add (get_global $inputBufferSize) (i32.const 1)))
        (br $loop)))
    (if (i32.eqz (get_global $inputBufferSize))
      (then (call $push (i32.const 0)))
      (else 
        (i32.store (i32.const !inBase) (i32.const 0))
        (call $push (i32.const -1)))))
  (data (i32.const 137104) "\u0080\u0017\u0002\u0000\u0006REFILL\u0000\u0097\u0000\u0000\u0000")
  (elem (i32.const 0x97) $refill)

  ;; 6.2.2295
  (func $TO
    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const !wordBase))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (call $find)
    (if (i32.eqz (call $pop)) (call $fail (i32.const 0x20000))) ;; undefined word
    (i32.store (i32.add (call $body (call $pop)) (i32.const 4)) (call $pop)))
  (data (i32.const 137120) "\u0090\u0017\u0002\u0000\u0002TO\u0000\u0098\u0000\u0000\u0000")
  (elem (i32.const 0x98) $TO)

  ;; 6.1.2395
  (func $UNUSED
    (call $push (i32.shr_s (i32.sub (i32.const !memorySize) (get_global $here)) (i32.const 2))))
  (data (i32.const 137132) "\u00a0\u0017\u0002\u0000\u0006UNUSED\u0000\u0099\u0000\u0000\u0000")
  (elem (i32.const 0x99) $UNUSED)

  ;; 6.2.2535
  (func $backslash
    (local $char i32)
    (block $endSkipComments
      (loop $skipComments
        (set_local $char (call $readChar))
        (br_if $endSkipComments (i32.eq (get_local $char) 
                                        (i32.const 0x0a #| '\n' |#)))
        (br_if $endSkipComments (i32.eq (get_local $char) (i32.const -1)))
        (br $skipComments))))
  (data (i32.const 137148) "\u00ac\u0017\u0002\u0000\u0081\u005c\u0000\u0000\u009a\u0000\u0000\u0000")
  (elem (i32.const 0x9a) $backslash) ;; immediate

  ;; 6.1.2250
  (func $SOURCE-ID
    (call $push (get_global $sourceID)))
  (data (i32.const 137160) "\u00bc\u0017\u0002\u0000\u0009SOURCE-ID\u0000\u0000\u009b\u0000\u0000\u0000")
  (elem (i32.const 0x9b) $SOURCE-ID)

  (func $dspFetch
    (i32.store
     (get_global $tos)
     (get_global $tos))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 137180) "\u00c8\u0017\u0002\u0000\u0004DSP@\u0000\u0000\u0000\u009c\u0000\u0000\u0000")
  (elem (i32.const 0x9c) $dspFetch)

  (func $S0
    (call $push (i32.const !stackBase)))
  (data (i32.const 137196) "\u00dc\u0017\u0002\u0000\u0002S0\u0000\u009d\u0000\u0000\u0000")
  (elem (i32.const 0x9d) $S0)

  (func $latest
    (i32.store (get_global $tos) (get_global $latest))
    (set_global $tos (i32.add (get_global $tos) (i32.const 4))))
  (data (i32.const 137208) "\u00ec\u0017\u0002\u0000\u0006LATEST\u0000\u009e\u0000\u0000\u0000")
  (elem (i32.const 0x9e) $latest)

  (func $HEX
    (i32.store (i32.const !baseBase) (i32.const 16)))
  (data (i32.const #x21820) "\u0008\u0018\u0002\u0000\u0003HEX\u00a0\u0000\u0000\u0000")
  (elem (i32.const #xa0) $HEX)

  ;; 6.2.2298
  (func $TRUE
    (call $push (i32.const 0xffffffff)))
  (data (i32.const #x2182c) "\u0020\u0018\u0002\u0000" "\u0004" "TRUE000" "\u00a1\u0000\u0000\u0000")
  (elem (i32.const #xa1) $TRUE)

  ;; 6.2.1485
  (func $FALSE
    (call $push (i32.const 0x0)))
  (data (i32.const #x2183c) "\u002c\u0018\u0002\u0000" "\u0005" "FALSE00" "\u00a2\u0000\u0000\u0000")
  (elem (i32.const #xa2) $FALSE)

  ;; 6.2.1930
  (func $NIP
    (call $SWAP) (call $DROP))
  (data (i32.const #x2184c) "\u003c\u0018\u0002\u0000" "\u0003" "NIP" "\u00a3\u0000\u0000\u0000")
  (elem (i32.const #xa3) $NIP)

  ;; 6.2.2300
  (func $TUCK
    (call $SWAP) (call $OVER))
  (data (i32.const #x21858) "\u004c\u0018\u0002\u0000" "\u0003" "NIP" "\u00a4\u0000\u0000\u0000")
  (elem (i32.const #xa4) $TUCK)

  (func $UWIDTH
    (local $v i32)
    (local $r i32)
    (local $base i32)
    (set_local $v (call $pop))
    (set_local $base (i32.load (i32.const !baseBase)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eqz (get_local $v)))
        (set_local $r (i32.add (get_local $r) (i32.const 1)))
        (set_local $v (i32.div_s (get_local $v) (get_local $base)))
        (br $loop)))
    (call $push (get_local $r)))
  (data (i32.const #x21864) "\u0058\u0018\u0002\u0000" "\u0006" "UWIDTH0" "\u00a5\u0000\u0000\u0000")
  (elem (i32.const #xa5) $UWIDTH)

  ;; 6.2.2405
  (data (i32.const #x21874) "\u0064\u0018\u0002\u0000" "\u0005" "VALUE00" "\u004c\u0000\u0000\u0000") ;; !constantIndex
  
  ;; 15.6.1.0220
  ;; : .S DSP@ S0 BEGIN 2DUP > WHILE DUP @ U.  SPACE 4 + REPEAT 2DROP ;

  ;; High-level words
  (!prelude #<<EOF
    \ 6.1.2320
    : U.
      BASE @ /MOD
      ?DUP IF RECURSE THEN
      DUP 10 < IF 48 ELSE 10 - 65 THEN
      +
      EMIT
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

  ;; Initializes compilation.
  ;; Parameter indicates the type of code we're compiling: type 0 (no params), 
  ;; or type 1 (1 param)
  (func $startColon (param $params i32)
    (i32.store8 (i32.const !moduleHeaderFunctionTypeBase) (get_local $params))
    (set_global $cp (i32.const !moduleBodyBase))
    (set_global $currentLocal (i32.add (i32.const -1) (get_local $params)))
    (set_global $lastLocal (i32.add (i32.const -1) (get_local $params)))
    (set_global $branchNesting (i32.const -1)))

  (func $endColon
    (local $bodySize i32)
    (local $nameLength i32)

    (call $emitEnd)

    ;; Update code size
    (set_local $bodySize (i32.sub (get_global $cp) (i32.const !moduleHeaderBase))) 
    (i32.store 
      (i32.const !moduleHeaderCodeSizeBase)
      (call $leb128-4p
         (i32.sub (get_local $bodySize) 
                  (i32.const !moduleHeaderCodeSizeOffsetPlus4))))

    ;; Update body size
    (i32.store 
      (i32.const !moduleHeaderBodySizeBase)
      (call $leb128-4p
         (i32.sub (get_local $bodySize) 
                  (i32.const !moduleHeaderBodySizeOffsetPlus4))))

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

    ;; Write a name section (if we're ending the code for the current dictionary entry)
    (if (i32.eq (i32.load (call $body (get_global $latest)))
                (get_global $nextTableIndex))
      (then
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
        (set_global $cp (i32.add (get_global $cp) (get_local $nameLength)))))

    ;; Load the code
    (call $shell_load (i32.const !moduleHeaderBase) 
                      (i32.sub (get_global $cp) (i32.const !moduleHeaderBase))
                      (get_global $nextTableIndex))

    (set_global $nextTableIndex (i32.add (get_global $nextTableIndex) (i32.const 1))))


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

    (if (i32.eqz (tee_local $length (i32.load8_u (i32.const !wordBase))))
      (return (i32.const -1)))

    (set_local $p (i32.const !wordBasePlus1))
    (set_local $end (i32.add (i32.const !wordBasePlus1) (get_local $length)))
    (set_local $base (i32.load (i32.const !baseBase)))

    ;; Read first character
    (if (i32.eq (tee_local $char (i32.load8_u (i32.const !wordBasePlus1)))
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

  (func $fail (param $str i32)
    (call $push (get_local $str))
    (call $COUNT)
    (call $TYPE)
    (call $shell_emit (i32.const 10))
    (call $ABORT))


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Interpreter
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; Interprets the string in the input, until the end of string is reached.
  ;; Returns 0 if processed, 1 if still compiling, or traps if a word 
  ;; was not found.
  (func $interpret (result i32)
    (local $findResult i32)
    (local $findToken i32)
    (local $error i32)
    (set_local $error (i32.const 0))
    (set_global $tors (i32.const !returnStackBase))
    (block $endLoop
      (loop $loop
        (call $readWord (i32.const 0x20))
        (br_if $endLoop (i32.eqz (i32.load8_u (i32.const !wordBase))))
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
                (call $fail (i32.const 0x20000))))) ;; undefined word
          (else ;; Found the word. 
            ;; Are we compiling or is it immediate?
            (if (i32.or (i32.eqz (i32.load (i32.const !stateBase)))
                        (i32.eq (get_local $findResult) (i32.const 1)))
              (then
                (call $push (get_local $findToken))
                (call $EXECUTE))
              (else
                ;; We're compiling a non-immediate
                (call $compileCall (get_local $findToken))))))
          (br $loop)))
    ;; 'WORD' left the address on the stack
    (drop (call $pop))
    (return (i32.load (i32.const !stateBase))))

  (func $readWord (param $delimiter i32)
    (local $char i32)
    (local $stringPtr i32)

    ;; Skip leading delimiters
    (block $endSkipBlanks
      (loop $skipBlanks
        (set_local $char (call $readChar))
        (br_if $skipBlanks (i32.eq (get_local $char) (get_local $delimiter)))
        (br_if $skipBlanks (i32.eq (get_local $char) (i32.const 0x0a #| ' ' |#)))
        (br $endSkipBlanks)))

    (set_local $stringPtr (i32.const !wordBasePlus1))
    (if (i32.ne (get_local $char) (i32.const -1)) 
      (if (i32.ne (get_local $char) (i32.const 0x0a))
        (then 
          ;; Search for delimiter
          (i32.store8 (i32.const !wordBasePlus1) (get_local $char))
          (set_local $stringPtr (i32.const !wordBasePlus2))
          (block $endReadChars
            (loop $readChars
              (set_local $char (call $readChar))
              (br_if $endReadChars (i32.eq (get_local $char) (get_local $delimiter)))
              (br_if $endReadChars (i32.eq (get_local $char) (i32.const 0x0a #| ' ' |#)))
              (br_if $endReadChars (i32.eq (get_local $char) (i32.const -1)))
              (i32.store8 (get_local $stringPtr) (get_local $char))
              (set_local $stringPtr (i32.add (get_local $stringPtr) (i32.const 0x1)))
              (br $readChars))))))

     ;; Write word length
     (i32.store8 (i32.const !wordBase) 
       (i32.sub (get_local $stringPtr) (i32.const !wordBasePlus1)))
     
     (call $push (i32.const !wordBase)))

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
    (call $emitIf)

    (set_global $branchNesting (i32.add (get_global $branchNesting) (i32.const 1))))

  (func $compileThen 
    (set_global $branchNesting (i32.sub (get_global $branchNesting) (i32.const 1)))
    (call $emitEnd))

  (func $compileDo
    (set_global $currentLocal (i32.add (get_global $currentLocal) (i32.const 3)))
    (if (i32.gt_s (get_global $currentLocal) (get_global $lastLocal))
      (then
        (set_global $lastLocal (get_global $currentLocal))))

    ;; Save branch nesting
    (i32.store (get_global $tors) (get_global $branchNesting))
    (set_global $tors (i32.add (get_global $tors) (i32.const 4)))
    (set_global $branchNesting (i32.const 0))

    (call $compilePop)
    (call $emitSetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $compilePop)
    (call $emitSetLocal (get_global $currentLocal))

    (call $emitGetLocal (get_global $currentLocal))
    (call $emitGetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $emitGreaterEqualSigned)
    (call $emitSetLocal (i32.sub (get_global $currentLocal) (i32.const 2)))

    (call $emitBlock)
    (call $emitLoop))
  
  (func $compileLoop 
    (call $emitConst (i32.const 1))
    (call $emitGetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $emitAdd)
    (call $emitSetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))

    (call $emitGetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $emitGetLocal (get_global $currentLocal))
    (call $emitGreaterEqualSigned)
    (call $emitBrIf (i32.const 1))
    (call $compileLoopEnd))

  (func $compilePlusLoop 
    (call $compilePop)
    (call $emitGetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $emitAdd)
    (call $emitSetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))

    (call $emitGetLocal (i32.sub (get_global $currentLocal) (i32.const 2)))
    (call $emitEqualsZero)
    (call $emitIf)
    (call $emitGetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $emitGetLocal (get_global $currentLocal))
    (call $emitLesserSigned)
    (call $emitBrIf (i32.const 2))
    (call $emitElse)
    (call $emitGetLocal (i32.sub (get_global $currentLocal) (i32.const 1)))
    (call $emitGetLocal (get_global $currentLocal))
    (call $emitGreaterEqualSigned)
    (call $emitBrIf (i32.const 2))
    (call $emitEnd)

    (call $compileLoopEnd))

  ;; Assumes increment is on the operand stack
  (func $compileLoopEnd
    (local $btors i32)
    (call $emitBr (i32.const 0))
    (call $emitEnd)
    (call $emitEnd)
    (set_global $currentLocal (i32.sub (get_global $currentLocal) (i32.const 3)))

    ;; Restore branch nesting
    (set_global $branchNesting (i32.load (tee_local $btors (i32.sub (get_global $tors) (i32.const 4)))))
    (set_global $tors (get_local $btors)))


  (func $compileLeave
    (call $emitBr (i32.add (get_global $branchNesting) (i32.const 1))))

  (func $compileBegin
    (call $emitBlock)
    (call $emitLoop)
    (set_global $branchNesting (i32.add (get_global $branchNesting) (i32.const 2))))

  (func $compileWhile
    (call $compilePop)
    (call $emitEqualsZero)
    (call $emitBrIf (i32.const 1)))

  (func $compileRepeat
    (call $emitBr (i32.const 0))
    (call $emitEnd)
    (call $emitEnd)
    (set_global $branchNesting (i32.sub (get_global $branchNesting) (i32.const 2))))

  (func $compileUntil
    (call $compilePop)
    (call $emitEqualsZero)
    (call $emitBrIf (i32.const 0))
    (call $emitBr (i32.const 1))
    (call $emitEnd)
    (call $emitEnd)
    (set_global $branchNesting (i32.sub (get_global $branchNesting) (i32.const 2))))

  (func $compileRecurse
    ;; call 0
    (i32.store8 (get_global $cp) (i32.const 0x10))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (i32.const 0x00))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $compilePop
    (call $emitICall (i32.const 2) (i32.const !popIndex)))


  (func $compileCall (param $findToken i32)
    (local $body i32)
    (set_local $body (call $body (get_local $findToken)))
    (if (i32.and (i32.load (i32.add (get_local $findToken) (i32.const 4)))
                 (i32.const !fData))
      (then
        (call $emitConst (i32.add (get_local $body) (i32.const 4)))
        (call $emitICall (i32.const 1) (i32.load (get_local $body))))
      (else
        (call $emitICall (i32.const 0) (i32.load (get_local $body))))))
  (elem (i32.const !compileCallIndex) $compileCall)

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

  (func $emitIf
    (i32.store8 (get_global $cp) (i32.const 0x04))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1)))
    (i32.store8 (get_global $cp) (i32.const 0x40))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

  (func $emitElse
    (i32.store8 (get_global $cp) (i32.const 0x05))
    (set_global $cp (i32.add (get_global $cp) (i32.const 1))))

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

  (func $emitLesserSigned
    (i32.store8 (get_global $cp) (i32.const 0x48))
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

  (func $pushDataAddress (param $d i32)
    (call $push (get_local $d)))
  (elem (i32.const !pushDataAddressIndex) $pushDataAddress)

  (func $setLatestBody (param $v i32)
    (i32.store (call $body (get_global $latest)) (get_local $v)))
  (elem (i32.const !setLatestBodyIndex) $setLatestBody)

  (func $pushIndirect (param $v i32)
    (call $push (i32.load (get_local $v))))
  (elem (i32.const !pushIndirectIndex) $pushIndirect)

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
      (call $fail (i32.const 0x2005C)))) ;; word not interpretable

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
          (return (i32.const -1)))
        (else
          (set_local $n (i32.load8_s (i32.add (get_global $inputBufferBase) (get_local $in))))
          (i32.store (i32.const !inBase) (i32.add (get_local $in) (i32.const 1)))
          (return (get_local $n)))))
    (unreachable))

  (func $loadPrelude (export "loadPrelude")
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
    (call $SWAP)
    (call $c-store))

  (func $sieve
    (local $i i32)
    (local $end i32)
    (call $here) 
    (call $OVER) 
    (call $erase)
    (call $push (i32.const 2))
    (block $endLoop1
      (loop $loop1
        (call $two-dupe) 
        (call $DUP) 
        (call $star) 
        (call $greater-than)
        (br_if $endLoop1 (i32.eqz (call $pop)))
        (call $DUP) 
        (call $sieve_prime)
        (if (i32.ne (call $pop) (i32.const 0))
          (block
            (call $two-dupe) 
            (call $DUP) 
            (call $star)
            (set_local $i (call $pop))
            (set_local $end (call $pop))
            (block $endLoop2
              (loop $loop2
                (call $push (get_local $i))
                (call $sieve_composite) 
                (call $DUP)
                (set_local $i (i32.add (call $pop) (get_local $i)))
                (br_if $endLoop2 (i32.ge_s (get_local $i) (get_local $end)))
                (br $loop2)))))
        (call $one-plus)
        (br $loop1)))
    (call $DROP) 
    (call $push (i32.const 1))
    (call $SWAP) 
    (call $push (i32.const 2))
    (set_local $i (call $pop))
    (set_local $end (call $pop))
    (block $endLoop3
      (loop $loop3
        (call $push (get_local $i))
        (call $sieve_prime) 
        (if (i32.ne (call $pop) (i32.const 0))
        (block
          (call $DROP)
          (call $push (get_local $i))))
        (set_local $i (i32.add (i32.const 1) (get_local $i)))
        (br_if $endLoop3 (i32.ge_s (get_local $i) (get_local $end)))
        (br $loop3))))
  (data (i32.const 137224) "\u00f8\u0017\u0002\u0000" "\u000c" "sieve_direct\u0000\u0000\u0000" "\u009f\u0000\u0000\u0000")
  (elem (i32.const 0x9f) $sieve)
    
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Data
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; The dictionary has entries of the following form:
  ;; - prev (4 bytes): Pointer to start of previous entry
  ;; - flags|name-length (1 byte): Length of the entry name, ORed with
  ;;   flags in the top 3 bits.
  ;;   Flags is an ORed value of:
  ;;        Immediate: 0x80
  ;;        Data: 0x40
  ;;        Hidden: 0x20
  ;; - name (n bytes): Name characters. End is 4-byte aligned.
  ;; - code pointer (4 bytes): Index into the function 
  ;;   table of code to execute
  ;; - data (m bytes)
  ;;
  ;; Execution tokens are addresses of dictionary entries

  (data (i32.const !baseBase) "\u000A\u0000\u0000\u0000")
  (data (i32.const !stateBase) "\u0000\u0000\u0000\u0000")
  (data (i32.const !inBase) "\u0000\u0000\u0000\u0000")
  (data (i32.const !moduleHeaderBase)
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
      "\u00FA" ;; Type 0
      
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
        "\u00FD\u0000\u0000\u0000\u007F") ;; # #i32 locals (padded)
  (data (i32.const !preludeDataBase)  !preludeData)

  (func (export "tos") (result i32)
    (get_global $tos))

  (func (export "interpret") (result i32)
    (local $result i32)
    (call $refill)
    (drop (call $pop))
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

  ;; Used for experiments
  (func (export "set_state") (param $latest i32) (param $here i32)
    (set_global $latest (get_local $latest))
    (set_global $here (get_local $here)))

  ;; Table starts with 16 reserved addresses for utility, non-words 
  ;; functions (used in compiled words). From then on, the built-in
  ;; words start.
  (table (export "table") !nextTableIndex anyfunc)

  (global $latest (mut i32) (i32.const #x21874))
  (global $here (mut i32) (i32.const #x21884))
  (global $nextTableIndex (mut i32) (i32.const !nextTableIndex))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Compilation state
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (global $currentLocal (mut i32) (i32.const 0))
  (global $lastLocal (mut i32) (i32.const -1))
  (global $branchNesting (mut i32) (i32.const -1))

  ;; Compilation pointer
  (global $cp (mut i32) (i32.const !moduleBodyBase)))

;; 
;; Adding a word:
;; - Create the function
;; - Add the dictionary entry to memory as data
;; - Update the $latest and $here globals
;; - Add the table entry as elem
;; - Update !nextTableIndex
