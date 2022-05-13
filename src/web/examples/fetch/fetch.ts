import "./fetch.css";
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

  // Bind "age" call to a function that fetches the age of the given person, and calls the continuation callback
  forth.bind("age", async (stack) => {
    const name = stack.popString();
    const result = await (
      await fetch("https://api.agify.io/?name=" + encodeURIComponent(name))
    ).json();

    // After this point, use the `forth` object directly, since we're no longer in the callback.
    forth.push(parseInt(result.age));
    forth.interpret("AGE-CB");
  });

  // Load Forth code to bind the "age" call, and define the continuation callback
  forth.interpret(`
: AGE ( c-addr u -- )
  S" age" SCALL 
;

: AGE-CB ( d -- )
  ." Your age is " .
;

: GUESS-AGE ( -- )
  S" Remko" AGE
;
`);

  // Ask for a number (via Forth) when the user clicks the button
  btn.addEventListener("click", () => {
    forth.interpret("GUESS-AGE");
  });
})();
