import * as jsx from "./jsx";
import "./Editor.css";

const highlightClass: Record<string, string> = {
  ":": "c1",
  ";": "c1",
  CONSTANT: "c1",
  VARIABLE: "c1",
  I: "c1",
  J: "c1",

  DO: "c2",
  LOOP: "c2",
  REPEAT: "c2",
  UNTIL: "c2",
  "+LOOP": "c2",
  BEGIN: "c2",
  UNLOOP: "c2",
  IF: "c2",
  ELSE: "c2",
  THEN: "c2",
};

export default class Editor {
  textEl: HTMLTextAreaElement;
  codeEl: HTMLElement;
  preEl: HTMLPreElement;
  el: HTMLDivElement;

  constructor() {
    this.textEl = <textarea autofocus spellcheck={false}></textarea>;
    this.codeEl = <code class="language-forth" />;
    this.preEl = <pre aria-hidden="true">{this.codeEl}</pre>;
    this.el = (
      <div class="editor">
        {this.preEl}
        {this.textEl}
      </div>
    );
    this.textEl.addEventListener("input", (ev) => {
      this.#setCode(this.textEl.value);
      this.#updateScroll();
    });
    this.textEl.addEventListener("scroll", () => {
      this.#updateScroll();
    });
  }

  setValue(v: string) {
    this.textEl.value = v;
    this.#setCode(v);
  }

  #setCode(v: string) {
    // Add an invisible character at the end if it ends with newline, to avoid <pre> from stripping it
    if (v[v.length - 1] == "\n") {
      v += " ";
    }

    this.codeEl.innerText = "";
    const vs = v.split(/(\s+)/);
    let nextIsDefinition = false;
    let inComment = false;
    for (const v of vs) {
      let parentEl: HTMLElement = this.codeEl;
      let cls: string | undefined;
      if (inComment || v === "(") {
        cls = "c-com";
      } else if (!isNaN(v as any)) {
        cls = "c-num";
      } else if (nextIsDefinition && v.trim().length > 0) {
        cls = "c-def";
        nextIsDefinition = false;
      } else {
        cls = highlightClass[v];
      }
      if (cls != null) {
        const spanEl = document.createElement("span");
        spanEl.className = cls;
        parentEl.appendChild(spanEl);
        parentEl = spanEl;
      }
      parentEl.appendChild(document.createTextNode(v));

      if (v === ":" || v === "CONSTANT" || v === "VARIABLE" || v === "VALUE") {
        nextIsDefinition = true;
      } else if (v === "(") {
        inComment = true;
      } else if (inComment && v === ")") {
        inComment = false;
      }
    }
  }

  #updateScroll() {
    this.preEl.scrollTop = this.textEl.scrollTop;
    this.preEl.scrollLeft = this.textEl.scrollLeft;
  }

  getValue(): string {
    return this.textEl.value;
  }

  focus() {
    this.textEl.focus();
  }
}
