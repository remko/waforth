// Source: https://rosettacode.org/wiki/Sieve_of_Eratosthenes#JavaScript

export default function sieve(n) {
  if (n < 2) {
    return n;
  }
  const nums = new Uint8Array(n + 1);
  for (let i = 2; i * i <= n; i++) {
    if (!nums[i]) {
      for (let j = i * i; j <= n; j += i) {
        nums[j] = 1;
      }
    }
  }
  let lastPrime = 0;
  for (let i = 2; i < n; i++) {
    if (!nums[i]) {
      // Print number.
      // console.log(p);
      lastPrime = i;
    }
  }
  return lastPrime;
}
