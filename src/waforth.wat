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

  ;; Memory size:
  ;;   MEMORY_SIZE := 104857600     (100*1024*1024)
  ;;   MEMORY_SIZE_PAGES := 1600     (MEMORY_SIZE / 65536)
  ;;
  ;; Memory layout:
  ;;   BASE_BASE          :=   0x100
  ;;   STATE_BASE         :=   0x104
  ;;   IN_BASE            :=   0x108
  ;;   WORD_BASE          :=   0x200
  ;;   WORD_BASE_PLUS_1   :=   0x201
  ;;   WORD_BASE_PLUS_2   :=   0x202
  ;;   INPUT_BUFFER_BASE  :=   0x300
  ;;   (Compiled modules are limited to 4096 bytes until Chrome refuses to load them synchronously)
  ;;   MODULE_HEADER_BASE :=  0x1000 
  ;;   STACK_BASE := 0x10000
  ;;   RETURN_STACK_BASE  :=  0x2000
  ;;   STRINGS_BASE       := 0x20000
  ;;   DICTIONARY_BASE    := 0x21000
  (memory (export "memory") MEMORY_SIZE_PAGES)

  (type $word (func))
  (type $dataWord (func (param i32)))

  (global $tos (mut i32) (i32.const STACK_BASE))
  (global $tors (mut i32) (i32.const RETURN_STACK_BASE))
  (global $inputBufferBase (mut i32) (i32.const INPUT_BUFFER_BASE))
  (global $inputBufferSize (mut i32) (i32.const 0))

  (global $sourceID (mut i32) (i32.const 0))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Data
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (data (i32.const BASE_BASE) "\0A\00\00\00")
  (data (i32.const STATE_BASE) "\00\00\00\00")
  (data (i32.const IN_BASE) "\00\00\00\00")

  (data (i32.const MODULE_HEADER_BASE)
    "\00\61\73\6D" ;; Header
    "\01\00\00\00" ;; Version

    "\01" "\11" ;; Type section
      "\04" ;; #Entries
        "\60\00\00" ;; (func)
        "\60\01\7F\00" ;; (func (param i32))
        "\60\00\01\7F" ;; (func (result i32))
        "\60\01\7f\01\7F" ;; (func (param i32) (result i32))

    "\02" "\2B" ;; Import section
      "\03" ;; #Entries
      "\03\65\6E\76" "\05\74\61\62\6C\65" ;; 'env' . 'table'
        "\01" "\70" "\00" "\FB\00\00\00" ;; table, anyfunc, flags, initial size
      "\03\65\6E\76" "\06\6d\65\6d\6f\72\79" ;; 'env' . 'memory'
        "\02" "\00" "\01" ;; memory
      "\03\65\6E\76" "\03\74\6f\73" ;; 'env' . 'tos'
        "\03" "\7F" "\00" ;; global, i32, immutable

    
    "\03" "\02" ;; Function section
      "\01" ;; #Entries
      "\FA" ;; Type 0
      
    "\09" "\0a" ;; Element section
      "\01" ;; #Entries
      "\00" ;; Table 0
      "\41\FC\00\00\00\0B" ;; i32.const ..., end
      "\01" ;; #elements
        "\00" ;; function 0

    "\0A" "\FF\00\00\00" ;; Code section (padded length)
    "\01" ;; #Bodies
      "\FE\00\00\00" ;; Body size (padded)
      "\01" ;; #locals
        "\FD\00\00\00\7F") ;; # #i32 locals (padded)

  ;; Compiled module header offsets:
  ;;
  ;;   MODULE_HEADER_SIZE := 0x68
  ;;   MODULE_HEADER_CODE_SIZE_OFFSET := 0x59
  ;;   MODULE_HEADER_CODE_SIZE_OFFSET_PLUS_4 := 0x5d
  ;;   MODULE_HEADER_BODY_SIZE_OFFSET := 0x5e
  ;;   MODULE_HEADER_BODY_SIZE_OFFSET_PLUS_4 := 0x62
  ;;   MODULE_HEADER_LOCAL_COUNT_OFFSET := 0x63
  ;;   MODULE_HEADER_TABLE_INDEX_OFFSET := 0x51
  ;;   MODULE_HEADER_TABLE_INITIAL_SIZE_OFFSET := 0x2b
  ;;   MODULE_HEADER_FUNCTION_TYPE_OFFSET := 0x4b
  ;;
  ;;   MODULE_BODY_BASE := 0x1068                    (MODULE_HEADER_BASE + MODULE_HEADER_SIZE)
  ;;   MODULE_HEADER_CODE_SIZE_BASE := 0x1059          (MODULE_HEADER_BASE + MODULE_HEADER_CODE_SIZE_OFFSET)
  ;;   MODULE_HEADER_BODY_SIZE_BASE := 0x105e          (MODULE_HEADER_BASE + MODULE_HEADER_BODY_SIZE_OFFSET)
  ;;   MODULE_HEADER_LOCAL_COUNT_BASE := 0x1063        (MODULE_HEADER_BASE + MODULE_HEADER_LOCAL_COUNT_OFFSET)
  ;;   MODULE_HEADER_TABLE_INDEX_BASE := 0x1051        (MODULE_HEADER_BASE + MODULE_HEADER_TABLE_INDEX_OFFSET)
  ;;   MODULE_HEADER_TABLE_INITIAL_SIZE_BASE := 0x102b  (MODULE_HEADER_BASE + MODULE_HEADER_TABLE_INITIAL_SIZE_OFFSET)
  ;;   MODULE_HEADER_FUNCTION_TYPE_BASE := 0x104b      (MODULE_HEADER_BASE + MODULE_HEADER_FUNCTION_TYPE_OFFSET)


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Constant strings
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (data (i32.const 0x20000) "\0eundefined word")
  (data (i32.const 0x20014) "\0ddivision by 0")
  (data (i32.const 0x20028) "\10incomplete input")
  (data (i32.const 0x2003C) "\0bmissing ')'")
  (data (i32.const 0x2004C) "\09missing \22")
  (data (i32.const 0x2005C) "\24word not supported in interpret mode")
  (data (i32.const 0x20084) "\0Fnot implemented")
  
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Built-in words
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; These follow the following pattern:
  ;; - WebAssembly function definition (func ...)
  ;; - Dictionary entry in memory (data ...)
  ;; - Function table entry (elem ...)
  ;;
  ;; The dictionary entry has the following form:
  ;; - prev (4 bytes): Pointer to start of previous entry
  ;; - flags|name-length (1 byte): Length of the entry name, OR-ed with
  ;;   flags in the top 3 bits.
  ;;   Flags is an OR-ed value of
  ;;      F_IMMEDIATE := 0x80
  ;;      F_DATA := 0x40
  ;;      F_HIDDEN := 0x20
  ;;   Length is acquired by masking
  ;;      LENGTH_MASK := 0x1F
  ;; - name (n bytes): Name characters. End is 4-byte aligned.
  ;; - code pointer (4 bytes): Index into the function 
  ;;   table of code to execute
  ;; - data (optional m bytes, only if 'data' flag is set)
  ;;
  ;; Execution tokens are addresses of dictionary entries
  ;;
  ;; The following table indices are predefined:
  ;;   PUSH_INDEX := 1
  ;;   POP_INDEX := 2
  ;;   PUSH_DATA_ADDRESS_INDEX := 3
  ;;   SET_LATEST_BODY_INDEX := 4
  ;;   COMPILE_CALL_INDEX := 5
  ;;   PUSH_INDIRECT_INDEX := 6
  ;;   TYPE_INDEX := 0x85
  ;;   ABORT_INDEX := 0x39
  ;;   CONSTANT_INDEX := 0x4c
  ;;   NEXT_TABLE_INDEX := 0xa7

  ;; 6.1.0010 ! 
  (func $!
    (local $bbtos i32)
    (i32.store (i32.load (i32.sub (global.get $tos) (i32.const 4)))
               (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))))
    (global.set $tos (local.get $bbtos)))
  (data (i32.const DICTIONARY_BASE) "\00\00\00\00\01!\00\00\10\00\00\00")
  (elem (i32.const 0x10) $!)

  (func $# (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135180) "\00\10\02\00\01#\00\00\11\00\00\00")
  (elem (i32.const 0x11) $#)

  (func $#> (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135192) "\0c\10\02\00\02#>\00\12\00\00\00")
  (elem (i32.const 0x12) $#>)

  (func $#S (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135204) "\18\10\02\00\02#S\00\13\00\00\00")
  (elem (i32.const 0x13) $#S)

  ;; 6.1.0070
  (func $'
    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const WORD_BASE))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (call $FIND)
    (drop (call $pop)))
  (data (i32.const 135216) "$\10\02\00\01'\00\00\14\00\00\00")
  (elem (i32.const 0x14) $')

  ;; 6.1.0080
  (func $paren
    (local $c i32)
    (block $endLoop
      (loop $loop
        (if (i32.lt_s (tee_local $c (call $readChar)) (i32.const 0)) 
          (call $fail (i32.const 0x2003C))) ;; missing ')'
        (br_if $endLoop (i32.eq (local.get $c) (i32.const 41)))
        (br $loop))))
  (data (i32.const 135228) "0\10\02\00" "\81" (; immediate ;) "(\00\00\15\00\00\00")
  (elem (i32.const 0x15) $paren)

  ;; 6.1.0090
  (func $*
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.mul (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135240) "<\10\02\00\01*\00\00\16\00\00\00")
  (elem (i32.const 0x16) $*)

  ;; 6.1.0100
  (func $*/
    (local $bbtos i32)
    (local $bbbtos i32)
    (i32.store (tee_local $bbbtos (i32.sub (global.get $tos) (i32.const 12)))
               (i32.wrap/i64
                  (i64.div_s
                      (i64.mul (i64.extend_s/i32 (i32.load (local.get $bbbtos)))
                               (i64.extend_s/i32 (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8))))))
                      (i64.extend_s/i32 (i32.load (i32.sub (global.get $tos) (i32.const 4)))))))
    (global.set $tos (local.get $bbtos)))
  (data (i32.const 135252) "H\10\02\00\02*/\00\17\00\00\00")
  (elem (i32.const 0x17) $*/)

  ;; 6.1.0110
  (func $*/MOD
    (local $btos i32)
    (local $bbtos i32)
    (local $bbbtos i32)
    (local $x1 i64)
    (local $x2 i64)
    (i32.store (tee_local $bbbtos (i32.sub (global.get $tos) (i32.const 12)))
               (i32.wrap/i64
                  (i64.rem_s
                      (tee_local $x1 (i64.mul (i64.extend_s/i32 (i32.load (local.get $bbbtos)))
                                              (i64.extend_s/i32 (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))))))
                      (tee_local $x2 (i64.extend_s/i32 (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))))))))
    (i32.store (local.get $bbtos) (i32.wrap/i64 (i64.div_s (local.get $x1) (local.get $x2))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135264) "T\10\02\00\05*/MOD\00\00\18\00\00\00")
  (elem (i32.const 0x18) $*/MOD)

  ;; 6.1.0120
  (func $+
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.add (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135280) "`\10\02\00\01+\00\00\19\00\00\00")
  (elem (i32.const 0x19) $+)

  ;; 6.1.0130
  (func $+!
    (local $addr i32)
    (local $bbtos i32)
    (i32.store (tee_local $addr (i32.load (i32.sub (global.get $tos) (i32.const 4))))
               (i32.add (i32.load (local.get $addr))
                        (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8))))))
    (global.set $tos (local.get $bbtos)))
  (data (i32.const 135292) "p\10\02\00\02+!\00\1a\00\00\00")
  (elem (i32.const 0x1a) $+!)

  ;; 6.1.0140
  (func $+LOOP
    (call $ensureCompiling)
    (call $compilePlusLoop))
  (data (i32.const 135304) "|\10\02\00" "\85" (; immediate ;) "+LOOP\00\00" "\1b\00\00\00")
  (elem (i32.const 0x1b) $+LOOP)

  ;; 6.1.0150
  (func $comma
    (i32.store
      (global.get $here)
      (i32.load (i32.sub (global.get $tos) (i32.const 4))))
    (global.set $here (i32.add (global.get $here) (i32.const 4)))
    (global.set $tos (i32.sub (global.get $tos) (i32.const 4))))
  (data (i32.const 135320) "\88\10\02\00\01,\00\00\1c\00\00\00")
  (elem (i32.const 0x1c) $comma)

  ;; 6.1.0160
  (func $-
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.sub (i32.load (local.get $bbtos))
                        (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135332) "\98\10\02\00\01-\00\00\1d\00\00\00")
  (elem (i32.const 0x1d) $-)

  ;; 6.1.0180
  (func $.q
    (call $ensureCompiling)
    (call $Sq)
    (call $emitICall (i32.const 0) (i32.const TYPE_INDEX)))
  (data (i32.const 135344) "\a4\10\02\00" "\82" (; immediate ;) ".\22\00" "\1e\00\00\00")
  (elem (i32.const 0x1e) $.q)

  ;; 6.1.0230
  (func $/
    (local $btos i32)
    (local $bbtos i32)
    (local $divisor i32)
    (if (i32.eqz (tee_local $divisor (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))))
      (call $fail (i32.const 0x20014))) ;; division by 0
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.div_s (i32.load (local.get $bbtos)) (local.get $divisor)))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135356) "\b0\10\02\00\01/\00\00\1f\00\00\00")
  (elem (i32.const 0x1f) $/)

  ;; 6.1.0240
  (func $/MOD
    (local $btos i32)
    (local $bbtos i32)
    (local $n1 i32)
    (local $n2 i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.rem_s (tee_local $n1 (i32.load (local.get $bbtos)))
                          (tee_local $n2 (i32.load (tee_local $btos (i32.sub (global.get $tos) 
                                                                             (i32.const 4)))))))
    (i32.store (local.get $btos) (i32.div_s (local.get $n1) (local.get $n2))))
  (data (i32.const 135368) "\bc\10\02\00\04/MOD\00\00\00 \00\00\00")
  (elem (i32.const 0x20) $/MOD)

  ;; 6.1.0250
  (func $0<
    (local $btos i32)
    (if (i32.lt_s (i32.load (tee_local $btos (i32.sub (global.get $tos) 
                                                     (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (local.get $btos) (i32.const -1)))
      (else (i32.store (local.get $btos) (i32.const 0)))))
  (data (i32.const 135384) "\c8\10\02\00\020<\00!\00\00\00")
  (elem (i32.const 0x21) $0<)


  ;; 6.1.0270
  (func $0=
    (local $btos i32)
    (if (i32.eqz (i32.load (tee_local $btos (i32.sub (global.get $tos) 
                                                     (i32.const 4)))))
      (then (i32.store (local.get $btos) (i32.const -1)))
      (else (i32.store (local.get $btos) (i32.const 0)))))
  (data (i32.const 135396) "\d8\10\02\00\020=\00\22\00\00\00")
  (elem (i32.const 0x22) $0=)

  ;; 6.1.0290
  (func $1+
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.add (i32.load (local.get $btos)) (i32.const 1))))
  (data (i32.const 135408) "\e4\10\02\00\021+\00#\00\00\00")
  (elem (i32.const 0x23) $1+)

  ;; 6.1.0300
  (func $1-
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.sub (i32.load (local.get $btos)) (i32.const 1))))
  (data (i32.const 135420) "\f0\10\02\00\021-\00$\00\00\00")
  (elem (i32.const 0x24) $1-)


  ;; 6.1.0310
  (func $2! 
    (call $SWAP) (call $OVER) (call $!) (call $CELL+) (call $!))
  (data (i32.const 135432) "\fc\10\02\00\022!\00%\00\00\00")
  (elem (i32.const 0x25) $2!)

  ;; 6.1.0320
  (func $2*
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.shl (i32.load (local.get $btos)) (i32.const 1))))
  (data (i32.const 135444) "\08\11\02\00\022*\00&\00\00\00")
  (elem (i32.const 0x26) $2*)

  ;; 6.1.0330
  (func $2/
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.shr_s (i32.load (local.get $btos)) (i32.const 1))))
  (data (i32.const 135456) "\14\11\02\00\022/\00'\00\00\00")
  (elem (i32.const 0x27) $2/)

  ;; 6.1.0350
  (func $2@ 
    (call $DUP)
    (call $CELL+)
    (call $@)
    (call $SWAP)
    (call $@))
  (data (i32.const 135468) " \11\02\00\022@\00(\00\00\00")
  (elem (i32.const 0x28) $2@)


  ;; 6.1.0370 
  (func $2DROP
    (global.set $tos (i32.sub (global.get $tos) (i32.const 8))))
  (data (i32.const 135480) ",\11\02\00\052DROP\00\00)\00\00\00")
  (elem (i32.const 0x29) $2DROP)

  ;; 6.1.0380
  (func $2DUP
    (i32.store (global.get $tos)
               (i32.load (i32.sub (global.get $tos) (i32.const 8))))
    (i32.store (i32.add (global.get $tos) (i32.const 4))
               (i32.load (i32.sub (global.get $tos) (i32.const 4))))
    (global.set $tos (i32.add (global.get $tos) (i32.const 8))))
  (data (i32.const 135496) "8\11\02\00\042DUP\00\00\00*\00\00\00")
  (elem (i32.const 0x2a) $2DUP)

  ;; 6.1.0400
  (func $2OVER
    (i32.store (global.get $tos)
               (i32.load (i32.sub (global.get $tos) (i32.const 16))))
    (i32.store (i32.add (global.get $tos) (i32.const 4))
               (i32.load (i32.sub (global.get $tos) (i32.const 12))))
    (global.set $tos (i32.add (global.get $tos) (i32.const 8))))
  (data (i32.const 135512) "H\11\02\00\052OVER\00\00+\00\00\00")
  (elem (i32.const 0x2b) $2OVER)

  ;; 6.1.0430
  (func $2SWAP
    (local $x1 i32)
    (local $x2 i32)
    (local.set $x1 (i32.load (i32.sub (global.get $tos) (i32.const 16))))
    (local.set $x2 (i32.load (i32.sub (global.get $tos) (i32.const 12))))
    (i32.store (i32.sub (global.get $tos) (i32.const 16))
               (i32.load (i32.sub (global.get $tos) (i32.const 8))))
    (i32.store (i32.sub (global.get $tos) (i32.const 12))
               (i32.load (i32.sub (global.get $tos) (i32.const 4))))
    (i32.store (i32.sub (global.get $tos) (i32.const 8))
               (local.get $x1))
    (i32.store (i32.sub (global.get $tos) (i32.const 4))
               (local.get $x2)))
  (data (i32.const 135528) "X\11\02\00\052SWAP\00\00,\00\00\00")
  (elem (i32.const 0x2c) $2SWAP)

  ;; 6.1.0450
  (func $:
    (call $CREATE)
    (call $hidden)

    ;; Turn off (default) data flag
    (i32.store 
      (i32.add (global.get $latest) (i32.const 4))
      (i32.xor 
        (i32.load (i32.add (global.get $latest) (i32.const 4)))
        (i32.const F_DATA)))

    ;; Store the code pointer already
    ;; The code hasn't been loaded yet, but since nothing can affect the next table
    ;; index, we can assume the index will be correct. This allows semicolon to be
    ;; agnostic about whether it is compiling a word or a DOES>.
    (i32.store (call $body (global.get $latest)) (global.get $nextTableIndex))

    (call $startColon (i32.const 0))
    (call $right-bracket))
  (data (i32.const 135544) "h\11\02\00\01:\00\00-\00\00\00")
  (elem (i32.const 0x2d) $:)

  ;; 6.1.0460
  (func $semicolon
    (call $ensureCompiling)
    (call $endColon)
    (call $hidden)
    (call $left-bracket))
  (data (i32.const 135556) "x\11\02\00" "\81" (; immediate ;) ";\00\00" ".\00\00\00")
  (elem (i32.const 0x2e) $semicolon)

  ;; 6.1.0480
  (func $<
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_s (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8))))
                  (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135568) "\84\11\02\00\01<\00\00/\00\00\00")
  (elem (i32.const 0x2f) $<)

  (func $<# (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135580) "\90\11\02\00\02<#\000\00\00\00")
  (elem (i32.const 0x30) $<#)

  ;; 6.1.0530
  (func $=
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.eq (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8))))
                (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135592) "\9c\11\02\00\01=\00\001\00\00\00")
  (elem (i32.const 0x31) $=)

  ;; 6.1.0540
  (func $>
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.gt_s (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8))))
                  (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135604) "\a8\11\02\00\01>\00\002\00\00\00")
  (elem (i32.const 0x32) $>)

  ;; 6.1.0550
  (func $>BODY
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.add (call $body (i32.load (local.get $btos)))
                        (i32.const 4))))
  (data (i32.const 135616) "\b4\11\02\00\05>BODY\00\003\00\00\00")
  (elem (i32.const 0x33) $>BODY)

  ;; 6.1.0560
  (func $>IN
    (i32.store (global.get $tos) (i32.const IN_BASE))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 135632) "\c0\11\02\00\03>IN4\00\00\00")
  (elem (i32.const 0x34) $>IN)

  (func $>NUMBER (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 135644) "\d0\11\02\00\07>NUMBER5\00\00\00")
  (elem (i32.const 0x35) $>NUMBER)

  ;; 6.1.0580
  (func $>R
    (global.set $tos (i32.sub (global.get $tos) (i32.const 4)))
    (i32.store (global.get $tors) (i32.load (global.get $tos)))
    (global.set $tors (i32.add (global.get $tors) (i32.const 4))))
  (data (i32.const 135660) "\dc\11\02\00\02>R\006\00\00\00")
  (elem (i32.const 0x36) $>R)

  ;; 6.1.0630 
  (func $?DUP
    (local $btos i32)
    (if (i32.ne (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))
                (i32.const 0))
      (then
        (i32.store (global.get $tos)
                   (i32.load (local.get $btos)))
        (global.set $tos (i32.add (global.get $tos) (i32.const 4))))))
  (data (i32.const 135672) "\ec\11\02\00\04?DUP\00\00\007\00\00\00")
  (elem (i32.const 0x37) $?DUP)

  ;; 6.1.0650
  (func $@
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.load (i32.load (local.get $btos)))))
  (data (i32.const 135688) "\f8\11\02\00\01@\00\008\00\00\00")
  (elem (i32.const 0x38) $@)

  ;; 6.1.0670 ABORT 
  (func $ABORT
    (global.set $tos (i32.const STACK_BASE))
    (call $QUIT))
  ;; WARNING: If you change this table index, make sure the emitted ICalls are also updated
  (data (i32.const 135700) "\08\12\02\00\05ABORT\00\009\00\00\00")
  (elem (i32.const 0x39) $ABORT) ;; none

  ;; 6.1.0680 ABORT"
  (func $ABORTq
    (call $compileIf)
    (call $Sq)
    (call $emitICall (i32.const 0) (i32.const TYPE_INDEX))
    (call $emitICall (i32.const 0) (i32.const ABORT_INDEX))
    (call $compileThen))
  (data (i32.const 135716) "\14\12\02\00" "\86" (; immediate ;) "ABORT\22\00" ":\00\00\00")
  (elem (i32.const 0x3a) $ABORTq)

  ;; 6.1.0690
  (func $ABS
    (local $btos i32)
    (local $v i32)
    (local $y i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.sub (i32.xor (tee_local $v (i32.load (local.get $btos)))
                                 (tee_local $y (i32.shr_s (local.get $v) (i32.const 31))))
                        (local.get $y))))
  (data (i32.const 135732) "$\12\02\00\03ABS;\00\00\00")
  (elem (i32.const 0x3b) $ABS)

  ;; 6.1.0695
  (func $ACCEPT
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (call $shell_accept (i32.load (local.get $bbtos))
                                   (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135744) "4\12\02\00\06ACCEPT\00<\00\00\00")
  (elem (i32.const 0x3c) $ACCEPT)

  ;; 6.1.0705
  (func $ALIGN
    (global.set $here (i32.and
                        (i32.add (global.get $here) (i32.const 3))
                        (i32.const -4 (; ~3 ;)))))
  (data (i32.const 135760) "@\12\02\00\05ALIGN\00\00=\00\00\00")
  (elem (i32.const 0x3d) $ALIGN)

  ;; 6.1.0706
  (func $ALIGNED
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.and (i32.add (i32.load (local.get $btos)) (i32.const 3))
                        (i32.const -4 (; ~3 ;)))))
  (data (i32.const 135776) "P\12\02\00\07ALIGNED>\00\00\00")
  (elem (i32.const 0x3e) $ALIGNED)

  ;; 6.1.0710
  (func $ALLOT
    (global.set $here (i32.add (global.get $here) (call $pop))))
  (data (i32.const 135792) "`\12\02\00\05ALLOT\00\00?\00\00\00")
  (elem (i32.const 0x3f) $ALLOT)

  ;; 6.1.0720
  (func $AND
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.and (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 135808) "p\12\02\00\03AND@\00\00\00")
  (elem (i32.const 0x40) $AND)

  ;; 6.1.0750 
  (func $BASE
   (i32.store (global.get $tos) (i32.const BASE_BASE))
   (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 135820) "\80\12\02\00\04BASE\00\00\00A\00\00\00")
  (elem (i32.const 0x41) $BASE)
  
  ;; 6.1.0760 
  (func $BEGIN
    (call $ensureCompiling)
    (call $compileBegin))
  (data (i32.const 135836) "\8c\12\02\00" "\85" (; immediate ;) "BEGIN\00\00" "B\00\00\00")
  (elem (i32.const 0x42) $BEGIN)

  ;; 6.1.0770
  (func $BL (call $push (i32.const 32)))
  (data (i32.const 135852) "\9c\12\02\00\02BL\00C\00\00\00")
  (elem (i32.const 0x43) $BL)

  ;; 6.1.0850
  (func $C!
    (local $bbtos i32)
    (i32.store8 (i32.load (i32.sub (global.get $tos) (i32.const 4)))
                (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))))
    (global.set $tos (local.get $bbtos)))
  (data (i32.const 135864) "\ac\12\02\00\02C!\00D\00\00\00")
  (elem (i32.const 0x44) $C!)

  ;; 6.1.0860
  (func $Cc
    (i32.store8 (global.get $here)
                (i32.load (i32.sub (global.get $tos) (i32.const 4))))
    (global.set $here (i32.add (global.get $here) (i32.const 1)))
    (global.set $tos (i32.sub (global.get $tos) (i32.const 4))))
  (data (i32.const 135876) "\b8\12\02\00\02C,\00E\00\00\00")
  (elem (i32.const 0x45) $Cc)

  ;; 6.1.0870
  (func $C@
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.load8_u (i32.load (local.get $btos)))))
  (data (i32.const 135888) "\c4\12\02\00\02C@\00F\00\00\00")
  (elem (i32.const 0x46) $C@)

  (func $CELL+ 
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.add (i32.load (local.get $btos)) (i32.const 4))))
  (data (i32.const 135900) "\d0\12\02\00\05CELL+\00\00G\00\00\00")
  (elem (i32.const 0x47) $CELL+)

  (func $CELLS 
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.shl (i32.load (local.get $btos)) (i32.const 2))))
  (data (i32.const 135916) "\dc\12\02\00\05CELLS\00\00H\00\00\00")
  (elem (i32.const 0x48) $CELLS)

  ;; 6.1.0895
  (func $CHAR
    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const WORD_BASE))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (i32.store (i32.sub (global.get $tos) (i32.const 4))
               (i32.load8_u (i32.const WORD_BASE_PLUS_1))))
  (data (i32.const 135932) "\ec\12\02\00\04CHAR\00\00\00I\00\00\00")
  (elem (i32.const 0x49) $CHAR)

  (func $CHAR+ (call $1+))
  (data (i32.const 135948) "\fc\12\02\00\05CHAR+\00\00J\00\00\00")
  (elem (i32.const 0x4a) $CHAR+)

  (func $CHARS)
  (data (i32.const 135964) "\0c\13\02\00\05CHARS\00\00K\00\00\00")
  (elem (i32.const 0x4b) $CHARS)

  ;; 6.1.0950
  (func $CONSTANT 
    (call $CREATE)
    (i32.store (i32.sub (global.get $here) (i32.const 4)) (i32.const PUSH_INDIRECT_INDEX))
    (i32.store (global.get $here) (call $pop))
    (global.set $here (i32.add (global.get $here) (i32.const 4))))
  (data (i32.const 135980) "\1c\13\02\00" "\08" "CONSTANT\00\00\00" "L\00\00\00")
  (elem (i32.const CONSTANT_INDEX) $CONSTANT)

  ;; 6.1.0980
  (func $COUNT
    (local $btos i32)
    (local $addr i32)
    (i32.store (global.get $tos)
               (i32.load8_u (tee_local $addr (i32.load (tee_local $btos (i32.sub (global.get $tos) 
                                                                               (i32.const 4)))))))
    (i32.store (local.get $btos) (i32.add (local.get $addr) (i32.const 1)))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136000) ",\13\02\00\05COUNT\00\00M\00\00\00")
  (elem (i32.const 0x4d) $COUNT)

  (func $CR 
    (call $push (i32.const 10)) (call $EMIT))
  (data (i32.const 136016) "@\13\02\00\02CR\00N\00\00\00")
  (elem (i32.const 0x4e) $CR)

  ;; 6.1.1000
  (func $CREATE
    (local $length i32)

    (i32.store (global.get $here) (global.get $latest))
    (global.set $latest (global.get $here))
    (global.set $here (i32.add (global.get $here) (i32.const 4)))

    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const WORD_BASE))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (drop (call $pop))
    (i32.store8 (global.get $here) (tee_local $length (i32.load8_u (i32.const WORD_BASE))))
    (global.set $here (i32.add (global.get $here) (i32.const 1)))

    (call $memcopy (global.get $here) (i32.const WORD_BASE_PLUS_1) (local.get $length))

    (global.set $here (i32.add (global.get $here) (local.get $length)))

    (call $ALIGN)

    (i32.store (global.get $here) (i32.const PUSH_DATA_ADDRESS_INDEX))
    (global.set $here (i32.add (global.get $here) (i32.const 4)))
    (i32.store (global.get $here) (i32.const 0))

    (call $setFlag (i32.const F_DATA)))
  (data (i32.const 136028) "P\13\02\00\06CREATE\00O\00\00\00")
  (elem (i32.const 0x4f) $CREATE)

  (func $DECIMAL 
    (i32.store (i32.const BASE_BASE) (i32.const 10)))
  (data (i32.const 136044) "\5c\13\02\00\07DECIMALP\00\00\00")
  (elem (i32.const 0x50) $DECIMAL)

  ;; 6.1.1200
  (func $DEPTH
   (i32.store (global.get $tos)
              (i32.shr_u (i32.sub (global.get $tos) (i32.const STACK_BASE)) (i32.const 2)))
   (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136060) "l\13\02\00\05DEPTH\00\00Q\00\00\00")
  (elem (i32.const 0x51) $DEPTH)


  ;; 6.1.1240
  (func $DO
    (call $ensureCompiling)
    (call $compileDo))
  (data (i32.const 136076) "|\13\02\00" "\82" (; immediate ;) "DO\00" "R\00\00\00")
  (elem (i32.const 0x52) $DO)

  ;; 6.1.1250
  (func $DOES>
    (call $ensureCompiling)
    (call $emitConst (i32.add (global.get $nextTableIndex) (i32.const 1)))
    (call $emitICall (i32.const 1) (i32.const SET_LATEST_BODY_INDEX))
    (call $endColon)
    (call $startColon (i32.const 1))
    (call $compilePushLocal (i32.const 0)))
  (data (i32.const 136088) "\8c\13\02\00" "\85" (; immediate ;) "DOES>\00\00" "S\00\00\00")
  (elem (i32.const 0x53) $DOES>)

  ;; 6.1.1260
  (func $DROP
    (global.set $tos (i32.sub (global.get $tos) (i32.const 4))))
  (data (i32.const 136104) "\98\13\02\00\04DROP\00\00\00T\00\00\00")
  (elem (i32.const 0x54) $DROP)

  ;; 6.1.1290
  (func $DUP
   (i32.store
    (global.get $tos)
    (i32.load (i32.sub (global.get $tos) (i32.const 4))))
   (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136120) "\a8\13\02\00\03DUPU\00\00\00")
  (elem (i32.const 0x55) $DUP)

  ;; 6.1.1310
  (func $ELSE
    (call $ensureCompiling)
    (call $emitElse))
  (data (i32.const 136132) "\b8\13\02\00" "\84" (; immediate ;) "ELSE\00\00\00" "V\00\00\00")
  (elem (i32.const 0x56) $ELSE)

  ;; 6.1.1320
  (func $EMIT
    (call $shell_emit (i32.load (i32.sub (global.get $tos) (i32.const 4))))
    (global.set $tos (i32.sub (global.get $tos) (i32.const 4))))
  (data (i32.const 136148) "\c4\13\02\00\04EMIT\00\00\00W\00\00\00")
  (elem (i32.const 0x57) $EMIT)

  (func $ENVIRONMENT (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136164) "\d4\13\02\00\0bENVIRONMENTX\00\00\00")
  (elem (i32.const 0x58) $ENVIRONMENT)

  ;; 6.1.1360
  (func $EVALUATE
    (local $bbtos i32)
    (local $prevSourceID i32)
    (local $prevIn i32)
    (local $prevInputBufferBase i32)
    (local $prevInputBufferSize i32)

    ;; Save input state
    (local.set $prevSourceID (global.get $sourceID))
    (local.set $prevIn (i32.load (i32.const IN_BASE)))
    (local.set $prevInputBufferSize (global.get $inputBufferSize))
    (local.set $prevInputBufferBase (global.get $inputBufferBase))

    (global.set $sourceID (i32.const -1))
    (global.set $inputBufferBase (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))))
    (global.set $inputBufferSize (i32.load (i32.sub (global.get $tos) (i32.const 4))))
    (i32.store (i32.const IN_BASE) (i32.const 0))

    (global.set $tos (local.get $bbtos))
    (drop (call $interpret))

    ;; Restore input state
    (global.set $sourceID (local.get $prevSourceID))
    (i32.store (i32.const IN_BASE) (local.get $prevIn))
    (global.set $inputBufferBase (local.get $prevInputBufferBase))
    (global.set $inputBufferSize (local.get $prevInputBufferSize)))
  (data (i32.const 136184) "\e4\13\02\00\08EVALUATE\00\00\00Y\00\00\00")
  (elem (i32.const 0x59) $EVALUATE)

  ;; 6.1.1370
  (func $EXECUTE
    (local $xt i32)
    (local $body i32)
    (local.set $body (call $body (tee_local $xt (call $pop))))
    (if (i32.and (i32.load (i32.add (local.get $xt) (i32.const 4)))
                 (i32.const F_DATA))
      (then
        (call_indirect (type $dataWord) (i32.add (local.get $body) (i32.const 4))
                                        (i32.load (local.get $body))))
      (else
        (call_indirect (type $word) (i32.load (local.get $body))))))
  (data (i32.const 136204) "\f8\13\02\00\07EXECUTEZ\00\00\00")
  (elem (i32.const 0x5a) $EXECUTE)

  ;; 6.1.1380
  (func $EXIT
    (call $ensureCompiling)
    (call $emitReturn))
  (data (i32.const 136220) "\0c\14\02\00" "\84" (; immediate ;) "EXIT\00\00\00" "[\00\00\00")
  (elem (i32.const 0x5b) $EXIT)

  ;; 6.1.1540
  (func $FILL
    (local $bbbtos i32)
    (call $memset (i32.load (tee_local $bbbtos (i32.sub (global.get $tos) (i32.const 12))))
                  (i32.load (i32.sub (global.get $tos) (i32.const 4)))
                  (i32.load (i32.sub (global.get $tos) (i32.const 8))))
    (global.set $tos (local.get $bbbtos)))
  (data (i32.const 136236) "\1c\14\02\00\04FILL\00\00\00\5c\00\00\00")
  (elem (i32.const 0x5c) $FILL)

  ;; 6.1.1550
  (func $FIND
    (local $entryP i32)
    (local $entryNameP i32)
    (local $entryLF i32)
    (local $wordP i32)
    (local $wordStart i32)
    (local $wordLength i32)
    (local $wordEnd i32)

    (local.set $wordLength 
               (i32.load8_u (tee_local $wordStart (i32.load (i32.sub (global.get $tos) 
                                                                  (i32.const 4))))))
    (local.set $wordStart (i32.add (local.get $wordStart) (i32.const 1)))
    (local.set $wordEnd (i32.add (local.get $wordStart) (local.get $wordLength)))

    (local.set $entryP (global.get $latest))
    (block $endLoop
      (loop $loop
        (local.set $entryLF (i32.load (i32.add (local.get $entryP) (i32.const 4))))
        (block $endCompare
          (if (i32.and 
                (i32.eq (i32.and (local.get $entryLF) (i32.const F_HIDDEN)) (i32.const 0))
                (i32.eq (i32.and (local.get $entryLF) (i32.const LENGTH_MASK))
                        (local.get $wordLength)))
            (then
              (local.set $wordP (local.get $wordStart))
              (local.set $entryNameP (i32.add (local.get $entryP) (i32.const 5)))
              (block $endCompareLoop
                (loop $compareLoop
                  (br_if $endCompare (i32.ne (i32.load8_s (local.get $entryNameP))
                                             (i32.load8_s (local.get $wordP))))
                  (local.set $entryNameP (i32.add (local.get $entryNameP) (i32.const 1)))
                  (local.set $wordP (i32.add (local.get $wordP) (i32.const 1)))
                  (br_if $endCompareLoop (i32.eq (local.get $wordP)
                                                 (local.get $wordEnd)))
                  (br $compareLoop)))
              (i32.store (i32.sub (global.get $tos) (i32.const 4))
                         (local.get $entryP))
              (if (i32.eqz (i32.and (local.get $entryLF) (i32.const F_IMMEDIATE)))
                (then
                  (call $push (i32.const -1)))
                (else
                  (call $push (i32.const 1))))
              (return))))
        (local.set $entryP (i32.load (local.get $entryP)))
        (br_if $endLoop (i32.eqz (local.get $entryP)))
        (br $loop)))
    (call $push (i32.const 0)))
  (data (i32.const 136252) ",\14\02\00\04FIND\00\00\00]\00\00\00")
  (elem (i32.const 0x5d) $FIND)

  ;; 6.1.1561
  (func $FM/MOD
    (local $btos i32)
    (local $bbbtos i32)
    (local $n1 i64)
    (local $n2 i32)
    (i32.store (tee_local $bbbtos (i32.sub (global.get $tos) (i32.const 12)))
               (i32.wrap/i64 (i64.rem_s (tee_local $n1 (i64.load (local.get $bbbtos)))
                             (i64.extend_s/i32 (tee_local $n2 (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))))))))
    (i32.store (i32.sub (global.get $tos) (i32.const 8))
               (i32.wrap/i64 (i64.div_s (local.get $n1) (i64.extend_s/i32 (local.get $n2)))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 136268) "<\14\02\00\06FM/MOD\00^\00\00\00")
  (elem (i32.const 0x5e) $FM/MOD)

  ;; 6.1.1650
  (func $HERE
    (i32.store (global.get $tos) (global.get $here))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136284) "L\14\02\00\04HERE\00\00\00_\00\00\00")
  (elem (i32.const 0x5f) $HERE)

  (func $HOLD (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136300) "\5c\14\02\00\04HOLD\00\00\00`\00\00\00")
  (elem (i32.const 0x60) $HOLD)

  ;; 6.1.1680
  (func $I
    (call $ensureCompiling)
    (call $compilePushLocal (i32.sub (global.get $currentLocal) (i32.const 1))))
  (data (i32.const 136316) "l\14\02\00" "\81" (; immediate ;) "I\00\00" "a\00\00\00")
  (elem (i32.const 0x61) $I)

  ;; 6.1.1700
  (func $IF
    (call $ensureCompiling)
    (call $compileIf))
  (data (i32.const 136328) "|\14\02\00" "\82" (; immediate ;) "IF\00" "b\00\00\00")
  (elem (i32.const 0x62) $IF)

  ;; 6.1.1710
  (func $IMMEDIATE
    (call $setFlag (i32.const F_IMMEDIATE)))
  (data (i32.const 136340) "\88\14\02\00\09IMMEDIATE\00\00c\00\00\00")
  (elem (i32.const 0x63) $IMMEDIATE)

  ;; 6.1.1720
  (func $INVERT
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.xor (i32.load (local.get $btos)) (i32.const -1))))
  (data (i32.const 136360) "\94\14\02\00\06INVERT\00d\00\00\00")
  (elem (i32.const 0x64) $INVERT)

  ;; 6.1.1730
  (func $J
    (call $ensureCompiling)
    (call $compilePushLocal (i32.sub (global.get $currentLocal) (i32.const 4))))
  (data (i32.const 136376) "\a8\14\02\00\81J\00\00e\00\00\00")
  (elem (i32.const 0x65) $J) ;; immediate

  ;; 6.1.1750
  (func $KEY
    (i32.store (global.get $tos) (call $shell_key))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136388) "\b8\14\02\00\03KEYf\00\00\00")
  (elem (i32.const 0x66) $KEY)

  ;; 6.1.1760
  (func $LEAVE
    (call $ensureCompiling)
    (call $compileLeave))
  (data (i32.const 136400) "\c4\14\02\00\85LEAVE\00\00g\00\00\00")
  (elem (i32.const 0x67) $LEAVE) ;; immediate


  ;; 6.1.1780
  (func $LITERAL
    (call $ensureCompiling)
    (call $compilePushConst (call $pop)))
  (data (i32.const 136416) "\d0\14\02\00\87LITERALh\00\00\00")
  (elem (i32.const 0x68) $LITERAL) ;; immediate

  ;; 6.1.1800
  (func $LOOP
    (call $ensureCompiling)
    (call $compileLoop))
  (data (i32.const 136432) "\e0\14\02\00\84LOOP\00\00\00i\00\00\00")
  (elem (i32.const 0x69) $LOOP) ;; immediate

  ;; 6.1.1805
  (func $LSHIFT
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.shl (i32.load (local.get $bbtos))
                        (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 136448) "\f0\14\02\00\06LSHIFT\00j\00\00\00")
  (elem (i32.const 0x6a) $LSHIFT)

  ;; 6.1.1810
  (func $M*
    (local $bbtos i32)
    (i64.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i64.mul (i64.extend_s/i32 (i32.load (local.get $bbtos)))
                        (i64.extend_s/i32 (i32.load (i32.sub (global.get $tos) 
                                                             (i32.const 4)))))))
  (data (i32.const 136464) "\00\15\02\00\02M*\00k\00\00\00")
  (elem (i32.const 0x6b) $M*)

  ;; 6.1.1870
  (func $MAX
    (local $btos i32)
    (local $bbtos i32)
    (local $v i32)
    (if (i32.lt_s (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8))))
                  (tee_local $v (i32.load (tee_local $btos (i32.sub (global.get $tos) 
                                                                    (i32.const 4))))))
      (then
        (i32.store (local.get $bbtos) (local.get $v))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 136476) "\10\15\02\00\03MAXl\00\00\00")
  (elem (i32.const 0x6c) $MAX)

  ;; 6.1.1880
  (func $MIN
    (local $btos i32)
    (local $bbtos i32)
    (local $v i32)
    (if (i32.gt_s (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8))))
                  (tee_local $v (i32.load (tee_local $btos (i32.sub (global.get $tos) 
                                                                    (i32.const 4))))))
      (then
        (i32.store (local.get $bbtos) (local.get $v))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 136488) "\1c\15\02\00\03MINm\00\00\00")
  (elem (i32.const 0x6d) $MIN)

  ;; 6.1.1890
  (func $MOD
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.rem_s (i32.load (local.get $bbtos))
                          (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 136500) "(\15\02\00\03MODn\00\00\00")
  (elem (i32.const 0x6e) $MOD)

  ;; 6.1.1900
  (func $MOVE
    (local $bbbtos i32)
    (call $memcopy (i32.load (i32.sub (global.get $tos) (i32.const 8)))
                   (i32.load (tee_local $bbbtos (i32.sub (global.get $tos) (i32.const 12))))
                   (i32.load (i32.sub (global.get $tos) (i32.const 4))))
    (global.set $tos (local.get $bbbtos)))
  (data (i32.const 136512) "4\15\02\00\04MOVE\00\00\00o\00\00\00")
  (elem (i32.const 0x6f) $MOVE)

  ;; 6.1.1910
  (func $NEGATE
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.sub (i32.const 0) (i32.load (local.get $btos)))))
  (data (i32.const 136528) "@\15\02\00\06NEGATE\00p\00\00\00")
  (elem (i32.const 0x70) $NEGATE)

  ;; 6.1.1980
  (func $OR
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.or (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 136544) "P\15\02\00\02OR\00q\00\00\00")
  (elem (i32.const 0x71) $OR)

  ;; 6.1.1990
  (func $OVER
    (i32.store (global.get $tos)
               (i32.load (i32.sub (global.get $tos) (i32.const 8))))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136556) "`\15\02\00\04OVER\00\00\00r\00\00\00")
  (elem (i32.const 0x72) $OVER)

  ;; 6.1.2033
  (func $POSTPONE
    (local $FINDToken i32)
    (local $FINDResult i32)
    (call $ensureCompiling)
    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const WORD_BASE))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (call $FIND)
    (if (i32.eqz (tee_local $FINDResult (call  $pop))) (call $fail (i32.const 0x20000))) ;; undefined word
    (local.set $FINDToken (call $pop))
    (if (i32.eq (local.get $FINDResult) (i32.const 1))
      (then (call $compileCall (local.get $FINDToken)))
      (else
        (call $emitConst (local.get $FINDToken))
        (call $emitICall (i32.const 1) (i32.const COMPILE_CALL_INDEX)))))
  (data (i32.const 136572) "l\15\02\00\88POSTPONE\00\00\00s\00\00\00")
  (elem (i32.const 0x73) $POSTPONE) ;; immediate

  ;; 6.1.2050
  (func $QUIT
    (global.set $tors (i32.const RETURN_STACK_BASE))
    (global.set $sourceID (i32.const 0))
    (unreachable))
  (data (i32.const 136592) "|\15\02\00\04QUIT\00\00\00t\00\00\00")
  (elem (i32.const 0x74) $QUIT)

  ;; 6.1.2060
  (func $R>
    (global.set $tors (i32.sub (global.get $tors) (i32.const 4)))
    (i32.store (global.get $tos) (i32.load (global.get $tors)))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136608) "\90\15\02\00\02R>\00u\00\00\00")
  (elem (i32.const 0x75) $R>)

  ;; 6.1.2070
  (func $R@
    (i32.store (global.get $tos) (i32.load (i32.sub (global.get $tors) (i32.const 4))))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136620) "\a0\15\02\00\02R@\00v\00\00\00")
  (elem (i32.const 0x76) $R@)

  ;; 6.1.2120 
  (func $RECURSE 
    (call $ensureCompiling)
    (call $compileRecurse))
  (data (i32.const 136632) "\ac\15\02\00\87RECURSEw\00\00\00")
  (elem (i32.const 0x77) $RECURSE) ;; immediate


  ;; 6.1.2140
  (func $REPEAT
    (call $ensureCompiling)
    (call $compileRepeat))
  (data (i32.const 136648) "\b8\15\02\00\86REPEAT\00x\00\00\00")
  (elem (i32.const 0x78) $REPEAT) ;; immediate

  ;; 6.1.2160 ROT 
  (func $ROT
    (local $tmp i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $bbbtos i32)
    (local.set $tmp (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))))
    (i32.store (local.get $btos) 
               (i32.load (tee_local $bbbtos (i32.sub (global.get $tos) (i32.const 12)))))
    (i32.store (local.get $bbbtos) 
               (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))))
    (i32.store (local.get $bbtos) 
               (local.get $tmp)))
  (data (i32.const 136664) "\c8\15\02\00\03ROTy\00\00\00")
  (elem (i32.const 0x79) $ROT)

  ;; 6.1.2162
  (func $RSHIFT
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.shr_u (i32.load (local.get $bbtos))
                          (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 136676) "\d8\15\02\00\06RSHIFT\00z\00\00\00")
  (elem (i32.const 0x7a) $RSHIFT)

  ;; 6.1.2165
  (func $Sq
    (local $c i32)
    (local $start i32)
    (call $ensureCompiling)
    (local.set $start (global.get $here))
    (block $endLoop
      (loop $loop
        (if (i32.lt_s (tee_local $c (call $readChar)) (i32.const 0))
          (call $fail (i32.const 0x2003C))) ;; missing closing quote
        (br_if $endLoop (i32.eq (local.get $c) (i32.const 0x22)))
        (i32.store8 (global.get $here) (local.get $c))
        (global.set $here (i32.add (global.get $here) (i32.const 1)))
        (br $loop)))
    (call $compilePushConst (local.get $start))
    (call $compilePushConst (i32.sub (global.get $here) (local.get $start)))
    (call $ALIGN))
  (data (i32.const 136692) "\e4\15\02\00\82S\22\00{\00\00\00")
  (elem (i32.const 0x7b) $Sq) ;; immediate

  ;; 6.1.2170
  (func $S>D
    (local $btos i32)
    (i64.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i64.extend_s/i32 (i32.load (local.get $btos))))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136704) "\f4\15\02\00\03S>D|\00\00\00")
  (elem (i32.const 0x7c) $S>D)

  (func $SIGN (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136716) "\00\16\02\00\04SIGN\00\00\00}\00\00\00")
  (elem (i32.const 0x7d) $SIGN)

  (func $SM/REM (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136732) "\0c\16\02\00\06SM/REM\00~\00\00\00")
  (elem (i32.const 0x7e) $SM/REM)

  ;; 6.1.2216
  (func $SOURCE 
    (call $push (global.get $inputBufferBase))
    (call $push (global.get $inputBufferSize)))
  (data (i32.const 136748) "\1c\16\02\00\06SOURCE\00\7f\00\00\00")
  (elem (i32.const 0x7f) $SOURCE)

  ;; 6.1.2220
  (func $SPACE (call $BL) (call $EMIT))
  (data (i32.const 136764) ",\16\02\00\05SPACE\00\00\80\00\00\00")
  (elem (i32.const 0x80) $SPACE)

  (func $SPACES 
    (local $i i32)
    (local.set $i (call $pop))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.le_s (local.get $i) (i32.const 0)))
        (call $SPACE)
        (local.set $i (i32.sub (local.get $i) (i32.const 1)))
        (br $loop))))
  (data (i32.const 136780) "<\16\02\00\06SPACES\00\81\00\00\00")
  (elem (i32.const 0x81) $SPACES)

  ;; 6.1.2250
  (func $STATE
    (i32.store (global.get $tos) (i32.const STATE_BASE))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 136796) "L\16\02\00\05STATE\00\00\82\00\00\00")
  (elem (i32.const 0x82) $STATE)

  ;; 6.1.2260
  (func $SWAP
    (local $btos i32)
    (local $bbtos i32)
    (local $tmp i32)
    (local.set $tmp (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))))
    (i32.store (local.get $bbtos) 
               (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))))
    (i32.store (local.get $btos) (local.get $tmp)))
  (data (i32.const 136812) "\5c\16\02\00\04SWAP\00\00\00\83\00\00\00")
  (elem (i32.const 0x83) $SWAP)

  ;; 6.1.2270
  (func $THEN
    (call $ensureCompiling)
    (call $compileThen))
  (data (i32.const 136828) "l\16\02\00\84THEN\00\00\00\84\00\00\00")
  (elem (i32.const 0x84) $THEN) ;; immediate

  ;; 6.1.2310 TYPE 
  (func $TYPE
    (local $p i32)
    (local $end i32)
    (local.set $end (i32.add (call $pop) (tee_local $p (call $pop))))
    (block $endLoop
     (loop $loop
       (br_if $endLoop (i32.eq (local.get $p) (local.get $end)))
       (call $shell_emit (i32.load8_u (local.get $p)))
       (local.set $p (i32.add (local.get $p) (i32.const 1)))
       (br $loop))))
  ;; WARNING: If you change this table index, make sure the emitted ICalls are also updated
  (data (i32.const 136844) "|\16\02\00\04TYPE\00\00\00\85\00\00\00")
  (elem (i32.const 0x85) $TYPE) ;; none

  (func $U.
    (call $U._ (call $pop) (i32.load (i32.const BASE_BASE)))
    (call $shell_emit (i32.const 0x20)))
  (data (i32.const 136860) "\8c\16\02\00\02U.\00\86\00\00\00")
  (elem (i32.const 0x86) $U.)

  ;; 6.1.2340
  (func $U<
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_u (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8))))
                  (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 136872) "\9c\16\02\00\02U<\00\87\00\00\00")
  (elem (i32.const 0x87) $U<)

  ;; 6.1.2360
  (func $UM*
    (local $bbtos i32)
    (i64.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i64.mul (i64.extend_u/i32 (i32.load (local.get $bbtos)))
                        (i64.extend_u/i32 (i32.load (i32.sub (global.get $tos) 
                                                             (i32.const 4)))))))
  (data (i32.const 136884) "\a8\16\02\00\03UM*\88\00\00\00")
  (elem (i32.const 0x88) $UM*)

  (func $UM/MOD (call $fail (i32.const 0x20084))) ;; not implemented
  (data (i32.const 136896) "\b4\16\02\00\06UM/MOD\00\89\00\00\00")
  (elem (i32.const 0x89) $UM/MOD) ;; TODO: Rename

  ;; 6.1.2380
  (func $UNLOOP
    (call $ensureCompiling))
  (data (i32.const 136912) "\c0\16\02\00\86UNLOOP\00\8a\00\00\00")
  (elem (i32.const 0x8a) $UNLOOP) ;; immediate

  ;; 6.1.2390
  (func $UNTIL
    (call $ensureCompiling)
    (call $compileUntil))
  (data (i32.const 136928) "\d0\16\02\00\85UNTIL\00\00\8b\00\00\00")
  (elem (i32.const 0x8b) $UNTIL) ;; immediate

  ;; 6.1.2410
  (func $VARIABLE
    (call $CREATE)
    (global.set $here (i32.add (global.get $here) (i32.const 4))))
  (data (i32.const 136944) "\e0\16\02\00\08VARIABLE\00\00\00\8c\00\00\00")
  (elem (i32.const 0x8c) $VARIABLE)

  ;; 6.1.2430
  (func $WHILE
    (call $ensureCompiling)
    (call $compileWhile))
  (data (i32.const 136964) "\f0\16\02\00\85WHILE\00\00\8d\00\00\00")
  (elem (i32.const 0x8d) $WHILE) ;; immediate

  ;; 6.1.2450
  (func $WORD
    (call $readWord (call $pop)))
  (data (i32.const 136980) "\04\17\02\00\04WORD\00\00\00\8e\00\00\00")
  (elem (i32.const 0x8e) $WORD)

  ;; 6.1.2490
  (func $XOR
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8)))
               (i32.xor (i32.load (tee_local $btos (i32.sub (global.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (global.set $tos (local.get $btos)))
  (data (i32.const 136996) "\14\17\02\00\03XOR\8f\00\00\00")
  (elem (i32.const 0x8f) $XOR)

  ;; 6.1.2500
  (func $left-bracket
    (call $ensureCompiling)
    (i32.store (i32.const STATE_BASE) (i32.const 0)))
  (data (i32.const 137008) "$\17\02\00\81[\00\00\90\00\00\00")
  (elem (i32.const 0x90) $left-bracket) ;; immediate

  ;; 6.1.2510
  (func $bracket-tick
    (call $ensureCompiling)
    (call $')
    (call $compilePushConst (call $pop)))
  (data (i32.const 137020) "0\17\02\00\83[']\91\00\00\00")
  (elem (i32.const 0x91) $bracket-tick) ;; immediate

  ;; 6.1.2520
  (func $bracket-char
    (call $ensureCompiling)
    (call $CHAR)
    (call $compilePushConst (call $pop)))
  (data (i32.const 137032) "<\17\02\00\86[CHAR]\00\92\00\00\00")
  (elem (i32.const 0x92) $bracket-char) ;; immediate

  ;; 6.1.2540
  (func $right-bracket
    (i32.store (i32.const STATE_BASE) (i32.const 1)))
  (data (i32.const 137048) "H\17\02\00\01]\00\00\93\00\00\00")
  (elem (i32.const 0x93) $right-bracket)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; 6.2.0280
  (func $0>
    (local $btos i32)
    (if (i32.gt_s (i32.load (tee_local $btos (i32.sub (global.get $tos) 
                                                     (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (local.get $btos) (i32.const -1)))
      (else (i32.store (local.get $btos) (i32.const 0)))))
  (data (i32.const 137060) "X\17\02\00\020>\00\94\00\00\00")
  (elem (i32.const 0x94) $0>)

  ;; 6.2.1350
  (func $ERASE
    (local $bbtos i32)
    (call $memset (i32.load (tee_local $bbtos (i32.sub (global.get $tos) (i32.const 8))))
                  (i32.const 0)
                  (i32.load (i32.sub (global.get $tos) (i32.const 4))))
    (global.set $tos (local.get $bbtos)))
  (data (i32.const 137072) "d\17\02\00\05ERASE\00\00\95\00\00\00")
  (elem (i32.const 0x95) $ERASE)

  ;; 6.2.2030
  (func $PICK
    (local $btos i32)
    (i32.store (tee_local $btos (i32.sub (global.get $tos) (i32.const 4)))
               (i32.load (i32.sub (global.get $tos) 
                                  (i32.shl (i32.add (i32.load (local.get $btos))
                                                    (i32.const 2))
                                           (i32.const 2))))))
  (data (i32.const 137088) "p\17\02\00\04PICK\00\00\00\96\00\00\00")
  (elem (i32.const 0x96) $PICK)

  ;; 6.2.2125
  (func $REFILL
    (local $char i32)
    (global.set $inputBufferSize (i32.const 0))
    (if (i32.eq (global.get $sourceID) (i32.const -1))
      (then
        (call $push (i32.const -1))
        (return)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eq (tee_local $char (call $shell_getc)) (i32.const -1)))
        (i32.store8 (i32.add (i32.const INPUT_BUFFER_BASE) (global.get $inputBufferSize)) 
                   (local.get $char))
        (global.set $inputBufferSize (i32.add (global.get $inputBufferSize) (i32.const 1)))
        (br $loop)))
    (if (i32.eqz (global.get $inputBufferSize))
      (then (call $push (i32.const 0)))
      (else 
        (i32.store (i32.const IN_BASE) (i32.const 0))
        (call $push (i32.const -1)))))
  (data (i32.const 137104) "\80\17\02\00\06REFILL\00\97\00\00\00")
  (elem (i32.const 0x97) $REFILL)

  ;; 6.2.2295
  (func $TO
    (call $readWord (i32.const 0x20))
    (if (i32.eqz (i32.load8_u (i32.const WORD_BASE))) (call $fail (i32.const 0x20028))) ;; incomplete input
    (call $FIND)
    (if (i32.eqz (call $pop)) (call $fail (i32.const 0x20000))) ;; undefined word
    (i32.store (i32.add (call $body (call $pop)) (i32.const 4)) (call $pop)))
  (data (i32.const 137120) "\90\17\02\00\02TO\00\98\00\00\00")
  (elem (i32.const 0x98) $TO)

  ;; 6.1.2395
  (func $UNUSED
    (call $push (i32.shr_s (i32.sub (i32.const MEMORY_SIZE) (global.get $here)) (i32.const 2))))
  (data (i32.const 137132) "\a0\17\02\00\06UNUSED\00\99\00\00\00")
  (elem (i32.const 0x99) $UNUSED)

  ;; 6.2.2535
  (func $\
    (local $char i32)
    (block $endSkipComments
      (loop $skipComments
        (local.set $char (call $readChar))
        (br_if $endSkipComments (i32.eq (local.get $char) 
                                        (i32.const 0x0a (; '\n' ;))))
        (br_if $endSkipComments (i32.eq (local.get $char) (i32.const -1)))
        (br $skipComments))))
  (data (i32.const 137148) "\ac\17\02\00\81\5c\00\00\9a\00\00\00")
  (elem (i32.const 0x9a) $\) ;; immediate

  ;; 6.1.2250
  (func $SOURCE-ID
    (call $push (global.get $sourceID)))
  (data (i32.const 137160) "\bc\17\02\00\09SOURCE-ID\00\00\9b\00\00\00")
  (elem (i32.const 0x9b) $SOURCE-ID)

  (func $DSP@
    (i32.store
     (global.get $tos)
     (global.get $tos))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 137180) "\c8\17\02\00\04DSP@\00\00\00\9c\00\00\00")
  (elem (i32.const 0x9c) $DSP@)

  (func $S0
    (call $push (i32.const STACK_BASE)))
  (data (i32.const 137196) "\dc\17\02\00\02S0\00\9d\00\00\00")
  (elem (i32.const 0x9d) $S0)

  (func $LATEST
    (i32.store (global.get $tos) (global.get $latest))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (data (i32.const 137208) "\ec\17\02\00\06LATEST\00\9e\00\00\00")
  (elem (i32.const 0x9e) $LATEST)

  (func $HEX
    (i32.store (i32.const BASE_BASE) (i32.const 16)))
  (data (i32.const 0x21820) "\08\18\02\00\03HEX\a0\00\00\00")
  (elem (i32.const 0xa0) $HEX)

  ;; 6.2.2298
  (func $TRUE
    (call $push (i32.const 0xffffffff)))
  (data (i32.const 0x2182c) "\20\18\02\00" "\04" "TRUE000" "\a1\00\00\00")
  (elem (i32.const 0xa1) $TRUE)

  ;; 6.2.1485
  (func $FALSE
    (call $push (i32.const 0x0)))
  (data (i32.const 0x2183c) "\2c\18\02\00" "\05" "FALSE00" "\a2\00\00\00")
  (elem (i32.const 0xa2) $FALSE)

  ;; 6.2.1930
  (func $NIP
    (call $SWAP) (call $DROP))
  (data (i32.const 0x2184c) "\3c\18\02\00" "\03" "NIP" "\a3\00\00\00")
  (elem (i32.const 0xa3) $NIP)

  ;; 6.2.2300
  (func $TUCK
    (call $SWAP) (call $OVER))
  (data (i32.const 0x21858) "\4c\18\02\00" "\03" "NIP" "\a4\00\00\00")
  (elem (i32.const 0xa4) $TUCK)

  (func $UWIDTH
    (local $v i32)
    (local $r i32)
    (local $base i32)
    (local.set $v (call $pop))
    (local.set $base (i32.load (i32.const BASE_BASE)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eqz (local.get $v)))
        (local.set $r (i32.add (local.get $r) (i32.const 1)))
        (local.set $v (i32.div_s (local.get $v) (local.get $base)))
        (br $loop)))
    (call $push (local.get $r)))
  (data (i32.const 0x21864) "\58\18\02\00" "\06" "UWIDTH0" "\a5\00\00\00")
  (elem (i32.const 0xa5) $UWIDTH)

  ;; 6.2.2405
  (data (i32.const 0x21874) "\64\18\02\00" "\05" "VALUE00" "\4c\00\00\00") ;; CONSTANT_INDEX

  ;; 6.1.0180
  (func $.
    (local $v i32)
    (local.set $v (call $pop))
    (if (i32.lt_s (local.get $v) (i32.const 0))
      (then
        (call $shell_emit (i32.const 0x2d))
        (local.set $v (i32.sub (i32.const 0) (local.get $v)))))
    (call $U._ (local.get $v) (i32.load (i32.const BASE_BASE)))
    (call $shell_emit (i32.const 0x20)))
  (data (i32.const 0x21884) "\74\18\02\00" "\01" ".00" "\a6\00\00\00")
  (elem (i32.const 0xa6) $.)

  (func $U._ (param $v i32) (param $base i32)
    (local $m i32)
    (local.set $m (i32.rem_u (local.get $v) (local.get $base)))
    (local.set $v (i32.div_u (local.get $v) (local.get $base)))
    (if (i32.eqz (local.get $v))
      (then)
      (else (call $U._ (local.get $v) (local.get $base))))
    (if (i32.ge_u (local.get $m) (i32.const 10))
      (then
        (call $shell_emit (i32.add (local.get $m) (i32.const 0x37))))
      (else
        (call $shell_emit (i32.add (local.get $m) (i32.const 0x30))))))

  
  ;; Initializes compilation.
  ;; Parameter indicates the type of code we're compiling: type 0 (no params), 
  ;; or type 1 (1 param)
  (func $startColon (param $params i32)
    (i32.store8 (i32.const MODULE_HEADER_FUNCTION_TYPE_BASE) (local.get $params))
    (global.set $cp (i32.const MODULE_BODY_BASE))
    (global.set $currentLocal (i32.add (i32.const -1) (local.get $params)))
    (global.set $lastLocal (i32.add (i32.const -1) (local.get $params)))
    (global.set $branchNesting (i32.const -1)))

  (func $endColon
    (local $bodySize i32)
    (local $nameLength i32)

    (call $emitEnd)

    ;; Update code size
    (local.set $bodySize (i32.sub (global.get $cp) (i32.const MODULE_HEADER_BASE))) 
    (i32.store 
      (i32.const MODULE_HEADER_CODE_SIZE_BASE)
      (call $leb128-4p
         (i32.sub (local.get $bodySize) 
                  (i32.const MODULE_HEADER_CODE_SIZE_OFFSET_PLUS_4))))

    ;; Update body size
    (i32.store 
      (i32.const MODULE_HEADER_BODY_SIZE_BASE)
      (call $leb128-4p
         (i32.sub (local.get $bodySize) 
                  (i32.const MODULE_HEADER_BODY_SIZE_OFFSET_PLUS_4))))

    ;; Update #locals
    (i32.store 
      (i32.const MODULE_HEADER_LOCAL_COUNT_BASE)
      (call $leb128-4p (i32.add (global.get $lastLocal) (i32.const 1))))

    ;; Update table offset
    (i32.store 
      (i32.const MODULE_HEADER_TABLE_INDEX_BASE)
      (call $leb128-4p (global.get $nextTableIndex)))
    ;; Also store the initial table size to satisfy other tools (e.g. wasm-as)
    (i32.store 
      (i32.const MODULE_HEADER_TABLE_INITIAL_SIZE_BASE)
      (call $leb128-4p (i32.add (global.get $nextTableIndex) (i32.const 1))))

    ;; Write a name section (if we're ending the code for the current dictionary entry)
    (if (i32.eq (i32.load (call $body (global.get $latest)))
                (global.get $nextTableIndex))
      (then
        (local.set $nameLength (i32.and (i32.load8_u (i32.add (global.get $latest) (i32.const 4)))
                                        (i32.const LENGTH_MASK)))
        (i32.store8 (global.get $cp) (i32.const 0))
        (i32.store8 (i32.add (global.get $cp) (i32.const 1)) 
                    (i32.add (i32.const 13) (i32.mul (i32.const 2) (local.get $nameLength))))
        (i32.store8 (i32.add (global.get $cp) (i32.const 2)) (i32.const 0x04))
        (i32.store8 (i32.add (global.get $cp) (i32.const 3)) (i32.const 0x6e))
        (i32.store8 (i32.add (global.get $cp) (i32.const 4)) (i32.const 0x61))
        (i32.store8 (i32.add (global.get $cp) (i32.const 5)) (i32.const 0x6d))
        (i32.store8 (i32.add (global.get $cp) (i32.const 6)) (i32.const 0x65))
        (global.set $cp (i32.add (global.get $cp) (i32.const 7)))

        (i32.store8 (global.get $cp) (i32.const 0x00))
        (i32.store8 (i32.add (global.get $cp) (i32.const 1)) 
                    (i32.add (i32.const 1) (local.get $nameLength)))
        (i32.store8 (i32.add (global.get $cp) (i32.const 2)) (local.get $nameLength)) 
        (global.set $cp (i32.add (global.get $cp) (i32.const 3)))
        (call $memcopy (global.get $cp)
                      (i32.add (global.get $latest) (i32.const 5))
                      (local.get $nameLength))
        (global.set $cp (i32.add (global.get $cp) (local.get $nameLength)))

        (i32.store8 (global.get $cp) (i32.const 0x01))
        (i32.store8 (i32.add (global.get $cp) (i32.const 1)) 
                    (i32.add (i32.const 3) (local.get $nameLength)))
        (i32.store8 (i32.add (global.get $cp) (i32.const 2)) (i32.const 0x01))
        (i32.store8 (i32.add (global.get $cp) (i32.const 3)) (i32.const 0x00))
        (i32.store8 (i32.add (global.get $cp) (i32.const 4)) (local.get $nameLength))
        (global.set $cp (i32.add (global.get $cp) (i32.const 5)))
        (call $memcopy (global.get $cp)
                      (i32.add (global.get $latest) (i32.const 5))
                      (local.get $nameLength))
        (global.set $cp (i32.add (global.get $cp) (local.get $nameLength)))))

    ;; Load the code
    (call $shell_load (i32.const MODULE_HEADER_BASE) 
                      (i32.sub (global.get $cp) (i32.const MODULE_HEADER_BASE))
                      (global.get $nextTableIndex))

    (global.set $nextTableIndex (i32.add (global.get $nextTableIndex) (i32.const 1))))


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

    (if (i32.eqz (tee_local $length (i32.load8_u (i32.const WORD_BASE))))
      (return (i32.const -1)))

    (local.set $p (i32.const WORD_BASE_PLUS_1))
    (local.set $end (i32.add (i32.const WORD_BASE_PLUS_1) (local.get $length)))
    (local.set $base (i32.load (i32.const BASE_BASE)))

    ;; Read first character
    (if (i32.eq (tee_local $char (i32.load8_u (i32.const WORD_BASE_PLUS_1)))
                (i32.const 0x2d (; '-' ;)))
      (then 
        (local.set $sign (i32.const -1))
        (local.set $char (i32.const 48 (; '0' ;) )))
      (else 
        (local.set $sign (i32.const 1))))

    ;; Read all characters
    (local.set $value (i32.const 0))
    (block $endLoop
      (loop $loop
        (if (i32.lt_s (local.get $char) (i32.const 48 (; '0' ;) ))
          (return (i32.const -1)))

        (if (i32.le_s (local.get $char) (i32.const 57 (; '9' ;) ))
          (then
            (local.set $n (i32.sub (local.get $char) (i32.const 48))))
          (else
            (if (i32.lt_s (local.get $char) (i32.const 65 (; 'A' ;) ))
              (return (i32.const -1)))
            (local.set $n (i32.sub (local.get $char) (i32.const 55)))
            (if (i32.ge_s (local.get $n) (local.get $base))
              (return (i32.const -1)))))

        (local.set $value (i32.add (i32.mul (local.get $value) (local.get $base))
                                   (local.get $n)))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br_if $endLoop (i32.eq (local.get $p) (local.get $end)))
        (local.set $char (i32.load8_s (local.get $p)))
        (br $loop)))
    (call $push (i32.mul (local.get $sign) (local.get $value)))
    (return (i32.const 0)))

  (func $fail (param $str i32)
    (call $push (local.get $str))
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
    (local $FINDResult i32)
    (local $FINDToken i32)
    (local $error i32)
    (local.set $error (i32.const 0))
    (global.set $tors (i32.const RETURN_STACK_BASE))
    (block $endLoop
      (loop $loop
        (call $readWord (i32.const 0x20))
        (br_if $endLoop (i32.eqz (i32.load8_u (i32.const WORD_BASE))))
        (call $FIND)
        (local.set $FINDResult (call $pop))
        (local.set $FINDToken (call $pop))
        (if (i32.eqz (local.get $FINDResult))
          (then ;; Not in the dictionary. Is it a number?
            (if (i32.eqz (call $number))
              (then ;; It's a number. Are we compiling?
                (if (i32.ne (i32.load (i32.const STATE_BASE)) (i32.const 0))
                  (then
                    ;; We're compiling. Pop it off the stack and 
                    ;; add it to the compiled list
                    (call $compilePushConst (call $pop)))))
                  ;; We're not compiling. Leave the number on the stack.
              (else ;; It's not a number.
                (call $fail (i32.const 0x20000))))) ;; undefined word
          (else ;; Found the word. 
            ;; Are we compiling or is it immediate?
            (if (i32.or (i32.eqz (i32.load (i32.const STATE_BASE)))
                        (i32.eq (local.get $FINDResult) (i32.const 1)))
              (then
                (call $push (local.get $FINDToken))
                (call $EXECUTE))
              (else
                ;; We're compiling a non-immediate
                (call $compileCall (local.get $FINDToken))))))
          (br $loop)))
    ;; 'WORD' left the address on the stack
    (drop (call $pop))
    (return (i32.load (i32.const STATE_BASE))))

  (func $readWord (param $delimiter i32)
    (local $char i32)
    (local $stringPtr i32)

    ;; Skip leading delimiters
    (block $endSkipBlanks
      (loop $skipBlanks
        (local.set $char (call $readChar))
        (br_if $skipBlanks (i32.eq (local.get $char) (local.get $delimiter)))
        (br_if $skipBlanks (i32.eq (local.get $char) (i32.const 0x0a (; ' ' ;))))
        (br $endSkipBlanks)))

    (local.set $stringPtr (i32.const WORD_BASE_PLUS_1))
    (if (i32.ne (local.get $char) (i32.const -1)) 
      (if (i32.ne (local.get $char) (i32.const 0x0a))
        (then 
          ;; Search for delimiter
          (i32.store8 (i32.const WORD_BASE_PLUS_1) (local.get $char))
          (local.set $stringPtr (i32.const WORD_BASE_PLUS_2))
          (block $endReadChars
            (loop $readChars
              (local.set $char (call $readChar))
              (br_if $endReadChars (i32.eq (local.get $char) (local.get $delimiter)))
              (br_if $endReadChars (i32.eq (local.get $char) (i32.const 0x0a (; ' ' ;))))
              (br_if $endReadChars (i32.eq (local.get $char) (i32.const -1)))
              (i32.store8 (local.get $stringPtr) (local.get $char))
              (local.set $stringPtr (i32.add (local.get $stringPtr) (i32.const 0x1)))
              (br $readChars))))))

     ;; Write word length
     (i32.store8 (i32.const WORD_BASE) 
       (i32.sub (local.get $stringPtr) (i32.const WORD_BASE_PLUS_1)))
     
     (call $push (i32.const WORD_BASE)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Compiler functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $compilePushConst (param $n i32)
    (call $emitConst (local.get $n))
    (call $emitICall (i32.const 1) (i32.const PUSH_INDEX)))

  (func $compilePushLocal (param $n i32)
    (call $emitGetLocal (local.get $n))
    (call $emitICall (i32.const 1) (i32.const PUSH_INDEX)))

  (func $compileIf
    (call $compilePop)
    (call $emitConst (i32.const 0))

    ;; ne
    (i32.store8 (global.get $cp) (i32.const 0x47))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))

    ;; if (empty block)
    (call $emitIf)

    (global.set $branchNesting (i32.add (global.get $branchNesting) (i32.const 1))))

  (func $compileThen 
    (global.set $branchNesting (i32.sub (global.get $branchNesting) (i32.const 1)))
    (call $emitEnd))

  (func $compileDo
    (global.set $currentLocal (i32.add (global.get $currentLocal) (i32.const 3)))
    (if (i32.gt_s (global.get $currentLocal) (global.get $lastLocal))
      (then
        (global.set $lastLocal (global.get $currentLocal))))

    ;; Save branch nesting
    (i32.store (global.get $tors) (global.get $branchNesting))
    (global.set $tors (i32.add (global.get $tors) (i32.const 4)))
    (global.set $branchNesting (i32.const 0))

    (call $compilePop)
    (call $emitSetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $compilePop)
    (call $emitSetLocal (global.get $currentLocal))

    (call $emitGetLocal (global.get $currentLocal))
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitGreaterEqualSigned)
    (call $emitSetLocal (i32.sub (global.get $currentLocal) (i32.const 2)))

    (call $emitBlock)
    (call $emitLoop))
  
  (func $compileLoop 
    (call $emitConst (i32.const 1))
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitAdd)
    (call $emitSetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))

    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitGetLocal (global.get $currentLocal))
    (call $emitGreaterEqualSigned)
    (call $emitBrIf (i32.const 1))
    (call $compileLoopEnd))

  (func $compilePlusLoop 
    (call $compilePop)
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitAdd)
    (call $emitSetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))

    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 2)))
    (call $emitEqualsZero)
    (call $emitIf)
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitGetLocal (global.get $currentLocal))
    (call $emitLesserSigned)
    (call $emitBrIf (i32.const 2))
    (call $emitElse)
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitGetLocal (global.get $currentLocal))
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
    (global.set $currentLocal (i32.sub (global.get $currentLocal) (i32.const 3)))

    ;; Restore branch nesting
    (global.set $branchNesting (i32.load (tee_local $btors (i32.sub (global.get $tors) (i32.const 4)))))
    (global.set $tors (local.get $btors)))


  (func $compileLeave
    (call $emitBr (i32.add (global.get $branchNesting) (i32.const 1))))

  (func $compileBegin
    (call $emitBlock)
    (call $emitLoop)
    (global.set $branchNesting (i32.add (global.get $branchNesting) (i32.const 2))))

  (func $compileWhile
    (call $compilePop)
    (call $emitEqualsZero)
    (call $emitBrIf (i32.const 1)))

  (func $compileRepeat
    (call $emitBr (i32.const 0))
    (call $emitEnd)
    (call $emitEnd)
    (global.set $branchNesting (i32.sub (global.get $branchNesting) (i32.const 2))))

  (func $compileUntil
    (call $compilePop)
    (call $emitEqualsZero)
    (call $emitBrIf (i32.const 0))
    (call $emitBr (i32.const 1))
    (call $emitEnd)
    (call $emitEnd)
    (global.set $branchNesting (i32.sub (global.get $branchNesting) (i32.const 2))))

  (func $compileRecurse
    ;; call 0
    (i32.store8 (global.get $cp) (i32.const 0x10))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x00))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $compilePop
    (call $emitICall (i32.const 2) (i32.const POP_INDEX)))


  (func $compileCall (param $FINDToken i32)
    (local $body i32)
    (local.set $body (call $body (local.get $FINDToken)))
    (if (i32.and (i32.load (i32.add (local.get $FINDToken) (i32.const 4)))
                 (i32.const F_DATA))
      (then
        (call $emitConst (i32.add (local.get $body) (i32.const 4)))
        (call $emitICall (i32.const 1) (i32.load (local.get $body))))
      (else
        (call $emitICall (i32.const 0) (i32.load (local.get $body))))))
  (elem (i32.const COMPILE_CALL_INDEX) $compileCall)

  (func $emitICall (param $type i32) (param $n i32)
    (call $emitConst (local.get $n))

    (i32.store8 (global.get $cp) (i32.const 0x11))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (local.get $type))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x00))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitBlock
    (i32.store8 (global.get $cp) (i32.const 0x02))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x40))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitLoop
    (i32.store8 (global.get $cp) (i32.const 0x03))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x40))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitConst (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x41))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $cp (call $leb128 (global.get $cp) (local.get $n))))

  (func $emitIf
    (i32.store8 (global.get $cp) (i32.const 0x04))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x40))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitElse
    (i32.store8 (global.get $cp) (i32.const 0x05))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitEnd
    (i32.store8 (global.get $cp) (i32.const 0x0b))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitBr (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x0c))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (local.get $n))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitBrIf (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x0d))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (local.get $n))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitSetLocal (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x21))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $cp (call $leb128 (global.get $cp) (local.get $n))))

  (func $emitGetLocal (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x20))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $cp (call $leb128 (global.get $cp) (local.get $n))))

  (func $emitAdd
    (i32.store8 (global.get $cp) (i32.const 0x6a))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitEqualsZero
    (i32.store8 (global.get $cp) (i32.const 0x45))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitGreaterEqualSigned
    (i32.store8 (global.get $cp) (i32.const 0x4e))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitLesserSigned
    (i32.store8 (global.get $cp) (i32.const 0x48))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitReturn
    (i32.store8 (global.get $cp) (i32.const 0x0f))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Word helper function
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $push (export "push") (param $v i32)
    (i32.store (global.get $tos) (local.get $v))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4))))
  (elem (i32.const PUSH_INDEX) $push)

  (func $pop (export "pop") (result i32)
    (global.set $tos (i32.sub (global.get $tos) (i32.const 4)))
    (i32.load (global.get $tos)))
  (elem (i32.const POP_INDEX) $pop)

  (func $pushDataAddress (param $d i32)
    (call $push (local.get $d)))
  (elem (i32.const PUSH_DATA_ADDRESS_INDEX) $pushDataAddress)

  (func $setLatestBody (param $v i32)
    (i32.store (call $body (global.get $latest)) (local.get $v)))
  (elem (i32.const SET_LATEST_BODY_INDEX) $setLatestBody)

  (func $pushIndirect (param $v i32)
    (call $push (i32.load (local.get $v))))
  (elem (i32.const PUSH_INDIRECT_INDEX) $pushIndirect)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Helper functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $setFlag (param $v i32)
    (i32.store 
      (i32.add (global.get $latest) (i32.const 4))
      (i32.or 
        (i32.load (i32.add (global.get $latest) (i32.const 4)))
        (local.get $v))))

  (func $ensureCompiling
    (if (i32.eqz (i32.load (i32.const STATE_BASE)))
      (call $fail (i32.const 0x2005C)))) ;; word not interpretable

  ;; Toggle the hidden flag
  (func $hidden
    (i32.store 
      (i32.add (global.get $latest) (i32.const 4))
      (i32.xor 
        (i32.load (i32.add (global.get $latest) (i32.const 4)))
        (i32.const F_HIDDEN))))

  (func $memcopy (param $dst i32) (param $src i32) (param $n i32)
    (local $end i32)
    (if (i32.gt_u (local.get $dst) (local.get $src))
      (then
        (local.set $end (local.get $src))
        (local.set $src (i32.sub (i32.add (local.get $src) (local.get $n)) (i32.const 1)))
        (local.set $dst (i32.sub (i32.add (local.get $dst) (local.get $n)) (i32.const 1)))
        (block $endLoop
        (loop $loop
          (br_if $endLoop (i32.lt_u (local.get $src) (local.get $end)))
          (i32.store8 (local.get $dst) (i32.load8_u (local.get $src)))
          (local.set $src (i32.sub (local.get $src) (i32.const 1)))
          (local.set $dst (i32.sub (local.get $dst) (i32.const 1)))
          (br $loop))))
      (else
        (local.set $end (i32.add (local.get $src) (local.get $n)))
        (block $endLoop
          (loop $loop
            (br_if $endLoop (i32.eq (local.get $src) (local.get $end)))
            (i32.store8 (local.get $dst) (i32.load8_u (local.get $src)))
            (local.set $src (i32.add (local.get $src) (i32.const 1)))
            (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
            (br $loop))))))

   (func $memset (param $dst i32) (param $c i32) (param $n i32)
    (local $end i32)
    (local.set $end (i32.add (local.get $dst) (local.get $n)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eq (local.get $dst) (local.get $end)))
        (i32.store8 (local.get $dst) (local.get $c))
        (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
        (br $loop))))

  ;; LEB128 with fixed 4 bytes (with padding bytes)
  ;; This means we can only represent 28 bits, which should be plenty.
  (func $leb128-4p (export "leb128_4p") (param $n i32) (result i32)
    (i32.or
      (i32.or 
        (i32.or
          (i32.or
            (i32.and (local.get $n) (i32.const 0x7F))
            (i32.shl
              (i32.and
                (local.get $n)
                (i32.const 0x3F80))
              (i32.const 1)))
          (i32.shl
            (i32.and
              (local.get $n)
              (i32.const 0x1FC000))
            (i32.const 2)))
        (i32.shl
          (i32.and
            (local.get $n)
            (i32.const 0xFE00000))
          (i32.const 3)))
      (i32.const 0x808080)))

  ;; Encodes `value` as leb128 to `p`, and returns the address pointing after the data
  (func $leb128 (export "leb128") (param $p i32) (param $value i32) (result i32)
    (local $more i32)
    (local $byte i32)
    (local.set $more (i32.const 1))
    (block $endLoop
      (loop $loop
        (local.set $byte (i32.and (i32.const 0x7F) (local.get $value)))
        (local.set $value (i32.shr_s (local.get $value) (i32.const 7)))
        (if (i32.or (i32.and (i32.eqz (local.get $value)) 
                             (i32.eq (i32.and (local.get $byte) (i32.const 0x40))
                                     (i32.const 0)))
                    (i32.and (i32.eq (local.get $value) (i32.const -1))
                             (i32.eq (i32.and (local.get $byte) (i32.const 0x40))
                                     (i32.const 0x40))))
          (then
            (local.set $more (i32.const 0)))
          (else
            (local.set $byte (i32.or (local.get $byte) (i32.const 0x80)))))
        (i32.store8 (local.get $p) (local.get $byte))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br_if $loop (local.get $more))
        (br $endLoop)))
    (local.get $p))

  (func $body (param $xt i32) (result i32)
    (i32.and
      (i32.add
        (i32.add 
          (local.get $xt)
          (i32.and
            (i32.load8_u (i32.add (local.get $xt) (i32.const 4)))
            (i32.const LENGTH_MASK)))
        (i32.const 8 (; 4 + 1 + 3 ;)))
      (i32.const -4)))

  (func $readChar (result i32)
    (local $n i32)
    (local $in i32)
    (loop $loop
      (if (i32.ge_u (tee_local $in (i32.load (i32.const IN_BASE)))
                    (global.get $inputBufferSize))
        (then
          (return (i32.const -1)))
        (else
          (local.set $n (i32.load8_s (i32.add (global.get $inputBufferBase) (local.get $in))))
          (i32.store (i32.const IN_BASE) (i32.add (local.get $in) (i32.const 1)))
          (return (local.get $n)))))
    (unreachable))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; A sieve with direct calls. Only here for benchmarking
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $sieve_prime
    (call $HERE) (call $+) 
    (call $C@) (call $0=))

  (func $sieve_composite
    (call $HERE)
    (call $+)
    (i32.store (global.get $tos) (i32.const 1))
    (global.set $tos (i32.add (global.get $tos) (i32.const 4)))
    (call $SWAP)
    (call $C!))

  (func $sieve
    (local $i i32)
    (local $end i32)
    (call $HERE) 
    (call $OVER) 
    (call $ERASE)
    (call $push (i32.const 2))
    (block $endLoop1
      (loop $loop1
        (call $2DUP) 
        (call $DUP) 
        (call $*) 
        (call $>)
        (br_if $endLoop1 (i32.eqz (call $pop)))
        (call $DUP) 
        (call $sieve_prime)
        (if (i32.ne (call $pop) (i32.const 0))
          (block
            (call $2DUP) 
            (call $DUP) 
            (call $*)
            (local.set $i (call $pop))
            (local.set $end (call $pop))
            (block $endLoop2
              (loop $loop2
                (call $push (local.get $i))
                (call $sieve_composite) 
                (call $DUP)
                (local.set $i (i32.add (call $pop) (local.get $i)))
                (br_if $endLoop2 (i32.ge_s (local.get $i) (local.get $end)))
                (br $loop2)))))
        (call $1+)
        (br $loop1)))
    (call $DROP) 
    (call $push (i32.const 1))
    (call $SWAP) 
    (call $push (i32.const 2))
    (local.set $i (call $pop))
    (local.set $end (call $pop))
    (block $endLoop3
      (loop $loop3
        (call $push (local.get $i))
        (call $sieve_prime) 
        (if (i32.ne (call $pop) (i32.const 0))
        (block
          (call $DROP)
          (call $push (local.get $i))))
        (local.set $i (i32.add (i32.const 1) (local.get $i)))
        (br_if $endLoop3 (i32.ge_s (local.get $i) (local.get $end)))
        (br $loop3))))
  (data (i32.const 137224) "\f8\17\02\00" "\0c" "sieve_direct\00\00\00" "\9f\00\00\00")
  (elem (i32.const 0x9f) $sieve)
    
  (func (export "tos") (result i32)
    (global.get $tos))

  (func (export "interpret") (result i32)
    (local $result i32)
    (call $REFILL)
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
    (local.get $result))

  ;; Used for experiments
  (func (export "set_state") (param $latest i32) (param $here i32)
    (global.set $latest (local.get $latest))
    (global.set $here (local.get $here)))

  ;; Table starts with 16 reserved addresses for utility, non-words 
  ;; functions (used in compiled words). From then on, the built-in
  ;; words start.
  (table (export "table") NEXT_TABLE_INDEX anyfunc)

  (global $latest (mut i32) (i32.const 0x21884))
  (global $here (mut i32) (i32.const 0x21890))
  (global $nextTableIndex (mut i32) (i32.const NEXT_TABLE_INDEX))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Compilation state
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (global $currentLocal (mut i32) (i32.const 0))
  (global $lastLocal (mut i32) (i32.const -1))
  (global $branchNesting (mut i32) (i32.const -1))

  ;; Compilation pointer
  (global $cp (mut i32) (i32.const MODULE_BODY_BASE)))
