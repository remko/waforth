export type Example = {
  name: string;
  program: string;
};

export default [
  {
    name: "Square",
    program: `
200 FORWARD
90 RIGHT
200 FORWARD
90 RIGHT
200 FORWARD
90 RIGHT
200 FORWARD
90 RIGHT
`,
  },
  {
    name: "Square (w/ LOOP)",
    program: `
: SQUARE ( n -- )
  4 0 DO
    DUP FORWARD
    90 RIGHT
  LOOP
;

250 SQUARE
`,
  },
  {
    name: "Pentagram",
    program: `
: PENTAGRAM ( n -- )
  18 RIGHT
  5 0 DO
    DUP FORWARD
    144 RIGHT
  LOOP
;
  
450 PENTAGRAM
`,
  },
  {
    name: "Seeker",
    program: `
: SEEKER ( n -- )
  4 0 DO
    DUP FORWARD
    PENUP
    DUP FORWARD
    PENDOWN
    DUP FORWARD
    90 RIGHT
  LOOP
;

100 SEEKER
`,
  },
  {
    name: "Flower",
    program: `
: SQUARE ( n -- )
  4 0 DO
    DUP FORWARD
    90 RIGHT
  LOOP
;

: FLOWER ( n -- )
  24 0 DO
    DUP SQUARE
    15 RIGHT
  LOOP
;

250 FLOWER
`,
  },
  {
    name: "Spiral (Recursive)",
    program: `
: SPIRAL ( n -- )
  DUP 1 < IF DROP EXIT THEN 
  DUP FORWARD
  15 RIGHT
  98 100 */ RECURSE
;

PENUP -500 -180 SETXY PENDOWN
140 SPIRAL
`,
  },
  {
    name: "Outward Square Spiral",
    program: `
: SPIRAL ( n1 n2 -- )
  OVER 800 > IF 2DROP EXIT THEN 
  OVER FORWARD
  DUP RIGHT
  SWAP 10 + SWAP
  RECURSE
;

1 90 SPIRAL
`,
  },
  {
    name: "Crooked Outward Square Spiral",
    program: `
91 CONSTANT ANGLE

: SPIRAL ( n -- )
  DUP 800 > IF DROP EXIT THEN 
  DUP FORWARD
  ANGLE RIGHT
  10 +
  RECURSE
;

1 SPIRAL`,
  },
].map((e) => ({ ...e, program: e.program.trimStart() }));
