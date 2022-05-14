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
  forth.bind("?ip", async () => {
    const cbxt = forth.pop();
    try {
      const result = await (
        await fetch("https://api.ipify.org?format=json")
      ).json();
      forth.pushString(result.ip);
      forth.push(cbxt);
      forth.interpret("EXECUTE");
    } catch (e) {
      console.error(e);
    }
  });

  // Load Forth code to bind the "age" call, and define the continuation callback
  forth.interpret(`
: ?IP-CB ( c-addr n -- )
  ." Your IP address is " TYPE CR
;

: ?IP ( -- )
  ['] ?IP-CB
  S" ?ip" SCALL 
;
`);

  // Ask for a number (via Forth) when the user clicks the button
  btn.addEventListener("click", () => {
    forth.interpret("?IP");
  });
})();
