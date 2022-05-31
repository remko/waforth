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
  (table (export "table") 0xa8 funcref)


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Data
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;;
  ;; Memory size:
  ;;   MEMORY_SIZE       := 104857600   (100*1024*1024)
  ;;   MEMORY_SIZE_PAGES :=      1600   (MEMORY_SIZE / 65536)
  ;;
  ;; Memory layout:
  ;;   INPUT_BUFFER_BASE  :=     0x0
  ;;   INPUT_BUFFER_SIZE  :=  0x1000
  ;;   (Compiled modules are limited to 4096 bytes until Chrome refuses to load them synchronously)
  ;;   MODULE_HEADER_BASE :=  0x1000 
  ;;   RETURN_STACK_BASE  :=  0x2000
  ;;   STACK_BASE         := 0x10000
  ;;   DATA_SPACE_BASE    := 0x20000
  ;;
  ;; Transient regions, offset from HERE:
  ;;   PICTURED_OUTPUT_OFFSET := 0x200 (filled backward)
  ;;   WORD_OFFSET            := 0x200 
  ;;   PAD_OFFSET             := 0x304 (WORD_OFSET + 1 + 0xFF)
  ;;
  (memory (export "memory") 0x640 (; = MEMORY_SIZE_PAGES ;))

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
  (data (i32.const 0x2000f) "\0d" "division by 0")
  (data (i32.const 0x2001d) "\10" "incomplete input")
  (data (i32.const 0x2002e) "\24" "word not supported in interpret mode")
  (data (i32.const 0x20053) "\0f" "not implemented")
  (data (i32.const 0x20063) "\11" "ADDRESS-UNIT-BITS")
  (data (i32.const 0x20075) "\0f" "/COUNTED-STRING")
  (data (i32.const 0x20085) "\0b" "stack empty")

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

  ;; [6.1.0010](https://forth-standard.org/standard/core/Store)
  (func $! (param $tos i32) (result i32)
    (local $bbtos i32)
    (i32.store (i32.load (i32.sub (local.get $tos) (i32.const 4)))
                (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (local.get $bbtos))
  (data (i32.const 0x20094) "\00\00\00\00" "\01" "!  " "\10\00\00\00")
  (elem (i32.const 0x10) $!)

  ;; [6.2.0200](https://forth-standard.org/standard/core/Dotp)
  (func $.p (param $tos i32) (result i32)
    (call $type (call $parse (i32.const 0x29 (; = ')' ;))))
    (local.get $tos))
  (data (i32.const 0x200a0) "\94\00\02\00" "\82" (; F_IMMEDIATE ;) ".( " "\11\00\00\00")
  (elem (i32.const 0x11) $.p)

  ;; [6.1.0030](https://forth-standard.org/standard/core/num)
  (func $# (param $tos i32) (result i32)
    (local $v i64)
    (local $base i64)
    (local $bbtos i32)
    (local $m i64)
    (local $npo i32)
    (local.set $base (i64.extend_i32_u (i32.load (i32.const 0x20364 (; = body(BASE) ;)))))
    (local.set $v (i64.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (local.set $m (i64.rem_u (local.get $v) (local.get $base)))
    (local.set $v (i64.div_u (local.get $v) (local.get $base)))
    (i32.store8 (local.tee $npo (i32.sub (global.get $po) (i32.const 1)))
      (call $numberToChar (i32.wrap_i64 (local.get $m))))
    (i64.store (local.get $bbtos) (local.get $v))
    (global.set $po (local.get $npo))
    (local.get $tos))
  (data (i32.const 0x200ac) "\a0\00\02\00" "\01" "#  " "\12\00\00\00")
  (elem (i32.const 0x12) $#)

  ;; [6.1.0040](https://forth-standard.org/standard/core/num-end)
  (func $#> (param $tos i32) (result i32)
    (i32.store (i32.sub (local.get $tos) (i32.const 8)) (global.get $po))
    (i32.store (i32.sub (local.get $tos) (i32.const 4)) (i32.sub (i32.add (global.get $here) (i32.const 0x200 (; = PICTURED_OUTPUT_OFFSET ;))) (global.get $po)))
    (local.get $tos))
  (data (i32.const 0x200b8) "\ac\00\02\00" "\02" "#> " "\13\00\00\00")
  (elem (i32.const 0x13) $#>)

  ;; [6.1.0050](https://forth-standard.org/standard/core/numS)
  (func $#S (param $tos i32) (result i32) 
    (local $v i64)
    (local $base i64)
    (local $bbtos i32)
    (local $m i64)
    (local $po i32)
    (local.set $base (i64.extend_i32_u (i32.load (i32.const 0x20364 (; = body(BASE) ;)))))
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
  (data (i32.const 0x200c4) "\b8\00\02\00" "\02" "#S " "\14\00\00\00")
  (elem (i32.const 0x14) $#S)

  ;; [6.1.0070](https://forth-standard.org/standard/core/Tick)
  (func $' (param $tos i32) (result i32)
    (i32.store (local.get $tos) (drop (call $find! (call $parseName))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x200d0) "\c4\00\02\00" "\01" "'  " "\15\00\00\00")
  (elem (i32.const 0x15) $')

  ;; [6.1.0080](https://forth-standard.org/standard/core/p)
  (func $paren (param $tos i32) (result i32)
    (drop (drop (call $parse (i32.const 0x29 (; = ')' ;)))))
    (local.get $tos))
  (data (i32.const 0x200dc) "\d0\00\02\00" "\81" (; F_IMMEDIATE ;) "(  " "\16\00\00\00")
  (elem (i32.const 0x16) $paren)

  ;; [6.1.0090](https://forth-standard.org/standard/core/Times)
  (func $* (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.mul (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 0x200e8) "\dc\00\02\00" "\01" "*  " "\17\00\00\00")
  (elem (i32.const 0x17) $*)

  ;; [6.1.0100](https://forth-standard.org/standard/core/TimesDiv)
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
  (data (i32.const 0x200f4) "\e8\00\02\00" "\02" "*/ " "\18\00\00\00")
  (elem (i32.const 0x18) $*/)

  ;; [6.1.0110](https://forth-standard.org/standard/core/TimesDivMOD)
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
  (data (i32.const 0x20100) "\f4\00\02\00" "\05" "*/MOD  " "\19\00\00\00")
  (elem (i32.const 0x19) $*/MOD)

  ;; [6.1.0120](https://forth-standard.org/standard/core/Plus)
  (func $+ (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.add (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 0x20110) "\00\01\02\00" "\01" "+  " "\1a\00\00\00")
  (elem (i32.const 0x1a) $+)

  ;; [6.1.0130](https://forth-standard.org/standard/core/PlusStore)
  (func $+! (param $tos i32) (result i32)
    (local $addr i32)
    (local $bbtos i32)
    (i32.store (local.tee $addr (i32.load (i32.sub (local.get $tos) (i32.const 4))))
                (i32.add (i32.load (local.get $addr))
                        (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))))
    (local.get $bbtos))
  (data (i32.const 0x2011c) "\10\01\02\00" "\02" "+! " "\1b\00\00\00")
  (elem (i32.const 0x1b) $+!)

  ;; [6.1.0140](https://forth-standard.org/standard/core/PlusLOOP)
  (func $+LOOP (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compilePlusLoop))
  (data (i32.const 0x20128) "\1c\01\02\00" "\85" (; F_IMMEDIATE ;) "+LOOP  " "\1c\00\00\00")
  (elem (i32.const 0x1c) $+LOOP)

  ;; [6.1.0150](https://forth-standard.org/standard/core/Comma)
  (func $comma (param $tos i32) (result i32)
    (i32.store
      (global.get $here)
      (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (global.set $here (i32.add (global.get $here) (i32.const 4)))
    (i32.sub (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20138) "\28\01\02\00" "\01" ",  " "\1d\00\00\00")
  (elem (i32.const 0x1d) $comma)

  ;; [6.1.0160](https://forth-standard.org/standard/core/Minus)
  (func $- (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.sub (i32.load (local.get $bbtos))
                        (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
    (local.get $btos))
  (data (i32.const 0x20144) "\38\01\02\00" "\01" "-  " "\1e\00\00\00")
  (elem (i32.const 0x1e) $-)

  ;; [6.1.0180](https://forth-standard.org/standard/core/d)
  (func $. (param $tos i32) (result i32)
    (local $v i32)
    (local.get $tos)
    (local.set $v (call $pop))
    (if (i32.lt_s (local.get $v) (i32.const 0))
      (then
        (call $shell_emit (i32.const 0x2d))
        (local.set $v (i32.sub (i32.const 0) (local.get $v)))))
    (call $U._ (local.get $v) (i32.load (i32.const 0x20364 (; = body(BASE) ;))))
    (call $shell_emit (i32.const 0x20)))
  (data (i32.const 0x20150) "\44\01\02\00" "\01" ".  " "\1f\00\00\00")
  (elem (i32.const 0x1f) $.)

  ;; [6.1.0190](https://forth-standard.org/standard/core/Dotq)
  (func $.q (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $Sq)
    (call $emitICall (i32.const 0) (i32.const 0x96 (; = index("TYPE") ;))))
  (data (i32.const 0x2015c) "\50\01\02\00" "\82" (; F_IMMEDIATE ;) ".\22 " "\20\00\00\00")
  (elem (i32.const 0x20) $.q)

  ;; [15.6.1.0220](https://forth-standard.org/standard/tools/DotS)
  (func $.S (param $tos i32) (result i32)
    (local $p i32)
    (local.set $p (i32.const 0x10000 (; = STACK_BASE ;)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.ge_u (local.get $p) (local.get $tos)))
        (call $U._ (i32.load (local.get $p)) (i32.load (i32.const 0x20364 (; = body(BASE) ;))))
        (call $shell_emit (i32.const 0x20))
        (local.set $p (i32.add (local.get $p) (i32.const 4)))
        (br $loop)))
    (local.get $tos))
  (data (i32.const 0x20168) "\5c\01\02\00" "\02" ".S " "\21\00\00\00")
  (elem (i32.const 0x21) $.S)

  ;; [6.1.0230](https://forth-standard.org/standard/core/Div)
  (func $/ (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $divisor i32)
    (if (i32.eqz (local.tee $divisor (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
      (call $fail (i32.const 0x2000f (; = str("division by 0") ;))))
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.div_s (i32.load (local.get $bbtos)) (local.get $divisor)))
    (local.get $btos))
  (data (i32.const 0x20174) "\68\01\02\00" "\01" "/  " "\22\00\00\00")
  (elem (i32.const 0x22) $/)

  ;; [6.1.0240](https://forth-standard.org/standard/core/DivMOD)
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
  (data (i32.const 0x20180) "\74\01\02\00" "\04" "/MOD   " "\23\00\00\00")
  (elem (i32.const 0x23) $/MOD)

  ;; [6.1.0250](https://forth-standard.org/standard/core/Zeroless)
  (func $0< (param $tos i32) (result i32)
    (local $btos i32)
    (if (i32.lt_s (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                      (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (local.get $btos) (i32.const -1)))
      (else (i32.store (local.get $btos) (i32.const 0))))
    (local.get $tos))
  (data (i32.const 0x20190) "\80\01\02\00" "\02" "0< " "\24\00\00\00")
  (elem (i32.const 0x24) $0<)

  ;; [6.1.0270](https://forth-standard.org/standard/core/ZeroEqual)
  (func $0= (param $tos i32) (result i32)
    (local $btos i32)
    (if (i32.eqz (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                      (i32.const 4)))))
      (then (i32.store (local.get $btos) (i32.const -1)))
      (else (i32.store (local.get $btos) (i32.const 0))))
    (local.get $tos))
  (data (i32.const 0x2019c) "\90\01\02\00" "\02" "0= " "\25\00\00\00")
  (elem (i32.const 0x25) $0=)

  ;; [6.2.0280](https://forth-standard.org/standard/core/Zeromore)
  (func $0> (param $tos i32) (result i32)
    (local $btos i32)
    (if (i32.gt_s (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                      (i32.const 4))))
                  (i32.const 0))
      (then (i32.store (local.get $btos) (i32.const -1)))
      (else (i32.store (local.get $btos) (i32.const 0))))
    (local.get $tos))
  (data (i32.const 0x201a8) "\9c\01\02\00" "\02" "0> " "\26\00\00\00")
  (elem (i32.const 0x26) $0>)

  ;; [6.1.0290](https://forth-standard.org/standard/core/OnePlus)
  (func $1+ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.add (i32.load (local.get $btos)) (i32.const 1)))
    (local.get $tos))
  (data (i32.const 0x201b4) "\a8\01\02\00" "\02" "1+ " "\27\00\00\00")
  (elem (i32.const 0x27) $1+)

  ;; [6.1.0300](https://forth-standard.org/standard/core/OneMinus)
  (func $1- (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.sub (i32.load (local.get $btos)) (i32.const 1)))
    (local.get $tos))
  (data (i32.const 0x201c0) "\b4\01\02\00" "\02" "1- " "\28\00\00\00")
  (elem (i32.const 0x28) $1-)

  ;; [6.1.0310](https://forth-standard.org/standard/core/TwoStore)
  (func $2! (param $tos i32) (result i32)
    (local.get $tos)
    (call $SWAP) (call $OVER) (call $!) (call $CELL+) (call $!))
  (data (i32.const 0x201cc) "\c0\01\02\00" "\02" "2! " "\29\00\00\00")
  (elem (i32.const 0x29) $2!)

  ;; [6.1.0320](https://forth-standard.org/standard/core/TwoTimes)
  (func $2* (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.shl (i32.load (local.get $btos)) (i32.const 1)))
    (local.get $tos))
  (data (i32.const 0x201d8) "\cc\01\02\00" "\02" "2* " "\2a\00\00\00")
  (elem (i32.const 0x2a) $2*)

  ;; [6.1.0330](https://forth-standard.org/standard/core/TwoDiv)
  (func $2/ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.shr_s (i32.load (local.get $btos)) (i32.const 1)))
    (local.get $tos))
  (data (i32.const 0x201e4) "\d8\01\02\00" "\02" "2/ " "\2b\00\00\00")
  (elem (i32.const 0x2b) $2/)

  ;; [6.1.0350](https://forth-standard.org/standard/core/TwoFetch)
  (func $2@  (param $tos i32) (result i32)
    (local.get $tos)
    (call $DUP)
    (call $CELL+)
    (call $@)
    (call $SWAP)
    (call $@))
  (data (i32.const 0x201f0) "\e4\01\02\00" "\02" "2@ " "\2c\00\00\00")
  (elem (i32.const 0x2c) $2@)

  ;; [6.1.0370](https://forth-standard.org/standard/core/TwoDROP)
  (func $2DROP (param $tos i32) (result i32)
    (i32.sub (local.get $tos) (i32.const 8)))
  (data (i32.const 0x201fc) "\f0\01\02\00" "\05" "2DROP  " "\2d\00\00\00")
  (elem (i32.const 0x2d) $2DROP)

  ;; [6.1.0380](https://forth-standard.org/standard/core/TwoDUP)
  (func $2DUP (param $tos i32) (result i32)
    (i32.store (local.get $tos)
                (i32.load (i32.sub (local.get $tos) (i32.const 8))))
    (i32.store (i32.add (local.get $tos) (i32.const 4))
                (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (i32.add (local.get $tos) (i32.const 8)))
  (data (i32.const 0x2020c) "\fc\01\02\00" "\04" "2DUP   " "\2e\00\00\00")
  (elem (i32.const 0x2e) $2DUP)

  ;; [6.1.0400](https://forth-standard.org/standard/core/TwoOVER)
  (func $2OVER (param $tos i32) (result i32)
    (i32.store (local.get $tos)
                (i32.load (i32.sub (local.get $tos) (i32.const 16))))
    (i32.store (i32.add (local.get $tos) (i32.const 4))
                (i32.load (i32.sub (local.get $tos) (i32.const 12))))
    (i32.add (local.get $tos) (i32.const 8)))
  (data (i32.const 0x2021c) "\0c\02\02\00" "\05" "2OVER  " "\2f\00\00\00")
  (elem (i32.const 0x2f) $2OVER)

  ;; [6.1.0430](https://forth-standard.org/standard/core/TwoSWAP)
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
  (data (i32.const 0x2022c) "\1c\02\02\00" "\05" "2SWAP  " "\30\00\00\00")
  (elem (i32.const 0x30) $2SWAP)

  ;; [6.1.0450](https://forth-standard.org/standard/core/Colon)
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
  (data (i32.const 0x2023c) "\2c\02\02\00" "\01" ":  " "\31\00\00\00")
  (elem (i32.const 0x31) $:)

  ;; [6.1.0460](https://forth-standard.org/standard/core/Semi)
  (func $semicolon (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $endColon)
    (call $hidden)
    (call $left-bracket))
  (data (i32.const 0x20248) "\3c\02\02\00" "\81" (; F_IMMEDIATE ;) ";  " "\32\00\00\00")
  (elem (i32.const 0x32) $semicolon)

  ;; [6.1.0480](https://forth-standard.org/standard/core/less)
  (func $< (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_s (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                  (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (local.get $btos))
  (data (i32.const 0x20254) "\48\02\02\00" "\01" "<  " "\33\00\00\00")
  (elem (i32.const 0x33) $<)

  ;; [6.1.0490](https://forth-standard.org/standard/core/num-start)
  (func $<# (param $tos i32) (result i32)
    (global.set $po (i32.add (global.get $here) (i32.const 0x200 (; = PICTURED_OUTPUT_OFFSET ;))))
    (local.get $tos))
  (data (i32.const 0x20260) "\54\02\02\00" "\02" "<# " "\34\00\00\00")
  (elem (i32.const 0x34) $<#)

  ;; [6.1.0530](https://forth-standard.org/standard/core/Equal)
  (func $= (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.eq (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (local.get $btos))
  (data (i32.const 0x2026c) "\60\02\02\00" "\01" "=  " "\35\00\00\00")
  (elem (i32.const 0x35) $=)

  ;; [6.1.0540](https://forth-standard.org/standard/core/more)
  (func $> (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.gt_s (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                  (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (local.get $btos))
  (data (i32.const 0x20278) "\6c\02\02\00" "\01" ">  " "\36\00\00\00")
  (elem (i32.const 0x36) $>)

  ;; [6.1.0550](https://forth-standard.org/standard/core/toBODY)
  (func $>BODY (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
      (i32.add (call $body (i32.load (local.get $btos))) (i32.const 4)))
    (local.get $tos))
  (data (i32.const 0x20284) "\78\02\02\00" "\05" ">BODY  " "\37\00\00\00")
  (elem (i32.const 0x37) $>BODY)

  ;; [6.1.0560](https://forth-standard.org/standard/core/toIN)
  (data (i32.const 0x20294) "\84\02\02\00" "\43" (; F_DATA ;) ">IN" "\03\00\00\00" (; = pack(PUSH_DATA_ADDRESS_INDEX) ;) "\00\00\00\00")

  ;; [6.1.0570](https://forth-standard.org/standard/core/toNUMBER)
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
  (data (i32.const 0x202a4) "\94\02\02\00" "\07" ">NUMBER" "\38\00\00\00")
  (elem (i32.const 0x38) $>NUMBER)

  ;; [6.1.0580](https://forth-standard.org/standard/core/toR)
  (func $>R (param $tos i32) (result i32)
    (local.tee $tos (i32.sub (local.get $tos) (i32.const 4)))
    (i32.store (global.get $tors) (i32.load (local.get $tos)))
    (global.set $tors (i32.add (global.get $tors) (i32.const 4))))
  (data (i32.const 0x202b4) "\a4\02\02\00" "\02" ">R " "\39\00\00\00")
  (elem (i32.const 0x39) $>R)

  ;; [6.1.0630](https://forth-standard.org/standard/core/qDUP)
  (func $?DUP (param $tos i32) (result i32)
    (local $btos i32)
    (if (result i32) (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
      (then
        (i32.store (local.get $tos)
          (i32.load (local.get $btos)))
        (i32.add (local.get $tos) (i32.const 4)))
      (else 
        (local.get $tos))))
  (data (i32.const 0x202c0) "\b4\02\02\00" "\04" "?DUP   " "\3a\00\00\00")
  (elem (i32.const 0x3a) $?DUP)

  ;; [6.1.0650](https://forth-standard.org/standard/core/Fetch)
  (func $@ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
      (i32.load (i32.load (local.get $btos))))
    (local.get $tos))
  (data (i32.const 0x202d0) "\c0\02\02\00" "\01" "@  " "\3b\00\00\00")
  (elem (i32.const 0x3b) $@)

  ;; [6.1.0670](https://forth-standard.org/standard/core/ABORT)
  (func $ABORT (param $tos i32) (result i32)
    (global.set $error (i32.const 0x3 (; = ERR_ABORT ;)))
    (call $quit (i32.const 0x10000 (; = STACK_BASE ;))))
  (data (i32.const 0x202dc) "\d0\02\02\00" "\05" "ABORT  " "\3c\00\00\00")
  (elem (i32.const 0x3c) $ABORT)

  ;; [6.1.0680](https://forth-standard.org/standard/core/ABORTq)
  (func $ABORTq (param $tos i32) (result i32)
    (local.get $tos)
    (call $compileIf)
    (call $Sq)
    (call $emitICall (i32.const 0) (i32.const 0x96 (; = index("TYPE") ;)))
    (call $emitICall (i32.const 0) (i32.const 0x3c (; = index("ABORT") ;)))
    (call $compileThen))
  (data (i32.const 0x202ec) "\dc\02\02\00" "\86" (; F_IMMEDIATE ;) "ABORT\22 " "\3d\00\00\00")
  (elem (i32.const 0x3d) $ABORTq)

  ;; [6.1.0690](https://forth-standard.org/standard/core/ABS)
  (func $ABS (param $tos i32) (result i32)
    (local $btos i32)
    (local $v i32)
    (local $y i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.sub (i32.xor (local.tee $v (i32.load (local.get $btos)))
                                  (local.tee $y (i32.shr_s (local.get $v) (i32.const 31))))
                        (local.get $y)))
    (local.get $tos))
  (data (i32.const 0x202fc) "\ec\02\02\00" "\03" "ABS" "\3e\00\00\00")
  (elem (i32.const 0x3e) $ABS)

  ;; [6.1.0695](https://forth-standard.org/standard/core/ACCEPT)
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
  (data (i32.const 0x20308) "\fc\02\02\00" "\06" "ACCEPT " "\3f\00\00\00")
  (elem (i32.const 0x3f) $ACCEPT)

  ;; [6.1.0705](https://forth-standard.org/standard/core/ALIGN)
  (func $ALIGN (param $tos i32) (result i32)
    (global.set $here (call $aligned (global.get $here)))
    (local.get $tos))
  (data (i32.const 0x20318) "\08\03\02\00" "\05" "ALIGN  " "\40\00\00\00")
  (elem (i32.const 0x40) $ALIGN)

  ;; [6.1.0706](https://forth-standard.org/standard/core/ALIGNED)
  (func $ALIGNED (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
      (call $aligned (i32.load (local.get $btos))))
    (local.get $tos))
  (data (i32.const 0x20328) "\18\03\02\00" "\07" "ALIGNED" "\41\00\00\00")
  (elem (i32.const 0x41) $ALIGNED)

  ;; [6.1.0710](https://forth-standard.org/standard/core/ALLOT)
  (func $ALLOT (param $tos i32) (result i32)
    (local $v i32)
    (local.get $tos)
    (local.set $v (call $pop))
    (global.set $here (i32.add (global.get $here) (local.get $v))))
  (data (i32.const 0x20338) "\28\03\02\00" "\05" "ALLOT  " "\42\00\00\00")
  (elem (i32.const 0x42) $ALLOT)

  ;; [6.1.0720](https://forth-standard.org/standard/core/AND)
  (func $AND (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.and (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 0x20348) "\38\03\02\00" "\03" "AND" "\43\00\00\00")
  (elem (i32.const 0x43) $AND)

  ;; [6.1.0750](https://forth-standard.org/standard/core/BASE)
  (data (i32.const 0x20354) "\48\03\02\00" "\44" (; F_DATA ;) "BASE   " "\03\00\00\00" (; = pack(PUSH_DATA_ADDRESS_INDEX) ;) "\0a\00\00\00" (; = pack(10) ;))

  ;; [6.1.0760](https://forth-standard.org/standard/core/BEGIN)
  (func $BEGIN (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileBegin))
  (data (i32.const 0x20368) "\54\03\02\00" "\85" (; F_IMMEDIATE ;) "BEGIN  " "\44\00\00\00")
  (elem (i32.const 0x44) $BEGIN)

  ;; [6.1.0770](https://forth-standard.org/standard/core/BL)
  (func $BL (param $tos i32) (result i32)
    (call $push (local.get $tos) (i32.const 32)))
  (data (i32.const 0x20378) "\68\03\02\00" "\02" "BL " "\45\00\00\00")
  (elem (i32.const 0x45) $BL)

  ;; [6.1.0850](https://forth-standard.org/standard/core/CStore)
  (func $C! (param $tos i32) (result i32)
    (local $bbtos i32)
    (i32.store8 (i32.load (i32.sub (local.get $tos) (i32.const 4)))
                (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (local.get $bbtos))
  (data (i32.const 0x20384) "\78\03\02\00" "\02" "C! " "\46\00\00\00")
  (elem (i32.const 0x46) $C!)

  ;; [6.1.0860](https://forth-standard.org/standard/core/CComma)
  (func $Cc (param $tos i32) (result i32)
    (i32.store8 (global.get $here)
                (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (global.set $here (i32.add (global.get $here) (i32.const 1)))
    (i32.sub (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20390) "\84\03\02\00" "\02" "C, " "\47\00\00\00")
  (elem (i32.const 0x47) $Cc)

  ;; [6.2.0855](https://forth-standard.org/standard/core/Cq)
  (func $Cq (param $tos i32) (result i32)
    (local $c i32)
    (local $addr i32)
    (local $len i32)
    (local.get $tos)
    (call $ensureCompiling)
    (local.set $addr (local.set $len (call $parse (i32.const 0x22 (; = '"' ;)))))
    (i32.store8 (global.get $here) (local.get $len))
    (memory.copy
      (i32.add (global.get $here) (i32.const 1)) 
      (local.get $addr) 
      (local.get $len))
    (call $compilePushConst (global.get $here))
    (global.set $here 
      (call $aligned (i32.add (i32.add (global.get $here) (i32.const 1)) (local.get $len)))))
  (data (i32.const 0x2039c) "\90\03\02\00" "\82" (; F_IMMEDIATE ;) "C\22 " "\48\00\00\00")
  (elem (i32.const 0x48) $Cq)

  ;; [6.1.0870](https://forth-standard.org/standard/core/CFetch)
  (func $C@ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.load8_u (i32.load (local.get $btos))))
    (local.get $tos))
  (data (i32.const 0x203a8) "\9c\03\02\00" "\02" "C@ " "\49\00\00\00")
  (elem (i32.const 0x49) $C@)

  ;; [6.1.0880](https://forth-standard.org/standard/core/CELLPlus)
  (func $CELL+ (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.add (i32.load (local.get $btos)) (i32.const 4)))
    (local.get $tos))
  (data (i32.const 0x203b4) "\a8\03\02\00" "\05" "CELL+  " "\4a\00\00\00")
  (elem (i32.const 0x4a) $CELL+)

  ;; [6.1.0890](https://forth-standard.org/standard/core/CELLS)
  (func $CELLS (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.shl (i32.load (local.get $btos)) (i32.const 2)))            
    (local.get $tos))
  (data (i32.const 0x203c4) "\b4\03\02\00" "\05" "CELLS  " "\4b\00\00\00")
  (elem (i32.const 0x4b) $CELLS)

  ;; [6.1.0895](https://forth-standard.org/standard/core/CHAR)
  (func $CHAR (param $tos i32) (result i32)
    (local $addr i32)
    (local $len i32)
    (local.set $addr (local.set $len (call $parseName)))
    (if (i32.eqz (local.get $len))
      (then
        (call $fail (i32.const 0x2001d (; = str("incomplete input") ;)))))
    (i32.store (local.get $tos) (i32.load8_u (local.get $addr)))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x203d4) "\c4\03\02\00" "\04" "CHAR   " "\4c\00\00\00")
  (elem (i32.const 0x4c) $CHAR)

  ;; [6.1.0897](https://forth-standard.org/standard/core/CHARPlus)
  (func $CHAR+ (param $tos i32) (result i32)
    (call $1+ (local.get $tos)))
  (data (i32.const 0x203e4) "\d4\03\02\00" "\05" "CHAR+  " "\4d\00\00\00")
  (elem (i32.const 0x4d) $CHAR+)

  ;; [6.1.0898](https://forth-standard.org/standard/core/CHARS)
  (func $CHARS (param $tos i32) (result i32)
    (local.get $tos))
  (data (i32.const 0x203f4) "\e4\03\02\00" "\05" "CHARS  " "\4e\00\00\00")
  (elem (i32.const 0x4e) $CHARS)

  ;; [6.1.0950](https://forth-standard.org/standard/core/CONSTANT)
  (func $CONSTANT (param $tos i32) (result i32)
    (local $v i32)
    (local.get $tos)
    (call $CREATE)
    (i32.store (i32.sub (global.get $here) (i32.const 4)) (i32.const 0x6 (; = PUSH_INDIRECT_INDEX ;)))
    (local.set $v (call $pop))
    (i32.store (global.get $here) (local.get $v))
    (global.set $here (i32.add (global.get $here) (i32.const 4))))
  (data (i32.const 0x20404) "\f4\03\02\00" "\08" "CONSTANT   " "\4f\00\00\00")
  (elem (i32.const 0x4f) $CONSTANT)

  ;; [6.1.0980](https://forth-standard.org/standard/core/COUNT)
  (func $COUNT (param $tos i32) (result i32)
    (local $btos i32)
    (local $addr i32)
    (i32.store (local.get $tos)
                (i32.load8_u (local.tee $addr (i32.load (local.tee $btos (i32.sub (local.get $tos) 
                                                                                (i32.const 4)))))))
    (i32.store (local.get $btos) (i32.add (local.get $addr) (i32.const 1)))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20418) "\04\04\02\00" "\05" "COUNT  " "\50\00\00\00")
  (elem (i32.const 0x50) $COUNT)

  ;; [6.1.0990](https://forth-standard.org/standard/core/CR)
  (func $CR (param $tos i32) (result i32)
    (call $push (local.get $tos) (i32.const 10)) (call $EMIT))
  (data (i32.const 0x20428) "\18\04\02\00" "\02" "CR " "\51\00\00\00")
  (elem (i32.const 0x51) $CR)

  ;; [6.1.1000](https://forth-standard.org/standard/core/CREATE)
  (func $CREATE (param $tos i32) (result i32)
    (local $addr i32)
    (local $len i32)
    (local $here i32)

    (i32.store (global.get $here) (global.get $latest))
    (global.set $latest (global.get $here))
    (global.set $here (i32.add (global.get $here) (i32.const 4)))

    (local.set $addr (local.set $len (call $parseName)))
    (if (i32.eqz (local.get $len))
      (call $fail (i32.const 0x2001d (; = str("incomplete input") ;))))
    (i32.store8 (global.get $here) (local.get $len))
    (memory.copy 
      (local.tee $here (i32.add (global.get $here) (i32.const 1)))
      (local.get $addr)
      (local.get $len))
    (global.set $here (call $aligned (i32.add (local.get $here) (local.get $len))))
    (i32.store (global.get $here) (i32.const 0x3 (; = PUSH_DATA_ADDRESS_INDEX ;)))
    (global.set $here (i32.add (global.get $here) (i32.const 4)))
    (i32.store (global.get $here) (i32.const 0))
    (call $setFlag (i32.const 0x40 (; = F_DATA ;)))
    (local.get $tos))
  (data (i32.const 0x20434) "\28\04\02\00" "\06" "CREATE " "\52\00\00\00")
  (elem (i32.const 0x52) $CREATE)

  ;; [6.1.1170](https://forth-standard.org/standard/core/DECIMAL)
  (func $DECIMAL (param $tos i32) (result i32)
    (i32.store (i32.const 0x20364 (; = body(BASE) ;)) (i32.const 10))
    (local.get $tos))
  (data (i32.const 0x20444) "\34\04\02\00" "\07" "DECIMAL" "\53\00\00\00")
  (elem (i32.const 0x53) $DECIMAL)

  ;; [6.1.1200](https://forth-standard.org/standard/core/DEPTH)
  (func $DEPTH (param $tos i32) (result i32)
    (i32.store (local.get $tos)
              (i32.shr_u (i32.sub (local.get $tos) (i32.const 0x10000 (; = STACK_BASE ;))) (i32.const 2)))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20454) "\44\04\02\00" "\05" "DEPTH  " "\54\00\00\00")
  (elem (i32.const 0x54) $DEPTH)

  ;; [6.1.1240](https://forth-standard.org/standard/core/DO)
  (func $DO (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileDo))
  (data (i32.const 0x20464) "\54\04\02\00" "\82" (; F_IMMEDIATE ;) "DO " "\55\00\00\00")
  (elem (i32.const 0x55) $DO)

  ;; [6.1.1250](https://forth-standard.org/standard/core/DOES)
  (func $DOES> (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $emitConst (i32.add (global.get $nextTableIndex) (i32.const 1)))
    (call $emitICall (i32.const 1) (i32.const 0x4 (; = SET_LATEST_BODY_INDEX ;)))
    (call $endColon)
    (call $startColon (i32.const 1))
    (call $compilePushLocal (i32.const 1)))
  (data (i32.const 0x20470) "\64\04\02\00" "\85" (; F_IMMEDIATE ;) "DOES>  " "\56\00\00\00")
  (elem (i32.const 0x56) $DOES>)

  ;; [6.1.1260](https://forth-standard.org/standard/core/DROP)
  (func $DROP (param $tos i32) (result i32)
    (i32.sub (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20480) "\70\04\02\00" "\04" "DROP   " "\57\00\00\00")
  (elem (i32.const 0x57) $DROP)

  ;; [6.1.1290](https://forth-standard.org/standard/core/DUP)
  (func $DUP (param $tos i32) (result i32)
    (i32.store (local.get $tos)
      (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20490) "\80\04\02\00" "\03" "DUP" "\58\00\00\00")
  (elem (i32.const 0x58) $DUP)

  ;; [6.1.1310](https://forth-standard.org/standard/core/ELSE)
  (func $ELSE (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $emitElse))
  (data (i32.const 0x2049c) "\90\04\02\00" "\84" (; F_IMMEDIATE ;) "ELSE   " "\59\00\00\00")
  (elem (i32.const 0x59) $ELSE)

  ;; [6.1.1320](https://forth-standard.org/standard/core/EMIT)
  (func $EMIT (param $tos i32) (result i32)
    (call $shell_emit (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (i32.sub (local.get $tos) (i32.const 4)))
  (data (i32.const 0x204ac) "\9c\04\02\00" "\04" "EMIT   " "\5a\00\00\00")
  (elem (i32.const 0x5a) $EMIT)

  ;; [6.1.1345](https://forth-standard.org/standard/core/ENVIRONMENTq)
  (func $ENVIRONMENT? (param $tos i32) (result i32)
    (local $addr i32)
    (local $len i32)
    (local $btos i32)
    (local $bbtos i32)
    (local.set $addr (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (local.set $len (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (if (result i32) (call $stringEqual (local.get $addr) (local.get $len) (i32.const 0x20064 (; = str("ADDRESS-UNIT-BITS") + 1 ;)) (i32.const 0x11 (; = len("ADDRESS-UNIT-BITS") ;)))
      (then
        (i32.store (local.get $bbtos) (i32.const 8))
        (i32.store (local.get $btos) (i32.const -1))
        (local.get $tos))
      (else 
        (if (result i32) (call $stringEqual (local.get $addr) (local.get $len) (i32.const 0x20076 (; = str("/COUNTED-STRING") + 1 ;)) (i32.const 0xf (; = len("/COUNTED-STRING") ;)))
          (then
            (i32.store (local.get $bbtos) (i32.const 255))
            (i32.store (local.get $btos) (i32.const -1))
            (local.get $tos))
          (else
            (i32.store (local.get $bbtos) (i32.const 0))
            (local.get $btos))))))
  (data (i32.const 0x204bc) "\ac\04\02\00" "\0c" "ENVIRONMENT?   " "\5b\00\00\00")
  (elem (i32.const 0x5b) $ENVIRONMENT?)

  ;; [6.2.1350](https://forth-standard.org/standard/core/ERASE)
  (func $ERASE (param $tos i32) (result i32)
    (local $bbtos i32)
    (memory.fill 
      (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
      (i32.const 0)
      (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (local.get $bbtos))
  (data (i32.const 0x204d4) "\bc\04\02\00" "\05" "ERASE  " "\5c\00\00\00")
  (elem (i32.const 0x5c) $ERASE)

  ;; [6.1.1360](https://forth-standard.org/standard/core/EVALUATE)
  (func $EVALUATE (param $tos i32) (result i32)
    (local $bbtos i32)
    (local $prevSourceID i32)
    (local $prevIn i32)
    (local $prevInputBufferBase i32)
    (local $prevInputBufferSize i32)

    ;; Save input state
    (local.set $prevSourceID (global.get $sourceID))
    (local.set $prevIn (i32.load (i32.const 0x202a0 (; = body(>IN) ;))))
    (local.set $prevInputBufferSize (global.get $inputBufferSize))
    (local.set $prevInputBufferBase (global.get $inputBufferBase))

    (global.set $sourceID (i32.const -1))
    (global.set $inputBufferBase (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (global.set $inputBufferSize (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (i32.store (i32.const 0x202a0 (; = body(>IN) ;)) (i32.const 0))

    (call $interpret (local.get $bbtos))

    ;; Restore input state
    (global.set $sourceID (local.get $prevSourceID))
    (i32.store (i32.const 0x202a0 (; = body(>IN) ;)) (local.get $prevIn))
    (global.set $inputBufferBase (local.get $prevInputBufferBase))
    (global.set $inputBufferSize (local.get $prevInputBufferSize)))
  (data (i32.const 0x204e4) "\d4\04\02\00" "\08" "EVALUATE   " "\5d\00\00\00")
  (elem (i32.const 0x5d) $EVALUATE)

  ;; [6.1.1370](https://forth-standard.org/standard/core/EXECUTE)
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
  (data (i32.const 0x204f8) "\e4\04\02\00" "\07" "EXECUTE" "\5e\00\00\00")
  (elem (i32.const 0x5e) $EXECUTE)

  ;; [6.1.1380](https://forth-standard.org/standard/core/EXIT)
  (func $EXIT (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $emitReturn))
  (data (i32.const 0x20508) "\f8\04\02\00" "\84" (; F_IMMEDIATE ;) "EXIT   " "\5f\00\00\00")
  (elem (i32.const 0x5f) $EXIT)

  ;; [6.2.1485](https://forth-standard.org/standard/core/FALSE)
  (func $FALSE (param $tos i32) (result i32)
    (call $push (local.get $tos) (i32.const 0x0)))
  (data (i32.const 0x20518) "\08\05\02\00" "\05" "FALSE  " "\60\00\00\00")
  (elem (i32.const 0x60) $FALSE)

  ;; [6.1.1540](https://forth-standard.org/standard/core/FILL)
  (func $FILL (param $tos i32) (result i32)
    (local $bbbtos i32)
    (memory.fill 
      (i32.load (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12))))
      (i32.load (i32.sub (local.get $tos) (i32.const 4)))
      (i32.load (i32.sub (local.get $tos) (i32.const 8))))
    (local.get $bbbtos))
  (data (i32.const 0x20528) "\18\05\02\00" "\04" "FILL   " "\61\00\00\00")
  (elem (i32.const 0x61) $FILL)

  ;; [6.1.1550](https://forth-standard.org/standard/core/FIND)
  (func $FIND (param $tos i32) (result i32)
    (local $caddr i32)
    (local $xt i32)
    (local $r i32)
    (local.set $xt (local.set $r 
      (call $find     
        (i32.add (local.tee $caddr (i32.load (i32.sub (local.get $tos) (i32.const 4)))) (i32.const 1))
        (i32.load8_u (local.get $caddr)))))
    (if (i32.eqz (local.get $r))
      (then (i32.store (i32.sub (local.get $tos) (i32.const 4)) (local.get $caddr)))
      (else (i32.store (i32.sub (local.get $tos) (i32.const 4)) (local.get $xt))))
    (i32.store (local.get $tos) (local.get $r))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20538) "\28\05\02\00" "\04" "FIND   " "\62\00\00\00")
  (elem (i32.const 0x62) $FIND)

  ;; [6.1.1561](https://forth-standard.org/standard/core/FMDivMOD)
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
  (data (i32.const 0x20548) "\38\05\02\00" "\06" "FM/MOD " "\63\00\00\00")
  (elem (i32.const 0x63) $FM/MOD)

  ;; [6.1.1650](https://forth-standard.org/standard/core/HERE)
  (func $HERE (param $tos i32) (result i32)
    (i32.store (local.get $tos) (global.get $here))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20558) "\48\05\02\00" "\04" "HERE   " "\64\00\00\00")
  (elem (i32.const 0x64) $HERE)

  ;; [6.2.1660](https://forth-standard.org/standard/core/HEX)
  (func $HEX (param $tos i32) (result i32)
    (i32.store (i32.const 0x20364 (; = body(BASE) ;)) (i32.const 16))
    (local.get $tos))
  (data (i32.const 0x20568) "\58\05\02\00" "\03" "HEX" "\65\00\00\00")
  (elem (i32.const 0x65) $HEX)

  ;; [6.1.1670](https://forth-standard.org/standard/core/HOLD)
  (func $HOLD (param $tos i32) (result i32)
    (local $btos i32)
    (local $npo i32)
    (i32.store8 
      (local.tee $npo (i32.sub (global.get $po) (i32.const 1)))
      (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (global.set $po (local.get $npo))
    (local.get $btos))
  (data (i32.const 0x20574) "\68\05\02\00" "\04" "HOLD   " "\66\00\00\00")
  (elem (i32.const 0x66) $HOLD)

  ;; [6.1.1680](https://forth-standard.org/standard/core/I)
  (func $I (param $tos i32) (result i32)
    (i32.store (local.get $tos) (i32.load (i32.sub (global.get $tors) (i32.const 4))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20584) "\74\05\02\00" "\01" "I  " "\67\00\00\00")
  (elem (i32.const 0x67) $I)

  ;; [6.1.1700](https://forth-standard.org/standard/core/IF)
  (func $IF (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileIf))
  (data (i32.const 0x20590) "\84\05\02\00" "\82" (; F_IMMEDIATE ;) "IF " "\68\00\00\00")
  (elem (i32.const 0x68) $IF)

  ;; [6.1.1710](https://forth-standard.org/standard/core/IMMEDIATE)
  (func $IMMEDIATE (param $tos i32) (result i32)
    (call $setFlag (i32.const 0x80 (; = F_IMMEDIATE ;)))
    (local.get $tos))
  (data (i32.const 0x2059c) "\90\05\02\00" "\09" "IMMEDIATE  " "\69\00\00\00")
  (elem (i32.const 0x69) $IMMEDIATE)

  ;; [6.1.1720](https://forth-standard.org/standard/core/INVERT)
  (func $INVERT (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.xor (i32.load (local.get $btos)) (i32.const -1)))
    (local.get $tos))
  (data (i32.const 0x205b0) "\9c\05\02\00" "\06" "INVERT " "\6a\00\00\00")
  (elem (i32.const 0x6a) $INVERT)

  ;; [6.1.1730](https://forth-standard.org/standard/core/J)
  (func $J (param $tos i32) (result i32)
    (i32.store (local.get $tos) (i32.load (i32.sub (global.get $tors) (i32.const 8))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x205c0) "\b0\05\02\00" "\01" "J  " "\6b\00\00\00")
  (elem (i32.const 0x6b) $J)

  ;; [6.1.1750](https://forth-standard.org/standard/core/KEY)
  (func $KEY (param $tos i32) (result i32)
    (i32.store (local.get $tos) (call $shell_key))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x205cc) "\c0\05\02\00" "\03" "KEY" "\6c\00\00\00")
  (elem (i32.const 0x6c) $KEY)

  (func $LATEST (param $tos i32) (result i32)
    (i32.store (local.get $tos) (global.get $latest))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x205d8) "\cc\05\02\00" "\06" "LATEST " "\6d\00\00\00")
  (elem (i32.const 0x6d) $LATEST)

  ;; [6.1.1760](https://forth-standard.org/standard/core/LEAVE)
  (func $LEAVE (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileLeave))
  (data (i32.const 0x205e8) "\d8\05\02\00" "\85" (; F_IMMEDIATE ;) "LEAVE  " "\6e\00\00\00")
  (elem (i32.const 0x6e) $LEAVE)

  ;; [6.1.1780](https://forth-standard.org/standard/core/LITERAL)
  (func $LITERAL (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compilePushConst (call $pop)))
  (data (i32.const 0x205f8) "\e8\05\02\00" "\87" (; F_IMMEDIATE ;) "LITERAL" "\6f\00\00\00")
  (elem (i32.const 0x6f) $LITERAL)

  ;; [6.1.1800](https://forth-standard.org/standard/core/LOOP)
  (func $LOOP (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileLoop))
  (data (i32.const 0x20608) "\f8\05\02\00" "\84" (; F_IMMEDIATE ;) "LOOP   " "\70\00\00\00")
  (elem (i32.const 0x70) $LOOP)

  ;; [6.1.1805](https://forth-standard.org/standard/core/LSHIFT)
  (func $LSHIFT (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.shl (i32.load (local.get $bbtos))
                        (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
    (local.get $btos))
  (data (i32.const 0x20618) "\08\06\02\00" "\06" "LSHIFT " "\71\00\00\00")
  (elem (i32.const 0x71) $LSHIFT)

  ;; [6.1.1810](https://forth-standard.org/standard/core/MTimes)
  (func $M* (param $tos i32) (result i32)
    (local $bbtos i32)
    (i64.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i64.mul (i64.extend_i32_s (i32.load (local.get $bbtos)))
                        (i64.extend_i32_s (i32.load (i32.sub (local.get $tos) 
                                                              (i32.const 4))))))
    (local.get $tos))
  (data (i32.const 0x20628) "\18\06\02\00" "\02" "M* " "\72\00\00\00")
  (elem (i32.const 0x72) $M*)

  ;; [6.1.1870](https://forth-standard.org/standard/core/MAX)
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
  (data (i32.const 0x20634) "\28\06\02\00" "\03" "MAX" "\73\00\00\00")
  (elem (i32.const 0x73) $MAX)

  ;; [6.1.1880](https://forth-standard.org/standard/core/MIN)
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
  (data (i32.const 0x20640) "\34\06\02\00" "\03" "MIN" "\74\00\00\00")
  (elem (i32.const 0x74) $MIN)

  ;; [6.1.1890](https://forth-standard.org/standard/core/MOD)
  (func $MOD (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.rem_s (i32.load (local.get $bbtos))
                          (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
    (local.get $btos))
  (data (i32.const 0x2064c) "\40\06\02\00" "\03" "MOD" "\75\00\00\00")
  (elem (i32.const 0x75) $MOD)

  ;; [6.1.1900](https://forth-standard.org/standard/core/MOVE)
  (func $MOVE (param $tos i32) (result i32)
    (local $bbbtos i32)
    (memory.copy 
      (i32.load (i32.sub (local.get $tos) (i32.const 8)))
      (i32.load (local.tee $bbbtos (i32.sub (local.get $tos) (i32.const 12))))
      (i32.load (i32.sub (local.get $tos) (i32.const 4))))
    (local.get $bbbtos))
  (data (i32.const 0x20658) "\4c\06\02\00" "\04" "MOVE   " "\76\00\00\00")
  (elem (i32.const 0x76) $MOVE)

  ;; [6.1.1910](https://forth-standard.org/standard/core/NEGATE)
  (func $NEGATE (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
                (i32.sub (i32.const 0) (i32.load (local.get $btos))))
    (local.get $tos))
  (data (i32.const 0x20668) "\58\06\02\00" "\06" "NEGATE " "\77\00\00\00")
  (elem (i32.const 0x77) $NEGATE)

  ;; [6.2.1930](https://forth-standard.org/standard/core/NIP)
  (func $NIP (param $tos i32) (result i32)
    (local.get $tos)
    (call $SWAP) (call $DROP))
  (data (i32.const 0x20678) "\68\06\02\00" "\03" "NIP" "\78\00\00\00")
  (elem (i32.const 0x78) $NIP)

  ;; [6.1.1980](https://forth-standard.org/standard/core/OR)
  (func $OR (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.or (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 0x20684) "\78\06\02\00" "\02" "OR " "\79\00\00\00")
  (elem (i32.const 0x79) $OR)

  ;; [6.1.1990](https://forth-standard.org/standard/core/OVER)
  (func $OVER (param $tos i32) (result i32)
    (i32.store (local.get $tos)
                (i32.load (i32.sub (local.get $tos) (i32.const 8))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20690) "\84\06\02\00" "\04" "OVER   " "\7a\00\00\00")
  (elem (i32.const 0x7a) $OVER)

  ;; [6.2.2000](https://forth-standard.org/standard/core/PAD)
  (func $PAD (param $tos i32) (result i32)
    (i32.store (local.get $tos) (i32.add (global.get $here) (i32.const 0x304 (; = PAD_OFFSET ;))))
    (i32.add (local.get $tos) (i32.const 0x4)))
  (data (i32.const 0x206a0) "\90\06\02\00" "\03" "PAD" "\7b\00\00\00")
  (elem (i32.const 0x7b) $PAD)

  ;; [6.2.2008](https://forth-standard.org/standard/core/PARSE)
  (func $PARSE (param $tos i32) (result i32)
    (local $addr i32)
    (local $len i32)
    (local $btos i32)
    (local.set $addr (local.set $len 
      (call $parse 
        (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 0x4)))))))
    (i32.store (local.get $btos) (local.get $addr))
    (i32.store (local.get $tos) (local.get $len))
    (i32.add (local.get $tos) (i32.const 0x4)))
  (data (i32.const 0x206ac) "\a0\06\02\00" "\05" "PARSE  " "\7c\00\00\00")
  (elem (i32.const 0x7c) $PARSE)

  ;; [6.2.2020](https://forth-standard.org/standard/core/PARSE-NAME)
  (func $PARSE-NAME (param $tos i32) (result i32)
    (local $addr i32)
    (local $len i32)
    (local.set $addr (local.set $len (call $parseName)))
    (i32.store (local.get $tos) (local.get $addr))
    (i32.store (i32.add (local.get $tos) (i32.const 0x4)) (local.get $len))
    (i32.add (local.get $tos) (i32.const 0x8)))
  (data (i32.const 0x206bc) "\ac\06\02\00" "\0a" "PARSE-NAME " "\7d\00\00\00")
  (elem (i32.const 0x7d) $PARSE-NAME)

  ;; [6.2.2030](https://forth-standard.org/standard/core/PICK)
  (func $PICK (param $tos i32) (result i32)
    (local $btos i32)
    (i32.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
      (i32.load 
        (i32.sub 
          (local.get $tos) 
          (i32.shl (i32.add (i32.load (local.get $btos)) (i32.const 2)) (i32.const 2)))))
    (local.get $tos))
  (data (i32.const 0x206d0) "\bc\06\02\00" "\04" "PICK   " "\7e\00\00\00")
  (elem (i32.const 0x7e) $PICK)

  ;; [6.1.2033](https://forth-standard.org/standard/core/POSTPONE)
  (func $POSTPONE (param $tos i32) (result i32)
    (local $FINDToken i32)
    (local $FINDResult i32)
    (local.get $tos)
    (call $ensureCompiling)
    (local.set $FINDToken (local.set $FINDResult (call $find! (call $parseName))))
    (if (param i32) (result i32) (i32.eq (local.get $FINDResult) (i32.const 1))
      (then 
        (call $compileCall (local.get $FINDToken)))
      (else
        (call $emitConst (local.get $FINDToken))
        (call $emitICall (i32.const 1) (i32.const 0x5 (; = COMPILE_CALL_INDEX ;))))))
  (data (i32.const 0x206e0) "\d0\06\02\00" "\88" (; F_IMMEDIATE ;) "POSTPONE   " "\7f\00\00\00")
  (elem (i32.const 0x7f) $POSTPONE)

  ;; [6.1.2050](https://forth-standard.org/standard/core/QUIT)
  (func $QUIT (param $tos i32) (result i32)
    (global.set $error (i32.const 0x2 (; = ERR_QUIT ;)))
    (call $quit (local.get $tos)))
  (data (i32.const 0x206f4) "\e0\06\02\00" "\04" "QUIT   " "\80\00\00\00")
  (elem (i32.const 0x80) $QUIT)

  ;; [6.1.2060](https://forth-standard.org/standard/core/Rfrom)
  (func $R> (param $tos i32) (result i32)
    (global.set $tors (i32.sub (global.get $tors) (i32.const 4)))
    (i32.store (local.get $tos) (i32.load (global.get $tors)))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20704) "\f4\06\02\00" "\02" "R> " "\81\00\00\00")
  (elem (i32.const 0x81) $R>)

  ;; [6.1.2070](https://forth-standard.org/standard/core/RFetch)
  (func $R@ (param $tos i32) (result i32)
    (i32.store (local.get $tos) (i32.load (i32.sub (global.get $tors) (i32.const 4))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20710) "\04\07\02\00" "\02" "R@ " "\82\00\00\00")
  (elem (i32.const 0x82) $R@)

  ;; [6.1.2120](https://forth-standard.org/standard/core/RECURSE)
  (func $RECURSE  (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileRecurse))
  (data (i32.const 0x2071c) "\10\07\02\00" "\87" (; F_IMMEDIATE ;) "RECURSE" "\83\00\00\00")
  (elem (i32.const 0x83) $RECURSE)

  ;; [6.2.2125](https://forth-standard.org/standard/core/REFILL)
  (func $REFILL (param $tos i32) (result i32)
    (local $char i32)
    (global.set $inputBufferSize (i32.const 0))
    (i32.store (i32.const 0x202a0 (; = body(>IN) ;)) (i32.const 0))
    (local.get $tos)
    (if (param i32) (result i32) (i32.eq (global.get $sourceID) (i32.const -1))
      (then
        (call $push (i32.const -1))
        (return)))
    (global.set $inputBufferSize 
      (call $shell_read 
        (i32.const 0x0 (; = INPUT_BUFFER_BASE ;)) 
        (i32.const 0x1000 (; = INPUT_BUFFER_SIZE ;))))
    (if (param i32) (result i32) (i32.eqz (global.get $inputBufferSize))
      (then (call $push (i32.const 0)))
      (else (call $push (i32.const -1)))))
  (data (i32.const 0x2072c) "\1c\07\02\00" "\06" "REFILL " "\84\00\00\00")
  (elem (i32.const 0x84) $REFILL)

  ;; [6.1.2140](https://forth-standard.org/standard/core/REPEAT)
  (func $REPEAT (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileRepeat))
  (data (i32.const 0x2073c) "\2c\07\02\00" "\86" (; F_IMMEDIATE ;) "REPEAT " "\85\00\00\00")
  (elem (i32.const 0x85) $REPEAT)

  ;; [6.1.2160](https://forth-standard.org/standard/core/ROT)
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
  (data (i32.const 0x2074c) "\3c\07\02\00" "\03" "ROT" "\86\00\00\00")
  (elem (i32.const 0x86) $ROT)

  ;; [6.1.2162](https://forth-standard.org/standard/core/RSHIFT)
  (func $RSHIFT (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.shr_u (i32.load (local.get $bbtos))
                          (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))))
    (local.get $btos))
  (data (i32.const 0x20758) "\4c\07\02\00" "\06" "RSHIFT " "\87\00\00\00")
  (elem (i32.const 0x87) $RSHIFT)

  ;; [6.1.2165](https://forth-standard.org/standard/core/Sq)
  (func $Sq (param $tos i32) (result i32)
    (local $c i32)
    (local $addr i32)
    (local $len i32)
    (local.get $tos)
    (call $ensureCompiling)
    (local.set $addr (local.set $len (call $parse (i32.const 0x22 (; = '"' ;)))))
    (memory.copy (global.get $here) (local.get $addr) (local.get $len))
    (call $compilePushConst (global.get $here))
    (call $compilePushConst (local.get $len))
    (global.set $here 
      (call $aligned (i32.add (global.get $here) (local.get $len)))))
  (data (i32.const 0x20768) "\58\07\02\00" "\82" (; F_IMMEDIATE ;) "S\22 " "\88\00\00\00")
  (elem (i32.const 0x88) $Sq)

  ;; [6.1.2170](https://forth-standard.org/standard/core/StoD)
  (func $S>D (param $tos i32) (result i32)
    (local $btos i32)
    (i64.store (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))
      (i64.extend_i32_s (i32.load (local.get $btos))))
    (i32.add (local.get $tos) (i32.const 4)))
  (data (i32.const 0x20774) "\68\07\02\00" "\03" "S>D" "\89\00\00\00")
  (elem (i32.const 0x89) $S>D)

  (func $SCALL (param $tos i32) (result i32)
    (global.set $tos (local.get $tos))
    (call $shell_call)
    (global.get $tos))
  (data (i32.const 0x20780) "\74\07\02\00" "\05" "SCALL  " "\8a\00\00\00")
  (elem (i32.const 0x8a) $SCALL)

  ;; [6.1.2210](https://forth-standard.org/standard/core/SIGN)
  (func $SIGN (param $tos i32) (result i32)
    (local $btos i32)
    (local $npo i32)
    (if (i32.lt_s (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))) (i32.const 0))
      (then 
        (i32.store8 (local.tee $npo (i32.sub (global.get $po) (i32.const 1))) (i32.const 0x2d (; = '-' ;)))
        (global.set $po (local.get $npo))))
    (local.get $btos))
  (data (i32.const 0x20790) "\80\07\02\00" "\04" "SIGN   " "\8b\00\00\00")
  (elem (i32.const 0x8b) $SIGN)

  ;; [6.1.2214](https://forth-standard.org/standard/core/SMDivREM)
  ;;
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
  (data (i32.const 0x207a0) "\90\07\02\00" "\06" "SM/REM " "\8c\00\00\00")
  (elem (i32.const 0x8c) $SM/REM)

  ;; [6.1.2216](https://forth-standard.org/standard/core/SOURCE)
  (func $SOURCE (param $tos i32) (result i32)
    (local.get $tos)
    (call $push (global.get $inputBufferBase))
    (call $push (global.get $inputBufferSize)))
  (data (i32.const 0x207b0) "\a0\07\02\00" "\06" "SOURCE " "\8d\00\00\00")
  (elem (i32.const 0x8d) $SOURCE)

  ;; [6.2.2218](https://forth-standard.org/standard/core/SOURCE-ID)
  (func $SOURCE-ID (param $tos i32) (result i32)
    (call $push (local.get $tos) (global.get $sourceID)))
  (data (i32.const 0x207c0) "\b0\07\02\00" "\09" "SOURCE-ID  " "\8e\00\00\00")
  (elem (i32.const 0x8e) $SOURCE-ID)

  ;; [6.1.2220](https://forth-standard.org/standard/core/SPACE)
  (func $SPACE (param $tos i32) (result i32)
    (local.get $tos)
    (call $BL) (call $EMIT))
  (data (i32.const 0x207d4) "\c0\07\02\00" "\05" "SPACE  " "\8f\00\00\00")
  (elem (i32.const 0x8f) $SPACE)

  ;; [6.1.2230](https://forth-standard.org/standard/core/SPACES)
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
  (data (i32.const 0x207e4) "\d4\07\02\00" "\06" "SPACES " "\90\00\00\00")
  (elem (i32.const 0x90) $SPACES)

  ;; [6.1.2250](https://forth-standard.org/standard/core/STATE)
  (data (i32.const 0x207f4) "\e4\07\02\00" "\45" (; F_DATA ;) "STATE  " "\03\00\00\00" (; = pack(PUSH_DATA_ADDRESS_INDEX) ;) "\00\00\00\00" (; = pack(0) ;))

  ;; [6.1.2260](https://forth-standard.org/standard/core/SWAP)
  (func $SWAP (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (local $tmp i32)
    (local.set $tmp (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))))
    (i32.store (local.get $bbtos) 
                (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (i32.store (local.get $btos) (local.get $tmp))
    (local.get $tos))
  (data (i32.const 0x20808) "\f4\07\02\00" "\04" "SWAP   " "\91\00\00\00")
  (elem (i32.const 0x91) $SWAP)

  ;; [6.1.2270](https://forth-standard.org/standard/core/THEN)
  (func $THEN (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileThen))
  (data (i32.const 0x20818) "\08\08\02\00" "\84" (; F_IMMEDIATE ;) "THEN   " "\92\00\00\00")
  (elem (i32.const 0x92) $THEN)

  ;; [6.2.2295](https://forth-standard.org/standard/core/TO)
  (func $TO (param $tos i32) (result i32)
    (local $v i32)
    (local $xt i32)
    (local $btos i32)
    (local.set $xt (drop (call $find! (call $parseName))))
    (i32.store (i32.add (call $body (local.get $xt)) (i32.const 4)) 
      (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (local.get $btos))
  (data (i32.const 0x20828) "\18\08\02\00" "\02" "TO " "\93\00\00\00")
  (elem (i32.const 0x93) $TO)

  ;; [6.2.2298](https://forth-standard.org/standard/core/TRUE)
  (func $TRUE (param $tos i32) (result i32)
    (call $push (local.get $tos) (i32.const 0xffffffff)))
  (data (i32.const 0x20834) "\28\08\02\00" "\04" "TRUE   " "\94\00\00\00")
  (elem (i32.const 0x94) $TRUE)

  ;; [6.2.2300](https://forth-standard.org/standard/core/TUCK)
  (func $TUCK (param $tos i32) (result i32)
    (local.get $tos)
    (call $SWAP) (call $OVER))
  (data (i32.const 0x20844) "\34\08\02\00" "\04" "TUCK   " "\95\00\00\00")
  (elem (i32.const 0x95) $TUCK)

  ;; [6.1.2310](https://forth-standard.org/standard/core/TYPE)
  (func $TYPE (param $tos i32) (result i32)
    (local $p i32)
    (local $len i32)
    (local.get $tos)
    (local.set $len (call $pop))
    (local.set $p (call $pop))
    (call $type (local.get $p) (local.get $len)))
  (data (i32.const 0x20854) "\44\08\02\00" "\04" "TYPE   " "\96\00\00\00")
  (elem (i32.const 0x96) $TYPE)

  ;; [6.1.2320](https://forth-standard.org/standard/core/Ud)
  (func $U. (param $tos i32) (result i32)
    (local.get $tos)
    (call $U._ (call $pop) (i32.load (i32.const 0x20364 (; = body(BASE) ;))))
    (call $shell_emit (i32.const 0x20)))
  (data (i32.const 0x20864) "\54\08\02\00" "\02" "U. " "\97\00\00\00")
  (elem (i32.const 0x97) $U.)

  ;; [6.1.2340](https://forth-standard.org/standard/core/Uless)
  (func $U< (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (if (i32.lt_u (i32.load (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8))))
                  (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
      (then (i32.store (local.get $bbtos) (i32.const -1)))
      (else (i32.store (local.get $bbtos) (i32.const 0))))
    (local.get $btos))
  (data (i32.const 0x20870) "\64\08\02\00" "\02" "U< " "\98\00\00\00")
  (elem (i32.const 0x98) $U<)

  ;; [6.1.2360](https://forth-standard.org/standard/core/UMTimes)
  (func $UM* (param $tos i32) (result i32)
    (local $bbtos i32)
    (i64.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i64.mul (i64.extend_i32_u (i32.load (local.get $bbtos)))
                        (i64.extend_i32_u (i32.load (i32.sub (local.get $tos) 
                                                              (i32.const 4))))))
    (local.get $tos))
  (data (i32.const 0x2087c) "\70\08\02\00" "\03" "UM*" "\99\00\00\00")
  (elem (i32.const 0x99) $UM*)

  ;; [6.1.2370](https://forth-standard.org/standard/core/UMDivMOD)
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
  (data (i32.const 0x20888) "\7c\08\02\00" "\06" "UM/MOD " "\9a\00\00\00")
  (elem (i32.const 0x9a) $UM/MOD)

  ;; [6.1.2380](https://forth-standard.org/standard/core/UNLOOP)
  (func $UNLOOP (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $emitICall (i32.const 0) (i32.const 0x9 (; = END_DO_INDEX ;))))
  (data (i32.const 0x20898) "\88\08\02\00" "\86" (; F_IMMEDIATE ;) "UNLOOP " "\9b\00\00\00")
  (elem (i32.const 0x9b) $UNLOOP)

  ;; [6.1.2390](https://forth-standard.org/standard/core/UNTIL)
  (func $UNTIL (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileUntil))
  (data (i32.const 0x208a8) "\98\08\02\00" "\85" (; F_IMMEDIATE ;) "UNTIL  " "\9c\00\00\00")
  (elem (i32.const 0x9c) $UNTIL)

  ;; [6.2.2395](https://forth-standard.org/standard/core/UNUSED)
  (func $UNUSED (param $tos i32) (result i32)
    (local.get $tos)
    (call $push (i32.shr_s (i32.sub (i32.const 0x6400000 (; = MEMORY_SIZE ;)) (global.get $here)) (i32.const 2))))
  (data (i32.const 0x208b8) "\a8\08\02\00" "\06" "UNUSED " "\9d\00\00\00")
  (elem (i32.const 0x9d) $UNUSED)

  ;; [6.2.2405](https://forth-standard.org/standard/core/VALUE)
  (data (i32.const 0x208c8) "\b8\08\02\00" "\05" "VALUE  " "\4f\00\00\00" (; = pack(index("CONSTANT")) ;))

  ;; [6.1.2410](https://forth-standard.org/standard/core/VARIABLE)
  (func $VARIABLE (param $tos i32) (result i32)
    (local.get $tos)
    (call $CREATE)
    (global.set $here (i32.add (global.get $here) (i32.const 4))))
  (data (i32.const 0x208d8) "\c8\08\02\00" "\08" "VARIABLE   " "\9e\00\00\00")
  (elem (i32.const 0x9e) $VARIABLE)

  ;; [6.1.2430](https://forth-standard.org/standard/core/WHILE)
  (func $WHILE (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $compileWhile))
  (data (i32.const 0x208ec) "\d8\08\02\00" "\85" (; F_IMMEDIATE ;) "WHILE  " "\9f\00\00\00")
  (elem (i32.const 0x9f) $WHILE)

  ;; [6.1.2450](https://forth-standard.org/standard/core/WORD)
  (func $WORD (param $tos i32) (result i32)
    (local $wordBase i32)
    (local $addr i32)
    (local $len i32)
    (local $delimiter i32)
    (local.get $tos)
    (local.set $delimiter (call $pop))
    (call $skip (local.get $delimiter))
    (local.set $addr (local.set $len (call $parse (local.get $delimiter))))
    (memory.copy 
      (i32.add 
        (local.tee $wordBase (i32.add (global.get $here) (i32.const 0x200 (; = WORD_OFFSET ;)))) 
        (i32.const 1))
      (local.get $addr)
      (local.get $len))
    (i32.store8 (local.get $wordBase) (local.get $len))
    (call $push (local.get $wordBase)))
  (data (i32.const 0x208fc) "\ec\08\02\00" "\04" "WORD   " "\a0\00\00\00")
  (elem (i32.const 0xa0) $WORD)

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
            (i32.add (local.get $entryP) (i32.const 5))
            (i32.and (local.get $entryLF) (i32.const 0x1f (; = LENGTH_MASK ;))))
          (call $shell_emit (i32.const 0x20))))
      (local.set $entryP (i32.load (local.get $entryP)))
      (br_if $loop (local.get $entryP)))
    (local.get $tos))
  (data (i32.const 0x2090c) "\fc\08\02\00" "\05" "WORDS  " "\a1\00\00\00")
  (elem (i32.const 0xa1) $WORDS)

  ;; [6.1.2490](https://forth-standard.org/standard/core/XOR)
  (func $XOR (param $tos i32) (result i32)
    (local $btos i32)
    (local $bbtos i32)
    (i32.store (local.tee $bbtos (i32.sub (local.get $tos) (i32.const 8)))
                (i32.xor (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4))))
                        (i32.load (local.get $bbtos))))
    (local.get $btos))
  (data (i32.const 0x2091c) "\0c\09\02\00" "\03" "XOR" "\a2\00\00\00")
  (elem (i32.const 0xa2) $XOR)

  ;; [6.1.2500](https://forth-standard.org/standard/core/Bracket)
  (func $left-bracket (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (i32.store (i32.const 0x20804 (; = body(STATE) ;)) (i32.const 0)))
  (data (i32.const 0x20928) "\1c\09\02\00" "\81" (; F_IMMEDIATE ;) "[  " "\a3\00\00\00")
  (elem (i32.const 0xa3) $left-bracket)

  ;; [6.1.2510](https://forth-standard.org/standard/core/BracketTick)
  (func $bracket-tick (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $')
    (call $compilePushConst (call $pop)))
  (data (i32.const 0x20934) "\28\09\02\00" "\83" (; F_IMMEDIATE ;) "[']" "\a4\00\00\00")
  (elem (i32.const 0xa4) $bracket-tick)

  ;; [6.1.2520](https://forth-standard.org/standard/core/BracketCHAR)
  (func $bracket-char (param $tos i32) (result i32)
    (local.get $tos)
    (call $ensureCompiling)
    (call $CHAR)
    (call $compilePushConst (call $pop)))
  (data (i32.const 0x20940) "\34\09\02\00" "\86" (; F_IMMEDIATE ;) "[CHAR] " "\a5\00\00\00")
  (elem (i32.const 0xa5) $bracket-char)

  ;; [6.2.2535](https://forth-standard.org/standard/core/bs)
  (func $\ (param $tos i32) (result i32)
    (drop (drop (call $parse (i32.const 0x0a (; '\n' ;)))))
    (local.get $tos))
  (data (i32.const 0x20950) "\40\09\02\00" "\81" (; F_IMMEDIATE ;) "\5c  " "\a6\00\00\00")
  (elem (i32.const 0xa6) $\)

  ;; [6.1.2540](https://forth-standard.org/standard/right-bracket)
  (func $right-bracket (param $tos i32) (result i32)
    (i32.store (i32.const 0x20804 (; = body(STATE) ;)) (i32.const 1))
    (local.get $tos))
  (data (i32.const 0x2095c) "\50\09\02\00" "\01" "]  " "\a7\00\00\00")
  (elem (i32.const 0xa7) $right-bracket)


  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Interpreter
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; Interprets the string in the input, until the end of string is reached.
  ;; Returns 0 if processed, 1 if still compiling, or traps if a word 
  ;; was not found.
  (func $interpret (param $tos i32) (result i32)
    (local $FINDResult i32)
    (local $FINDToken i32)
    (local $error i32)
    (local $number i32)
    (local $wordAddr i32)
    (local $wordLen i32)
    (local.set $error (i32.const 0))
    (global.set $tors (i32.const 0x2000 (; = RETURN_STACK_BASE ;)))
    (block $endLoop 
      (loop $loop
        (local.set $wordAddr (local.set $wordLen (call $parseName)))
        (br_if $endLoop (i32.eqz (local.get $wordLen)))
        (local.set $FINDToken (local.set $FINDResult 
          (call $find (local.get $wordAddr) (local.get $wordLen))))
        (if (i32.eqz (local.get $FINDResult))
          (then ;; Not in the dictionary. Is it a number?
            (if (param i32) (i32.eqz (call $readNumber (local.get $wordAddr) (local.get $wordLen)))
              (then ;; It's a number. Are we compiling?
                (local.set $number)
                (if (i32.load (i32.const 0x20804 (; = body(STATE) ;)))
                  (then
                    ;; We're compiling. Pop it off the stack and 
                    ;; add it to the compiled list
                    (local.set $tos (call $compilePushConst (local.get $tos) (local.get $number))))
                  (else 
                    ;; We're not compiling. Put the number on the stack.
                    (local.set $tos (call $push (local.get $tos) (local.get $number))))))
              (else ;; It's not a number.
                (drop)
                (call $failUndefinedWord (local.get $wordAddr) (local.get $wordLen)))))
          (else ;; Found the word. 
            ;; Are we compiling or is it immediate?
            (if
                (i32.or 
                  (i32.eqz (i32.load (i32.const 0x20804 (; = body(STATE) ;))))
                  (i32.eq (local.get $FINDResult) (i32.const 1)))
              (then
                (local.get $tos)
                (call $push (local.get $FINDToken))
                (call $EXECUTE)
                (local.set $tos))
              (else
                ;; We're compiling a non-immediate
                (local.set $tos (call $compileCall (local.get $tos) (local.get $FINDToken)))))))
          (br $loop)))
    (local.get $tos))

  ;; Returns (number, unparsed length)
  (func $readNumber (param $addr i32) (param $len i32) (result i32 i32)
    (local $restcount i32)
    (local $value i32)
    (if (i32.eqz (local.get $len))
      (return (i32.const -1) (i32.const -1)))
    (call $number (i64.const 0) (local.get $addr) (local.get $len))
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
    (local.set $base (i32.load (i32.const 0x20364 (; = body(BASE) ;))))

    ;; Read first character
    (if (i32.eq (local.tee $char (i32.load8_u (local.get $p))) (i32.const 0x2d (; = '-' ;)))
      (then 
        (local.set $sign (i64.const -1))
        (local.set $char (i32.const 0x30 (; = '0' ;) ))
        (if (i32.eq (local.get $length) (i32.const 1))
          (then
            (return (local.get $value) (local.get $p) (local.get $length)))))
      (else 
        (local.set $sign (i64.const 1))))

    ;; Read all characters
    (block $endLoop
      (loop $loop
        (if (i32.lt_s (local.get $char) (i32.const 0x30 (; = '0' ;) ))
          (br $endLoop))      
        (if (i32.le_s (local.get $char) (i32.const 0x39 (; = '9' ;) ))
          (then 
            (local.set $n (i32.sub (local.get $char) (i32.const 48))))
          (else
            (if (i32.lt_s (local.get $char) (i32.const 0x41 (; = 'A' ;) ))
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
  
  (func $quit (param $tos i32) (result i32)
    (global.set $tos (local.get $tos))
    (global.set $tors (i32.const 0x2000 (; = RETURN_STACK_BASE ;)))
    (global.set $sourceID (i32.const 0))
    (i32.store (i32.const 0x20804 (; = body(STATE) ;)) (i32.const 0))
    (unreachable))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Interpreter state
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; Top of stack
  (global $tos (mut i32) (i32.const 0x10000 (; = STACK_BASE ;)))

  ;; Top of return stack
  (global $tors (mut i32) (i32.const 0x2000 (; = RETURN_STACK_BASE ;)))

  ;; Input buffer
  (global $inputBufferBase (mut i32) (i32.const 0x0 (; = INPUT_BUFFER_BASE ;)))
  (global $inputBufferSize (mut i32) (i32.const 0))

  ;; Source ID
  (global $sourceID (mut i32) (i32.const 0))

  ;; Dictionary pointers
  (global $latest (mut i32) (i32.const 0x2095c))
  (global $here (mut i32) (i32.const 0x20968))
  (global $nextTableIndex (mut i32) (i32.const 0xa8))

  ;; Pictured output pointer
  (global $po (mut i32) (i32.const -1))

  ;; Error code
  ;; 
  ;; This can only be inspected after an interpret() call (using error()).
  ;;
  ;; Values:
  ;;   ERR_UNKNOWN := 0x1   (Unknown error, e.g. exception during one of the `shell` functions)
  ;;   ERR_QUIT :=    0x2   (QUIT called)
  ;;   ERR_ABORT :=   0x3   (ABORT or ABORT" called)
  ;;   ERR_EOI :=     0x4   (No more user input received)
  (global $error (mut i32) (i32.const 0x0))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Compiler functions
  ;;
  ;; `compileXXXX` functions compile Forth words. These are mostly defined in terms of
  ;; several lower level `emitXXXX` functions.
  ;;
  ;; `emitXXXX` words are low level functions that emit a single WebAssembly 
  ;; instruction in binary format. This is a direct translation from the WebAssembly
  ;; spec.
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
                                        (i32.const 0x1f (; = LENGTH_MASK ;))))
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
    ;; Save branch nesting
    (i32.store (local.get $tos) (global.get $branchNesting))
    (local.set $tos (i32.add (local.get $tos) (i32.const 4)))
    (global.set $branchNesting (i32.const 0))

    ;; 1: $diff_i = end index - current index
    ;; 2: $end_i
    (global.set $currentLocal (i32.add (global.get $currentLocal) (i32.const 2)))
    (if (i32.gt_s (global.get $currentLocal) (global.get $lastLocal))
      (then
        (global.set $lastLocal (global.get $currentLocal))))

    ;; $1 = current index (temporary)
    (call $compilePop)
    (call $emitSetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    ;; $end_i = end index
    (call $compilePop)
    (call $emitSetLocal (global.get $currentLocal))

    ;; Already emit the block, so we can jump out of it before starting DO
    ;; in the conditional case
    (call $emitBlock)

    ;; startDo $1
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitICall (i32.const 1) (i32.const 0x1 (; = START_DO_INDEX ;)))
    
    ;; $diff = $1 - $end_i
    (call $emitGetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))
    (call $emitGetLocal (global.get $currentLocal))
    (call $emitSub)
    (call $emitSetLocal (i32.sub (global.get $currentLocal) (i32.const 1)))

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
    (call $emitICall (i32.const 1) (i32.const 0x2 (; = UPDATE_DO_INDEX ;)))
    
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
    (call $emitICall (i32.const 1) (i32.const 0x2 (; = UPDATE_DO_INDEX ;)))

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
    (call $emitICall (i32.const 0) (i32.const 0x9 (; = END_DO_INDEX ;)))
    (call $emitEnd)
    (call $emitEnd)
    (global.set $currentLocal (i32.sub (global.get $currentLocal) (i32.const 2)))

    ;; Restore branch nesting
    (global.set $branchNesting (i32.load (local.tee $btos (i32.sub (local.get $tos) (i32.const 4)))))
    (local.get $btos))

  (func $compileLeave
    (call $emitICall (i32.const 0) (i32.const 0x9 (; = END_DO_INDEX ;)))
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
  (elem (i32.const 0x5 (; = COMPILE_CALL_INDEX ;)) $compileCall)

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
  (elem (i32.const 0x1 (; = START_DO_INDEX ;)) $startDo)

  (func $endDo (param $tos i32) (result i32)
    (global.set $tors (i32.sub (global.get $tors) (i32.const 4)))
    (local.get $tos))
  (elem (i32.const 0x9 (; = END_DO_INDEX ;)) $endDo)

  (func $updateDo (param $tos i32) (param $i i32) (result i32)
    (i32.store (i32.sub (global.get $tors) (i32.const 4)) (local.get $i))
    (local.get $tos))
  (elem (i32.const 0x2 (; = UPDATE_DO_INDEX ;)) $updateDo)

  (func $pushDataAddress (param $tos i32) (param $d i32) (result i32)
    (call $push (local.get $tos) (local.get $d)))
  (elem (i32.const 0x3 (; = PUSH_DATA_ADDRESS_INDEX ;)) $pushDataAddress)

  (func $setLatestBody (param $tos i32) (param $v i32) (result i32)
    (i32.store (call $body (local.get $tos) (global.get $latest)) (local.get $v)))
  (elem (i32.const 0x4 (; = SET_LATEST_BODY_INDEX ;)) $setLatestBody)

  (func $pushIndirect (param $tos i32) (param $v i32) (result i32)
    (call $push (local.get $tos) (i32.load (local.get $v))))
  (elem (i32.const 0x6 (; = PUSH_INDIRECT_INDEX ;)) $pushIndirect)

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

  (func $fail (param $str i32)
    (call $type 
      (i32.add (local.get $str) (i32.const 1))
      (i32.load8_u (local.get $str)))
    (call $shell_emit (i32.const 10))
    (drop (call $ABORT (i32.const -1) (; unused ;))))

  (func $failUndefinedWord (param $addr i32) (param $len i32)
    (call $type (i32.const 0x20001) (i32.load8_u (i32.const 0x20000)))
    (call $shell_emit (i32.const 0x3a (; = ':' ;)))
    (call $shell_emit (i32.const 0x20 (; = ' ' ;)))
    (call $type (local.get $addr) (local.get $len))
    (call $shell_emit (i32.const 0x0a))
    (drop (call $ABORT (i32.const -1) (; unused ;))))

  (func $type (param $p i32) (param $len i32)
    (local $end i32)
    (local.set $end (i32.add (local.get $p) (local.get $len)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eq (local.get $p) (local.get $end)))
        (call $shell_emit (i32.load8_u (local.get $p)))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        (br $loop))))

  (func $setFlag (param $v i32)
    (i32.store 
      (i32.add (global.get $latest) (i32.const 4))
      (i32.or 
        (i32.load (i32.add (global.get $latest) (i32.const 4)))
        (local.get $v))))

  (func $ensureCompiling (param $tos i32) (result i32)
    (local.get $tos) 
    (if (param i32) (result i32) (i32.eqz (i32.load (i32.const 0x20804 (; = body(STATE) ;))))
      (call $fail (i32.const 0x2002e (; = str("word not supported in interpret mode") ;)))))

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
            (i32.const 0x1f (; = LENGTH_MASK ;))))
        (i32.const 8 (; 4 + 1 + 3 ;)))
      (i32.const -4)))

  (func $numberToChar (param $v i32) (result i32)
    (if (result i32) (i32.ge_u (local.get $v) (i32.const 10))
      (then
        (i32.add (local.get $v) (i32.const 0x37)))
      (else
        (i32.add (local.get $v) (i32.const 0x30)))))
  
  ;; Returns address+length
  (func $parseName (result i32 i32)
    (call $skip (i32.const 0x20 (; = ' ' ;)))
    (call $parse (i32.const 0x20 (; = ' ' ;))))

  ;; Returns address+length
  (func $parse (param $delim i32) (result i32 i32)
    (local $addr i32)
    (local $p i32)
    (local $end i32)
    (local $c i32)
    (local $delimited i32)
    (local.set $p 
      (local.tee $addr (i32.add (global.get $inputBufferBase) 
      (i32.load (i32.const 0x202a0 (; = body(>IN) ;))))))
    (local.set $end (i32.add (global.get $inputBufferBase) (global.get $inputBufferSize)))
    (local.set $delimited (i32.const 0))
    (block $endOfInput
      (block $delimiter
        (loop $read
          (br_if $endOfInput (i32.eq (local.get $p) (local.get $end)))
          (local.set $c (i32.load8_s (local.get $p)))
          (local.set $p (i32.add (local.get $p) (i32.const 1)))
          (br_if $delimiter (i32.eq (local.get $c) (i32.const 0xa)))
          (br_if $read (i32.ne (local.get $c) (local.get $delim)))))
      (local.set $delimited (i32.const 1)))
    (i32.store (i32.const 0x202a0 (; = body(>IN) ;)) 
      (i32.sub (local.get $p) (global.get $inputBufferBase)))
    (local.get $addr)
    (i32.sub
      (i32.sub (local.get $p) (local.get $delimited))
      (local.get $addr)))

  (func $skip (param $delim i32)
    (local $addr i32)
    (local $p i32)
    (local $end i32)
    (local $c i32)
    (local.set $p 
      (local.tee $addr (i32.add (global.get $inputBufferBase) 
      (i32.load (i32.const 0x202a0 (; = body(>IN) ;))))))
    (local.set $end (i32.add (global.get $inputBufferBase) (global.get $inputBufferSize)))
    (block $endLoop
      (loop $loop
        (br_if $endLoop (i32.eq (local.get $p) (local.get $end)))
        (local.set $c (i32.load8_s (local.get $p)))
        (br_if $endLoop (i32.ne (local.get $c) (local.get $delim)))
        (local.set $p (i32.add (local.get $p) (i32.const 1)))
        ;; Eat up a newline
        (br_if $loop (i32.ne (local.get $c) (i32.const 0xa)))))
    (i32.store (i32.const 0x202a0 (; = body(>IN) ;)) 
      (i32.sub (local.get $p) (global.get $inputBufferBase))))

  ;; Returns xt, type (0 = not found, 1 = immediate, -1 = non-immediate)
  (func $find (param $addr i32) (param $len i32) (result i32) (result i32)
    (local $entryP i32)
    (local $entryLF i32)
    (local.set $entryP (global.get $latest))
    (loop $loop
      (if 
          (i32.and 
            (i32.eqz
              (i32.and 
                (local.tee $entryLF (i32.load (i32.add (local.get $entryP) (i32.const 4))))
                (i32.const 0x20 (; = F_HIDDEN ;))))
            (call $stringEqual 
              (local.get $addr) (local.get $len)
              (i32.add (local.get $entryP) (i32.const 5)) (i32.and (local.get $entryLF) (i32.const 0x1f (; = LENGTH_MASK ;)))))
        (then
          (return
            (local.get $entryP)
            (select 
              (i32.const -1)
              (i32.const 1)
              (i32.eqz (i32.and (local.get $entryLF) (i32.const 0x80 (; = F_IMMEDIATE ;))))))))
      (local.set $entryP (i32.load (local.get $entryP)))
      (br_if $loop (local.get $entryP)))
    (i32.const 0) (i32.const 0))
  
  ;; Returns xt, type (1 = immediate, -1 = non-immediate)
  ;; Aborts if not found
  (func $find! (param $addr i32) (param $len i32) (result i32) (result i32)
    (local $r i32)
    (if (i32.eqz (local.tee $r (call $find (local.get $addr) (local.get $len))))      
      (call $failUndefinedWord (local.get $addr) (local.get $len)))
    (local.get $r))

  (func $aligned (param $addr i32) (result i32)
    (i32.and 
      (i32.add (local.get $addr) (i32.const 3)) 
      (i32.const -4 (; ~3 ;))))

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
  
  (func (export "error") (result i32)
    (global.get $error))

  (func (export "interpret") (param $silent i32)
    (local $state i32)
    (local $tos i32)
    (local.tee $tos (global.get $tos))
    (global.set $error (i32.const 0x1 (; = ERR_UNKNOWN ;)))
    (block $endLoop (param i32) (result i32)
      (loop $loop (param i32) (result i32)
        (call $REFILL)
        (br_if $endLoop (i32.eqz (call $pop)))
        (local.set $tos (call $interpret))

        ;; Check for stack underflow
        (if (i32.lt_s (local.get $tos) (i32.const 0x10000 (; = STACK_BASE ;)))
          (call $fail (i32.const 0x20085 (; = str("stack empty") ;))))

        ;; Show prompt
        (if (i32.eqz (local.get $silent))
          (then
            (if (i32.ge_s (i32.load (i32.const 0x20804 (; = body(STATE) ;))) (i32.const 0))
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
      (global.set $error (i32.const 0x4 (; = ERR_EOI ;))))

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
