const loadTests = require("./suite.js").default;
loadTests((s) => {
  return Buffer.from(s).toString("base64");
});
