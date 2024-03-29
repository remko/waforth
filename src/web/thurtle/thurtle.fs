: FORWARD ( n -- ) S" forward" SCALL ;
: BACKWARD ( n -- ) NEGATE FORWARD ;
: LEFT ( n -- ) S" rotate" SCALL ;
: RIGHT ( n -- ) NEGATE LEFT ;
: PENDOWN ( -- ) 1 S" pen" SCALL ;
: PENUP ( -- ) 0 S" pen" SCALL ;
: HIDETURTLE ( -- ) 0 S" turtle" SCALL ;
: SHOWTURTLE ( -- ) 1 S" turtle" SCALL ;
: SETPENSIZE ( n -- ) S" setpensize" SCALL ;
: SETPENCOLOR ( n -- ) S" setpencolor" SCALL ;
: SETSCREENCOLOR ( n -- ) S" setscreencolor" SCALL ;
: SETXY ( n1 n2 -- ) S" setxy" SCALL ;
: SETHEADING ( n -- ) S" setheading" SCALL ;

\ Aliases
: ⬆️ FORWARD ;
: ⬇️ BACKWARD ;
: ⬅️ LEFT ;
: ➡️ RIGHT ;
