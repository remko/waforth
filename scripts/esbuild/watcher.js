/* eslint-env node */
/* eslint @typescript-eslint/no-var-requires:0 */

const { createServer } = require("http");

function withWatcher(
  config,
  handleBuildFinished = () => {
    /* do nothing */
  },
  port = 8880
) {
  const watchClients = [];
  createServer((req, res) => {
    return watchClients.push(
      res.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Access-Control-Allow-Origin": "*",
        Connection: "keep-alive",
      })
    );
  }).listen(port);
  return {
    ...config,
    banner: {
      js: `(function () { new EventSource("http://localhost:${port}").onmessage = function() { location.reload();};})();`,
    },
    watch: {
      async onRebuild(error, result) {
        if (error) {
          console.error(error);
        } else {
          await handleBuildFinished(result);
          watchClients.forEach((res) => res.write("data: update\n\n"));
          watchClients.length = 0;
        }
      },
    },
  };
}

module.exports = {
  withWatcher,
};
