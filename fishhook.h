//
//  fishhook.h
//  fishhook
//
//  Created by Facebook on 2015-04-06.
//  Copyright (c) 2015 Facebook. All rights reserved.
//

#ifndef fishhook_h
#define fishhook_h

#include <stddef.h>
#include <stdint.h>

#if !defined(DEBUG)
#define DEBUG 0
#endif

#define FISHHOOK_EXPORT __attribute__((visibility("default")))

#ifdef __cplusplus
extern "C" {
#endif

/*
 * A structure representing a single symbol to be rebound.
 */
struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

/*
 * Rebinds symbols in the dynamic symbol table.
 * Returns 0 on success, or an error code on failure.
 */
FISHHOOK_EXPORT int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel);

/*
 * Rebinds symbols in a specific image.
 */
FISHHOOK_EXPORT int rebind_symbols_image(void *header,
    intptr_t slide,
    struct rebinding rebindings[],
    size_t rebindings_nel);

#ifdef __cplusplus
}
#endif

#endif /* fishhook_h */
