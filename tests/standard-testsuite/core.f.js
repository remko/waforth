export default `

: FOO ." Hello World" CR ;

CR
TESTING CORE WORDS

\\ ------------------------------------------------------------------------
TESTING BASIC ASSUMPTIONS

T{ -> }T               \\ START WITH CLEAN SLATE
( TEST IF ANY BITS ARE SET; ANSWER IN BASE 1 )
T{ : BITSSET? IF 0 0 ELSE 0 THEN ; -> }T
T{  0 BITSSET? -> 0 }T      ( ZERO IS ALL BITS CLEAR )
T{  1 BITSSET? -> 0 0 }T      ( OTHER NUMBER HAVE AT LEAST ONE BIT )
T{ -1 BITSSET? -> 0 0 }T

FOO

`;
