/*
 * Mirror the vendor runtime's already-encoded frames into v4l2loopback
 * devices so an RTSP server outside the vendor chroot can publish them
 * without re-encoding.
 *
 * The vendor application registers an encode callback per channel through
 * local_sdk_video_set_encode_frame_callback(). This library is preloaded so
 * that call lands here first: the vendor's callback is remembered, a wrapper
 * is registered in its place, and every frame is written to the matching
 * loopback device before being handed to the vendor unchanged.
 *
 * Nothing here is linked against a libc. The vendor process supplies the
 * symbols at runtime, which keeps the shim usable inside the vendor's uClibc
 * chroot while the rest of the system stays on musl.
 */

#include <linux/videodev2.h>
#include <sys/ioctl.h>

#define EXPORTED __attribute__((visibility("default")))

#define O_WRONLY 01
#define RTLD_LAZY 1
#define RTLD_NEXT ((void *)-1L)

#define VENDOR_SDK_PATH "/system/lib/liblocalsdk.so"
#define VENDOR_SDK_SYMBOL "local_sdk_video_set_encode_frame_callback"

/* The 3.10 headers predate HEVC; the fourcc itself is unchanged. */
#ifndef V4L2_PIX_FMT_HEVC
#define V4L2_PIX_FMT_HEVC v4l2_fourcc('H', 'E', 'V', 'C')
#endif

extern int open(const char *path, int flags, ...);
extern int close(int fd);
extern long write(int fd, const void *buffer, unsigned long count);
extern void *dlopen(const char *path, int flags);
extern void *dlsym(void *handle, const char *symbol);

struct vendor_frame {
	unsigned char *buffer;
	unsigned long length;
};

typedef int (*frame_callback)(struct vendor_frame *);

struct channel {
	const char *device;
	unsigned int width;
	unsigned int height;
	unsigned int format;
	unsigned int frame_bytes;

	frame_callback vendor_callback;
	int fd;
	int unusable;
};

static int capture_channel_0(struct vendor_frame *frame);
static int capture_channel_1(struct vendor_frame *frame);
static int capture_channel_2(struct vendor_frame *frame);

/*
 * Channel geometry matches what the Atom Cam 2 vendor runtime encodes.
 * Vendor channel 3 is the third stream; it is mapped to index 2 below.
 *
 * frame_bytes bounds the loopback buffer. Left at zero, v4l2loopback sizes
 * its buffers from the raw geometry, which reserves several megabytes per
 * buffer for a stream that is already compressed to a fraction of that. On
 * an 87 MiB board that difference decides whether an RTSP server can run
 * alongside the vendor runtime, so each channel states a bound that
 * comfortably exceeds its largest keyframe.
 */
static struct channel channels[] = {
	{ "/dev/video0", 1920, 1080, V4L2_PIX_FMT_H264, 512u * 1024u, 0, -1, 0 },
	{ "/dev/video1", 640, 360, V4L2_PIX_FMT_HEVC, 192u * 1024u, 0, -1, 0 },
	{ "/dev/video2", 1920, 1080, V4L2_PIX_FMT_HEVC, 512u * 1024u, 0, -1, 0 },
};

#define CHANNEL_COUNT ((int)(sizeof(channels) / sizeof(channels[0])))

static const frame_callback capture_callbacks[CHANNEL_COUNT] = {
	capture_channel_0,
	capture_channel_1,
	capture_channel_2,
};

static int (*vendor_set_encode_frame_callback)(int channel, void *callback);

/*
 * Resolved on first use rather than from a constructor: a preloaded library's
 * constructor can run before the dynamic linker is ready to serve dlopen(),
 * and failing to resolve here would leave the vendor runtime with no encode
 * callback at all, which stalls every encoder channel.
 *
 * RTLD_NEXT is the reliable form for an interposed symbol. The explicit
 * library path stays as a fallback for the case where RTLD_NEXT is
 * unsupported.
 */
static int resolve_vendor_callback_setter(void)
{
	void *handle;

	if (vendor_set_encode_frame_callback != 0) {
		return 1;
	}

	vendor_set_encode_frame_callback = dlsym(RTLD_NEXT, VENDOR_SDK_SYMBOL);

	if (vendor_set_encode_frame_callback != 0) {
		return 1;
	}

	handle = dlopen(VENDOR_SDK_PATH, RTLD_LAZY);

	if (handle != 0) {
		vendor_set_encode_frame_callback =
			dlsym(handle, VENDOR_SDK_SYMBOL);
	}

	return vendor_set_encode_frame_callback != 0;
}

/*
 * The loopback device is opened on the first frame rather than at startup so
 * that a missing or busy device costs one attempt instead of blocking the
 * vendor runtime. Writes with no RTSP reader attached are rejected by the
 * loopback driver, which keeps this path allocation-free.
 */
static void open_channel(struct channel *entry)
{
	struct v4l2_format format;
	int stream_type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	int fd = open(entry->device, O_WRONLY);

	if (fd < 0) {
		entry->unusable = 1;
		return;
	}

	__builtin_memset(&format, 0, sizeof(format));

	/* Start from the driver's own view so unset fields keep valid values. */
	format.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	ioctl(fd, VIDIOC_G_FMT, &format);

	format.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	format.fmt.pix.width = entry->width;
	format.fmt.pix.height = entry->height;
	format.fmt.pix.pixelformat = entry->format;
	format.fmt.pix.field = V4L2_FIELD_NONE;
	format.fmt.pix.colorspace = V4L2_COLORSPACE_SMPTE170M;
	format.fmt.pix.sizeimage = entry->frame_bytes;
	format.fmt.pix.bytesperline = 0;

	if (ioctl(fd, VIDIOC_S_FMT, &format) < 0 ||
	    ioctl(fd, VIDIOC_STREAMON, &stream_type) < 0) {
		close(fd);
		entry->unusable = 1;
		return;
	}

	entry->fd = fd;
}

static int capture(int index, struct vendor_frame *frame)
{
	struct channel *entry = &channels[index];

	if (entry->fd < 0 && !entry->unusable) {
		open_channel(entry);
	}

	if (entry->fd >= 0 && frame != 0 && frame->buffer != 0 &&
	    frame->length <= entry->frame_bytes) {
		write(entry->fd, frame->buffer, frame->length);
	}

	return entry->vendor_callback(frame);
}

static int capture_channel_0(struct vendor_frame *frame)
{
	return capture(0, frame);
}

static int capture_channel_1(struct vendor_frame *frame)
{
	return capture(1, frame);
}

static int capture_channel_2(struct vendor_frame *frame)
{
	return capture(2, frame);
}

EXPORTED int local_sdk_video_set_encode_frame_callback(int channel,
						       void *callback)
{
	int index;

	if (!resolve_vendor_callback_setter()) {
		return -1;
	}

	/* The vendor runtime encodes on channels 0, 1, and 3. */
	switch (channel) {
	case 0:
	case 1:
		index = channel;
		break;
	case 3:
		index = 2;
		break;
	default:
		return vendor_set_encode_frame_callback(channel, callback);
	}

	if (callback != 0 && channels[index].vendor_callback == 0) {
		channels[index].vendor_callback = (frame_callback)callback;
		callback = (void *)capture_callbacks[index];
	}

	return vendor_set_encode_frame_callback(channel, callback);
}
