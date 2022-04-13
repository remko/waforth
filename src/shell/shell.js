import $ from "jquery";
import WAForth from "./WAForth";
import sieve from "./sieve";
import "./shell.css";

window.jQuery = $;
require("jq-console");

document.title = "WAForth";

const forth = new WAForth();

const consoleEl = document.createElement("div");
consoleEl.className = "console";
document.body.appendChild(consoleEl);

const messageContainerEl = document.createElement("div");
messageContainerEl.className = "messageContainer";
const messageEl = document.createElement("div");
messageEl.className = "message";
messageContainerEl.appendChild(messageEl);
document.body.appendChild(messageContainerEl);

let jqconsole = $(consoleEl).jqconsole("WAForth\n", "");
$(consoleEl).hide();
$(".jqconsole-header").html(
  "<span><a target='_blank' href='https://github.com/remko/waforth'>WAForth</a>\n</span>"
);
let outputBuffer = [];
forth.onEmit = (c) => {
  outputBuffer.push(String.fromCharCode(c));
};

function prompt() {
  jqconsole.Prompt(false, (input) => {
    jqconsole.Write(" ");

    // Avoid console inserting a newline
    const $el = $(".jqconsole-old-prompt span").last();
    $el.html($el.html().replace(/\n$/, ""));

    forth.run(input);
    let output = outputBuffer.join("");
    if (output.length === 0) {
      output = "\n";
    }
    jqconsole.Write(output, "jqconsole-output");
    outputBuffer = [];
    prompt();
  });
}

$(messageEl).text("Loading...");
forth.start().then(
  () => {
    forth.run(sieve);
    outputBuffer = [];
    $(messageEl).hide();
    $(consoleEl).show();
    prompt();
  },
  () => {
    $(messageEl).addClass("error").text("Error");
  }
);
