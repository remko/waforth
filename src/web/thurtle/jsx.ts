type JSXElement<T> = Omit<Partial<T>, "children"> & {
  class?: string;
  role?: string;
};

declare global {
  namespace JSX {
    interface IntrinsicElements {
      div: JSXElement<HTMLDivElement>;
      nav: JSXElement<HTMLElement>;
      a: JSXElement<HTMLAnchorElement>;
      img: JSXElement<HTMLImageElement>;
      p: JSXElement<HTMLParagraphElement>;
      select: JSXElement<HTMLSelectElement>;
      textarea: JSXElement<HTMLTextAreaElement>;
      button: JSXElement<HTMLButtonElement>;
      svg: JSXElement<
        Omit<SVGSVGElement, "width" | "height" | "viewBox" | "fill">
      > & {
        width?: string;
        height?: string;
        viewBox?: string;
        fill?: string;
        xmlns: "http://www.w3.org/2000/svg";
      };
      path: JSXElement<SVGPathElement> & {
        xmlns: "http://www.w3.org/2000/svg";
        d?: string;
      };
      g: JSXElement<Omit<SVGGraphicsElement, "transform">> & {
        xmlns: "http://www.w3.org/2000/svg";
        transform?: string;
      };
      [elemName: string]: any;
    }
  }
}

type Props = Record<string, any>;
type Child = HTMLElement | string;

export const createElement = (
  tag: string | ((props: Props, ...children: Child[]) => HTMLElement),
  props: Record<string, any>,
  ...children: Child[]
) => {
  if (typeof tag === "function") {
    return tag(props, ...children);
  }
  const element =
    props?.xmlns == null
      ? document.createElement(tag)
      : document.createElementNS(props.xmlns, tag);
  Object.entries(props || {}).forEach(([name, value]) => {
    if (name.startsWith("on") && name.toLowerCase() in window) {
      element.addEventListener(name.toLowerCase().substr(2), value);
    } else {
      element.setAttribute(name, value.toString());
    }
  });

  children.forEach((child) => {
    appendChild(element, child);
  });

  return element;
};

const appendChild = (parent: HTMLElement, child: Child | Child[]) => {
  if (Array.isArray(child))
    child.forEach((nestedChild) => appendChild(parent, nestedChild));
  else
    parent.appendChild(
      (child as HTMLElement).nodeType
        ? (child as HTMLElement)
        : document.createTextNode(child as string)
    );
};

export const createFragment = (props: Props, ...children: Child[]) => {
  return children;
};
