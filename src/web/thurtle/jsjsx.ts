// Simple version of JSX that does not require a DOM

function elementToHTML(el: any) {
  const out: string[] = [];
  out.push("<", el._tag);
  for (const [k, v] of Object.entries(el)) {
    if (typeof v == "function" || k.startsWith("_") || k === "innerHTML") {
      continue;
    }
    if (k === "style" && typeof v !== "string") {
      // TODO
      continue;
    }
    out.push(" ", k, '="', v as string, '"');
  }
  out.push(">");
  for (const child of el._children) {
    out.push(elementToHTML(child));
  }
  out.push("</", el._tag, ">");
  return out.join("");
}
class JSJSX {
  createElement(tag: any, props: any = {}, ...children: any[]) {
    return {
      _tag: tag,
      _children: children ?? [],
      ...props,
      appendChild(c: any) {
        this._children.push(c);
      },
      setAttribute(k: any, v: any) {
        this[k] = v;
      },
    };
  }

  toHTML(el: any) {
    return elementToHTML(el);
  }
}

export default JSJSX;
