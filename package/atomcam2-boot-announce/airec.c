/*
 * Record raw PCM from the Atom Cam 2 microphone via libimp IMP_AI.
 * PCM format: signed 16-bit, 8000 Hz, mono (matches aoplay, so a recording
 * can be played straight back with atomcam2-aoplay).
 *
 * Run with iCamera_app STOPPED (vendor owns the audio device otherwise).
 * Usage: airec <file.pcm> [seconds] [rate] [gain]
 *   default: /tmp/mic.raw 5 8000 (gain: -1 = leave at default)
 *
 * Build: mips-linux-uclibc-gnu-gcc -O2 -march=mips32r2 -I<sdk111> \
 *   -Wl,--dynamic-linker=/atom/lib/ld-uClibc.so.0 \
 *   airec.c -L lib -limp -lalog -lpthread -lm -lrt -o airec
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <imp/imp_audio.h>

#define NUM_PER_FRM 400
#define FRM_NUM 40

static int step(const char *label, int rc)
{
	fprintf(stderr, "airec: %-22s = %d\n", label, rc);
	fflush(stderr);
	return rc;
}

int main(int argc, char **argv)
{
	const char *path = (argc > 1) ? argv[1] : "/tmp/mic.raw";
	int seconds = (argc > 2) ? atoi(argv[2]) : 5;
	int rate = (argc > 3) ? atoi(argv[3]) : 8000;
	int gain = (argc > 4) ? atoi(argv[4]) : -1;   /* IMP_AI_SetGain, -1 = skip */
	/* The mic is AI device 1 (the speaker DAC is AO device 0). */
	int dev = 1, chn = 0;
	IMPAudioIOAttr attr;
	IMPAudioIChnParam chnParam;
	long target, total = 0;
	int frames = 0;

	FILE *f = fopen(path, "wb");
	if (!f) { fprintf(stderr, "airec: cannot open %s\n", path); return 1; }

	memset(&attr, 0, sizeof(attr));
	attr.samplerate = rate;
	attr.bitwidth = AUDIO_BIT_WIDTH_16;
	attr.soundmode = AUDIO_SOUND_MODE_MONO;
	attr.frmNum = FRM_NUM;
	attr.numPerFrm = NUM_PER_FRM;
	attr.chnCnt = 1;

	if (step("IMP_AI_SetPubAttr", IMP_AI_SetPubAttr(dev, &attr)) != 0) return 1;
	if (step("IMP_AI_Enable", IMP_AI_Enable(dev)) != 0) return 1;

	memset(&chnParam, 0, sizeof(chnParam));
	chnParam.usrFrmDepth = 20;
	if (step("IMP_AI_SetChnParam", IMP_AI_SetChnParam(dev, chn, &chnParam)) != 0) return 1;
	if (step("IMP_AI_EnableChn", IMP_AI_EnableChn(dev, chn)) != 0) return 1;
	step("IMP_AI_SetVol(100)", IMP_AI_SetVol(dev, chn, 100));
	if (gain >= 0) {
		char label[32];
		snprintf(label, sizeof(label), "IMP_AI_SetGain(%d)", gain);
		step(label, IMP_AI_SetGain(dev, chn, gain));
	}

	target = (long)rate * 2 * seconds;   /* 16-bit mono => 2 bytes/sample */
	fprintf(stderr, "airec: recording %d s (%ld bytes) to %s\n", seconds, target, path);
	fflush(stderr);

	while (total < target) {
		if (IMP_AI_PollingFrame(dev, chn, 1000) != 0) continue;
		IMPAudioFrame frm;
		memset(&frm, 0, sizeof(frm));
		if (IMP_AI_GetFrame(dev, chn, &frm, BLOCK) != 0) break;
		if (frm.len > 0 && frm.virAddr) {
			fwrite((void *)frm.virAddr, 1, frm.len, f);
			total += frm.len;
			frames++;
		}
		IMP_AI_ReleaseFrame(dev, chn, &frm);
	}

	fclose(f);
	fprintf(stderr, "airec: recorded %d frames, %ld bytes\n", frames, total);

	IMP_AI_DisableChn(dev, chn);
	IMP_AI_Disable(dev);
	fprintf(stderr, "airec: done\n");
	return 0;
}
