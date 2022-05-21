export type Program = {
  name: string;
  program: string;
  isExample: boolean;
  isEphemeral?: boolean;
};

const examples: Program[] = [
  {
    name: "Square",
    isExample: true,
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
    isExample: true,
    program: `
: SQUARE ( n -- )
  4 0 DO
    DUP FORWARD
    90 RIGHT
  LOOP
  DROP
;

250 SQUARE
`,
  },
  {
    name: "Pentagram",
    isExample: true,
    program: `
: PENTAGRAM ( n -- )
  18 RIGHT
  5 0 DO
    DUP FORWARD
    144 RIGHT
  LOOP
  DROP
;
  
450 PENTAGRAM
`,
  },
  {
    name: "Seeker",
    isExample: true,
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
  DROP
;

100 SEEKER
`,
  },
  {
    name: "Flower",
    isExample: true,
    program: `
: SQUARE ( n -- )
  4 0 DO
    DUP FORWARD
    90 RIGHT
  LOOP
  DROP
;

: FLOWER ( n -- )
  24 0 DO
    DUP SQUARE
    15 RIGHT
  LOOP
  DROP
;

250 FLOWER
`,
  },
  {
    name: "Spiral (Recursive)",
    isExample: true,
    program: `
: SPIRAL ( n -- )
  DUP 1 < IF DROP EXIT THEN 
  DUP FORWARD
  15 RIGHT
  98 100 */ RECURSE
;

140 SPIRAL
`,
  },
  {
    name: "Outward Square Spiral",
    isExample: true,
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
    isExample: true,
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
  {
    name: "Snowflake",
    isExample: true,
    program: `
730 CONSTANT LENGTH
6   CONSTANT DEPTH

: SIDE ( length depth -- )
  DUP 0= IF 
    DROP FORWARD EXIT 
  THEN
  SWAP 3 / SWAP 1-
  2DUP RECURSE
  60 LEFT 2DUP RECURSE
  120 RIGHT 2DUP RECURSE
  60 LEFT RECURSE
;

: SNOWFLAKE ( -- )
  3 0 DO 
    LENGTH DEPTH SIDE
    120 RIGHT
  LOOP
;

1 SETPENSIZE
SNOWFLAKE
`,
  },
  {
    name: "Plant",
    isExample: true,
    program: `
450 CONSTANT SIZE
7   CONSTANT BRANCHES
160 CONSTANT SPREAD

VARIABLE RND
HERE RND !

: RANDOM ( -- n )
  RND @ 75 * 74 + 65537 MOD
  DUP RND !
;

: CHOOSE ( n1 -- n2 )
  RANDOM 65537 */MOD SWAP DROP 
; 

: PLANT ( size angle -- )
  OVER 10 < IF 2DROP EXIT THEN
  DUP RIGHT
  OVER FORWARD
  BRANCHES 0 DO
    OVER 2/
    SPREAD CHOOSE SPREAD 2/ -
    RECURSE
  LOOP
  PENUP SWAP BACKWARD PENDOWN
  LEFT
;
  
1 SETPENSIZE
SIZE 0 PLANT
`,
  },
].map((e) => ({ ...e, program: e.program.trimStart() }));

// Load programs
let programs = examples.slice();
try {
  const prgs = window.localStorage.getItem("thurtle:programs");
  if (prgs != null) {
    programs.push(...JSON.parse(prgs));
  }
} catch (e) {
  // ignore
}

export function listPrograms(): Program[] {
  return programs;
}

export function getProgram(name: string): Program | undefined {
  return listPrograms().find((e) => e.name === name);
}

function savePrograms() {
  console.log("SavePrograms", programs);
  try {
    window.localStorage.setItem(
      "thurtle:programs",
      JSON.stringify(programs.filter((p) => !p.isExample && !p.isEphemeral))
    );
  } catch (e) {
    console.error(e);
    window.alert("Unable to save");
  }
}

export function saveProgram(
  name: string,
  program: string,
  ephemeral = false
): boolean {
  const prg = getProgram(name);
  let isNew = false;
  if (prg != null) {
    prg.program = program;
    prg.isEphemeral = ephemeral;
  } else {
    isNew = true;
    programs.push({
      name,
      isExample: false,
      program,
      isEphemeral: ephemeral,
    });
  }
  savePrograms();
  return isNew;
}

export function deleteProgram(name: string) {
  programs = programs.filter((p) => p.name != name);
  savePrograms();
}
