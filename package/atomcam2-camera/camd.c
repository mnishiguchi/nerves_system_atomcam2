/*
 * 方式B Stage 5 spike: native camera daemon with a runtime-controllable OSD.
 * Pipeline: sensor -> ISP -> FrameSource -> OSD -> H.264 -> v4l2loopback.
 *
 * Two overlays, each toggled live from IEx via a control file:
 *   - clock: real HH:MM:SS timestamp (bottom-left), redrawn each second
 *   - logo:  100x100 bitmap (bottom-right)
 *
 *   cmd "echo 'clock off' > /tmp/camd.ctl"
 *   cmd "echo 'clock on'  > /tmp/camd.ctl"
 *   cmd "echo 'logo off'  > /tmp/camd.ctl"
 *   cmd "echo 'logo on'   > /tmp/camd.ctl"
 *   cmd "echo quit        > /tmp/camd.ctl"
 *
 * Run with iCamera_app STOPPED and sensor_gc2053_t31.ko loaded.  Start
 * v4l2rtspserver on /dev/video0 after this writer has set the loopback format.
 *
 * Build (device uClibc toolchain, 1.1.1 headers + samples for font/logo):
 *   mips-linux-uclibc-gnu-gcc -O2 -march=mips32r2 -I<sdk111> -I<libimp-samples> \
 *     -Wl,--dynamic-linker=/atom/lib/ld-uClibc.so.0 \
 *     camd.c -L lib -limp -lalog -lpthread -lm -lrt -o camd
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <time.h>
#include <sys/ioctl.h>
#include <linux/videodev2.h>

#include <imp/imp_common.h>
#include <imp/imp_isp.h>
#include <imp/imp_system.h>
#include <imp/imp_framesource.h>
#include <imp/imp_encoder.h>
#include <imp/imp_osd.h>

#include "bgramapinfo.h"            /* gBgramap[13] font, gBgramapHight */
#include "logodata_100x100_bgra.h" /* logodata_100x100_bgra[] */

#ifndef V4L2_PIX_FMT_H264
#define V4L2_PIX_FMT_H264 v4l2_fourcc('H', '2', '6', '4')
#endif

#define W 1920
#define H 1080
#define FR_NUM 25
#define FR_DEN 1
#define CHN 0
#define GRP 0
#define ASM_MAX (1024 * 1024)
#define CTL_PATH "/tmp/camd.ctl"

#define OSD_CELL_W 16          /* per-glyph cell width factor (sample) */
#define OSD_ROW_H  34
#define CLOCK_CHARS 20
#define CLOCK_W (CLOCK_CHARS * OSD_CELL_W)   /* 320 */

static unsigned char asm_buf[ASM_MAX];
static uint32_t clock_buf[CLOCK_CHARS * OSD_ROW_H * OSD_CELL_W]; /* bgra */

static IMPRgnHandle rgnClock, rgnLogo;

/* Overlay positions (top-left origin of each region). Defaults: clock at the
 * right edge, logo at the left edge; both runtime-movable. */
static int clock_x, clock_y, logo_x, logo_y;

static void move_clock(int x, int y)
{
	clock_x = x; clock_y = y;
	IMPOSDRgnAttr a;
	memset(&a, 0, sizeof(a));
	a.type = OSD_REG_PIC;
	a.rect.p0.x = x; a.rect.p0.y = y;
	a.rect.p1.x = x + CLOCK_W - 1; a.rect.p1.y = y + OSD_ROW_H - 1;
	a.fmt = PIX_FMT_BGRA;
	a.data.picData.pData = NULL;
	IMP_OSD_SetRgnAttr(rgnClock, &a);
}

static void move_logo(int x, int y)
{
	logo_x = x; logo_y = y;
	IMPOSDRgnAttr l;
	memset(&l, 0, sizeof(l));
	l.type = OSD_REG_PIC;
	l.rect.p0.x = x; l.rect.p0.y = y;
	l.rect.p1.x = x + 100 - 1; l.rect.p1.y = y + 100 - 1;
	l.fmt = PIX_FMT_BGRA;
	l.data.picData.pData = logodata_100x100_bgra;
	IMP_OSD_SetRgnAttr(rgnLogo, &l);
}

/* Runtime rate-control tuning. Mosquito noise around sharp OSD edges is a
 * low-bitrate artifact; raise the bitrate (or lower maxQP) to suppress it. */
static void set_bitrate(int kbps)
{
	IMPEncoderAttrRcMode rc;
	if (IMP_Encoder_GetChnAttrRcMode(CHN, &rc) < 0) return;
	rc.attrVbr.uTargetBitRate = kbps;
	rc.attrVbr.uMaxBitRate = kbps + kbps / 2;
	if (IMP_Encoder_SetChnAttrRcMode(CHN, &rc) < 0) return;
	fprintf(stderr, "camd: bitrate -> %d kbps\n", kbps);
}

static void set_qp(int minqp, int maxqp)
{
	IMPEncoderAttrRcMode rc;
	if (IMP_Encoder_GetChnAttrRcMode(CHN, &rc) < 0) return;
	rc.attrVbr.iMinQP = minqp;
	rc.attrVbr.iMaxQP = maxqp;
	if (IMP_Encoder_SetChnAttrRcMode(CHN, &rc) < 0) return;
	fprintf(stderr, "camd: qp -> min %d max %d\n", minqp, maxqp);
}

static int step(const char *label, int rc)
{
	fprintf(stderr, "camd: %-26s = %d\n", label, rc);
	fflush(stderr);
	return rc;
}

/* Render current time into clock_buf and push it to the OSD region. */
static void render_clock(void)
{
	char s[40];
	/* Device runs in UTC; render Japan time (JST = UTC+9) regardless of TZ. */
	time_t t = time(NULL) + 9 * 3600;
	struct tm *lt = gmtime(&t);
	strftime(s, sizeof(s), "%Y-%m-%d %H:%M:%S", lt);

	memset(clock_buf, 0, sizeof(clock_buf));
	int pen = 0;
	unsigned i, j;
	for (i = 0; i < CLOCK_CHARS && s[i]; i++) {
		int idx;
		char c = s[i];
		if (c >= '0' && c <= '9') idx = c - '0';
		else if (c == '-') idx = 10;
		else if (c == ' ') idx = 11;
		else if (c == ':') idx = 12;
		else continue;
		int adv = gBgramap[idx].width;
		uint32_t *glyph = gBgramap[idx].pdata;
		for (j = 0; j < OSD_ROW_H; j++) {
			memcpy((uint32_t *)clock_buf + j * CLOCK_CHARS * OSD_CELL_W + pen,
			       glyph + j * adv, adv * 4);
		}
		pen += adv;
	}
	IMPOSDRgnAttrData d;
	memset(&d, 0, sizeof(d));
	d.picData.pData = clock_buf;
	IMP_OSD_UpdateRgnAttrData(rgnClock, &d);
}

static int loopback_open(const char *dev)
{
	int fd = open(dev, O_WRONLY);
	if (fd < 0) { fprintf(stderr, "camd: open(%s): %s\n", dev, strerror(errno)); return -1; }
	struct v4l2_format fmt;
	int type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	memset(&fmt, 0, sizeof(fmt));
	fmt.type = type;
	ioctl(fd, VIDIOC_G_FMT, &fmt);
	fmt.fmt.pix.width = W;
	fmt.fmt.pix.height = H;
	fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_H264;
	fmt.fmt.pix.field = V4L2_FIELD_NONE;
	fmt.fmt.pix.colorspace = V4L2_COLORSPACE_SMPTE170M;
	fmt.fmt.pix.sizeimage = 512u * 1024u;
	fmt.fmt.pix.bytesperline = 0;
	if (ioctl(fd, VIDIOC_S_FMT, &fmt) < 0 || ioctl(fd, VIDIOC_STREAMON, &type) < 0) {
		fprintf(stderr, "camd: loopback setup: %s\n", strerror(errno));
		close(fd);
		return -1;
	}
	return fd;
}

/* Poll control file; apply one command; clear it. Returns 1 to quit. */
static int poll_ctl(void)
{
	int fd = open(CTL_PATH, O_RDONLY);
	if (fd < 0) return 0;
	char buf[128];
	int n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0) return 0;
	buf[n] = 0;
	while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r' || buf[n-1] == ' ')) buf[--n] = 0;
	if (n == 0) return 0;

	int quit = 0;
	int a, b;
	if      (!strcmp(buf, "clock on"))  IMP_OSD_ShowRgn(rgnClock, GRP, 1);
	else if (!strcmp(buf, "clock off")) IMP_OSD_ShowRgn(rgnClock, GRP, 0);
	else if (!strcmp(buf, "logo on"))   IMP_OSD_ShowRgn(rgnLogo, GRP, 1);
	else if (!strcmp(buf, "logo off"))  IMP_OSD_ShowRgn(rgnLogo, GRP, 0);
	else if (sscanf(buf, "bitrate %d", &a) == 1) set_bitrate(a);
	else if (sscanf(buf, "qp %d %d", &a, &b) == 2) set_qp(a, b);
	else if (sscanf(buf, "clockpos %d %d", &a, &b) == 2) move_clock(a, b);
	else if (sscanf(buf, "logopos %d %d", &a, &b) == 2) move_logo(a, b);
	else if (!strcmp(buf, "quit"))      quit = 1;
	else fprintf(stderr, "camd: ctl unknown '%s'\n", buf);
	if (!quit) fprintf(stderr, "camd: ctl '%s'\n", buf);
	fflush(stderr);

	int wfd = open(CTL_PATH, O_WRONLY | O_TRUNC);
	if (wfd >= 0) close(wfd);
	return quit;
}

static int osd_init(void)
{
	if (step("IMP_OSD_CreateGroup", IMP_OSD_CreateGroup(GRP)) < 0) return -1;

	rgnClock = IMP_OSD_CreateRgn(NULL);
	rgnLogo  = IMP_OSD_CreateRgn(NULL);
	if (rgnClock == INVHANDLE || rgnLogo == INVHANDLE) { fprintf(stderr, "camd: CreateRgn failed\n"); return -1; }
	IMP_OSD_RegisterRgn(rgnClock, GRP, NULL);
	IMP_OSD_RegisterRgn(rgnLogo, GRP, NULL);

	/* clock region: PIC, bottom-left */
	IMPOSDRgnAttr a;
	memset(&a, 0, sizeof(a));
	a.type = OSD_REG_PIC;
	a.rect.p0.x = clock_x;
	a.rect.p0.y = clock_y;
	a.rect.p1.x = clock_x + CLOCK_W - 1;
	a.rect.p1.y = clock_y + OSD_ROW_H - 1;
	a.fmt = PIX_FMT_BGRA;
	a.data.picData.pData = NULL;
	if (step("SetRgnAttr clock", IMP_OSD_SetRgnAttr(rgnClock, &a)) < 0) return -1;

	IMPOSDGrpRgnAttr g;
	memset(&g, 0, sizeof(g));
	g.show = 1; g.gAlphaEn = 1; g.fgAlhpa = 0xff; g.layer = 3;
	IMP_OSD_SetGrpRgnAttr(rgnClock, GRP, &g);

	/* logo region: PIC 100x100, bottom-right */
	IMPOSDRgnAttr l;
	memset(&l, 0, sizeof(l));
	l.type = OSD_REG_PIC;
	l.rect.p0.x = logo_x;
	l.rect.p0.y = logo_y;
	l.rect.p1.x = logo_x + 100 - 1;
	l.rect.p1.y = logo_y + 100 - 1;
	l.fmt = PIX_FMT_BGRA;
	l.data.picData.pData = logodata_100x100_bgra;
	if (step("SetRgnAttr logo", IMP_OSD_SetRgnAttr(rgnLogo, &l)) < 0) return -1;

	IMPOSDGrpRgnAttr gl;
	memset(&gl, 0, sizeof(gl));
	gl.show = 1; gl.gAlphaEn = 1; gl.fgAlhpa = 0xff; gl.layer = 2;
	IMP_OSD_SetGrpRgnAttr(rgnLogo, GRP, &gl);
	return 0;
}

int main(int argc, char **argv)
{
	int frames = (argc > 1) ? atoi(argv[1]) : 100000;
	const char *dev = (argc > 2) ? argv[2] : "/dev/video0";
	const char *sensor = (argc > 3) ? argv[3] : "gc2053";
	int addr = (argc > 4) ? (int)strtol(argv[4], NULL, 0) : 0x37;
	int bitrate = (argc > 5) ? atoi(argv[5]) : 3000;   /* kbps; raise to cut mosquito noise */

	IMPSensorInfo si;
	IMPFSChnAttr fs;
	IMPEncoderChnAttr echn;
	IMPCell fs_cell = { DEV_ID_FS, CHN, 0 };
	IMPCell osd_cell = { DEV_ID_OSD, GRP, 0 };
	IMPCell enc_cell = { DEV_ID_ENC, CHN, 0 };
	int rc, i;
	long total = 0; int got = 0;

	int cfd = open(CTL_PATH, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (cfd >= 0) close(cfd);

	memset(&si, 0, sizeof(si));
	strncpy(si.name, sensor, sizeof(si.name) - 1);
	si.cbus_type = TX_SENSOR_CONTROL_INTERFACE_I2C;
	strncpy(si.i2c.type, sensor, sizeof(si.i2c.type) - 1);
	si.i2c.addr = addr;

	if (step("IMP_ISP_Open", IMP_ISP_Open()) < 0) return 1;
	if (step("IMP_ISP_AddSensor", IMP_ISP_AddSensor(&si)) < 0) return 1;
	if (step("IMP_ISP_EnableSensor", IMP_ISP_EnableSensor()) < 0) return 1;
	if (step("IMP_System_Init", IMP_System_Init()) < 0) return 1;
	if (step("IMP_ISP_EnableTuning", IMP_ISP_EnableTuning()) < 0) return 1;

	memset(&fs, 0, sizeof(fs));
	fs.pixFmt = PIX_FMT_NV12;
	fs.outFrmRateNum = FR_NUM; fs.outFrmRateDen = FR_DEN;
	fs.nrVBs = 3; fs.type = FS_PHY_CHANNEL;
	fs.picWidth = W; fs.picHeight = H;
	if (step("FrameSource_CreateChn", IMP_FrameSource_CreateChn(CHN, &fs)) < 0) return 1;
	if (step("FrameSource_SetChnAttr", IMP_FrameSource_SetChnAttr(CHN, &fs)) < 0) return 1;

	if (step("Encoder_CreateGroup", IMP_Encoder_CreateGroup(CHN)) < 0) return 1;

	/* defaults: clock at right edge, logo at left edge (bottom) */
	clock_x = W - CLOCK_W - 16; clock_y = H - OSD_ROW_H - 16;
	logo_x = 16;                logo_y = H - 100 - 16;

	if (osd_init() < 0) return 1;

	memset(&echn, 0, sizeof(echn));
	rc = IMP_Encoder_SetDefaultParam(&echn, IMP_ENC_PROFILE_AVC_MAIN, IMP_ENC_RC_MODE_VBR,
			W, H, FR_NUM, FR_DEN, FR_NUM, 0, -1, bitrate);
	if (step("Encoder_SetDefaultParam", rc) < 0) return 1;
	if (step("Encoder_CreateChn", IMP_Encoder_CreateChn(CHN, &echn)) < 0) return 1;
	if (step("Encoder_RegisterChn", IMP_Encoder_RegisterChn(CHN, CHN)) < 0) return 1;

	if (step("Bind FS->OSD", IMP_System_Bind(&fs_cell, &osd_cell)) < 0) return 1;
	if (step("Bind OSD->ENC", IMP_System_Bind(&osd_cell, &enc_cell)) < 0) return 1;
	if (step("IMP_OSD_Start", IMP_OSD_Start(GRP)) < 0) return 1;

	if (step("FrameSource_EnableChn", IMP_FrameSource_EnableChn(CHN)) < 0) return 1;

	int lfd = loopback_open(dev);
	if (lfd < 0) return 1;
	step("loopback ready", 0);

	if (step("Encoder_StartRecvPic", IMP_Encoder_StartRecvPic(CHN)) < 0) return 1;

	render_clock();
	fprintf(stderr, "camd: running at %d kbps. control via %s\n", bitrate, CTL_PATH);
	fprintf(stderr, "camd:   clock on|off / logo on|off / bitrate <kbps> / qp <min> <max> / quit\n");
	fflush(stderr);

	for (i = 0; i < frames; i++) {
		if (poll_ctl()) break;
		if ((i % FR_NUM) == 0) render_clock();   /* once per second */

		rc = IMP_Encoder_PollingStream(CHN, 1000);
		if (rc < 0) continue;
		IMPEncoderStream stream;
		if (IMP_Encoder_GetStream(CHN, &stream, 1) < 0) break;

		unsigned int p; size_t len = 0;
		for (p = 0; p < stream.packCount; p++) {
			IMPEncoderPack *pk = &stream.pack[p];
			if (pk->length == 0 || len + pk->length > ASM_MAX) continue;
			uint32_t rem = stream.streamSize - pk->offset;
			if (pk->length <= rem) {
				memcpy(asm_buf + len, (void *)(stream.virAddr + pk->offset), pk->length);
			} else {
				memcpy(asm_buf + len, (void *)(stream.virAddr + pk->offset), rem);
				memcpy(asm_buf + len + rem, (void *)(uintptr_t)stream.virAddr, pk->length - rem);
			}
			len += pk->length;
		}
		if (len > 0 && write(lfd, asm_buf, len) > 0) { total += len; got++; }
		IMP_Encoder_ReleaseStream(CHN, &stream);
	}

	fprintf(stderr, "camd: exiting after %d frames, %ld bytes\n", got, total);
	fflush(stderr);

	int stype = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	ioctl(lfd, VIDIOC_STREAMOFF, &stype);
	close(lfd);
	IMP_Encoder_StopRecvPic(CHN);
	IMP_FrameSource_DisableChn(CHN);
	IMP_OSD_ShowRgn(rgnClock, GRP, 0);
	IMP_OSD_ShowRgn(rgnLogo, GRP, 0);
	IMP_System_UnBind(&osd_cell, &enc_cell);
	IMP_System_UnBind(&fs_cell, &osd_cell);
	IMP_OSD_UnRegisterRgn(rgnClock, GRP);
	IMP_OSD_UnRegisterRgn(rgnLogo, GRP);
	IMP_OSD_DestroyRgn(rgnClock);
	IMP_OSD_DestroyRgn(rgnLogo);
	IMP_OSD_DestroyGroup(GRP);
	IMP_Encoder_UnRegisterChn(CHN);
	IMP_Encoder_DestroyChn(CHN);
	IMP_Encoder_DestroyGroup(CHN);
	IMP_FrameSource_DestroyChn(CHN);
	IMP_ISP_DisableTuning();
	IMP_System_Exit();
	IMP_ISP_DisableSensor();
	IMP_ISP_DelSensor(&si);
	IMP_ISP_Close();
	return (got > 0) ? 0 : 1;
}
