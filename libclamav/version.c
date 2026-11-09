#ifdef HAVE_CONFIG_H
#include "vigilixav-config.h"
#endif
#include "vigilixav.h"
#include "version.h"

#ifndef REPO_VERSION
#define REPO_VERSION VERSION
#endif

/* libclamav's version is always the SVN revision (if available) */
const char *cl_retver(void)
{
    return REPO_VERSION "" VERSION_SUFFIX;
}
