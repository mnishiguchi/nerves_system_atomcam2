/*
 * Keep protected Nerves resources under Nerves ownership while satisfying the
 * vendor runtime's narrow compatibility checks.
 */

#define EXPORTED __attribute__((visibility("default")))

static int strings_equal(const char *left, const char *right)
{
	if (left == 0 || right == 0) {
		return 0;
	}

	while (*left != '\0' && *left == *right) {
		left++;
		right++;
	}

	return *left == *right;
}

EXPORTED int local_sdk_open_watchdog(void)
{
	return 0;
}

EXPORTED int local_sdk_set_watchdog_timeout(int timeout)
{
	(void)timeout;
	return 0;
}

EXPORTED int local_sdk_feed_watchdog(void)
{
	return 0;
}

EXPORTED int mount(const char *source, const char *target,
		   const char *filesystemtype, unsigned long mountflags,
		   const void *data)
{
	(void)filesystemtype;
	(void)mountflags;
	(void)data;

	if (strings_equal(source, "/dev/mmcblk0p1") &&
	    strings_equal(target, "/media/mmc")) {
		return 0;
	}

	return -1;
}

EXPORTED int umount(const char *target)
{
	return strings_equal(target, "/media/mmc") ? 0 : -1;
}

EXPORTED int umount2(const char *target, int flags)
{
	(void)flags;
	return strings_equal(target, "/media/mmc") ? 0 : -1;
}

EXPORTED int local_sdk_close_watchdog(void)
{
	return 0;
}
