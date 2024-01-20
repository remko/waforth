export function ulzDecode(src: Uint8Array) {
  const dst: Array<number> = [];
  let sp = 0;
  while (sp < src.length) {
    const c = src[sp++];
    if (c & 0x80) {
      // CPY
      let length;
      if (c & 0x40) {
        if (sp >= src.length) {
          throw new Error(`incomplete CPY2`);
        }
        length = ((c & 0x3f) << 8) | src[sp++];
      } else {
        length = c & 0x3f;
      }
      if (sp >= src.length) {
        throw new Error(`incomplete CPY`);
      }
      let cp = dst.length - (src[sp++] + 1);
      if (cp < 0) {
        throw new Error(`CPY underflow`);
      }
      for (let i = 0; i < length + 4; i++) {
        dst.push(dst[cp++]);
      }
    } else {
      // LIT
      if (sp + c >= src.length) {
        throw new Error(`LIT out of bounds: ${sp} + ${c} >= ${src.length}`);
      }
      for (let i = 0; i < c + 1; i++) {
        dst.push(src[sp++]);
      }
    }
  }
  return new Uint8Array(dst);
}

const MIN_MAX_LENGTH = 4;

function findBestMatch(
  src: Uint8Array,
  sp: number,
  dlen: number,
  slen: number
) {
  let bmlen = 0;
  let bmp = 0;
  let dp = sp - dlen;
  for (; dlen; dp++, dlen--) {
    let i = 0;
    for (; ; i++) {
      if (i == slen) {
        return [dp, i];
      }
      if (src[sp + i] != src[dp + (i % dlen)]) {
        break;
      }
    }
    if (i > bmlen) {
      bmlen = i;
      bmp = dp;
    }
  }
  return [bmp, bmlen];
}

export function ulzEncode(src: Uint8Array) {
  let dst: Array<number> = [];
  let sp = 0;
  let litp = -1;
  while (sp < src.length) {
    const dlen = Math.min(sp, 256);
    const slen = Math.min(src.length - sp, 0x3fff + MIN_MAX_LENGTH);
    const [bmp, bmlen] = findBestMatch(src, sp, dlen, slen);
    if (bmlen >= MIN_MAX_LENGTH) {
      // CPY
      const bmctl = bmlen - MIN_MAX_LENGTH;
      if (bmctl > 0x3f) {
        // 	CPY2
        dst.push((bmctl >> 8) | 0xc0);
        dst.push(bmctl & 0xff);
      } else {
        dst.push(bmctl | 0x80);
      }
      dst.push(sp - bmp - 1);
      sp += bmlen;
      litp = -1;
    } else {
      // LIT
      if (litp >= 0) {
        if ((dst[litp] += 1) == 127) {
          litp = -1;
        }
      } else {
        dst.push(0);
        litp = dst.length - 1;
      }
      dst.push(src[sp++]);
    }
  }
  return new Uint8Array(dst);
}
