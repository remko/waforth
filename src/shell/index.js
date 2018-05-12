import WAForth from "./WAForth";

const forth = new WAForth();

const terminal = document.getElementById("terminal");
forth.onEmit = c => {
  terminal.value = terminal.value + String.fromCharCode(c);
};
forth.start().then(() => {
  const command = [];
  terminal.addEventListener("keydown", function(ev) {
    var isPrintable =
      !ev.altKey && !ev.altGraphKey && !ev.ctrlKey && !ev.metaKey;
    if (ev.keyCode == 13) {
      ev.preventDefault();
      console.log("SUBMIT", command.join(""));
      window.setTimeout(() => {
        ev.target.value = ev.target.value + " ok\n";
      }, 500);
    } else if (ev.keyCode == 8) {
      if (command.length > 0) {
        command.pop();
      }
    } else if (isPrintable) {
      command.push(ev.key);
    }
  });
});
