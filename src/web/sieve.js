// Copied from https://rosettacode.org/wiki/Sieve_of_Eratosthenes#Forth
export default `
  : prime? HERE + C@ 0= ;
  : composite! HERE + 1 SWAP C! ;

  : sieve
    HERE OVER ERASE
    2
    BEGIN
      2DUP DUP * >
    WHILE
      DUP prime? IF
        2DUP DUP * DO
          I composite!
        DUP +LOOP
      THEN
      1+
    REPEAT
    DROP
    1 SWAP 2 DO I prime? IF DROP I THEN LOOP .
  ;
`;
