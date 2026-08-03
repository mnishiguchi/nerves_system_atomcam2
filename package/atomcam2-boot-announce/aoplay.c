/*
 * Play a raw PCM file through the Atom Cam 2 speaker via libimp IMP_AO.
 * PCM format: signed 16-bit, 8000 Hz, mono (matches the attr below).
 *
 * Run with iCamera_app STOPPED (vendor owns the audio device otherwise).
 * Usage: aoplay [file.pcm]   default /data/tone16.raw
 *
 * Build: mips-linux-uclibc-gnu-gcc -O2 -march=mips32r2 -I<sdk111> \
 *   -Wl,--dynamic-linker=/atom/lib/ld-uClibc.so.0 \
 *   aoplay.c -L lib -limp -lalog -lpthread -lm -lrt -o aoplay
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <imp/imp_audio.h>

/* speaker_ctl.ko: opening /dev/speakerctl enables the external power amp;
 * ioctl(fd, MODE) with MODE 0..4 sets the gain step (one-wire pulse train on
 * GPIO63). Keep the fd open for the whole playback. */
#define SPEAKERCTL "/dev/speakerctl"

#define NUM_PER_FRM 400
#define BYTES_PER_FRM (NUM_PER_FRM * 2)   /* 16-bit mono */
#define FRM_NUM 40                          /* deeper buffer to avoid underruns */

static int step(const char *label, int rc)
{
	fprintf(stderr, "aoplay: %-22s = %d\n", label, rc);
	fflush(stderr);
	return rc;
}

int main(int argc, char **argv)
{
	const char *path = (argc > 1) ? argv[1] : "/data/tone16.raw";
	int gain = (argc > 2) ? atoi(argv[2]) : 1;   /* speaker amp gain step 0..4 */
	int rate = (argc > 3) ? atoi(argv[3]) : 8000;  /* PCM sample rate */
	int vol = (argc > 4) ? atoi(argv[4]) : 60;   /* IMP_AO_SetVol, 100 = 0dB */
	int dev = 0, chn = 0;
	IMPAudioIOAttr attr;
	unsigned char buf[BYTES_PER_FRM];
	int frames = 0;
	long total = 0;
	size_t n;

	FILE *f = fopen(path, "rb");
	if (!f) { fprintf(stderr, "aoplay: cannot open %s\n", path); return 1; }

	/* Enable the external power amp (open) and set gain (ioctl MODE). */
	int spk = open(SPEAKERCTL, O_RDWR);
	if (spk < 0) {
		fprintf(stderr, "aoplay: WARN cannot open %s (amp off)\n", SPEAKERCTL);
	} else {
		int r = ioctl(spk, gain, 0);
		fprintf(stderr, "aoplay: speaker amp on, gain mode %d (ioctl=%d)\n", gain, r);
	}

	memset(&attr, 0, sizeof(attr));
	attr.samplerate = rate;
	attr.bitwidth = AUDIO_BIT_WIDTH_16;
	attr.soundmode = AUDIO_SOUND_MODE_MONO;
	attr.frmNum = FRM_NUM;
	attr.numPerFrm = NUM_PER_FRM;
	attr.chnCnt = 1;

	if (step("IMP_AO_SetPubAttr", IMP_AO_SetPubAttr(dev, &attr)) != 0) return 1;

	{
		IMPAudioIOAttr got;
		memset(&got, 0, sizeof(got));
		if (IMP_AO_GetPubAttr(dev, &got) == 0)
			fprintf(stderr, "aoplay: DAC actual samplerate=%d bitwidth=%d soundmode=%d numPerFrm=%d\n",
				got.samplerate, got.bitwidth, got.soundmode, got.numPerFrm);
	}
	if (step("IMP_AO_Enable", IMP_AO_Enable(dev)) != 0) return 1;
	if (step("IMP_AO_EnableChn", IMP_AO_EnableChn(dev, chn)) != 0) return 1;
	{
		char label[32];
		snprintf(label, sizeof(label), "IMP_AO_SetVol(%d)", vol);
		step(label, IMP_AO_SetVol(dev, chn, vol));
	}

	fprintf(stderr, "aoplay: playing %s\n", path);
	fflush(stderr);

	while ((n = fread(buf, 1, sizeof(buf), f)) > 0) {
		if (n < sizeof(buf))                 /* zero-pad final partial frame */
			memset(buf + n, 0, sizeof(buf) - n);
		IMPAudioFrame frm;
		memset(&frm, 0, sizeof(frm));
		frm.bitwidth = AUDIO_BIT_WIDTH_16;
		frm.soundmode = AUDIO_SOUND_MODE_MONO;
		frm.virAddr = (uint32_t *)buf;
		frm.len = (int)sizeof(buf);
		if (IMP_AO_SendFrame(dev, chn, &frm, BLOCK) != 0) {
			fprintf(stderr, "aoplay: SendFrame failed at frame %d\n", frames);
			break;
		}
		frames++;
		total += n;
	}

	fclose(f);
	fprintf(stderr, "aoplay: sent %d frames, %ld bytes\n", frames, total);

	/* Everything above only queues into the frmNum ring; wait until the DAC
	 * has actually drained it before tearing the channel and the amp down. */
	if (step("IMP_AO_FlushChnBuf", IMP_AO_FlushChnBuf(dev, chn)) != 0) {
		IMPAudioOChnState st;
		while (IMP_AO_QueryChnStat(dev, chn, &st) == 0 && st.chnBusyNum > 0)
			usleep(50 * 1000);
	}
	usleep(300 * 1000);

	IMP_AO_DisableChn(dev, chn);
	IMP_AO_Disable(dev);
	if (spk >= 0) close(spk);   /* closing releases the amp */
	fprintf(stderr, "aoplay: done\n");
	return 0;
}
