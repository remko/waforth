import "promise-polyfill/src/polyfill";
import $ from "jquery";
import WAForth from "./WAForth";
import sieve from "./sieve";
import "./index.css";

window.jQuery = $;
require("jq-console");

const forth = new WAForth();

let jqconsole = $("#console").jqconsole("WAForth\n", "");
$("#console").hide();
$(".jqconsole-header").html(
  "<span><a target='_blank' href='https://github.com/remko/waforth'>WAForth</a>\n</span>"
);
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
