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

  // Bind async "ip?" call to a function that fetches your IP address
  forth.bindAsync("ip?", async () => {
    const result = await (
      await fetch("https://api.ipify.org?format=json")
    ).json();
    forth.pushString(result.ip);
  });

  // Load Forth code to bind the "ip?" call, and define the continuation callback
  forth.interpret(`
( IP? callback. Called after IP address was received )
: IP?-CB ( true c-addr n | false -- )
  IF 
    ." Your IP address is " TYPE CR
  ELSE
    ." Unable to fetch IP address" CR
  THEN
;

( Fetch the IP address, and print it to console )
: IP? ( -- )
  ['] IP?-CB
  S" ip?" SCALL 
;
`);

  // Ask for a number (via Forth) when the user clicks the button
  btn.addEventListener("click", () => {
    forth.interpret("IP?");
  });
})();
