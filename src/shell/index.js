import WAForth from "./WAForth";
import $ from "jquery";

window.jQuery = $;
require("jq-console");

const sieve = `
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

const forth = new WAForth();

let jqconsole = $("#console").jqconsole("WAForth\n", "");
$("#console").hide();
let outputBuffer = [];
forth.onEmit = c => {
  outputBuffer.push(String.fromCharCode(c));
};

function prompt() {
  jqconsole.Prompt(false, input => {
    jqconsole.Write(" ");

    // Avoid console inserting a newline
    const $el = $(".jqconsole-old-prompt span").last();
    $el.html($el.html().replace(/\n$/, ""));

    forth.run(input);
    jqconsole.Write(outputBuffer.join(""), "jqconsole-output");
    outputBuffer = [];
    prompt();
  });
}

$("#message").text("Loading...");
forth.start().then(
  () => {
    forth.run(sieve);
    outputBuffer = [];
    $("#message").hide();
    $("#console").show();
    prompt();
  },
  () => {
    $("#message")
      .addClass("error")
      .text("Error");
  }
);
