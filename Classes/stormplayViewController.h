//
//  stormplayViewController.h
//  stormplay
//
//  Created by bf apple on 12-5-23.
//  Copyright 2012 baofeng.com All rights reserved.
//  yubo@baofeng.com
//

#import <UIKit/UIKit.h>
#import "playAudio.h"
#import "EAGLView.h"
#import "player.h"


@class EAGLView;
@class playAudio;

@interface stormplayViewController : UIViewController {
	VideoState *gis;
	UIView *uiview;
	EAGLView *glView;
	playAudio *playaudio;
	UISlider   *VolumeSlider;
	UISlider   *SeekSlider;
	UIButton   *StartButton;	
	UILabel	   *TimeLabel;
	
	
	
}




@property (nonatomic, retain) IBOutlet UIView *uiview;
@property (nonatomic, retain) IBOutlet EAGLView *glView;
@property (nonatomic, retain) IBOutlet playAudio *playaudio;
@property (nonatomic, retain) IBOutlet UISlider   *VolumeSlider;
@property (nonatomic, retain) IBOutlet UISlider   *SeekSlider;
@property (nonatomic, retain) IBOutlet UIButton   *StartButton;
@property (nonatomic, retain) IBOutlet UILabel	   *TimeLabel;


- (IBAction)setOutputVolume:(UISlider *)sender;
- (IBAction)setPlaySeek:(UISlider *)sender;
- (IBAction)setPlayStart:(id)sender;

- (IBAction)setUISliderDrag:(UISlider *)sender;
- (IBAction)setUISliderUpInside:(UISlider *)sender;
- (IBAction)setUISliderUpOutside:(UISlider *)sender;
- (IBAction)setUISliderDragEnter:(UISlider *)sender;
- (IBAction)setUISliderDragExit:(UISlider *)sender;

- (void)setUIDefaults;
- (int)initPlay;
- (void)drawFrame;
- (void)startVideo;
- (void)stopVideo;
- (void)startAudio;
- (int) stream_component_open:(VideoState *)is stream_index:(int)stream_index;
- (void) video_image_display;
- (void) video_refresh;

static void audioCallback(void *inUserData,AudioQueueRef inAQ,
						  AudioQueueBufferRef buffer);


void check_gl_error(const char* op);

int EGL_DisplayRGBOverlay(VideoState *is,  EGL_Overlay *overlay, SDL_Rect *dstrect);
EGL_Overlay *EGL_CreateGRBOverlay(int w, int h, Uint32 format);
void EGL_FreeGRBOverlay(EGL_Overlay *overlay);


static void engine_draw_frame();
static void engine_term_display();
int native_main();
void check_gl_error(const char* op);
EGL_Surface * EGL_SetVideoMode (int width, int height, int bpp, Uint32 flags, VideoState *is);
void audio_term();
static int lockmgr(void **mtx, enum AVLockOp op);



VideoState *nativeInit(int argc, char *arg);
int nativeResize(VideoState *is, int w, int h);
- (void)nativeStart;
- (int)nativeRender;
int nativePause(VideoState *is);
int nativeDone(VideoState *is);
int nativeSeek(VideoState *is,int seek);
int nativeGetClock(VideoState *is);
int RemotePlayerMsg(int msgid, VideoState *is);
static int video_open(VideoState *is, int force_set_video_mode);
static double get_master_clock(VideoState *is);
static double get_video_clock(VideoState *is);

@end

