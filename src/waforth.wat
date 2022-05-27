;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; WAForth
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(module $WAForth

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; External function dependencies.
  ;; 
  ;; These are provided by JavaScript (or whoever instantiates the WebAssembly 
  ;; module)
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; Write a character to the output device
  (import "shell" "emit" (func $shell_emit (param i32)))

  ;; Read input from input device
  ;; Parameters: target address, maximum size
  ;; Returns: number of bytes read
  (import "shell" "read" (func $shell_read (param i32 i32) (result i32)))

  ;; Read a single key from the input device (without echoing)
  (import "shell" "key" (func $shell_key (result i32)))

  ;; Load a webassembly module.
  ;; Parameters: WASM bytecode memory offset, size
  (import "shell" "load" (func $shell_load (param i32 i32)))

  ;; Generic signal to shell
  (import "shell" "call" (func $shell_call))


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Function types
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; A regular compiled word is a function with only the 
  ;; top-of-stack pointer as parameter (and returns the new top-of-stack pointer)
  ;; Arguments are passed via the stack.
  (type $word (func (param i32) (result i32)))

  ;; Words with the 'data' flag set also get a pointer to data passed
  ;; as second parameter.
  (type $dataWord (func (param i32) (param i32) (result i32)))


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Function table
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; The function table contains entries for each defined word, and some helper
  ;; functions used in compiled words. All calls from compiled words to other words go
  ;; through this table.
  ;;
  ;; The table starts with 16 reserved addresses for utility, non-words 
  ;; functions (used in compiled words). From then on, the built-in words start.
  ;;
  ;; Predefined entries:
  ;;
  ;;   START_DO_INDEX := 1
  ;;   UPDATE_DO_INDEX := 2
  ;;   PUSH_DATA_ADDRESS_INDEX := 3
  ;;   SET_LATEST_BODY_INDEX := 4
  ;;   COMPILE_CALL_INDEX := 5
  ;;   PUSH_INDIRECT_INDEX := 6
  ;;   END_DO_INDEX := 9
  ;;   TYPE_INDEX := 0x85
  ;;   ABORT_INDEX := 0x39
  ;;   CONSTANT_INDEX := 0x4c
  ;;   NEXT_TABLE_INDEX := 0xab   (; Next available table index for a compiled word ;)
  (table (export "table") 0xab (; = NEXT_TABLE_INDEX ;) funcref)


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Data
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;;
  ;; Memory size:
  ;;   MEMORY_SIZE := 104857600     (100*1024*1024)
  ;;   MEMORY_SIZE_PAGES := 1600    (MEMORY_SIZE / 65536)
  ;;
  ;; Memory layout:
  ;;   INPUT_BUFFER_BASE  :=   0x300
  ;;   INPUT_BUFFER_SIZE  :=   0x700
  ;;   (Compiled modules are limited to 4096 bytes until Chrome refuses to load them synchronously)
  ;;   MODULE_HEADER_BASE :=  0x1000 
  ;;   RETURN_STACK_BASE  :=  0x2000
  ;;   STACK_BASE         := 0x10000
  ;;   DATA_SPACE_BASE    := 0x20000 
  ;;
  ;;   PICTURED_OUTPUT_OFFSET := 0x200 (offset from HERE; filled backward)
  ;;   WORD_OFFSET := 0x200 (offset from HERE)
  ;;
  (memory (export "memory") 1600 (; = MEMORY_SIZE_PAGES ;))

  ;; The header of a WebAssembly module for a compiled word.
  ;; The body of the compiled word is directly appended to the end
  ;; of this chunk:
  ;;
  ;; Bytes with the top 4 bits set (0xF.) are placeholders
  ;; for patching, for which the offsets are computed below:
  ;;
  ;;   MODULE_HEADER_CODE_SIZE_PLACEHOLDER          := 0xFF
  ;;   MODULE_HEADER_BODY_SIZE_PLACEHOLDER          := 0xFE
  ;;   MODULE_HEADER_LOCAL_COUNT_PLACEHOLDER        := 0xFD
  ;;   MODULE_HEADER_TABLE_INDEX_PLACEHOLDER        := 0xFC
  ;;   MODULE_HEADER_TABLE_INITIAL_SIZE_PLACEHOLDER := 0xFB
  ;;   MODULE_HEADER_FUNCTION_TYPE_PLACEHOLDER      := 0xFA
  (data (i32.const 0x1000 (; = MODULE_HEADER_BASE ;))
    "\00\61\73\6D" ;; Header
    "\01\00\00\00" ;; Version

    "\01" "\12" ;; Type section
      "\03" ;; #Entries
        "\60\01\7f\01\7f" ;; (func (param i32) (result i32))
        "\60\02\7f\7f\01\7f" ;; (func (param i32) (param i32) (result i32))
        "\60\01\7f\02\7F\7f" ;; (func (param i32) (result i32) (result i32))


    "\02" "\20" ;; Import section
      "\02" ;; #Entries
      "\03\65\6E\76" "\05\74\61\62\6C\65" ;; 'env' . 'table'
        "\01" "\70" "\00" "\FB\00\00\00" ;; table, funcref, flags, initial size
      "\03\65\6E\76" "\06\6d\65\6d\6f\72\79" ;; 'env' . 'memory'
        "\02" "\00" "\01" ;; memory

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
        "\FD\00\00\00\7F"  ;; # #i32 locals (padded)
        "\20\00") ;; local.get 0

  ;; Compiled module header offsets:
  ;;
  ;;   MODULE_HEADER_SIZE := 0x60
  ;;   MODULE_HEADER_CODE_SIZE_OFFSET := 0x4f
  ;;   MODULE_HEADER_CODE_SIZE_OFFSET_PLUS_4 := 0x53
  ;;   MODULE_HEADER_BODY_SIZE_OFFSET := 0x54
  ;;   MODULE_HEADER_BODY_SIZE_OFFSET_PLUS_4 := 0x58
  ;;   MODULE_HEADER_LOCAL_COUNT_OFFSET := 0x59
  ;;   MODULE_HEADER_TABLE_INDEX_OFFSET := 0x47
  ;;   MODULE_HEADER_TABLE_INITIAL_SIZE_OFFSET := 0x2c
  ;;   MODULE_HEADER_FUNCTION_TYPE_OFFSET := 0x41
  ;;
  ;;   MODULE_BODY_BASE := 0x1060                    (MODULE_HEADER_BASE + 0x60 (; = MODULE_HEADER_SIZE ;))
  ;;   MODULE_HEADER_CODE_SIZE_BASE := 0x104f          (MODULE_HEADER_BASE + 0x4f (; = MODULE_HEADER_CODE_SIZE_OFFSET ;))
  ;;   MODULE_HEADER_BODY_SIZE_BASE := 0x1054          (MODULE_HEADER_BASE + 0x54 (; = MODULE_HEADER_BODY_SIZE_OFFSET ;))
  ;;   MODULE_HEADER_LOCAL_COUNT_BASE := 0x1059        (MODULE_HEADER_BASE + 0x59 (; = MODULE_HEADER_LOCAL_COUNT_OFFSET ;))
  ;;   MODULE_HEADER_TABLE_INDEX_BASE := 0x1047        (MODULE_HEADER_BASE + 0x47 (; = MODULE_HEADER_TABLE_INDEX_OFFSET ;))
  ;;   MODULE_HEADER_TABLE_INITIAL_SIZE_BASE := 0x102c  (MODULE_HEADER_BASE + 0x2c (; = MODULE_HEADER_TABLE_INITIAL_SIZE_OFFSET ;))
  ;;   MODULE_HEADER_FUNCTION_TYPE_BASE := 0x1041      (MODULE_HEADER_BASE + 0x41 (; = MODULE_HEADER_FUNCTION_TYPE_OFFSET ;))


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Constant strings
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (data (i32.const 0x20000) "\0e" "undefined word")
  (data (i32.const 0x20014) "\0d" "division by 0")
  (data (i32.const 0x20028) "\10" "incomplete input")
  (data (i32.const 0x2003C) "\0b" "missing ')'")
  (data (i32.const 0x2004C) "\09" "missing \22")
  (data (i32.const 0x2005C) "\24" "word not supported in interpret mode")
  (data (i32.const 0x20084) "\0F" "not implemented")
  (data (i32.const 0x20090) "\11" "ADDRESS-UNIT-BITS")
  (data (i32.const 0x200A2) "\0F" "/COUNTED-STRING")
  (data (i32.const 0x200B2) "\11" "stack empty")

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Built-in words
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; These follow the following pattern:
  ;; - WebAssembly function definition: `(func ...)`
  ;; - Dictionary entry in memory: `(data ...)`
  ;; - Function table entry: `(elem ...)`
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

  ;; 6.1.0010
  (func $! (param $tos i32) (result i32)
    (local $bbtos i32)
    (i32.store (i32.load (i32.sub (local.get $tos) (i32.const 4)))
                (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (local.get $bbtos))
  (data (i32.const 0x21000) "\00\00\00\00" "\01" "!\00\00" "\10\00\00\00")
  (elem (i32.const 0x10) $!)

  ;; 6.1.0030
  (func $# (param $tos i32) (result i32)
    (local $v i64)
    (local $base i64)
    (local $bbtos i32)
    (local $m i64)
    (local $npo i32)
    (local.set $base (i64.extend_i32_u (i32.load (i32.const 0x218e4 (; = body(BASE) ;)))))
    (local.set $v (i64.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (local.set $m (i64.rem_u (local.get $v) (local.get $base)))
    (local.set $v (i64.div_u (local.get $v) (local.get $base)))
    (i32.store8 (local.tee $npo (i32.sub (global.get $po) (i32.const 1)))
      (call $numberToChar (i32.wrap_i64 (local.get $m))))
    (i64.store (local.get $bbtos) (local.get $v))
    (global.set $po (local.get $npo))
    (local.get $tos))
  (data (i32.const 135180) "\00\10\02\00" "\01" "#\00\00" "\11\00\00\00")
  (elem (i32.const 0x11) $#)

  ;; 6.1.0040
  (func $#> (param $tos i32) (result i32)
    (i32.store (i32.sub (local.get $tos) (i32.const 8)) (global.get $po))
    (i32.store (i32.sub (local.get $tos) (i32.const 4)) (i32.sub (i32.add (global.get $here) (i32.const 0x200 (; = PICTURED_OUTPUT_OFFSET ;))) (global.get $po)))
    (local.get $tos))
  (data (i32.const 135192) "\0c\10\02\00" "\02" "#>\00" "\12\00\00\00")
  (elem (i32.const 0x12) $#>)

  ;; 6.1.0050
  (func $#S (param $tos i32) (result i32) 
    (local $v i64)
    (local $base i64)
    (local $bbtos i32)
    (local $m i64)
    (local $po i32)
    (local.set $base (i64.extend_i32_u (i32.load (i32.const 0x218e4 (; = body(BASE) ;)))))
    (local.set $v (i64.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (local.set $po (global.get $po))
    (loop $loop
      (local.set $m (i64.rem_u (local.get $v) (local.get $base)))
      (local.set $v (i64.div_u (local.get $v) (local.get $base)))
      (i32.store8 (local.tee $po (i32.sub (local.get $po) (i32.const 1)))
        (call $numberToChar (i32.wrap_i64 (local.get $m))))
      (br_if $loop (i32.wrap_i64 (local.get $v))))
    (i64.store (local.get $bbtos) (local.get $v))
    (global.set $po (local.get $po))
    (local.get $tos))
  (data (i32.const 135204) "\18\10\02\00" "\02" "#S\00" "\13\00\00\00")
  (elem (i32.const 0x13) $#S)

  ;; 6.1.0070
  (func $' (param $tos i32) (result i32)
    (local.get $tos)
    (call $readWord (i32.const 0x20))
    (if (param i32) (result i32) (i32.eqz (i32.load8_u (call $wordBase))) 
      (then 
        (call $fail (i32.const 0x20028)))) ;; incomplete input
    (call $FIND)
    (drop (call $pop)))
  (data (i32.const 135216) "$\10\02\00" "\01" "'\00\00" "\14\00\00\00")
  (elem (i32.const 0x14) $')

  ;; 6.1.0080
  (func $paren (param $tos i32) (result i32)
    (local $c i32)
    (local.get $tos)
    (loop $loop (param i32) (result i32) 
      (if (param i32) (result i32) (i32.lt_s (local.tee $c (call $readChar)) (i32.const 0)) 
        (call $fail (i32.const 0x2003C))) ;; missing ')'
      (br_if $loop (i32.ne (local.get $c) (i32.const 41)))))
  (data (i32.const 135228) "0\10\02\00" "\81" (; immediate ;) "(\00\00" "\15\00\00\00")
  (elem (i32.const 0x15) $paren)

  ;; 6.1.0090
  (func $* (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.mul (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 135240) "<\10\02\00" "\01" "*\00\00" "\16\00\00\00")
  (elem (i32.const 0x16) $*)

  ;; 6.1.0100
  (func $*/ (param $tos i32) (result i32)
    (local $bbtos i32)
    (local $bbbtos i32)
    (i32.store (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12)))
                (i32.wrap_i64
                  (i64.div_s
                      (i64.mul (i64.extend_i32_s (i32.load (local.get $bbbtos)))
                                (i64.extend_i32_s (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))))
                      (i64.extend_i32_s (i32.load (i32.sub (local.get $tos) (i32.const 4)))))))
    (local.get $bbtos))
  (data (i32.const 135252) "H\10\02\00" "\02" "*/\00" "\17\00\00\00")
  (elem (i32.const 0x17) $*/)

  ;; 6.1.0110
  (func $*/MOD (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $bbbtos i32)
    (local $x1 i64)
    (local $x2 i64)
    (i32.store (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12)))
                (i32.wrap_i64
                  (i64.rem_s
                      (local.tee $x1 (i64.mul (i64.extend_i32_s (i32.load (local.get $bbbtos)))
                                              (i64.extend_i32_s (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))))
                      (local.tee $x2 (i64.extend_i32_s (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))))))
    (i32.store (local.get $bbtos) (i32.wrap_i64 (i64.div_s (local.get $x1) (local.get $x2))))
    (local.get $btos))
  (data (i32.const 135264) "T\10\02\00" "\05" "*/MOD\00\00" "\18\00\00\00")
  (elem (i32.const 0x18) $*/MOD)

  ;; 6.1.0120
  (func $+ (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.add (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 135280) "`\10\02\00" "\01" "+\00\00" "\19\00\00\00")
  (elem (i32.const 0x19) $+)

  ;; 6.1.0130
  (func $+! (param $tos i32) (result i32)
    (local $addr i32)
    (local $bbtos i32)
    (i32.store (local.tee $addr (i32.load (i32.sub (local.get $tos) (i32.const 4))))
                (i32.add (i32.load (local.get $addr))
                        (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))))
    (local.get $bbtos))
  (data (i32.const 135292) "p\10\02\00" "\02" "+!\00" "\1a\00\00\00")
  (elem (i32.const 0x1a) $+!)

  ;; 6.1.0140
  (func $+LOOP (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compilePlusLoop))
  (data (i32.const 135304) "|\10\02\00" "\85" (; immediate ;) "+LOOP\00\00" "\1b\00\00\00")
  (elem (i32.const 0x1b) $+LOOP)

  ;; 6.1.0150
  (func $comma (param $tos i32) (result i32)
    (i32.store
      (global.get $here)
      (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (global.set $here (i32.add (global.get $here) (i32.const 4)))
    (i32.sub (local.get $tos) (i32.const 4)))
  (data (i32.const 135320) "\88\10\02\00" "\01" ",\00\00" "\1c\00\00\00")
  (elem (i32.const 0x1c) $comma)

  ;; 6.1.0160
  (func $- (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.sub (i32.load (local.get $bbtos))
                        (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
    (local.get $btos))
  (data (i32.const 135332) "\98\10\02\00" "\01" "-\00\00" "\1d\00\00\00")
  (elem (i32.const 0x1d) $-)

  ;; 6.1.0180
  (func $. (param $tos i32) (result i32)
    (local $v i32)
    (local.get $tos)
    (local.set $v (call $pop))
    (if (i32.lt_s (local.get $v) (i32.const 0))
      (then
        (call $shell_emit (i32.const 0x2d))
        (local.set $v (i32.sub (i32.const 0) (local.get $v)))))
    (call $U._ (local.get $v) (i32.load (i32.const 0x218e4 (; = body(BASE) ;))))
    (call $shell_emit (i32.const 0x20)))
  (data (i32.const 0x21884) "\74\18\02\00" "\01" ".00" "\a6\00\00\00")
  (elem (i32.const 0xa6) $.)

  ;; 6.1.0190
  (func $.q (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $Sq)
    (call $emitICall (i32.const 0) (i32.const 0x85 (; = TYPE_INDEX ;))))
  (data (i32.const 135344) "\a4\10\02\00" "\82" (; immediate ;) ".\22\00" "\1e\00\00\00")
  (elem (i32.const 0x1e) $.q)

  ;; 15.6.1.0220
  (func $.S (param $tos i32) (result i32)
    (local $p i32)
    (local.set $p (i32.const 0x10000 (; = STACK_BASE ;)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.ge_u (local.get $p) (local.get $tos)))
        (call $U._ (i32.load (local.get $p)) (i32.load (i32.const 0x218e4 (; = body(BASE) ;))))
        (call $shell_emit (i32.const 0x20))
        (local.set $p (i32.add (local.get $p) (i32.const 4)))
        (br $loop)))
    (local.get $tos))
  (data (i32.const 0x21890) "\84\18\02\00" "\02" ".S0" "\a7\00\00\00")
  (elem (i32.const 0xa7) $.S)

  ;; 6.1.0230
  (func $/ (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $divisor i32)
    (if (i32.eqz (local.tee $divisor (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
      (return (call $fail (local.get $tos) (i32.const 0x20014)))) ;; division by 0
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.div_s (i32.load (local.get $bbtos)) (local.get $divisor)))
    (local.get $btos))
  (data (i32.const 135356) "\b0\10\02\00" "\01" "/\00\00" "\1f\00\00\00")
  (elem (i32.const 0x1f) $/)

  ;; 6.1.0240
  (func $/MOD (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $n1 i32)
    (local $n2 i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.rem_s (local.tee $n1 (i32.load (local.get $bbtos)))
                          (local.tee $n2 (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                                              (i32.const 4)))))))
    (i32.store (local.get $btos) (i32.div_s (local.get $n1) (local.get $n2)))
    (local.get $tos))
  (data (i32.const 135368) "\bc\10\02\00" "\04" "/MOD\00\00\00" " \00\00\00")
  (elem (i32.const 0x20) $/MOD)

  ;; 6.1.0250
  (func $0< (param $tos i32) (result i32)
    (local $btos i32)
    (if (i32.lt_s (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                      (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (local.get $btos) (i32.const -1)))
      (else (i32.store (local.get $btos) (i32.const 0))))
    (local.get $tos))
  (data (i32.const 135384) "\c8\10\02\00" "\02" "0<\00" "!\00\00\00")
  (elem (i32.const 0x21) $0<)

  ;; 6.1.0270
  (func $0= (param $tos i32) (result i32)
    (local $btos i32)
    (if (i32.eqz (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                      (i32.const 4)))))
      (then (i32.store (local.get $btos) (i32.const -1)))
      (else (i32.store (local.get $btos) (i32.const 0))))
    (local.get $tos))
  (data (i32.const 135396) "\d8\10\02\00" "\02" "0=\00" "\22\00\00\00")
  (elem (i32.const 0x22) $0=)

  ;; 6.2.0280
  (func $0> (param $tos i32) (result i32)
    (local $btos i32)
    (if (i32.gt_s (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                      (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (local.get $btos) (i32.const -1)))
      (else (i32.store (local.get $btos) (i32.const 0))))
    (local.get $tos))
  (data (i32.const 137060) "X\17\02\00" "\02" "0>\00" "\94\00\00\00")
  (elem (i32.const 0x94) $0>)

  ;; 6.1.0290
  (func $1+ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.add (i32.load (local.get $btos)) (i32.const 1)))
    (local.get $tos))
  (data (i32.const 135408) "\e4\10\02\00" "\02" "1+\00" "#\00\00\00")
  (elem (i32.const 0x23) $1+)

  ;; 6.1.0300
  (func $1- (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.sub (i32.load (local.get $btos)) (i32.const 1)))
    (local.get $tos))
  (data (i32.const 135420) "\f0\10\02\00" "\02" "1-\00" "$\00\00\00")
  (elem (i32.const 0x24) $1-)

  ;; 6.1.0310
  (func $2! (param $tos i32) (result i32)
    (local.get $tos)
    (call $SWAP) (call $OVER) (call $!) (call $CELL+) (call $!))
  (data (i32.const 135432) "\fc\10\02\00" "\02" "2!\00" "%\00\00\00")
  (elem (i32.const 0x25) $2!)

  ;; 6.1.0320
  (func $2* (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.shl (i32.load (local.get $btos)) (i32.const 1)))
    (local.get $tos))
  (data (i32.const 135444) "\08\11\02\00" "\02" "2*\00" "&\00\00\00")
  (elem (i32.const 0x26) $2*)

  ;; 6.1.0330
  (func $2/ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.shr_s (i32.load (local.get $btos)) (i32.const 1)))
    (local.get $tos))
  (data (i32.const 135456) "\14\11\02\00" "\02" "2/\00" "'\00\00\00")
  (elem (i32.const 0x27) $2/)

  ;; 6.1.0350
  (func $2@  (param $tos i32) (result i32)
    (local.get $tos)
    (call $DUP)
    (call $CELL+)
    (call $@)
    (call $SWAP)
    (call $@))
  (data (i32.const 135468) " \11\02\00" "\02" "2@\00" "(\00\00\00")
  (elem (i32.const 0x28) $2@)

  ;; 6.1.0370 
  (func $2DROP (param $tos i32) (result i32)
    (i32.sub (local.get $tos) (i32.const 8)))
  (data (i32.const 135480) ",\11\02\00" "\05" "2DROP\00\00" ")\00\00\00")
  (elem (i32.const 0x29) $2DROP)

  ;; 6.1.0380
  (func $2DUP (param $tos i32) (result i32)
    (i32.store (local.get $tos)
                (i32.load (i32.sub (local.get $tos) (i32.const 8))))
    (i32.store (i32.add (local.get $tos) (i32.const 4))
                (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (i32.add (local.get $tos) (i32.const 8)))
  (data (i32.const 135496) "8\11\02\00" "\04" "2DUP\00\00\00" "*\00\00\00")
  (elem (i32.const 0x2a) $2DUP)

  ;; 6.1.0400
  (func $2OVER (param $tos i32) (result i32)
    (i32.store (local.get $tos)
                (i32.load (i32.sub (local.get $tos) (i32.const 16))))
    (i32.store (i32.add (local.get $tos) (i32.const 4))
                (i32.load (i32.sub (local.get $tos) (i32.const 12))))
    (i32.add (local.get $tos) (i32.const 8)))
  (data (i32.const 135512) "H\11\02\00" "\05" "2OVER\00\00" "+\00\00\00")
  (elem (i32.const 0x2b) $2OVER)

  ;; 6.1.0430
  (func $2SWAP (param $tos i32) (result i32)
    (local $x1 i32)
    (local $x2 i32)
    (local.set $x1 (i32.load (i32.sub (local.get $tos) (i32.const 16))))
    (local.set $x2 (i32.load (i32.sub (local.get $tos) (i32.const 12))))
    (i32.store (i32.sub (local.get $tos) (i32.const 16))
                (i32.load (i32.sub (local.get $tos) (i32.const 8))))
    (i32.store (i32.sub (local.get $tos) (i32.const 12))
                (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (i32.store (i32.sub (local.get $tos) (i32.const 8))
                (local.get $x1))
    (i32.store (i32.sub (local.get $tos) (i32.const 4))
                (local.get $x2))
    (local.get $tos))
  (data (i32.const 135528) "X\11\02\00" "\05" "2SWAP\00\00" ",\00\00\00")
  (elem (i32.const 0x2c) $2SWAP)

  ;; 6.1.0450
  (func $: (param $tos i32) (result i32)
    (local.get $tos)
    (call $CREATE)
    (call $hidden)

    ;; Turn off (default) data flag
    (i32.store 
      (i32.add (global.get $latest) (i32.const 4))
      (i32.xor 
        (i32.load (i32.add (global.get $latest) (i32.const 4)))
        (i32.const 0x40 (; = F_DATA ;))))

    ;; Store the code pointer already
    ;; The code hasn't been loaded yet, but since nothing can affect the next table
    ;; index, we can assume the index will be correct. This allows semicolon to be
    ;; agnostic about whether it is compiling a word or a DOES>.
    (i32.store (call $body (global.get $latest)) (global.get $nextTableIndex))

    (call $startColon (i32.const 0))
    (call $right-bracket))
  (data (i32.const 135544) "h\11\02\00" "\01" ":\00\00" "-\00\00\00")
  (elem (i32.const 0x2d) $:)

  ;; 6.1.0460
  (func $semicolon (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $endColon)
    (call $hidden)
    (call $left-bracket))
  (data (i32.const 135556) "x\11\02\00" "\81" (; immediate ;) ";\00\00" ".\00\00\00")
  (elem (i32.const 0x2e) $semicolon)

  ;; 6.1.0480
  (func $< (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_s (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                  (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (local.get $btos))
  (data (i32.const 135568) "\84\11\02\00" "\01" "<\00\00" "/\00\00\00")
  (elem (i32.const 0x2f) $<)

  ;; 6.1.0490
  (func $<# (param $tos i32) (result i32)
    (global.set $po (i32.add (global.get $here) (i32.const 0x200 (; = PICTURED_OUTPUT_OFFSET ;))))
    (local.get $tos))
  (data (i32.const 135580) "\90\11\02\00" "\02" "<#\00" "0\00\00\00")
  (elem (i32.const 0x30) $<#)

  ;; 6.1.0530
  (func $= (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.eq (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (local.get $btos))
  (data (i32.const 135592) "\9c\11\02\00" "\01" "=\00\00" "1\00\00\00")
  (elem (i32.const 0x31) $=)

  ;; 6.1.0540
  (func $> (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.gt_s (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                  (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (local.get $btos))
  (data (i32.const 135604) "\a8\11\02\00" "\01" ">\00\00" "2\00\00\00")
  (elem (i32.const 0x32) $>)

  ;; 6.1.0550
  (func $>BODY (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
      (i32.add (call $body (i32.load (local.get $btos))) (i32.const 4)))
    (local.get $tos))
  (data (i32.const 135616) "\b4\11\02\00" "\05" ">BODY\00\00" "3\00\00\00")
  (elem (i32.const 0x33) $>BODY)

  ;; 6.1.0560
  (data (i32.const 0x218fc) "\e8\18\02\00" "\43" (; DATA ;) ">IN" "\03\00\00\00" "\00\00\00\00")

  ;; 6.1.0570
  (func $>NUMBER (param $tos i32) (result i32) 
    (local $btos i32)
    (local $bbtos i32)
    (local $bbbbtos i32)
    (local $value i64)
    (local $rest i32)
    (local $restcount i32)
    (call $number
      (i64.load (local.tee $bbbbtos (i32.sub (local.get $tos) (i32.const 16))))
      (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
      (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (local.set $restcount)
    (local.set $rest)
    (local.set $value)
    (i32.store (local.get $btos) (local.get $restcount))
    (i32.store (local.get $bbtos) (local.get $rest))
    (i64.store (local.get $bbbbtos) (local.get $value))
    (local.get $tos))
  (data (i32.const 135644) "\d0\11\02\00" "\07" ">NUMBER" "5\00\00\00")
  (elem (i32.const 0x35) $>NUMBER)

  ;; 6.1.0580
  (func $>R (param $tos i32) (result i32)
    (local.tee $tos (i32.sub (local.get $tos) (i32.const 4)))
    (i32.store (global.get $tors) (i32.load (local.get $tos)))
    (global.set $tors (i32.add (global.get $tors) (i32.const 4))))
  (data (i32.const 135660) "\dc\11\02\00" "\02" ">R\00" "6\00\00\00")
  (elem (i32.const 0x36) $>R)

  ;; 6.1.0630 
  (func $?DUP (param $tos i32) (result i32)
    (local $btos i32)
    (if (result i32) (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
      (then
        (i32.store (local.get $tos)
          (i32.load (local.get $btos)))
        (i32.add (local.get $tos) (i32.const 4)))
      (else 
        (local.get $tos))))
  (data (i32.const 135672) "\ec\11\02\00" "\04" "?DUP\00\00\00" "7\00\00\00")
  (elem (i32.const 0x37) $?DUP)

  ;; 6.1.0650
  (func $@ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
      (i32.load (i32.load (local.get $btos))))
    (local.get $tos))
  (data (i32.const 135688) "\f8\11\02\00" "\01" "@\00\00" "8\00\00\00")
  (elem (i32.const 0x38) $@)

  ;; 6.1.0670 ABORT 
  (func $ABORT (param $tos i32) (result i32)
    (call $QUIT (i32.const 0x10000 (; = STACK_BASE ;))))
  (data (i32.const 135700) "\08\12\02\00" "\05" "ABORT\00\00" "9\00\00\00")
  (elem (i32.const 0x39 (; = ABORT_INDEX ;)) $ABORT) ;; none

  ;; 6.1.0680 ABORT"
  (func $ABORTq (param $tos i32) (result i32)
    (local.get $tos)
    (call $compileIf)
    (call $Sq)
    (call $emitICall (i32.const 0) (i32.const 0x85 (; = TYPE_INDEX ;)))
    (call $emitICall (i32.const 0) (i32.const 0x39 (; = ABORT_INDEX ;)))
    (call $compileThen))
  (data (i32.const 135716) "\14\12\02\00" "\86" (; immediate ;) "ABORT\22\00" ":\00\00\00")
  (elem (i32.const 0x3a) $ABORTq)

  ;; 6.1.0690
  (func $ABS (param $tos i32) (result i32)
    (local $btos i32)
    (local $v i32)
    (local $y i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.sub (i32.xor (local.tee $v (i32.load (local.get $btos)))
                                  (local.tee $y (i32.shr_s (local.get $v) (i32.const 31))))
                        (local.get $y)))
    (local.get $tos))
  (data (i32.const 135732) "$\12\02\00" "\03" "ABS" ";\00\00\00")
  (elem (i32.const 0x3b) $ABS)

  ;; 6.1.0695
  (func $ACCEPT (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $addr i32)
    (local $p i32)
    (local $endp i32)
    (local $c i32)
    (local.set $endp 
      (i32.add 
        (local.tee $addr (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
        (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
    (local.set $p (local.get $addr))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eq (local.tee $c (call $shell_key)) (i32.const 0xa)))
        (i32.store8 (local.get $p) (local.get $c))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (call $shell_emit (local.get $c))
        (br_if $loop (i32.lt_u (local.get $p) (local.get $endp)))))
    (i32.store (local.get $bbtos)  (i32.sub (local.get $p) (local.get $addr)))
    (local.get $btos))
  (data (i32.const 135744) "4\12\02\00" "\06" "ACCEPT\00" "<\00\00\00")
  (elem (i32.const 0x3c) $ACCEPT)

  ;; 6.1.0705
  (func $ALIGN (param $tos i32) (result i32)
    (global.set $here (i32.and
                        (i32.add (global.get $here) (i32.const 3))
                        (i32.const -4 (; ~3 ;))))
    (local.get $tos))
  (data (i32.const 135760) "@\12\02\00" "\05" "ALIGN\00\00" "=\00\00\00")
  (elem (i32.const 0x3d) $ALIGN)

  ;; 6.1.0706
  (func $ALIGNED (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.and (i32.add (i32.load (local.get $btos)) (i32.const 3))
                        (i32.const -4 (; ~3 ;))))
    (local.get $tos))
  (data (i32.const 135776) "P\12\02\00" "\07" "ALIGNED" ">\00\00\00")
  (elem (i32.const 0x3e) $ALIGNED)

  ;; 6.1.0710
  (func $ALLOT (param $tos i32) (result i32)
    (local $v i32)
    (local.get $tos)
    (local.set $v (call $pop))
    (global.set $here (i32.add (global.get $here) (local.get $v))))
  (data (i32.const 135792) "`\12\02\00" "\05" "ALLOT\00\00" "?\00\00\00")
  (elem (i32.const 0x3f) $ALLOT)

  ;; 6.1.0720
  (func $AND (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.and (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 135808) "p\12\02\00" "\03" "AND" "@\00\00\00")
  (elem (i32.const 0x40) $AND)

  ;; 6.1.0750 
  (data (i32.const 0x218d4) "\c4\18\02\00" "\44" "BASE\00\00\00" "\03\00\00\00" (; = pack(PUSH_DATA_ADDRESS_INDEX) ;) "\0a\00\00\00" (; = pack(10) ;))

  ;; 6.1.0760 
  (func $BEGIN (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileBegin))
  (data (i32.const 135836) "\8c\12\02\00" "\85" (; immediate ;) "BEGIN\00\00" "B\00\00\00")
  (elem (i32.const 0x42) $BEGIN)

  ;; 6.1.0770
  (func $BL (param $tos i32) (result i32)
    (call $push (local.get $tos) (i32.const 32)))
  (data (i32.const 135852) "\9c\12\02\00" "\02" "BL\00" "C\00\00\00")
  (elem (i32.const 0x43) $BL)

  ;; 6.1.0850
  (func $C! (param $tos i32) (result i32)
    (local $bbtos i32)
    (i32.store8 (i32.load (i32.sub (local.get $tos) (i32.const 4)))
                (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (local.get $bbtos))
  (data (i32.const 135864) "\ac\12\02\00" "\02" "C!\00" "D\00\00\00")
  (elem (i32.const 0x44) $C!)

  ;; 6.1.0860
  (func $Cc (param $tos i32) (result i32)
    (i32.store8 (global.get $here)
                (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (global.set $here (i32.add (global.get $here) (i32.const 1)))
    (i32.sub (local.get $tos) (i32.const 4)))
  (data (i32.const 135876) "\b8\12\02\00" "\02" "C,\00" "E\00\00\00")
  (elem (i32.const 0x45) $Cc)

  ;; 6.1.0870
  (func $C@ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.load8_u (i32.load (local.get $btos))))
    (local.get $tos))
  (data (i32.const 135888) "\c4\12\02\00" "\02" "C@\00" "F\00\00\00")
  (elem (i32.const 0x46) $C@)

  ;; 6.1.0880
  (func $CELL+ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.add (i32.load (local.get $btos)) (i32.const 4)))
    (local.get $tos))
  (data (i32.const 135900) "\d0\12\02\00" "\05" "CELL+\00\00" "G\00\00\00")
  (elem (i32.const 0x47) $CELL+)

  ;; 6.1.0890
  (func $CELLS (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.shl (i32.load (local.get $btos)) (i32.const 2)))            
    (local.get $tos))
  (data (i32.const 135916) "\dc\12\02\00" "\05" "CELLS\00\00" "H\00\00\00")
  (elem (i32.const 0x48) $CELLS)

  ;; 6.1.0895
  (func $CHAR (param $tos i32) (result i32)
    (call $readWord (local.get $tos) (i32.const 0x20))
    (if (param i32) (result i32) (i32.eqz (i32.load8_u (call $wordBase)))
      (call $fail (i32.const 0x20028))) ;; incomplete input
    (local.tee $tos)
    (i32.store (i32.sub (local.get $tos) (i32.const 4))
                (i32.load8_u (i32.add (call $wordBase) (i32.const 1)))))
  (data (i32.const 135932) "\ec\12\02\00" "\04" "CHAR\00\00\00" "I\00\00\00")
  (elem (i32.const 0x49) $CHAR)

  ;; 6.1.0897
  (func $CHAR+ (param $tos i32) (result i32)
    (call $1+ (local.get $tos)))
  (data (i32.const 135948) "\fc\12\02\00" "\05" "CHAR+\00\00" "J\00\00\00")
  (elem (i32.const 0x4a) $CHAR+)

  ;; 6.1.0898
  (func $CHARS (param $tos i32) (result i32)
    (local.get $tos))
  (data (i32.const 135964) "\0c\13\02\00" "\05" "CHARS\00\00" "K\00\00\00")
  (elem (i32.const 0x4b) $CHARS)

  ;; 6.1.0950
  (func $CONSTANT (param $tos i32) (result i32)
    (local $v i32)
    (local.get $tos)
    (call $CREATE)
    (i32.store (i32.sub (global.get $here) (i32.const 4)) (i32.const 6 (; = PUSH_INDIRECT_INDEX ;)))
    (local.set $v (call $pop))
    (i32.store (global.get $here) (local.get $v))
    (global.set $here (i32.add (global.get $here) (i32.const 4))))
  (data (i32.const 135980) "\1c\13\02\00" "\08" "CONSTANT\00\00\00" "L\00\00\00")
  (elem (i32.const 0x4c (; = CONSTANT_INDEX ;)) $CONSTANT)

  ;; 6.1.0980
  (func $COUNT (param $tos i32) (result i32)
    (local $btos i32)
    (local $addr i32)
    (i32.store (local.get $tos)
                (i32.load8_u (local.tee $addr (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                                                (i32.const 4)))))))
    (i32.store (local.get $btos) (i32.add (local.get $addr) (i32.const 1)))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136000) ",\13\02\00" "\05" "COUNT\00\00" "M\00\00\00")
  (elem (i32.const 0x4d) $COUNT)

  ;; 6.1.0990
  (func $CR (param $tos i32) (result i32)
    (call $push (local.get $tos) (i32.const 10)) (call $EMIT))
  (data (i32.const 136016) "@\13\02\00" "\02" "CR\00" "N\00\00\00")
  (elem (i32.const 0x4e) $CR)

  ;; 6.1.1000
  (func $CREATE (param $tos i32) (result i32)
    (local $length i32)
    (local $here i32)

    (i32.store (global.get $here) (global.get $latest))
    (global.set $latest (global.get $here))
    (global.set $here (i32.add (global.get $here) (i32.const 4)))

    (local.get $tos)
    (call $readWord (i32.const 0x20))
    (if (param i32) (result i32) (i32.eqz (local.tee $length (i32.load8_u (call $wordBase))))
      (call $fail (i32.const 0x20028))) ;; incomplete input
    (drop (call $pop))
    (i32.store8 (global.get $here) (local.get $length))

    (memory.copy 
      (local.tee $here (i32.add (global.get $here) (i32.const 1)))
      (i32.add (call $wordBase) (i32.const 1)) 
      (local.get $length))

    (global.set $here (i32.add (local.get $here) (local.get $length)))

    (call $ALIGN)

    (i32.store (global.get $here) (i32.const 3 (; = PUSH_DATA_ADDRESS_INDEX ;)))
    (global.set $here (i32.add (global.get $here) (i32.const 4)))
    (i32.store (global.get $here) (i32.const 0))

    (call $setFlag (i32.const 0x40 (; = F_DATA ;))))
  (data (i32.const 136028) "P\13\02\00" "\06" "CREATE\00" "O\00\00\00")
  (elem (i32.const 0x4f) $CREATE)

  ;; 6.1.1170
  (func $DECIMAL (param $tos i32) (result i32)
    (i32.store (i32.const 0x218e4 (; = body(BASE) ;)) (i32.const 10))
    (local.get $tos))
  (data (i32.const 136044) "\5c\13\02\00" "\07" "DECIMAL" "P\00\00\00")
  (elem (i32.const 0x50) $DECIMAL)

  ;; 6.1.1200
  (func $DEPTH (param $tos i32) (result i32)
    (i32.store (local.get $tos)
              (i32.shr_u (i32.sub (local.get $tos) (i32.const 0x10000 (; = STACK_BASE ;))) (i32.const 2)))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136060) "l\13\02\00" "\05" "DEPTH\00\00" "Q\00\00\00")
  (elem (i32.const 0x51) $DEPTH)

  ;; 6.1.1240
  (func $DO (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileDo))
  (data (i32.const 136076) "|\13\02\00" "\82" (; immediate ;) "DO\00" "R\00\00\00")
  (elem (i32.const 0x52) $DO)

  ;; 6.1.1250
  (func $DOES> (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $emitConst (i32.add (global.get $nextTableIndex) (i32.const 1)))
    (call $emitICall (i32.const 1) (i32.const 4 (; = SET_LATEST_BODY_INDEX ;)))
    (call $endColon)
    (call $startColon (i32.const 1))
    (call $compilePushLocal (i32.const 1)))
  (data (i32.const 136088) "\8c\13\02\00" "\85" (; immediate ;) "DOES>\00\00" "S\00\00\00")
  (elem (i32.const 0x53) $DOES>)

  ;; 6.1.1260
  (func $DROP (param $tos i32) (result i32)
    (i32.sub (local.get $tos) (i32.const 4)))
  (data (i32.const 136104) "\98\13\02\00" "\04" "DROP\00\00\00" "T\00\00\00")
  (elem (i32.const 0x54) $DROP)

  ;; 6.1.1290
  (func $DUP (param $tos i32) (result i32)
    (i32.store (local.get $tos)
      (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136120) "\a8\13\02\00" "\03" "DUP" "U\00\00\00")
  (elem (i32.const 0x55) $DUP)

  ;; 6.1.1310
  (func $ELSE (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $emitElse))
  (data (i32.const 136132) "\b8\13\02\00" "\84" (; immediate ;) "ELSE\00\00\00" "V\00\00\00")
  (elem (i32.const 0x56) $ELSE)

  ;; 6.1.1320
  (func $EMIT (param $tos i32) (result i32)
    (call $shell_emit (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (i32.sub (local.get $tos) (i32.const 4)))
  (data (i32.const 136148) "\c4\13\02\00" "\04" "EMIT\00\00\00" "W\00\00\00")
  (elem (i32.const 0x57) $EMIT)

  ;; 6.1.1345
  (func $ENVIRONMENT? (param $tos i32) (result i32)
    (local $addr i32)
    (local $len i32)
    (local $btos i32)
    (local $bbtos i32)
    (local.set $addr (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (local.set $len (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (if (result i32) (call $stringEqual (local.get $addr) (local.get $len) (i32.const 0x20091) (i32.const 0x11) (; "ADDRESS-UNIT-BITS" ;))
      (then
        (i32.store (local.get $bbtos) (i32.const 8))
        (i32.store (local.get $btos) (i32.const -1))
        (local.get $tos))
      (else 
        (if (result i32) (call $stringEqual (local.get $addr) (local.get $len) (i32.const 0x200A3) (i32.const 0x0F) (; "/COUNTED-STRING" ;))
          (then
            (i32.store (local.get $bbtos) (i32.const 255))
            (i32.store (local.get $btos) (i32.const -1))
            (local.get $tos))
          (else
            (i32.store (local.get $bbtos) (i32.const 0))
            (local.get $btos))))))
  (data (i32.const 0x218ac) "\9c\18\02\00" "\0c" "ENVIRONMENT?000" "\a9\00\00\00")
  (elem (i32.const 0xa9) $ENVIRONMENT?)

  ;; 6.2.1350
  (func $ERASE (param $tos i32) (result i32)
    (local $bbtos i32)
    (memory.fill 
      (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
      (i32.const 0)
      (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (local.get $bbtos))
  (data (i32.const 137072) "d\17\02\00" "\05" "ERASE\00\00" "\95\00\00\00")
  (elem (i32.const 0x95) $ERASE)

  ;; 6.1.1360
  (func $EVALUATE (param $tos i32) (result i32)
    (local $bbtos i32)
    (local $prevSourceID i32)
    (local $prevIn i32)
    (local $prevInputBufferBase i32)
    (local $prevInputBufferSize i32)

    ;; Save input state
    (local.set $prevSourceID (global.get $sourceID))
    (local.set $prevIn (i32.load (i32.const 0x21908 (; body(>IN) ;))))
    (local.set $prevInputBufferSize (global.get $inputBufferSize))
    (local.set $prevInputBufferBase (global.get $inputBufferBase))

    (global.set $sourceID (i32.const -1))
    (global.set $inputBufferBase (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (global.set $inputBufferSize (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (i32.store (i32.const 0x21908 (; body(>IN) ;)) (i32.const 0))

    (drop (call $interpret (local.get $bbtos)))

    ;; Restore input state
    (global.set $sourceID (local.get $prevSourceID))
    (i32.store (i32.const 0x21908 (; body(>IN) ;)) (local.get $prevIn))
    (global.set $inputBufferBase (local.get $prevInputBufferBase))
    (global.set $inputBufferSize (local.get $prevInputBufferSize)))
  (data (i32.const 136184) "\e4\13\02\00" "\08" "EVALUATE\00\00\00" "Y\00\00\00")
  (elem (i32.const 0x59) $EVALUATE)

  ;; 6.1.1370
  (func $EXECUTE (param $tos i32) (result i32)
    (local $xt i32)
    (local $body i32)
    (local.get $tos)
    (local.set $body (call $body (local.tee $xt (call $pop))))
    (if (param i32) (result i32) (i32.and (i32.load8_u (i32.add (local.get $xt) (i32.const 4)))
                  (i32.const 0x40 (; = F_DATA ;)))
      (then
        (call_indirect (type $dataWord) (i32.add (local.get $body) (i32.const 4))
                                        (i32.load (local.get $body))))
      (else
        (call_indirect (type $word) (i32.load (local.get $body))))))
  (data (i32.const 136204) "\f8\13\02\00" "\07" "EXECUTE" "Z\00\00\00")
  (elem (i32.const 0x5a) $EXECUTE)

  ;; 6.1.1380
  (func $EXIT (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $emitReturn))
  (data (i32.const 136220) "\0c\14\02\00" "\84" (; immediate ;) "EXIT\00\00\00" "[\00\00\00")
  (elem (i32.const 0x5b) $EXIT)

  ;; 6.2.1485
  (func $FALSE (param $tos i32) (result i32)
    (call $push (local.get $tos) (i32.const 0x0)))
  (data (i32.const 0x2183c) "\2c\18\02\00" "\05" "FALSE00" "\a2\00\00\00")
  (elem (i32.const 0xa2) $FALSE)

  ;; 6.1.1540
  (func $FILL (param $tos i32) (result i32)
    (local $bbbtos i32)
    (memory.fill 
      (i32.load (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12))))
      (i32.load (i32.sub (local.get $tos) (i32.const 4)))
      (i32.load (i32.sub (local.get $tos) (i32.const 8))))
    (local.get $bbbtos))
  (data (i32.const 136236) "\1c\14\02\00" "\04" "FILL\00\00\00" "\5c\00\00\00")
  (elem (i32.const 0x5c) $FILL)

  ;; 6.1.1550
  (func $FIND (param $tos i32) (result i32)
    (local $entryP i32)
    (local $entryLF i32)
    (local $wordStart i32)
    (local $wordLength i32)
    (local.set $wordLength (i32.load8_u (local.tee $wordStart (i32.load (i32.sub (local.get $tos) (i32.const 4))))))
    (local.set $wordStart (i32.add (local.get $wordStart) (i32.const 1)))
    (local.set $entryP (global.get $latest))
    (loop $loop
      (if 
          (i32.and 
            (i32.eqz
              (i32.and 
                (local.tee $entryLF (i32.load (i32.add (local.get $entryP) (i32.const 4))))
                (i32.const 0x20 (; = F_HIDDEN ;))))
            (call $stringEqual 
              (local.get $wordStart) (local.get $wordLength)
              (i32.add (local.get $entryP) (i32.const 5)) (i32.and (local.get $entryLF) (i32.const 0x1F (; = LENGTH_MASK ;)))))
        (then
          (i32.store (i32.sub (local.get $tos) (i32.const 4)) (local.get $entryP))
          (call $push (local.get $tos)
            (select 
              (i32.const -1)
              (i32.const 1)
              (i32.eqz (i32.and (local.get $entryLF) (i32.const 0x80 (; = F_IMMEDIATE ;))))))
          (return)))
      (local.set $entryP (i32.load (local.get $entryP)))
      (br_if $loop (local.get $entryP)))
    (call $push (local.get $tos) (i32.const 0)))
  (data (i32.const 136252) ",\14\02\00" "\04" "FIND\00\00\00" "]\00\00\00")
  (elem (i32.const 0x5d) $FIND)

  ;; 6.1.1561
  (func $FM/MOD (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbbtos i32)
    (local $n1 i64)
    (local $n2 i64)
    (local $n2_32 i32)
    (local $q i32)
    (local $mod i32)
    (local.set $mod
      (i32.wrap_i64 
        (i64.rem_s 
          (local.tee $n1 (i64.load (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12)))))
          (local.tee $n2 (i64.extend_i32_s (local.tee $n2_32 (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))))))
    (local.set $q (i32.wrap_i64 (i64.div_s (local.get $n1) (local.get $n2))))
    (if 
        (i32.and 
          (i32.ne (local.get $mod (i32.const 0))) 
          (i64.lt_s (i64.xor (local.get $n1) (local.get $n2)) (i64.const 0)))
      (then
        (local.set $q (i32.sub (local.get $q) (i32.const 1)))
        (local.set $mod (i32.add (local.get $mod) (local.get $n2_32)))))
    (i32.store (local.get $bbbtos) (local.get $mod))
    (i32.store (i32.sub (local.get $tos) (i32.const 8)) (local.get $q))
    (local.get $btos))
  (data (i32.const 136268) "<\14\02\00" "\06" "FM/MOD\00" "^\00\00\00")
  (elem (i32.const 0x5e) $FM/MOD)

  ;; 6.1.1650
  (func $HERE (param $tos i32) (result i32)
    (i32.store (local.get $tos) (global.get $here))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136284) "L\14\02\00" "\04" "HERE\00\00\00" "_\00\00\00")
  (elem (i32.const 0x5f) $HERE)

  ;; 6.2.1660
  (func $HEX (param $tos i32) (result i32)
    (i32.store (i32.const 0x218e4 (; = body(BASE) ;)) (i32.const 16))
    (local.get $tos))
  (data (i32.const 0x21820) "\08\18\02\00" "\03" "HEX" "\a0\00\00\00")
  (elem (i32.const 0xa0) $HEX)

  ;; 6.1.1670
  (func $HOLD (param $tos i32) (result i32)
    (local $btos i32)
    (local $npo i32)
    (i32.store8 
      (local.tee $npo (i32.sub (global.get $po) (i32.const 1)))
      (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (global.set $po (local.get $npo))
    (local.get $btos))
  (data (i32.const 136300) "\5c\14\02\00" "\04" "HOLD\00\00\00" "`\00\00\00")
  (elem (i32.const 0x60) $HOLD)

  ;; 6.1.1680
  (func $I (param $tos i32) (result i32)
    (i32.store (local.get $tos) (i32.load (i32.sub (global.get $tors) (i32.const 4))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136316) "l\14\02\00" "\01" "I\00\00" "a\00\00\00")
  (elem (i32.const 0x61) $I)

  ;; 6.1.1700
  (func $IF (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileIf))
  (data (i32.const 136328) "|\14\02\00" "\82" (; immediate ;) "IF\00" "b\00\00\00")
  (elem (i32.const 0x62) $IF)

  ;; 6.1.1710
  (func $IMMEDIATE (param $tos i32) (result i32)
    (call $setFlag (i32.const 0x80 (; = F_IMMEDIATE ;)))
    (local.get $tos))
  (data (i32.const 136340) "\88\14\02\00" "\09" "IMMEDIATE\00\00" "c\00\00\00")
  (elem (i32.const 0x63) $IMMEDIATE)

  ;; 6.1.1720
  (func $INVERT (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.xor (i32.load (local.get $btos)) (i32.const -1)))
    (local.get $tos))
  (data (i32.const 136360) "\94\14\02\00" "\06" "INVERT\00" "d\00\00\00")
  (elem (i32.const 0x64) $INVERT)

  ;; 6.1.1730
  (func $J (param $tos i32) (result i32)
    (i32.store (local.get $tos) (i32.load (i32.sub (global.get $tors) (i32.const 8))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136376) "\a8\14\02\00" "\01" "J\00\00" "e\00\00\00")
  (elem (i32.const 0x65) $J)

  ;; 6.1.1750
  (func $KEY (param $tos i32) (result i32)
    (i32.store (local.get $tos) (call $shell_key))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136388) "\b8\14\02\00" "\03" "KEY" "f\00\00\00")
  (elem (i32.const 0x66) $KEY)

  (func $LATEST (param $tos i32) (result i32)
    (i32.store (local.get $tos) (global.get $latest))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 137208) "\ec\17\02\00" "\06" "LATEST\00" "\9e\00\00\00")
  (elem (i32.const 0x9e) $LATEST)

  ;; 6.1.1760
  (func $LEAVE (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileLeave))
  (data (i32.const 136400) "\c4\14\02\00" "\85" "LEAVE\00\00" "g\00\00\00")
  (elem (i32.const 0x67) $LEAVE) ;; immediate

  ;; 6.1.1780
  (func $LITERAL (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compilePushConst (call $pop)))
  (data (i32.const 136416) "\d0\14\02\00" "\87" "LITERAL" "h\00\00\00")
  (elem (i32.const 0x68) $LITERAL) ;; immediate

  ;; 6.1.1800
  (func $LOOP (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileLoop))
  (data (i32.const 136432) "\e0\14\02\00" "\84" "LOOP\00\00\00" "i\00\00\00")
  (elem (i32.const 0x69) $LOOP) ;; immediate

  ;; 6.1.1805
  (func $LSHIFT (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.shl (i32.load (local.get $bbtos))
                        (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
    (local.get $btos))
  (data (i32.const 136448) "\f0\14\02\00" "\06" "LSHIFT\00" "j\00\00\00")
  (elem (i32.const 0x6a) $LSHIFT)

  ;; 6.1.1810
  (func $M* (param $tos i32) (result i32)
    (local $bbtos i32)
    (i64.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i64.mul (i64.extend_i32_s (i32.load (local.get $bbtos)))
                        (i64.extend_i32_s (i32.load (i32.sub (local.get $tos) 
                                                              (i32.const 4))))))
    (local.get $tos))
  (data (i32.const 136464) "\00\15\02\00" "\02" "M*\00" "k\00\00\00")
  (elem (i32.const 0x6b) $M*)

  ;; 6.1.1870
  (func $MAX (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $v i32)
    (if (i32.lt_s (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                  (local.tee $v (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                                    (i32.const 4))))))
      (then
        (i32.store (local.get $bbtos) (local.get $v))))
    (local.get $btos))
  (data (i32.const 136476) "\10\15\02\00" "\03" "MAX" "l\00\00\00")
  (elem (i32.const 0x6c) $MAX)

  ;; 6.1.1880
  (func $MIN (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $v i32)
    (if (i32.gt_s (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                  (local.tee $v (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                                    (i32.const 4))))))
      (then
        (i32.store (local.get $bbtos) (local.get $v))))
    (local.get $btos))
  (data (i32.const 136488) "\1c\15\02\00" "\03" "MIN" "m\00\00\00")
  (elem (i32.const 0x6d) $MIN)

  ;; 6.1.1890
  (func $MOD (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.rem_s (i32.load (local.get $bbtos))
                          (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
    (local.get $btos))
  (data (i32.const 136500) "(\15\02\00" "\03" "MOD" "n\00\00\00")
  (elem (i32.const 0x6e) $MOD)

  ;; 6.1.1900
  (func $MOVE (param $tos i32) (result i32)
    (local $bbbtos i32)
    (memory.copy 
      (i32.load (i32.sub (local.get $tos) (i32.const 8)))
      (i32.load (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12))))
      (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (local.get $bbbtos))
  (data (i32.const 136512) "4\15\02\00" "\04" "MOVE\00\00\00" "o\00\00\00")
  (elem (i32.const 0x6f) $MOVE)

  ;; 6.1.1910
  (func $NEGATE (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.sub (i32.const 0) (i32.load (local.get $btos))))
    (local.get $tos))
  (data (i32.const 136528) "@\15\02\00" "\06" "NEGATE\00" "p\00\00\00")
  (elem (i32.const 0x70) $NEGATE)

  ;; 6.2.1930
  (func $NIP (param $tos i32) (result i32)
    (local.get $tos)
    (call $SWAP) (call $DROP))
  (data (i32.const 0x2184c) "\3c\18\02\00" "\03" "NIP" "\a3\00\00\00")
  (elem (i32.const 0xa3) $NIP)

  ;; 6.1.1980
  (func $OR (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.or (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 136544) "P\15\02\00" "\02" "OR\00" "q\00\00\00")
  (elem (i32.const 0x71) $OR)

  ;; 6.1.1990
  (func $OVER (param $tos i32) (result i32)
    (i32.store (local.get $tos)
                (i32.load (i32.sub (local.get $tos) (i32.const 8))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136556) "`\15\02\00" "\04" "OVER\00\00\00" "r\00\00\00")
  (elem (i32.const 0x72) $OVER)

  ;; 6.2.2030
  (func $PICK (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
      (i32.load 
        (i32.sub 
          (local.get $tos) 
          (i32.shl (i32.add (i32.load (local.get $btos)) (i32.const 2)) (i32.const 2)))))
    (local.get $tos))
  (data (i32.const 137088) "p\17\02\00" "\04" "PICK\00\00\00" "\96\00\00\00")
  (elem (i32.const 0x96) $PICK)

  ;; 6.1.2033
  (func $POSTPONE (param $tos i32) (result i32)
    (local $FINDToken i32)
    (local $FINDResult i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $readWord (i32.const 0x20))
    (if (param i32) (result i32) (i32.eqz (i32.load8_u (call $wordBase)))
      (call $fail (i32.const 0x20028))) ;; incomplete input
    (call $FIND)
    (local.set $FINDResult (call $pop))
    (if (param i32) (result i32) (i32.eqz (local.get $FINDResult)) 
      (call $failUndefinedWord))
    (local.set $FINDToken (call $pop))
    (if (param i32) (result i32) (i32.eq (local.get $FINDResult) (i32.const 1))
      (then 
        (call $compileCall (local.get $FINDToken)))
      (else
        (call $emitConst (local.get $FINDToken))
        (call $emitICall (i32.const 1) (i32.const 5 (; = COMPILE_CALL_INDEX ;))))))
  (data (i32.const 136572) "l\15\02\00" "\88" "POSTPONE\00\00\00" "s\00\00\00")
  (elem (i32.const 0x73) $POSTPONE) ;; immediate

  ;; 6.1.2050
  (func $QUIT (param $tos i32) (result i32)
    (global.set $tos (local.get $tos))
    (global.set $tors (i32.const 0x2000 (; = RETURN_STACK_BASE ;)))
    (global.set $sourceID (i32.const 0))
    (i32.store (i32.const 0x218f8 (; body(STATE) ;)) (i32.const 0))
    (unreachable))
  (data (i32.const 136592) "|\15\02\00" "\04" "QUIT\00\00\00" "t\00\00\00")
  (elem (i32.const 0x74) $QUIT)

  ;; 6.1.2060
  (func $R> (param $tos i32) (result i32)
    (global.set $tors (i32.sub (global.get $tors) (i32.const 4)))
    (i32.store (local.get $tos) (i32.load (global.get $tors)))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136608) "\90\15\02\00" "\02" "R>\00" "u\00\00\00")
  (elem (i32.const 0x75) $R>)

  ;; 6.1.2070
  (func $R@ (param $tos i32) (result i32)
    (i32.store (local.get $tos) (i32.load (i32.sub (global.get $tors) (i32.const 4))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136620) "\a0\15\02\00" "\02" "R@\00" "v\00\00\00")
  (elem (i32.const 0x76) $R@)

  ;; 6.1.2120 
  (func $RECURSE  (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileRecurse))
  (data (i32.const 136632) "\ac\15\02\00" "\87" "RECURSE" "w\00\00\00")
  (elem (i32.const 0x77) $RECURSE) ;; immediate

  ;; 6.2.2125
  (func $REFILL (param $tos i32) (result i32)
    (local $char i32)
    (global.set $inputBufferSize (i32.const 0))
    (local.get $tos)
    (if (param i32) (result i32) (i32.eq (global.get $sourceID) (i32.const -1))
      (then
        (call $push (i32.const -1))
        (return)))
    (global.set $inputBufferSize 
      (call $shell_read 
        (i32.const 0x300 (; = INPUT_BUFFER_BASE ;)) 
        (i32.const 0x700 (; = INPUT_BUFFER_SIZE ;))))
    (if (param i32) (result i32) (i32.eqz (global.get $inputBufferSize))
      (then (call $push (i32.const 0)))
      (else 
        (i32.store (i32.const 0x21908 (; body(>IN) ;)) (i32.const 0))
        (call $push (i32.const -1)))))
  (data (i32.const 137104) "\80\17\02\00" "\06" "REFILL\00" "\97\00\00\00")
  (elem (i32.const 0x97) $REFILL)

  ;; 6.1.2140
  (func $REPEAT (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileRepeat))
  (data (i32.const 136648) "\b8\15\02\00" "\86" "REPEAT\00" "x\00\00\00")
  (elem (i32.const 0x78) $REPEAT) ;; immediate

  ;; 6.1.2160 ROT 
  (func $ROT (param $tos i32) (result i32)
    (local $tmp i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $bbbtos i32)
    (local.set $tmp (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (i32.store (local.get $btos) 
      (i32.load (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12)))))
    (i32.store (local.get $bbbtos) 
      (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (i32.store (local.get $bbtos) (local.get $tmp))
    (local.get $tos))
  (data (i32.const 136664) "\c8\15\02\00" "\03" "ROT" "y\00\00\00")
  (elem (i32.const 0x79) $ROT)

  ;; 6.1.2162
  (func $RSHIFT (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.shr_u (i32.load (local.get $bbtos))
                          (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
    (local.get $btos))
  (data (i32.const 136676) "\d8\15\02\00" "\06" "RSHIFT\00" "z\00\00\00")
  (elem (i32.const 0x7a) $RSHIFT)

  ;; 6.1.2165
  (func $Sq (param $tos i32) (result i32)
    (local $c i32)
    (local $start i32)
    (local.get $tos)
    (call $ensureCompiling)
    (local.set $start (global.get $here))
    (block $endLoop (param i32) (result i32) 
      (loop $loop (param i32) (result i32) 
        (if (param i32) (result i32) (i32.lt_s (local.tee $c (call $readChar)) (i32.const 0))
          (call $fail (i32.const 0x2003C))) ;; missing closing quote
        (br_if $endLoop (i32.eq (local.get $c) (i32.const 0x22)))
        (i32.store8 (global.get $here) (local.get $c))
        (global.set $here (i32.add (global.get $here) (i32.const 1)))
        (br $loop)))
    (call $compilePushConst (local.get $start))
    (call $compilePushConst (i32.sub (global.get $here) (local.get $start)))
    (call $ALIGN))
  (data (i32.const 136692) "\e4\15\02\00" "\82" "S\22\00" "{\00\00\00")
  (elem (i32.const 0x7b) $Sq) ;; immediate

  ;; 6.1.2170
  (func $S>D (param $tos i32) (result i32)
    (local $btos i32)
    (i64.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
      (i64.extend_i32_s (i32.load (local.get $btos))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 136704) "\f4\15\02\00" "\03" "S>D" "|\00\00\00")
  (elem (i32.const 0x7c) $S>D)

  (func $SCALL (param $tos i32) (result i32)
    (global.set $tos (local.get $tos))
    (call $shell_call)
    (global.get $tos))
  (data (i32.const 0x218c4) "\ac\18\02\00" "\05" "SCALL\00\00" "\aa\00\00\00")
  (elem (i32.const 0xaa) $SCALL)

  ;; 6.1.2210
  (func $SIGN (param $tos i32) (result i32)
    (local $btos i32)
    (local $npo i32)
    (if (i32.lt_s (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))) (i32.const 0))
      (then 
        (i32.store8 (local.tee $npo (i32.sub (global.get $po) (i32.const 1))) (i32.const 0x2D (; '-' ;)))
        (global.set $po (local.get $npo))))
    (local.get $btos))
  (data (i32.const 136716) "\00\16\02\00" "\04" "SIGN\00\00\00" "}\00\00\00")
  (elem (i32.const 0x7d) $SIGN)

  ;; 6.1.2214
  ;; See e.g. https://www.nimblemachines.com/symmetric-division-considered-harmful/
  (func $SM/REM (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbbtos i32)
    (local $n1 i64)
    (local $n2 i64)
    (i32.store 
      (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12)))
      (i32.wrap_i64 
        (i64.rem_s 
          (local.tee $n1 (i64.load (local.get $bbbtos)))
          (local.tee $n2 (i64.extend_i32_s (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))))))
    (i32.store 
      (i32.sub (local.get $tos) (i32.const 8))
      (i32.wrap_i64 
        (i64.div_s (local.get $n1) (local.get $n2))))
    (local.get $btos))
  (data (i32.const 136732) "\0c\16\02\00" "\06" "SM/REM\00" "~\00\00\00")
  (elem (i32.const 0x7e) $SM/REM)

  ;; 6.1.2216
  (func $SOURCE (param $tos i32) (result i32)
    (local.get $tos)
    (call $push (global.get $inputBufferBase))
    (call $push (global.get $inputBufferSize)))
  (data (i32.const 136748) "\1c\16\02\00" "\06" "SOURCE\00" "\7f\00\00\00")
  (elem (i32.const 0x7f) $SOURCE)

  ;; 6.1.2250
  (func $SOURCE-ID (param $tos i32) (result i32)
    (call $push (local.get $tos) (global.get $sourceID)))
  (data (i32.const 137160) "\bc\17\02\00" "\09" "SOURCE-ID\00\00" "\9b\00\00\00")
  (elem (i32.const 0x9b) $SOURCE-ID)

  ;; 6.1.2220
  (func $SPACE (param $tos i32) (result i32)
    (local.get $tos)
    (call $BL) (call $EMIT))
  (data (i32.const 136764) ",\16\02\00" "\05" "SPACE\00\00" "\80\00\00\00")
  (elem (i32.const 0x80) $SPACE)

  ;; 6.1.2230
  (func $SPACES (param $tos i32) (result i32)
    (local $i i32)
    (local.get $tos)
    (local.set $i (call $pop))
    (block $endLoop (param i32) (result i32)
      (loop $loop (param i32) (result i32)
        (br_if $endLoop (i32.le_s (local.get $i) (i32.const 0)))
        (call $SPACE)
        (local.set $i (i32.sub (local.get $i) (i32.const 1)))
        (br $loop))))
  (data (i32.const 136780) "<\16\02\00" "\06" "SPACES\00" "\81\00\00\00")
  (elem (i32.const 0x81) $SPACES)

  ;; 6.1.2250
  (data (i32.const 0x218e8) "\d4\18\02\00" "\45" (; DATA ;) "STATE\00\00" "\03\00\00\00" (; = pack(PUSH_DATA_ADDRESS_INDEX) ;) "\00\00\00\00" (; = pack(0) ;))

  ;; 6.1.2260
  (func $SWAP (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $tmp i32)
    (local.set $tmp (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (i32.store (local.get $bbtos) 
                (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (i32.store (local.get $btos) (local.get $tmp))
    (local.get $tos))
  (data (i32.const 136812) "\5c\16\02\00" "\04" "SWAP\00\00\00" "\83\00\00\00")
  (elem (i32.const 0x83) $SWAP)

  ;; 6.1.2270
  (func $THEN (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileThen))
  (data (i32.const 136828) "l\16\02\00" "\84" "THEN\00\00\00" "\84\00\00\00")
  (elem (i32.const 0x84) $THEN) ;; immediate

  ;; 6.2.2295
  (func $TO (param $tos i32) (result i32)
    (local $v i32)
    (local $xt i32)
    (local.get $tos)
    (call $readWord (i32.const 0x20))
    (if (param i32) (result i32) (i32.eqz (i32.load8_u (call $wordBase)))
      (call $fail (i32.const 0x20028))) ;; incomplete input
    (call $FIND)
    (if (param i32) (result i32) (i32.eqz (call $pop)) 
      (call $failUndefinedWord))
    (local.set $xt (call $pop))
    (local.set $v (call $pop))
    (i32.store (i32.add (call $body (local.get $xt)) (i32.const 4)) (local.get $v)))
  (data (i32.const 137120) "\90\17\02\00" "\02" "TO\00" "\98\00\00\00")
  (elem (i32.const 0x98) $TO)

  ;; 6.2.2298
  (func $TRUE (param $tos i32) (result i32)
    (call $push (local.get $tos) (i32.const 0xffffffff)))
  (data (i32.const 0x2182c) "\20\18\02\00" "\04" "TRUE000" "\a1\00\00\00")
  (elem (i32.const 0xa1) $TRUE)

  ;; 6.2.2300
  (func $TUCK (param $tos i32) (result i32)
    (local.get $tos)
    (call $SWAP) (call $OVER))
  (data (i32.const 0x2190c) "\fc\18\02\00" "\04" "TUCK\00\00\00" "\a4\00\00\00")
  (elem (i32.const 0xa4) $TUCK)

  ;; 6.1.2310 TYPE 
  (func $TYPE (param $tos i32) (result i32)
    (local $p i32)
    (local $len i32)
    (local.get $tos)
    (local.set $len (call $pop))
    (local.set $p (call $pop))
    (call $type (local.get $len) (local.get $p)))
  ;; WARNING: If you change this table index, make sure the emitted ICalls are also updated
  (data (i32.const 136844) "|\16\02\00" "\04" "TYPE\00\00\00" "\85\00\00\00")
  (elem (i32.const 0x85) $TYPE) ;; none

  ;; 6.1.2320
  (func $U. (param $tos i32) (result i32)
    (local.get $tos)
    (call $U._ (call $pop) (i32.load (i32.const 0x218e4 (; = body(BASE) ;))))
    (call $shell_emit (i32.const 0x20)))
  (data (i32.const 136860) "\8c\16\02\00" "\02" "U.\00" "\86\00\00\00")
  (elem (i32.const 0x86) $U.)

  ;; 6.1.2340
  (func $U< (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_u (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                  (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (local.get $btos))
  (data (i32.const 136872) "\9c\16\02\00" "\02" "U<\00" "\87\00\00\00")
  (elem (i32.const 0x87) $U<)

  ;; 6.1.2360
  (func $UM* (param $tos i32) (result i32)
    (local $bbtos i32)
    (i64.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i64.mul (i64.extend_i32_u (i32.load (local.get $bbtos)))
                        (i64.extend_i32_u (i32.load (i32.sub (local.get $tos) 
                                                              (i32.const 4))))))
    (local.get $tos))
  (data (i32.const 136884) "\a8\16\02\00" "\03" "UM*" "\88\00\00\00")
  (elem (i32.const 0x88) $UM*)

  ;; 6.1.2370
  (func $UM/MOD (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbbtos i32)
    (local $n1 i64)
    (local $n2 i64)
    (i32.store 
      (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12)))
      (i32.wrap_i64 
        (i64.rem_u 
          (local.tee $n1 (i64.load (local.get $bbbtos)))
          (local.tee $n2 (i64.extend_i32_u (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))))))
    (i32.store 
      (i32.sub (local.get $tos) (i32.const 8))
      (i32.wrap_i64 
        (i64.div_u (local.get $n1) (local.get $n2))))
    (local.get $btos))
  (data (i32.const 136896) "\b4\16\02\00" "\06" "UM/MOD\00" "\89\00\00\00")
  (elem (i32.const 0x89) $UM/MOD) ;; TODO: Rename

  ;; 6.1.2380
  (func $UNLOOP (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $emitICall (i32.const 0) (i32.const 9 (; = END_DO_INDEX ;))))
  (data (i32.const 136912) "\c0\16\02\00" "\86" "UNLOOP\00" "\8a\00\00\00")
  (elem (i32.const 0x8a) $UNLOOP) ;; immediate

  ;; 6.1.2390
  (func $UNTIL (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileUntil))
  (data (i32.const 136928) "\d0\16\02\00" "\85" "UNTIL\00\00" "\8b\00\00\00")
  (elem (i32.const 0x8b) $UNTIL) ;; immediate

  ;; 6.1.2395
  (func $UNUSED (param $tos i32) (result i32)
    (local.get $tos)
    (call $push (i32.shr_s (i32.sub (i32.const 104857600 (; = MEMORY_SIZE ;)) (global.get $here)) (i32.const 2))))
  (data (i32.const 137132) "\a0\17\02\00" "\06" "UNUSED\00" "\99\00\00\00")
  (elem (i32.const 0x99) $UNUSED)

  (func $UWIDTH (param $tos i32) (result i32)
    (local $v i32)
    (local $r i32)
    (local $base i32)
    (local.get $tos)
    (local.set $v (call $pop))
    (local.set $base (i32.load (i32.const 0x218e4 (; = body(BASE) ;))))
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
  (data (i32.const 0x21874) "\64\18\02\00" "\05" "VALUE00" "\4c\00\00\00" (; = pack(CONSTANT_INDEX) ;))

  ;; 6.1.2410
  (func $VARIABLE (param $tos i32) (result i32)
    (local.get $tos)
    (call $CREATE)
    (global.set $here (i32.add (global.get $here) (i32.const 4))))
  (data (i32.const 136944) "\e0\16\02\00" "\08" "VARIABLE\00\00\00" "\8c\00\00\00")
  (elem (i32.const 0x8c) $VARIABLE)

  ;; 6.1.2430
  (func $WHILE (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileWhile))
  (data (i32.const 136964) "\f0\16\02\00" "\85" "WHILE\00\00" "\8d\00\00\00")
  (elem (i32.const 0x8d) $WHILE) ;; immediate

  ;; 6.1.2450
  (func $WORD (param $tos i32) (result i32)
    (local.get $tos)
    (call $readWord (call $pop)))
  (data (i32.const 136980) "\04\17\02\00" "\04" "WORD\00\00\00" "\8e\00\00\00")
  (elem (i32.const 0x8e) $WORD)

  ;; 15.6.1.2465
  (func $WORDS (param $tos i32) (result i32)
    (local $entryP i32)
    (local $entryLF i32)
    (local $entryL i32)
    (local $p i32)
    (local $pe i32)
    (local.set $entryP (global.get $latest))
    (loop $loop
      (local.set $entryLF (i32.load (i32.add (local.get $entryP) (i32.const 4))))
      (if (i32.eqz (i32.and (local.get $entryLF) (i32.const 0x20 (; = F_HIDDEN ;))))
        (then
          (call $type  
            (i32.and (local.get $entryLF) (i32.const 0x1F (; = LENGTH_MASK ;)))
            (i32.add (local.get $entryP) (i32.const 5)))
          (call $shell_emit (i32.const 0x20))))
      (local.set $entryP (i32.load (local.get $entryP)))
      (br_if $loop (local.get $entryP)))
    (local.get $tos))
  (data (i32.const 0x2189c) "\90\18\02\00" "\05" "WORDS00" "\a8\00\00\00")
  (elem (i32.const 0xa8) $WORDS)

  ;; 6.1.2490
  (func $XOR (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.xor (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 136996) "\14\17\02\00" "\03" "XOR" "\8f\00\00\00")
  (elem (i32.const 0x8f) $XOR)

  ;; 6.1.2500
  (func $left-bracket (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (i32.store (i32.const 0x218f8 (; body(STATE) ;)) (i32.const 0)))
  (data (i32.const 137008) "$\17\02\00" "\81" "[\00\00" "\90\00\00\00")
  (elem (i32.const 0x90) $left-bracket) ;; immediate

  ;; 6.1.2510
  (func $bracket-tick (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $')
    (call $compilePushConst (call $pop)))
  (data (i32.const 137020) "0\17\02\00" "\83" "[']" "\91\00\00\00")
  (elem (i32.const 0x91) $bracket-tick) ;; immediate

  ;; 6.1.2520
  (func $bracket-char (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $CHAR)
    (call $compilePushConst (call $pop)))
  (data (i32.const 137032) "<\17\02\00" "\86" "[CHAR]\00" "\92\00\00\00")
  (elem (i32.const 0x92) $bracket-char) ;; immediate

  ;; 6.2.2535
  (func $\ (param $tos i32) (result i32)
    (local $char i32)
    (block $endSkipComments
      (loop $skipComments
        (local.set $char (call $readChar))
        (br_if $endSkipComments (i32.eq (local.get $char) 
                                        (i32.const 0x0a (; '\n' ;))))
        (br_if $endSkipComments (i32.eq (local.get $char) (i32.const -1)))
        (br $skipComments)))
    (local.get $tos))
  (data (i32.const 137148) "\ac\17\02\00" "\81" "\5c\00\00" "\9a\00\00\00")
  (elem (i32.const 0x9a) $\) ;; immediate

  ;; 6.1.2540
  (func $right-bracket (param $tos i32) (result i32)
    (i32.store (i32.const 0x218f8 (; body(STATE) ;)) (i32.const 1))
    (local.get $tos))
  (data (i32.const 137048) "H\17\02\00" "\01" "]\00\00" "\93\00\00\00")
  (elem (i32.const 0x93) $right-bracket)

  (data (i32.const 135820) "\80\12\02\00" "\26" (; HIDDEN ;) "UNDEFIN" "A\00\00\00")
  (data (i32.const 136796) "L\16\02\00" "\26" (; HIDDEN ;) "UNDEFIN" "\82\00\00\00")
  (data (i32.const 137180) "\c8\17\02\00" "\24" (; HIDDEN ;) "UNDEFIN" "\9c\00\00\00")
  (data (i32.const 137196) "\dc\17\02\00" "\22" (; HIDDEN ;) "UND" "\9d\00\00\00")
  (data (i32.const 0x21858) "\4c\18\02\00" "\23" (; HIDDEN ;) "UND" "\a4\00\00\00")
  (data (i32.const 136164) "\d4\13\02\00" "\2b" (; HIDDEN ;) "UNDEFINED__" "X\00\00\00")
  (data (i32.const 137224) "\f8\17\02\00" "\2c" (; HIDDEN ;) "UNDEFINED___\00\00\00" "\9f\00\00\00")
  (data (i32.const 135632) "\c0\11\02\00" "\23" (; HIDDEN;) "UND" "4\00\00\00")

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Interpreter
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; Interprets the string in the input, until the end of string is reached.
  ;; Returns 0 if processed, 1 if still compiling, or traps if a word 
  ;; was not found.
  (func $interpret (param $tos i32) (result i32) (result i32)
    (local $FINDResult i32)
    (local $FINDToken i32)
    (local $error i32)
    (local $number i32)
    (local.set $error (i32.const 0))
    (global.set $tors (i32.const 0x2000 (; = RETURN_STACK_BASE ;)))
    (local.get $tos)
    (block $endLoop (param i32) (result i32) 
      (loop $loop (param i32) (result i32) 
        (call $readWord (i32.const 0x20))
        (br_if $endLoop (i32.eqz (i32.load8_u (call $wordBase))))
        (call $FIND)
        (local.set $FINDResult (call $pop))
        (local.set $FINDToken (call $pop))
        (if (param i32) (result i32) (i32.eqz (local.get $FINDResult))
          (then ;; Not in the dictionary. Is it a number?
            (if (param i32 i32) (result i32) (i32.eqz (call $readNumber))
              (then ;; It's a number. Are we compiling?
                (local.set $number)
                (if (param i32) (result i32) (i32.load (i32.const 0x218f8 (; = body(STATE) ;)))
                  (then
                    ;; We're compiling. Pop it off the stack and 
                    ;; add it to the compiled list
                    (call $compilePushConst (local.get $number)))
                  (else 
                    ;; We're not compiling. Put the number on the stack.
                    (call $push (local.get $number)))))
              (else ;; It's not a number.
                (drop)
                (call $failUndefinedWord)))) ;; undefined word
          (else ;; Found the word. 
            ;; Are we compiling or is it immediate?
            (if (param i32) (result i32) (i32.or (i32.eqz (i32.load (i32.const 0x218f8 (; body(STATE) ;))))
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
    (i32.load (i32.const 0x218f8 (; = body(STATE) ;))))

  (func $readWord (param $tos i32) (param $delimiter i32) (result i32)
    (local $char i32)
    (local $stringPtr i32)
    (local $wordBase i32)

    ;; Skip leading delimiters
    (block $endSkipBlanks
      (loop $skipBlanks
        (local.set $char (call $readChar))
        (br_if $skipBlanks (i32.eq (local.get $char) (local.get $delimiter)))
        (br_if $skipBlanks (i32.eq (local.get $char) (i32.const 0x0a (; ' ' ;))))
        (br $endSkipBlanks)))

    (local.set $stringPtr (i32.add (local.tee $wordBase (call $wordBase)) (i32.const 1)))
    (if (i32.ne (local.get $char) (i32.const -1)) 
      (if (i32.ne (local.get $char) (i32.const 0x0a))
        (then 
          ;; Search for delimiter
          (i32.store8 (i32.add (local.get $wordBase) (i32.const 1)) (local.get $char))
          (local.set $stringPtr (i32.add (local.get $wordBase) (i32.const 2)))
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
      (i32.store8 (local.get $wordBase)
        (i32.sub (local.get $stringPtr) (i32.add (local.get $wordBase) (i32.const 1))))
      
      (local.get $tos)
      (call $push (local.get $wordBase)))

  (func $readNumber (result i32 i32)
    (local $length i32)
    (local $restcount i32)
    (local $value i32)
    (if (i32.eqz (local.tee $length (i32.load8_u (call $wordBase))))
      (return (i32.const -1) (i32.const -1)))
    (call $number (i64.const 0) (i32.add (call $wordBase) (i32.const 1)) (local.get $length))
    (local.set $restcount)
    (drop)
    (i32.wrap_i64)
    (local.get $restcount))

  ;; Parse a number
  ;; Returns (number, unparsed start address, unparsed length)
  (func $number (param $value i64) (param $addr i32) (param $length i32) (result i64 i32 i32)
    (local $p i32)
    (local $sign i64)
    (local $char i32)
    (local $base i32)
    (local $end i32)
    (local $n i32)  
    (local.set $p (local.get $addr))
    (local.set $end (i32.add (local.get $p) (local.get $length)))  
    (local.set $base (i32.load (i32.const 0x218e4 (; = body(BASE) ;))))

    ;; Read first character
    (if (i32.eq (local.tee $char (i32.load8_u (local.get $p))) (i32.const 0x2d (; '-' ;)))
      (then 
        (local.set $sign (i64.const -1))
        (local.set $char (i32.const 48 (; '0' ;) ))
        (if (i32.eq (local.get $length) (i32.const 1))
          (then
            (return (local.get $value) (local.get $p) (local.get $length)))))
      (else 
        (local.set $sign (i64.const 1))))

    ;; Read all characters
    (block $endLoop
      (loop $loop
        (if (i32.lt_s (local.get $char) (i32.const 48 (; '0' ;) ))
          (br $endLoop))      
        (if (i32.le_s (local.get $char) (i32.const 57 (; '9' ;) ))
          (then 
            (local.set $n (i32.sub (local.get $char) (i32.const 48))))
          (else
            (if (i32.lt_s (local.get $char) (i32.const 65 (; 'A' ;) ))
              (br $endLoop))
            (local.set $n (i32.sub (local.get $char) (i32.const 55)))))
        (if (i32.ge_s (local.get $n) (local.get $base))
          (br $endLoop))
        (local.set $value 
          (i64.add 
            (i64.mul (local.get $value) (i64.extend_i32_u (local.get $base)))
            (i64.extend_i32_u (local.get $n))))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br_if $endLoop (i32.eq (local.get $p) (local.get $end)))
        (local.set $char (i32.load8_s (local.get $p)))
        (br $loop)))

    (i64.mul (local.get $sign) (local.get $value))
    (local.get $p) 
    (i32.sub (local.get $end) (local.get $p)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Interpreter state
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; Top of stack
  (global $tos (mut i32) (i32.const 0x10000 (; = STACK_BASE ;)))

  ;; Top of return stack
  (global $tors (mut i32) (i32.const 0x2000 (; = RETURN_STACK_BASE ;)))

  ;; Input buffer
  (global $inputBufferBase (mut i32) (i32.const 0x300 (; = INPUT_BUFFER_BASE ;)))
  (global $inputBufferSize (mut i32) (i32.const 0))

  ;; Source ID
  (global $sourceID (mut i32) (i32.const 0))

  ;; Dictionary pointers
  (global $latest (mut i32) (i32.const 0x2190c))
  (global $here (mut i32) (i32.const 0x2191c))
  (global $nextTableIndex (mut i32) (i32.const 0xab (; = NEXT_TABLE_INDEX ;)))

  ;; Pictured output pointer
  (global $po (mut i32) (i32.const -1))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Compiler functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; Initializes compilation.
  ;; Parameter indicates the type of code we're compiling: type 0 (no params), 
  ;; or type 1 (1 param)
  (func $startColon (param $type i32)
    (i32.store8 (i32.const 0x1041 (; = MODULE_HEADER_FUNCTION_TYPE_BASE ;)) (local.get $type))
    (global.set $cp (i32.const 0x1060 (; = MODULE_BODY_BASE ;)))
    (global.set $firstTemporaryLocal (i32.add (local.get $type) (i32.const 1)))
    ;; 1 temporary local for computations
    (global.set $currentLocal (global.get $firstTemporaryLocal))
    (global.set $lastLocal (global.get $currentLocal))
    (global.set $branchNesting (i32.const 0))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $endColon
    (local $bodySize i32)
    (local $nameLength i32)

    (call $emitEnd)

    ;; Update code size
    (local.set $bodySize (i32.sub (global.get $cp) (i32.const 0x1000 (; = MODULE_HEADER_BASE ;)))) 
    (i32.store 
      (i32.const 0x104f (; = MODULE_HEADER_CODE_SIZE_BASE ;))
      (call $leb128-4p
          (i32.sub (local.get $bodySize) 
                  (i32.const 0x53 (; = MODULE_HEADER_CODE_SIZE_OFFSET_PLUS_4 ;)))))

    ;; Update body size
    (i32.store 
      (i32.const 0x1054 (; = MODULE_HEADER_BODY_SIZE_BASE ;))
      (call $leb128-4p
          (i32.sub (local.get $bodySize) 
                  (i32.const 0x58 (; = MODULE_HEADER_BODY_SIZE_OFFSET_PLUS_4 ;)))))

    ;; Update #locals
    (i32.store 
      (i32.const 0x1059 (; = MODULE_HEADER_LOCAL_COUNT_BASE ;))
      (call $leb128-4p 
        (i32.add
          (i32.sub 
            (global.get $lastLocal) 
            (global.get $firstTemporaryLocal))
          (i32.const 1))))

    ;; Update table offset
    (i32.store 
      (i32.const 0x1047 (; = MODULE_HEADER_TABLE_INDEX_BASE ;))
      (call $leb128-4p (global.get $nextTableIndex)))
    ;; Also store the initial table size to satisfy other tools (e.g. wasm-as)
    (i32.store 
      (i32.const 0x102c (; = MODULE_HEADER_TABLE_INITIAL_SIZE_BASE ;))
      (call $leb128-4p (i32.add (global.get $nextTableIndex) (i32.const 1))))

    ;; Write a name section (if we're ending the code for the current dictionary entry)
    (if (i32.eq (i32.load (call $body (global.get $latest)))
                (global.get $nextTableIndex))
      (then
        (local.set $nameLength (i32.and (i32.load8_u (i32.add (global.get $latest) (i32.const 4)))
                                        (i32.const 0x1F (; = LENGTH_MASK ;))))
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
        (memory.copy 
          (global.get $cp)
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
        (memory.copy 
          (global.get $cp)
          (i32.add (global.get $latest) (i32.const 5))
          (local.get $nameLength))
        (global.set $cp (i32.add (global.get $cp) (local.get $nameLength)))))

    ;; Load the code
    (if (i32.ge_u (global.get $nextTableIndex) (table.size 0))
      (then (drop (table.grow 0 (ref.func $!) (table.size 0))))) ;; Double size
    (call $shell_load 
      (i32.const 0x1000 (; = MODULE_HEADER_BASE ;)) 
      (i32.sub (global.get $cp) (i32.const 0x1000 (; = MODULE_HEADER_BASE ;))))

    (global.set $nextTableIndex (i32.add (global.get $nextTableIndex) (i32.const 1))))

  (func $compilePushConst (param $n i32)
    (call $emitSetLocal (i32.const 0)) ;; Save tos currently on operand stack
    (call $emitGetLocal (i32.const 0)) ;; Put tos on operand stack again
    (call $emitConst (local.get $n))
    (call $compilePush))

  (func $compilePushLocal (param $n i32)
    (call $emitSetLocal (i32.const 0)) ;; Save tos currently on operand stack
    (call $emitGetLocal (i32.const 0)) ;; Put tos on operand stack again
    (call $emitGetLocal (local.get $n))
    (call $compilePush))

  (func $compilePush
    (call $emitStore)
    (call $emitGetLocal (i32.const 0)) ;; Put $tos+4 on operand stack
    (call $emitConst (i32.const 4))
    (call $emitAdd))

  (func $compileIf
    (call $compilePop)
    (call $emitConst (i32.const 0))
    (call $emitNotEqual)
    (call $emitIf)
    (global.set $branchNesting (i32.add (global.get $branchNesting) (i32.const 1))))

  (func $compileThen (param $tos i32) (result i32)
    (global.set $branchNesting (i32.sub (global.get $branchNesting) (i32.const 1)))
    (call $emitEnd)
    (call $compileEndDests (local.get $tos)))

  (func $compileDo (param $tos i32) (result i32)
    ;; 1: $diff_i = end index - current index
    ;; 2: $end_i
    (global.set $currentLocal (i32.add (global.get $currentLocal) (i32.const 2)))
    (if (i32.gt_s (global.get $currentLocal) (global.get $lastLocal))
      (then
        (global.set $lastLocal (global.get $currentLocal))))

    ;; Save branch nesting
    (i32.store (local.get $tos) (global.get $branchNesting))
    (local.set $tos (i32.add (local.get $tos) (i32.const 4)))
    (global.set $branchNesting (i32.const 0))

    ;; $1 = current index (temporary)
    (call $compilePop)
    (call $emitSetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    ;; $end_i = end index
    (call $compilePop)
    (call $emitSetLocal (global.get $currentLocal))

    ;; startDo $1
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitICall (i32.const 1) (i32.const 1 (; = START_DO_INDEX ;)))
    
    ;; $diff = $1 - $end_i
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitGetLocal (global.get $currentLocal))
    (call $emitSub)
    (call $emitSetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))

    (call $emitBlock)
    (call $emitLoop)
    (local.get $tos))

  (func $compileLoop (param $tos i32) (result i32)
    ;; $diff = $diff + 1
    (call $emitConst (i32.const 1))
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitAdd)
    (call $emitTeeLocal (i32.sub (global.get $currentLocal) (i32.const 1)))

    ;; updateDo $diff + $end_i
    (call $emitGetLocal (global.get $currentLocal))
    (call $emitAdd)
    (call $emitICall (i32.const 1) (i32.const 2 (; = UPDATE_DO_INDEX ;)))
    
    ;; loop if $diff != 0
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitConst (i32.const 0))
    (call $emitNotEqual)
    (call $emitBrIf (i32.const 0))

    (call $compileLoopEnd (local.get $tos)))

  (func $compilePlusLoop (param $tos i32) (result i32)
    ;; temporarily store old diff 
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitSetLocal (global.get $firstTemporaryLocal))

    ;; $diff = $diff + $n
    (call $compilePop)
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitAdd)
    (call $emitTeeLocal (i32.sub (global.get $currentLocal) (i32.const 1)))

    ;; updateDo $diff + $end_i
    (call $emitGetLocal (global.get $currentLocal))
    (call $emitAdd)
    (call $emitICall (i32.const 1) (i32.const 2 (; = UPDATE_DO_INDEX ;)))

    ;; compare signs to see if limit crossed
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitGetLocal (global.get $firstTemporaryLocal))
    (call $emitXOR)
    (call $emitConst (i32.const 0))
    (call $emitGreaterEqualSigned)
    (call $emitBrIf (i32.const 0))
    
    (call $compileLoopEnd (local.get $tos)))

  ;; Assumes increment is on the operand stack
  (func $compileLoopEnd (param $tos i32) (result i32)
    (local $btos i32)
    (call $emitICall (i32.const 0) (i32.const 9 (; = END_DO_INDEX ;)))
    (call $emitEnd)
    (call $emitEnd)
    (global.set $currentLocal (i32.sub (global.get $currentLocal) (i32.const 2)))

    ;; Restore branch nesting
    (global.set $branchNesting (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (local.get $btos))

  (func $compileLeave
    (call $emitICall (i32.const 0) (i32.const 9 (; = END_DO_INDEX ;)))
    (call $emitBr (i32.add (global.get $branchNesting) (i32.const 1))))

  (func $compileBegin (param $tos i32) (result i32)
    (call $emitLoop)
    (global.set $branchNesting (i32.add (global.get $branchNesting) (i32.const 1)))
    (i32.store (local.get $tos) (i32.or (global.get $branchNesting) (i32.const 0x80000000 (; dest bit ;))))
    (i32.add (local.get $tos) (i32.const 4)))

  (func $compileWhile
    (call $compileIf))

  (func $compileRepeat (param $tos i32) (result i32)
    (call $emitBr 
      (i32.sub 
        (global.get $branchNesting)
        (i32.and 
          (i32.load (i32.sub (local.get $tos) (i32.const 4)))
          (i32.const 0x7FFFFFFF))))
    (call $emitEnd)
    (global.set $branchNesting (i32.sub (global.get $branchNesting) (i32.const 1)))
    (call $compileEndDests (local.get $tos)))

  (func $compileUntil (param $tos i32) (result i32)
    (call $compilePop)
    (call $emitEqualsZero)
    (call $emitBrIf (i32.const 0))
    (call $compileEndDests (local.get $tos)))

  (func $compileEndDests (param $tos i32) (result i32)
    (local $btos i32)
    (block $endLoop
      (loop $loop
        (br_if $endLoop 
          (i32.or
            (i32.le_u (local.get $tos) (i32.const 0x10000 (; = STACK_BASE ;)))
            (i32.ne 
              (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
              (i32.or (global.get $branchNesting) (i32.const 0x80000000 (; dest bit ;))))))
        (call $emitEnd)
        (global.set $branchNesting (i32.sub (global.get $branchNesting) (i32.const 1)))
        (local.set $tos (local.get $btos))))
    (local.get $tos))

  (func $compileRecurse
    ;; call 0
    (i32.store8 (global.get $cp) (i32.const 0x10))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x00))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $compilePop
    (call $emitConst (i32.const 4))
    (call $emitSub)
    (call $emitTeeLocal (i32.const 0))
    (call $emitGetLocal (i32.const 0))
    (call $emitLoad))
    
  (func $compileCall (param $tos i32) (param $FINDToken i32) (result i32)
    (local $body i32)
    (local.set $body (call $body (local.get $FINDToken)))
    (if (i32.and (i32.load (i32.add (local.get $FINDToken) (i32.const 4)))
                  (i32.const 0x40 (; = F_DATA ;)))
      (then
        (call $emitConst (i32.add (local.get $body) (i32.const 4)))
        (call $emitICall (i32.const 1) (i32.load (local.get $body))))
      (else
        (call $emitICall (i32.const 0) (i32.load (local.get $body)))))
    (local.get $tos))
  (elem (i32.const 5 (; = COMPILE_CALL_INDEX ;)) $compileCall)

  (func $emitICall (param $type i32) (param $n i32)
    (call $emitConst (local.get $n))

    (i32.store8 (global.get $cp) (i32.const 0x11))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (local.get $type))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x00))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitBlock
    (i32.store8 (global.get $cp) (i32.const 0x02))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x00)) ;; Block type
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitLoop
    (i32.store8 (global.get $cp) (i32.const 0x03))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x00)) ;; Block type
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitConst (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x41))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $cp (call $leb128 (global.get $cp) (local.get $n)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitIf
    (i32.store8 (global.get $cp) (i32.const 0x04))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x00)) ;; Block type
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitElse
    (i32.store8 (global.get $cp) (i32.const 0x05))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitEnd
    (i32.store8 (global.get $cp) (i32.const 0x0b))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitBr (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x0c))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (local.get $n))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitBrIf (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x0d))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (local.get $n))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitSetLocal (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x21))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $cp (call $leb128 (global.get $cp) (local.get $n)))
    (global.set $lastEmitWasGetTOS (i32.eqz (local.get $n))))

  (func $emitGetLocal (param $n i32)
    (if (i32.or (i32.ne (local.get $n) (i32.const 0)) (i32.eqz (global.get $lastEmitWasGetTOS)))
      (then
        (i32.store8 (global.get $cp) (i32.const 0x20))
        (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
        (global.set $cp (call $leb128 (global.get $cp) (local.get $n))))
      (else
        ;; In case we have a TOS get after a TOS set, replace the previous one with tee.
        ;; Doesn't seem to have much of a performance impact, but this makes the code a little bit shorter, 
        ;; and easier to step through.
        (i32.store8 (i32.sub (global.get $cp) (i32.const 2)) (i32.const 0x22))))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitTeeLocal (param $n i32)
    (i32.store8 (global.get $cp) (i32.const 0x22))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $cp (call $leb128 (global.get $cp) (local.get $n)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitAdd
    (i32.store8 (global.get $cp) (i32.const 0x6a))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitSub
    (i32.store8 (global.get $cp) (i32.const 0x6b))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitXOR
    (i32.store8 (global.get $cp) (i32.const 0x73))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1))))

  (func $emitEqualsZero
    (i32.store8 (global.get $cp) (i32.const 0x45))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitNotEqual
    (i32.store8 (global.get $cp) (i32.const 0x47))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitGreaterEqualSigned
    (i32.store8 (global.get $cp) (i32.const 0x4e))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitLesserSigned
    (i32.store8 (global.get $cp) (i32.const 0x48))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitReturn
    (i32.store8 (global.get $cp) (i32.const 0x0f))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitStore
    (i32.store8 (global.get $cp) (i32.const 0x36))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x02)) ;; Alignment
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x00)) ;; Offset
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  (func $emitLoad
    (i32.store8 (global.get $cp) (i32.const 0x28))
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x02)) ;; Alignment
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (i32.store8 (global.get $cp) (i32.const 0x00)) ;; Offset
    (global.set $cp (i32.add (global.get $cp) (i32.const 1)))
    (global.set $lastEmitWasGetTOS (i32.const 0)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Compilation state
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (global $currentLocal (mut i32) (i32.const 0))
  (global $lastLocal (mut i32) (i32.const -1))
  (global $firstTemporaryLocal (mut i32) (i32.const 0))
  (global $branchNesting (mut i32) (i32.const -1))
  (global $lastEmitWasGetTOS (mut i32) (i32.const 0))

  ;; Compilation pointer
  (global $cp (mut i32) (i32.const 0x1060 (; = MODULE_BODY_BASE ;)))


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Word helper functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $startDo (param $tos i32) (param $i i32) (result i32)
    (i32.store (global.get $tors) (local.get $i))
    (global.set $tors (i32.add (global.get $tors) (i32.const 4)))
    (local.get $tos))
  (elem (i32.const 1 (; = START_DO_INDEX ;)) $startDo)

  (func $endDo (param $tos i32) (result i32)
    (global.set $tors (i32.sub (global.get $tors) (i32.const 4)))
    (local.get $tos))
  (elem (i32.const 9 (; = END_DO_INDEX ;)) $endDo)

  (func $updateDo (param $tos i32) (param $i i32) (result i32)
    (i32.store (i32.sub (global.get $tors) (i32.const 4)) (local.get $i))
    (local.get $tos))
  (elem (i32.const 2 (; = UPDATE_DO_INDEX ;)) $updateDo)

  (func $pushDataAddress (param $tos i32) (param $d i32) (result i32)
    (call $push (local.get $tos) (local.get $d)))
  (elem (i32.const 3 (; = PUSH_DATA_ADDRESS_INDEX ;)) $pushDataAddress)

  (func $setLatestBody (param $tos i32) (param $v i32) (result i32)
    (i32.store (call $body (local.get $tos) (global.get $latest)) (local.get $v)))
  (elem (i32.const 4 (; = SET_LATEST_BODY_INDEX ;)) $setLatestBody)

  (func $pushIndirect (param $tos i32) (param $v i32) (result i32)
    (call $push (local.get $tos) (i32.load (local.get $v))))
  (elem (i32.const 6 (; = PUSH_INDIRECT_INDEX ;)) $pushIndirect)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Helper functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $push (param $tos i32) (param $v i32) (result i32)
    (i32.store (local.get $tos) (local.get $v))
    (i32.add (local.get $tos) (i32.const 4)))

  (func $pop (param $tos i32) (result i32) (result i32)
    (local.tee $tos (i32.sub (local.get $tos) (i32.const 4)))
    (i32.load (local.get $tos)))

  ;; Returns 1 if equal, 0 if not
  (func $stringEqual (param $addr1 i32) (param $len1 i32) (param $addr2 i32) (param $len2 i32) (result i32)
    (local $end1 i32)
    (local $end2 i32)
    (if (i32.ne (local.get $len1) (local.get $len2))
      (return (i32.const 0)))
    (local.set $end1 (i32.add (local.get $addr1) (local.get $len1)))
    (local.set $end2 (i32.add (local.get $addr2) (local.get $len2)))
    (loop $loop (result i32)
      (if (i32.eq (local.get $addr1) (local.get $end1)) 
        (return (i32.const 1)))
      (if (i32.ne (i32.load8_s (local.get $addr1)) (i32.load8_s (local.get $addr2)))
        (return (i32.const 0)))
      (local.set $addr1 (i32.add (local.get $addr1) (i32.const 1)))
      (local.set $addr2 (i32.add (local.get $addr2)(i32.const 1)))
      (br $loop)))

  (func $fail (param $tos i32) (param $str i32) (result i32)
    (call $type 
      (i32.load8_u (local.get $str))
      (i32.add (local.get $str) (i32.const 1)))
    (call $shell_emit (i32.const 10))
    (call $ABORT (local.get $tos)))
  
  (func $type (param $len i32) (param $p i32)
    (local $end i32)
    (local.set $end (i32.add (local.get $p) (local.get $len)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eq (local.get $p) (local.get $end)))
        (call $shell_emit (i32.load8_u (local.get $p)))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br $loop))))

  (func $failUndefinedWord (param $tos i32) (result i32)
    (local $wordBase i32)
    (call $type (i32.load8_u (i32.const 0x20000)) (i32.const 0x20001))
    (call $shell_emit (i32.const 0x3a))
    (call $shell_emit (i32.const 0x20))
    (call $type 
      (i32.load8_u (local.tee $wordBase (call $wordBase)))
      (i32.add (local.get $wordBase) (i32.const 1)))
    (call $shell_emit (i32.const 0x0a))
    (call $ABORT (local.get $tos)))

  (func $setFlag (param $v i32)
    (i32.store 
      (i32.add (global.get $latest) (i32.const 4))
      (i32.or 
        (i32.load (i32.add (global.get $latest) (i32.const 4)))
        (local.get $v))))

  (func $ensureCompiling (param $tos i32) (result i32)
    (local.get $tos) 
    (if (param i32) (result i32) (i32.eqz (i32.load (i32.const 0x218f8 (; = body(STATE) ;))))
      (call $fail (i32.const 0x2005C)))) ;; word not interpretable

  ;; Toggle the hidden flag
  (func $hidden
    (i32.store 
      (i32.add (global.get $latest) (i32.const 4))
      (i32.xor 
        (i32.load (i32.add (global.get $latest) (i32.const 4)))
        (i32.const 0x20 (; = F_HIDDEN ;)))))

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
    (loop $loop
      (local.set $byte (i32.and (i32.const 0x7F) (local.get $value)))
      (local.set $value (i32.shr_s (local.get $value) (i32.const 7)))
      (if (i32.or (i32.and (i32.eqz (local.get $value)) 
                            (i32.eqz (i32.and (local.get $byte) (i32.const 0x40))))
                  (i32.and (i32.eq (local.get $value) (i32.const -1))
                            (i32.eq (i32.and (local.get $byte) (i32.const 0x40))
                                    (i32.const 0x40))))
        (then
          (local.set $more (i32.const 0)))
        (else
          (local.set $byte (i32.or (local.get $byte) (i32.const 0x80)))))
      (i32.store8 (local.get $p) (local.get $byte))
      (local.set $p (i32.add (local.get $p) (i32.const 1)))
      (br_if $loop (local.get $more)))
    (local.get $p))

  (func $body (param $xt i32) (result i32)
    (i32.and
      (i32.add
        (i32.add 
          (local.get $xt)
          (i32.and
            (i32.load8_u (i32.add (local.get $xt) (i32.const 4)))
            (i32.const 0x1F (; = LENGTH_MASK ;))))
        (i32.const 8 (; 4 + 1 + 3 ;)))
      (i32.const -4)))

  (func $readChar (result i32)
    (local $n i32)
    (local $in i32)
    (if (result i32) (i32.ge_u (local.tee $in (i32.load (i32.const 0x21908 (; body(>IN) ;))))
                  (global.get $inputBufferSize))
      (then
        (i32.const -1))
      (else
        (local.set $n (i32.load8_s (i32.add (global.get $inputBufferBase) (local.get $in))))
        (i32.store (i32.const 0x21908 (; body(>IN) ;)) (i32.add (local.get $in) (i32.const 1)))
        (local.get $n))))

    (func $numberToChar (param $v i32) (result i32)
      (if (result i32) (i32.ge_u (local.get $v) (i32.const 10))
        (then
          (i32.add (local.get $v) (i32.const 0x37)))
        (else
          (i32.add (local.get $v) (i32.const 0x30)))))
  
  (func $wordBase (result i32)
    (i32.add (global.get $here) (i32.const 0x200 (; = WORD_OFFSET ;))))

  (func $U._ (param $v i32) (param $base i32)
    (local $m i32)
    (local.set $m (i32.rem_u (local.get $v) (local.get $base)))
    (local.set $v (i32.div_u (local.get $v) (local.get $base)))
    (if (i32.eqz (local.get $v))
      (then)
      (else (call $U._ (local.get $v) (local.get $base))))
    (call $shell_emit (call $numberToChar (local.get $m))))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; API Functions
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
  (func (export "tos") (result i32)
    (global.get $tos))
  
  (func (export "here") (result i32)
    (global.get $here))

  (func (export "interpret") (param $silent i32) (result i32)
    (local $result i32)
    (local $tos i32)
    (local.tee $tos (global.get $tos))
    (block $endLoop (param i32) (result i32)
      (loop $loop (param i32) (result i32)
        (call $REFILL)
        (br_if $endLoop (i32.eqz (call $pop)))
        (local.set $result (call $interpret))
        (local.set $tos)

        ;; Check for stack underflow
        (if (i32.lt_s (local.get $tos) (i32.const 0x10000 (; = STACK_BASE ;)))
          (drop (call $fail (local.get $tos) (i32.const 0x200B2 (; stack empty ;)))))

        ;; Show prompt
        (if (i32.eqz (local.get $silent))
          (then
            (if (i32.ge_s (local.get $result) (i32.const 0))
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
            (call $shell_emit (i32.const 10))))
        (local.get $tos)
        (br $loop)))
      (global.set $tos)
      (local.get $result))

  (func (export "push") (param $v i32)
    (global.set $tos (call $push (global.get $tos) (local.get $v))))

  (func (export "pop") (result i32)
    (local $result i32)
    (local.set $result (call $pop (global.get $tos)))
    (global.set $tos)
    (local.get $result))

  ;; Used for experiments
  (func (export "set_state") (param $latest i32) (param $here i32)
    (global.set $latest (local.get $latest))
    (global.set $here (local.get $here)))
)
