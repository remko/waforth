const loadTests = require("./suite.js").default;
loadTests(undefined, (s) => {
  return Buffer.from(s).toString("base64");
});
