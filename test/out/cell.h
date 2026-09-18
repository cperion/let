#include <stdint.h>
typedef struct { int64_t tag; } Handle;
Handle made(int64_t n); void release(Handle h);
