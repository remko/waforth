import "./wafnb.css";
import Editor from "../../thurtle/Editor";

for (const n of document.querySelectorAll("[data-hook=code-cell")) {
  n.className = "code-cell";
  const program = n.textContent ?? "";
  const editor = new Editor();
  editor.setValue(program);
  n.innerHTML = "";
  n.appendChild(editor.el);
  editor.el.style.minHeight = "10em"; // FIXME
}
