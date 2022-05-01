// Source: https://rosettacode.org/wiki/Sieve_of_Eratosthenes#JavaScript

export default function sieve(limit) {
  const primes = [];
  if (limit >= 2) {
    const sqrtlmt = Math.sqrt(limit) - 2;
    const nums = [];
    for (let i = 2; i <= limit; i++) {
      nums.push(i);
    }
    for (let i = 0; i <= sqrtlmt; i++) {
      const p = nums[i];
      if (p) {
        for (let j = p * p - 2; j < nums.length; j += p) {
          nums[j] = 0;
        }
      }
    }
    for (let i = 0; i < nums.length; i++) {
      const p = nums[i];
      if (p) {
        primes.push(p);
      }
    }
  }
  return primes;
}
