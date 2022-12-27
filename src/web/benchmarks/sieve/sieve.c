#include <math.h>
#include <stdlib.h>

int sieve(int n) {
  if (n < 2) {
    return n;
  }
  char *sieve = calloc(n + 1, sizeof(char));
  sieve[0] = 1;
  sieve[1] = 1;
  for (int i = 2; i * i <= n; i++) {
    if (!sieve[i]) {
      for (int j = i * i; j <= n; j += i) {
        sieve[j] = 1;
      }
    }
  }
  int lastPrime = 0;
  for (int i = 2; i <= n; ++i) {
    if (!sieve[i]) {
      // printf("%d\n", i);
      lastPrime = i;
    }
  }
  free(sieve);
  return lastPrime;
}
