import { mocha } from "mocha";
import loadTests from "./tests";

mocha.setup("bdd");
loadTests();
// mocha.checkLeaks();
mocha.globals(["jQuery"]);
mocha.run();
