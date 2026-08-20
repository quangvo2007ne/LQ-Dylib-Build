#include "fishhook.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
    // Dummy stub
    return 0;
}

int rebind_symbols_image(void *header, intptr_t slide, struct rebinding rebindings[], size_t rebindings_nel) {
    return 0;
}
