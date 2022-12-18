#include <math.h>
#include <stdlib.h>

int sieve(int n) {
  if (n < 2) {
    return n;
  }
  int m = (int)sqrt((double)n);
  char *sieve = calloc(n + 1, sizeof(char));
  sieve[0] = 1;
  sieve[1] = 1;
  for (int i = 2; i <= m; i++) {
    if (!sieve[i]) {
      for (int j = i * i; j <= n; j += i) {
        if (!sieve[j]) {
          sieve[j] = 1;
        }
      }
    }
  }
  for (int i = n; i >= 0; --i) {
    if (sieve[i] == 0) {
      free(sieve);
      return i;
    }
  }
  free(sieve);
  return 0;
}
