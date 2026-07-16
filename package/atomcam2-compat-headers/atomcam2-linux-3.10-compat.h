#ifndef ATOMCAM2_LINUX_3_10_COMPAT_H
#define ATOMCAM2_LINUX_3_10_COMPAT_H

#include <linux/if_addr.h>

/*
 * Linux 3.10 predates the extended address flags attribute used by current
 * VintageNet. Attribute 8 is IFA_FLAGS in newer UAPI headers.
 */
#ifndef IFA_FLAGS
#define IFA_FLAGS 8
#undef IFA_MAX
#define IFA_MAX IFA_FLAGS
#endif

#endif
