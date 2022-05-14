/**
 * Simple example to show how to embed WAForth in JavaScript, and call JavaScript
 * from within Forth code.
 */

import "./prompt.css";
import WAForth from "waforth";

(async () => {
  // Create the UI
  document.body.innerHTML = `<button>Go!</button><pre></pre>`;
  const btn = document.querySelector("button")!;
  const log = document.querySelector("pre")!;

  // Initialize WAForth
  const forth = new WAForth();
  forth.onEmit = (c) => log.appendChild(document.createTextNode(c));
  await forth.load();

  // Bind "prompt" call to a function that pops up a JavaScript prompt, and pushes the entered number back on the stack
  forth.bind("prompt", (stack) => {
    const message = stack.popString();
    const result = window.prompt(message);
    stack.push(parseInt(result ?? ""));
  });

  // Load Forth code to bind the "prompt" call to a word, and call the word
  forth.interpret(`
( Call "prompt" with the given string )
: PROMPT ( c-addr u -- n )
  S" prompt" SCALL 
;

( Prompt the user for a number, and write it to output )
: ASK-NUMBER ( -- )
  S" Please enter a number" PROMPT
  ." The number was " . CR
;
`);

  // Ask for a number (via Forth) when the user clicks the button
  btn.addEventListener("click", () => {
    forth.interpret("ASK-NUMBER");
  });
})();
