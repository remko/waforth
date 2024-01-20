export function lzwEncode(data: Uint8Array) {
  const dict = new Map<string, number>();
  const out: Array<number> = [];
  let phrase = String.fromCharCode(data[0]);
  let code = 256;
  for (let i = 1; i < data.length; i++) {
    const chr = String.fromCharCode(data[i]);
    const nphrase = phrase + chr;
    if (dict.has(nphrase)) {
      phrase = nphrase;
    } else {
      out.push(phrase.length > 1 ? dict.get(phrase)! : phrase.charCodeAt(0));
      dict.set(nphrase, code);
      code++;
      phrase = chr;
    }
  }
  out.push(phrase.length > 1 ? dict.get(phrase)! : phrase.charCodeAt(0));
  return new TextEncoder().encode(
    out.map((c) => String.fromCharCode(c)).join("")
  );
}

export function lzwDecode(rdata: Uint8Array) {
  const data = [...new TextDecoder().decode(rdata)].map((c) => c.charCodeAt(0));
  let dict = new Map<number, number[]>();
  var curChar = data[0];
  var curPhrase = [curChar];
  var out = [curChar];
  var code = 256;
  for (var i = 1; i < data.length; i++) {
    const c = data[i];
    const phrase =
      c < 256
        ? [data[i]]
        : dict.has(c)
        ? dict.get(c)!
        : curPhrase.concat(curChar);
    out.push(...phrase);
    curChar = phrase[0];
    dict.set(code, curPhrase.concat(curChar));
    code++;
    curPhrase = phrase;
  }
  return new Uint8Array(out);
}
