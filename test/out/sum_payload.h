#include <stdint.h>
typedef struct { int64_t tag; } Handle;
typedef struct { int64_t tag; } Slot;
Handle made(int64_t n); void release(Handle h);
Slot slot(int64_t n); void drop(Slot s);
