import mocha from "mocha/mocha.js";
import loadTests from "./suite";
import "mocha/mocha.css";

const h1El = document.createElement("h1");
h1El.style = "font-family: sans-serif; margin: 1rem;";
h1El.appendChild(document.createTextNode("WAForth Unit Tests"));
document.body.appendChild(h1El);

const mochaEl = document.createElement("div");
mochaEl.id = "mocha";
document.body.appendChild(mochaEl);

mocha.setup("bdd");
loadTests();
// mocha.checkLeaks();
mocha.globals(["jQuery"]);
mocha.run();
