/*
 * Copyright (c) 2003 Fabrice Bellard
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/*
 * simple android media player based on the FFmpeg libraries
 * 2012-3
 * yubo@yubo.org
 */

/* 
 * for iso 
 * 2012-5
 * yubo@yubo.org
 */

//#define DEBUG_SYNC
#import "stormplayViewController.h"
#import "EAGLView.h"
#import "playAudio.h"

@implementation stormplayViewController


@synthesize glView, playaudio, uiview, VolumeSlider, TimeLabel;


#include "player.h"

#define GL_565 
static const char pic_data[] = 
#include "pic_352x288_rgb565.h"
;

static const char pcm_data[] =
#include "hello_clip_8000_16bit_mono.h"
;

const char program_name[] = "bbplay";
const int program_birth_year = 2012;
AVDictionary *format_opts, *codec_opts;

static int opt_help(const char *opt, const char *arg);

/* options specified by the user */
static AVInputFormat *file_iformat;
static const char *input_filename;
static char input_argv[512];
static const char *window_title;
static int fs_screen_width;
static int fs_screen_height;
static int screen_width  = 0;
static int screen_height = 0;
static int audio_disable;
static int video_disable;
static int wanted_stream[AVMEDIA_TYPE_NB] = {
    [AVMEDIA_TYPE_AUDIO]    = -1,
    [AVMEDIA_TYPE_VIDEO]    = -1,
    [AVMEDIA_TYPE_SUBTITLE] = -1,
};
static int seek_by_bytes = -1;
static int display_disable;
static int show_status = 1;
static int av_sync_type = AV_SYNC_AUDIO_MASTER;
static int64_t start_time = AV_NOPTS_VALUE;
static int64_t duration = AV_NOPTS_VALUE;
static int workaround_bugs = 1;
static int fast = 0;
static int genpts = 0;
static int lowres = 0;
static int idct = FF_IDCT_AUTO;
static enum AVDiscard skip_frame       = AVDISCARD_DEFAULT;
static enum AVDiscard skip_idct        = AVDISCARD_DEFAULT;
static enum AVDiscard skip_loop_filter = AVDISCARD_DEFAULT;
static int error_concealment = 3;
static int decoder_reorder_pts = -1;
static int autoexit;
static int exit_on_keydown;
static int exit_on_mousedown;
static int loop = 1;
static int framedrop = 1;
static enum ShowMode show_mode = SHOW_MODE_NONE;
static const char *audio_codec_name;
static const char *subtitle_codec_name;
static const char *video_codec_name;
static int rdftspeed = 20;

/* current context */
static int is_full_screen;
static int64_t audio_callback_time;

static AVPacket flush_pkt;

static EGL_Surface *screen;


/* audio */
// engine interfaces

EGL_Surface  *gVideo;
static GLuint s_texture = 0;
static int gResize = 0;

static struct AQPlayerState {
	AudioStreamBasicDescription dataFormat;
	AudioQueueRef queue;
	AudioQueueBufferRef buffers[NUM_BUFFERS];
	bool mIsRunning;
} AQ;


#pragma mark -
#pragma mark Actions

- (void) printTime:(int)time
{
	int m,h,s,t;
	t = time / 1000;
	m = (t % 3600) / 60;
	h = t / 3600;
	s = t % 60;
	NSString *str=[[NSString alloc] initWithFormat:@"%2d:%02d:%02d",h,m,s];
	
	[TimeLabel setText:str];
	[str release];
}


// handle output volume changes
- (IBAction)setOutputVolume:(UISlider *)sender
{
	NSLog(@"value %f min %f max %f",sender.value, sender.minimumValue, sender.maximumValue);
    AudioUnitParameterValue value = sender.value;
	OSStatus result = AudioQueueSetParameter(AQ.queue, kAudioQueueParam_Volume, value);
	if (result) { printf("setOutputVolume AudioQueueParameterValue Output result %ld %08X %4.4s\n", result, (unsigned int)result, (char*)&result); return; }
}



- (IBAction)setPlaySeek:(UISlider *)sender
{
	NSLog(@"stormplayViewController playSeek %f min %f max %f",sender.value, sender.minimumValue, sender.maximumValue);

	int seek = (int)sender.value;
	nativeSeek(gis,seek);
}

- (IBAction)setUISliderDrag:(UISlider *)sender
{
	NSLog(@"stormplayViewController setUISliderDragInside ");
	int seek = (int)sender.value;
	[self printTime:seek];
}


- (IBAction)setUISliderUpInside:(UISlider *)sender
{
	NSLog(@"stormplayViewController setUISliderUpInside ");
}

- (IBAction)setUISliderUpOutside:(UISlider *)sender
{
	NSLog(@"stormplayViewController setUISliderUpOutside ");
}

- (IBAction)setUISliderDragEnter:(UISlider *)sender
{
	NSLog(@"stormplayViewController setUISliderDragEnter ");
}

- (IBAction)setUISliderDragExit:(UISlider *)sender
{
	NSLog(@"stormplayViewController setUISliderDragExit ");
}


- (IBAction)setPlayStart:(id)sender
{
	NSLog(@"stormplayViewController setPlayStart ");
	
	if (!glView->animating) {
		//		gis = nativeInit(2, "play /Users/admin/Desktop/yubo/VID_20120421_191108.3gp");
		gis = nativeInit(2, "play /Users/admin/Desktop/yubo/1.rmvb");
		[self startVideo];
		[self nativeStart];
		[self setUIDefaults];
	}
}

#pragma mark -
#pragma mark player



void av_noreturn exit_program(int ret)
{
	eLog("exit_program [%d]\n",ret);
    exit(ret);
}

static int packet_queue_put(PacketQueue *q, AVPacket *pkt)
{
    AVPacketList *pkt1;
	
    /* duplicate the packet */
    if (pkt != &flush_pkt && av_dup_packet(pkt) < 0)
        return -1;
	
    pkt1 = av_malloc(sizeof(AVPacketList));
    if (!pkt1)
        return -1;
    pkt1->pkt = *pkt;
    pkt1->next = NULL;
	
	
    SDL_LockMutex(q->mutex);
	
    if (!q->last_pkt)
		
        q->first_pkt = pkt1;
    else
        q->last_pkt->next = pkt1;
    q->last_pkt = pkt1;
    q->nb_packets++;
    q->size += pkt1->pkt.size + sizeof(*pkt1);
    /* XXX: should duplicate packet data in DV case */
    SDL_CondSignal(q->cond);
	
    SDL_UnlockMutex(q->mutex);
    return 0;
}

/* packet queue handling */
static void packet_queue_init(PacketQueue *q)
{
    memset(q, 0, sizeof(PacketQueue));
    q->mutex = SDL_CreateMutex();
    q->cond = SDL_CreateCond();
    packet_queue_put(q, &flush_pkt);
}

static void packet_queue_flush(PacketQueue *q)
{
    AVPacketList *pkt, *pkt1;
	
    SDL_LockMutex(q->mutex);
    for (pkt = q->first_pkt; pkt != NULL; pkt = pkt1) {
        pkt1 = pkt->next;
        av_free_packet(&pkt->pkt);
        av_freep(&pkt);
    }
    q->last_pkt = NULL;
    q->first_pkt = NULL;
    q->nb_packets = 0;
    q->size = 0;
    SDL_UnlockMutex(q->mutex);
}

static void packet_queue_end(PacketQueue *q)
{
    packet_queue_flush(q);
    SDL_DestroyMutex(q->mutex);
    SDL_DestroyCond(q->cond);
}

static void packet_queue_abort(PacketQueue *q)
{
    SDL_LockMutex(q->mutex);
	
    q->abort_request = 1;
	
    SDL_CondSignal(q->cond);
	
    SDL_UnlockMutex(q->mutex);
}

/* return < 0 if aborted, 0 if no packet and > 0 if packet.  */
static int packet_queue_get(PacketQueue *q, AVPacket *pkt, int block)
{
    AVPacketList *pkt1;
    int ret;
	
    SDL_LockMutex(q->mutex);
	
    for (;;) {
        if (q->abort_request) {
            ret = -1;
            break;
        }
		
        pkt1 = q->first_pkt;
        if (pkt1) {
            q->first_pkt = pkt1->next;
            if (!q->first_pkt)
                q->last_pkt = NULL;
            q->nb_packets--;
            q->size -= pkt1->pkt.size + sizeof(*pkt1);
            *pkt = pkt1->pkt;
            av_free(pkt1);
            ret = 1;
            break;
        } else if (!block) {
            ret = 0;
            break;
        } else {
            SDL_CondWait(q->cond, q->mutex);
        }
    }
    SDL_UnlockMutex(q->mutex);
    return ret;
}







static inline int compute_mod(int a, int b)
{
    return a < 0 ? a%b + b : a%b;
}


static void stream_close(VideoState *is)
{
    VideoPicture *vp;
    int i;
    /* XXX: use a special url_shutdown call to abort parse cleanly */
    is->abort_request = 1;
    SDL_WaitThread(is->read_tid, NULL);
	//    SDL_WaitThread(is->refresh_tid, NULL);
	
    /* free all pictures */
    for (i = 0; i < VIDEO_PICTURE_QUEUE_SIZE; i++) {
        vp = &is->pictq[i];
        if (vp->bmp) {
			EGL_FreeGRBOverlay(vp->bmp);
            vp->bmp = NULL;
        }
    }
    SDL_DestroyMutex(is->pictq_mutex);
    SDL_DestroyCond(is->pictq_cond);
    SDL_DestroyMutex(is->subpq_mutex);
    SDL_DestroyCond(is->subpq_cond);
    if (is->img_convert_ctx)
        sws_freeContext(is->img_convert_ctx);
    av_free(is);
}

static void do_exit(VideoState *is)
{
    if (is) {
        stream_close(is);
    }
    av_lockmgr_register(NULL);
    uninit_opts();
    avformat_network_deinit();
    if (show_status)
        printf("\n");
    SDL_Quit();
    SDL_WaitThread(is->loop_tid, NULL);
    iLog("%s\n", "quit");
	
    exit(0);
}

static void sigterm_handler(int sig)
{
    exit(123);
}




static int video_open(VideoState *is, int force_set_video_mode)
{
    int flags = SDL_HWSURFACE | SDL_ASYNCBLIT | SDL_HWACCEL;
    int w,h;
    
	
	
    if (is_full_screen) flags |= SDL_FULLSCREEN;
    else                flags |= SDL_RESIZABLE;
	
    if (is_full_screen && fs_screen_width) {
        w = fs_screen_width;
        h = fs_screen_height;
    } else if (!is_full_screen && screen_width) {
        w = screen_width;
        h = screen_height;
    } else if (is->video_st && is->video_st->codec->width) {
        w = is->video_st->codec->width;
        h = is->video_st->codec->height;
		
    } else {
        w = 640;
        h = 480;
    }   
	
    
    if (screen && is->width == screen->w && screen->w == w
		&& is->height== screen->h && screen->h == h && !force_set_video_mode)
        return 0;
	//__YUBO need fix
	
    screen = EGL_SetVideoMode(is->width, is->height, 0, flags, is);
    if(!screen) {
        eLog("SDL: could not set video mode - exiting\n");
        do_exit(is);
    }
    if (!window_title)
        window_title = input_filename;
	//    SDL_WM_SetCaption(window_title, window_title);
	
    is->width  = screen->w;
    is->height = screen->h;
	
    return 0;
}
//
//
//static void video_image_display(VideoState *is)
//{
//    VideoPicture *vp;
//    AVPicture pict;
//    float aspect_ratio;
//    int width, height, x, y;
//    int i;
//    SDL_Rect rect;
//    
//	
//    vp = &is->pictq[is->pictq_rindex];
//    if (vp->bmp) {
//        /* XXX: use variable in the frame */
//        if (is->video_st->sample_aspect_ratio.num)
//            aspect_ratio = av_q2d(is->video_st->sample_aspect_ratio);
//        else if (is->video_st->codec->sample_aspect_ratio.num)
//            aspect_ratio = av_q2d(is->video_st->codec->sample_aspect_ratio);
//        else
//            aspect_ratio = 0;
//        if (aspect_ratio <= 0.0)
//            aspect_ratio = 1.0;
//        aspect_ratio *= (float)vp->width / (float)vp->height;
//		
//		
//        /* XXX: we suppose the screen has a 1.0 pixel ratio */
//		
//        height = is->height;
//        width = ((int)rint(height * aspect_ratio)) & ~1;
//        if (width > is->width) {
//            width = is->width;
//            height = ((int)rint(width / aspect_ratio)) & ~1;
//        }
//        x = (is->width - width) / 2;
//        y = (is->height - height) / 2;
//        is->no_background = 0;
//        rect.x = is->xleft + x;
//        rect.y = is->ytop  + y;
//        rect.w = FFMAX(width,  1);
//        rect.h = FFMAX(height, 1);
//		
//		
//		
//		
//        glClear(GL_COLOR_BUFFER_BIT);
//#ifdef GL_565       
//        glTexImage2D(GL_TEXTURE_2D,		/* target */
//					 0,			/* level */
//					 GL_RGB,			/* internal format */
//					 vp->bmp->w,		/* width */
//					 vp->bmp->h,		/* height */
//					 0,			/* border */
//					 GL_RGB,			/* format */
//					 GL_UNSIGNED_SHORT_5_6_5,/* type */
//					 vp->bmp->pict.data[0]);		/* pixels */
//#else
//		glTexImage2D(GL_TEXTURE_2D,		/* target */
//					 0,			/* level */
//					 GL_RGB,			/* internal format */
//					 vp->bmp->w,		/* width */
//					 vp->bmp->h,		/* height */
//					 0,			/* border */
//					 GL_RGB,			/* format */
//					 GL_UNSIGNED_BYTE,/* type */
//					 vp->bmp->pict.data[0]);		/* pixels */
//#endif	
//        glDrawTexiOES(rect.x , rect.y, 0, rect.w, rect.h);
//        //glDrawTexiOES(0 , 0, 0, vp->bmp->w, vp->bmp->h);
//        
//		//	        iLog("EGL_DisplayRGBOverlay glDrawTexiOES x[%d] y[%d] w[%d] h[%d]",
//		//	            rect.x , rect.y, rect.w, rect.h);
//        check_gl_error("video_image_display");
//        is->refresh = 1;
//		
//    }
//}


static int64_t video_time, video_frametime, video_fpstime;
static float video_avgFPS, video_framerrate;

/* display the current picture, if any */
- (void) video_display
{
	//iLog("video_display video_time[%lld] [%lld]\n", video_time, av_gettime());
	if (!screen)
        video_open(gis, 0);
    if (gis->video_st){
		video_time = av_gettime() / 1000;
		if (video_time >= (video_frametime + 1000)) {
			video_frametime = video_time;
			video_avgFPS += video_frametime;
			video_framerrate = 0;
			[self sysncPlayerClock];		
		}
		if (video_time >= (video_fpstime + 3000)) {
			video_fpstime = video_time;
			video_avgFPS /= 3.0f;
			video_avgFPS = 0;
		}
		video_framerrate++;
        [self video_image_display];
	}
}



/* get the current audio clock value */
static double get_audio_clock(VideoState *is)
{
    if (is->paused) {
        return is->audio_current_pts;
    } else {
        return is->audio_current_pts_drift + av_gettime() / 1000000.0;
    }
}

/* get the current video clock value */
static double get_video_clock(VideoState *is)
{
    if (is->paused) {
        return is->video_current_pts;
    } else {
        return is->video_current_pts_drift + av_gettime() / 1000000.0;
    }
}

/* get the current external clock value */
static double get_external_clock(VideoState *is)
{
    int64_t ti;
    ti = av_gettime();
    return is->external_clock + ((ti - is->external_clock_time) * 1e-6);
}

/* get the current master clock value */
static double get_master_clock(VideoState *is)
{
    double val;
	
    if (is->av_sync_type == AV_SYNC_VIDEO_MASTER) {
        if (is->video_st)
            val = get_video_clock(is);
        else
            val = get_audio_clock(is);
    } else if (is->av_sync_type == AV_SYNC_AUDIO_MASTER) {
        if (is->audio_st)
            val = get_audio_clock(is);
        else
            val = get_video_clock(is);
    } else {
        val = get_external_clock(is);
    }
    return val;
}





EGL_Surface * EGL_SetVideoMode (int width, int height, int bpp, Uint32 flags, VideoState *is){
    EGL_Surface *screen;
    if(gVideo == NULL){
        gVideo = (EGL_Surface *)malloc(sizeof(EGL_Surface));
        if(!gVideo){
            return NULL;
        }
        memset(gVideo,0,sizeof(EGL_Surface));
    }
    screen = gVideo;
    
	
	
    screen->w = width;
    screen->h = height;
    screen->flags = flags;    
    return screen;    
}


/* seek in the stream */
static void stream_seek(VideoState *is, int64_t pos, int64_t rel, int seek_by_bytes)
{
    if (!is->seek_req) {
        is->seek_pos = pos;
        is->seek_rel = rel;
        is->seek_flags &= ~AVSEEK_FLAG_BYTE;
        if (seek_by_bytes)
            is->seek_flags |= AVSEEK_FLAG_BYTE;
        is->seek_req = 1;
    }
}

/* pause or resume the video */
static void stream_toggle_pause(VideoState *is)
{
    if (is->paused) {
        is->frame_timer += av_gettime() / 1000000.0 + is->video_current_pts_drift - is->video_current_pts;
        if (is->read_pause_return != AVERROR(ENOSYS)) {
            is->video_current_pts = is->video_current_pts_drift + av_gettime() / 1000000.0;
        }
        is->video_current_pts_drift = is->video_current_pts - av_gettime() / 1000000.0;
    }
    is->paused = !is->paused;
}

static double compute_target_delay(double delay, VideoState *is)
{
    double sync_threshold, diff;
	
    /* update delay to follow master synchronisation source */
    if (((is->av_sync_type == AV_SYNC_AUDIO_MASTER && is->audio_st) ||
         is->av_sync_type == AV_SYNC_EXTERNAL_CLOCK)) {
        /* if video is slave, we try to correct big delays by
		 duplicating or deleting a frame */
        diff = get_video_clock(is) - get_master_clock(is);
		
        /* skip or repeat frame. We take into account the
		 delay to compute the threshold. I still don't know
		 if it is the best guess */
        sync_threshold = FFMAX(AV_SYNC_THRESHOLD, delay);
        if (fabs(diff) < AV_NOSYNC_THRESHOLD) {
            if (diff <= -sync_threshold)
                delay = 0;
            else if (diff >= sync_threshold)
                delay = 2 * delay;
        }
    }
#if defined(DEBUG_SYNC) 
	iLog("video: delay=%0.3f A-V=%f\n",
		 delay, -diff);
#endif
    return delay;
}

static void pictq_next_picture(VideoState *is) {
    /* update queue size and signal for next picture */
    if (++is->pictq_rindex == VIDEO_PICTURE_QUEUE_SIZE)
        is->pictq_rindex = 0;
	
    SDL_LockMutex(is->pictq_mutex);
    is->pictq_size--;
    SDL_CondSignal(is->pictq_cond);
    SDL_UnlockMutex(is->pictq_mutex);
}

static void update_video_pts(VideoState *is, double pts, int64_t pos) {
    double time = av_gettime() / 1000000.0;
    /* update current video pts */
    is->video_current_pts = pts;
    is->video_current_pts_drift = is->video_current_pts - time;
    is->video_current_pos = pos;
    is->frame_last_pts = pts;
}

/* called to display each frame */
- (void) video_refresh
{
    VideoState *is = gis;
    VideoPicture *vp;
    double time;
	
	
    if (is->video_st) {

        
	retry:
        if (is->pictq_size == 0) {
            SDL_LockMutex(is->pictq_mutex);
            if (is->frame_last_dropped_pts != AV_NOPTS_VALUE && is->frame_last_dropped_pts > is->frame_last_pts) {
                update_video_pts(is, is->frame_last_dropped_pts, is->frame_last_dropped_pos);
                is->frame_last_dropped_pts = AV_NOPTS_VALUE;
            }
            SDL_UnlockMutex(is->pictq_mutex);
            // nothing to do, no picture to display in the que
        } else {
            double last_duration, duration, delay;
            /* dequeue the picture */
            vp = &is->pictq[is->pictq_rindex];
			
            if (vp->skip) {
                pictq_next_picture(is);
                goto retry;
            }
			
            /* compute nominal last_duration */
            last_duration = vp->pts - is->frame_last_pts;
            if (last_duration > 0 && last_duration < 10.0) {
                /* if duration of the last frame was sane, update last_duration in video state */
                is->frame_last_duration = last_duration;
            }
            delay = compute_target_delay(is->frame_last_duration, is);
			
            time= av_gettime()/1000000.0;
            if (time < is->frame_timer + delay)
                return;
			
            if (delay > 0)
                is->frame_timer += delay * FFMAX(1, floor((time-is->frame_timer) / delay));
			
            SDL_LockMutex(is->pictq_mutex);
            update_video_pts(is, vp->pts, vp->pos);
            SDL_UnlockMutex(is->pictq_mutex);
			
            if (is->pictq_size > 1) {
                VideoPicture *nextvp = &is->pictq[(is->pictq_rindex + 1) % VIDEO_PICTURE_QUEUE_SIZE];
                duration = nextvp->pts - vp->pts; // More accurate this way, 1/time_base is often not reflecting FPS
            } else {
                duration = vp->duration;
            }
			
            if((framedrop>0 || (framedrop && is->audio_st)) && time > is->frame_timer + duration){
                if(is->pictq_size > 1){
                    is->frame_drops_late++;
                    pictq_next_picture(is);
#if defined(DEBUG_SYNC)                     
                    iLog("=====================frame drop [%d]!!!!\n",is->frame_drops_late);
#endif
                    goto retry;
                }
                // __SKIP ry send event to drop frame
                is->skip_pkt = 1;
                
				// iLog("frame drop pictq_size[%d]!!!!",is->pictq_size);
            }else{
                is->skip_pkt = 0;
            }
			
            /* display picture */
            if (!display_disable)
                [self video_display];
			
            pictq_next_picture(is);
        }
		
		
    } else if (is->audio_st) {
        /* draw the next audio frame */
		
        /* if only audio stream, then display the audio bars (better
		 than nothing, just to test the implementation */
		
        /* display picture */
        if (!display_disable)
            [self video_display];
    }
    if (show_status) {
        static int64_t last_time;
        int64_t cur_time;
        int aqsize, vqsize, sqsize;
        double av_diff;
		
        cur_time = av_gettime();
        if (!last_time || (cur_time - last_time) >= 30000) {
            aqsize = 0;
            vqsize = 0;
            sqsize = 0;
            if (is->audio_st)
                aqsize = is->audioq.size;
            if (is->video_st)
                vqsize = is->videoq.size;
            if (is->subtitle_st)
                sqsize = is->subtitleq.size;
            av_diff = 0;
            if (is->audio_st && is->video_st)
                av_diff = get_audio_clock(is) - get_video_clock(is);
			//	            iLog("%7.2f A-V:%7.3f fd=%4d aq=%5dKB vq=%5dKB sq=%5dB f=%"PRId64"/%"PRId64"   \r",
			//	                   get_master_clock(is),
			//	                   av_diff,
			//	                   is->frame_drops_early + is->frame_drops_late,
			//	                   aqsize / 1024,
			//	                   vqsize / 1024,
			//	                   sqsize,
			//	                   is->video_st ? is->video_st->codec->pts_correction_num_faulty_dts : 0,
			//	                   is->video_st ? is->video_st->codec->pts_correction_num_faulty_pts : 0);
            last_time = cur_time;
        }
    }
}

/* allocate a picture (needs to do that in main thread to avoid
 potential locking problems */
static void alloc_picture(void *opaque)
{
    VideoState *is = opaque;
    VideoPicture *vp;
	
    vp = &is->pictq[is->pictq_windex];
	
    if (vp->bmp)
        EGL_FreeGRBOverlay(vp->bmp);
	
    vp->width   = is->video_st->codec->width;
    vp->height  = is->video_st->codec->height;
    vp->pix_fmt = is->video_st->codec->pix_fmt;
    iLog("alloc_picture =========> vp[0x%x],is->pictq_windex[%d]\n",vp,is->pictq_windex);
	
	
	//	    vp->bmp = SDL_CreateYUVOverlay(vp->width, vp->height,
	//	                                   SDL_YV12_OVERLAY,
	//	                                   screen);
#ifdef GL_565
    vp->bmp = EGL_CreateGRBOverlay(vp->width, vp->height,
                                   PIX_FMT_RGB565);
#else
    vp->bmp = EGL_CreateGRBOverlay(vp->width, vp->height,
                                   PIX_FMT_RGB24);
#endif
    if (!vp->bmp || vp->bmp->pict.linesize[0]< vp->width) {
        /* SDL allocates a buffer smaller than requested if the video
         * overlay hardware is unable to support the requested size. */
        eLog("Error: the video system does not support an image\n"
			 "size of %dx%d pixels. Try using -lowres or -vf \"scale=w:h\"\n"
			 "to reduce the image size.\n", vp->width, vp->height );
        do_exit(is);
    }
	
    SDL_LockMutex(is->pictq_mutex);
    vp->allocated = 1;
    SDL_CondSignal(is->pictq_cond);
    SDL_UnlockMutex(is->pictq_mutex);
}

static int queue_picture(VideoState *is, AVFrame *src_frame, double pts1, int64_t pos)
{
    VideoPicture *vp;
    double frame_delay, pts = pts1;
	
    /* compute the exact PTS for the picture if it is omitted in the stream
     * pts1 is the dts of the pkt / pts of the frame */
    if (pts != 0) {
        /* update video clock with pts, if present */
        is->video_clock = pts;
    } else {
        pts = is->video_clock;
    }
    /* update video clock for next frame */
    frame_delay = av_q2d(is->video_st->codec->time_base);
    /* for MPEG2, the frame can be repeated, so we update the
	 clock accordingly */
    frame_delay += src_frame->repeat_pict * (frame_delay * 0.5);
    is->video_clock += frame_delay;
	
#if defined(DEBUG_SYNC)
    iLog("queue_picture frame_type=%c clock=%0.3f pts=%0.3f pictq_windex[%d],pictq_size[%d]\n",
		 av_get_picture_type_char(src_frame->pict_type), pts, pts1,is->pictq_windex,is->pictq_size);
#endif
    /* wait until we have space to put a new picture */
    SDL_LockMutex(is->pictq_mutex);
	
    while (is->pictq_size >= VIDEO_PICTURE_QUEUE_SIZE &&
           !is->videoq.abort_request) {
        SDL_CondWait(is->pictq_cond, is->pictq_mutex);
    }
    SDL_UnlockMutex(is->pictq_mutex);
	
    if (is->videoq.abort_request)
        return -1;
	
    vp = &is->pictq[is->pictq_windex];
	
    vp->duration = frame_delay;
	
    /* alloc or resize hardware picture buffer */
    if (!vp->bmp || vp->reallocate ||
        vp->width != is->video_st->codec->width ||
        vp->height != is->video_st->codec->height) {
        SDL_Event event;
		
        vp->allocated  = 0;
        vp->reallocate = 0;
		
        /* the allocation must be done in the main thread to avoid
		 locking problems */
        event.type = FF_ALLOC_EVENT;
        event.user.data1 = is;
        SDL_PushEvent(&event);
		
        /* wait until the picture is allocated */
        SDL_LockMutex(is->pictq_mutex);
        while (!vp->allocated && !is->videoq.abort_request) {
            SDL_CondWait(is->pictq_cond, is->pictq_mutex);
        }
        /* if the queue is aborted, we have to pop the pending ALLOC event or wait for the allocation to complete */
        if (is->videoq.abort_request && SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_EVENTMASK(FF_ALLOC_EVENT)) != 1) {
            while (!vp->allocated) {
                SDL_CondWait(is->pictq_cond, is->pictq_mutex);
            }
        }
        SDL_UnlockMutex(is->pictq_mutex);
		
        if (is->videoq.abort_request)
            return -1;
    }
	
    /* if the frame is not skipped, then display it */
    if (vp->bmp) {
        AVPicture pict;
		
        /* get a pointer on the bitmap */
		//        SDL_LockYUVOverlay (vp->bmp);
		
        memset(&pict, 0, sizeof(AVPicture));
        pict.data[0] = vp->bmp->pict.data[0];
		//        pict.data[1] = vp->bmp->pict.data[2];
		//        pict.data[2] = vp->bmp->pict.data[1];
		
        pict.linesize[0] = vp->bmp->pict.linesize[0];
		//        pict.linesize[1] = vp->bmp->pict.linesize[2];
		//        pict.linesize[2] = vp->bmp->pict.linesize[1];
		
		
		
        sws_flags = av_get_int(sws_opts, "sws_flags", NULL);
#ifdef GL_565  
        is->img_convert_ctx = sws_getCachedContext(is->img_convert_ctx,
												   vp->width, vp->height, vp->pix_fmt, vp->width, vp->height,
												   PIX_FMT_RGB565, sws_flags, NULL, NULL, NULL);
#else
        is->img_convert_ctx = sws_getCachedContext(is->img_convert_ctx,
												   vp->width, vp->height, vp->pix_fmt, vp->width, vp->height,
												   PIX_FMT_RGB24, sws_flags, NULL, NULL, NULL);
#endif        
        if (is->img_convert_ctx == NULL) {
            eLog("Cannot initialize the conversion context vp->pix_fmt[%d] -> rgb565",vp->pix_fmt);
            exit(1);
        }
        sws_scale(is->img_convert_ctx, src_frame->data, src_frame->linesize,
                  0, vp->height, pict.data, pict.linesize);
		//        if (pts > 182) saveYUV(src_frame);
		//        iLog("sws w%d h%d linesize%d",vp->width,vp->height,src_frame->linesize[0]);
        /* update the bitmap content */
		//        SDL_UnlockYUVOverlay(vp->bmp);
		
        vp->pts = pts;
        vp->pos = pos;
        vp->skip = 0;
		
        /* now we can update the picture count */
        if (++is->pictq_windex == VIDEO_PICTURE_QUEUE_SIZE)
            is->pictq_windex = 0;
        SDL_LockMutex(is->pictq_mutex);
        is->pictq_size++;
        SDL_UnlockMutex(is->pictq_mutex);
    }
    return 0;
}

static int get_video_frame(VideoState *is, AVFrame *frame, int64_t *pts, AVPacket *pkt)
{
    int got_picture, i;
	
    
    if (packet_queue_get(&is->videoq, pkt, 1) < 0)
        return -1;
	
    if (pkt->data == flush_pkt.data) {
        avcodec_flush_buffers(is->video_st->codec);
		
        SDL_LockMutex(is->pictq_mutex);
        // Make sure there are no long delay timers (ideally we should just flush the que but thats harder)
        for (i = 0; i < VIDEO_PICTURE_QUEUE_SIZE; i++) {
            is->pictq[i].skip = 1;
        }
        while (is->pictq_size && !is->videoq.abort_request) {
            SDL_CondWait(is->pictq_cond, is->pictq_mutex);
        }
        is->video_current_pos = -1;
        is->frame_last_pts = AV_NOPTS_VALUE;
        is->frame_last_duration = 0;
        is->frame_timer = (double)av_gettime() / 1000000.0;
        is->frame_last_dropped_pts = AV_NOPTS_VALUE;
        SDL_UnlockMutex(is->pictq_mutex);
		
        return 0;
    }
	
    if(is->skip_pkt){
		//			if (is->video_st->codec->codec_id == CODEC_ID_RV10 ||
		//				is->video_st->codec->codec_id == CODEC_ID_RV20 ||
		//				is->video_st->codec->codec_id == CODEC_ID_RV30 ||
		//				is->video_st->codec->codec_id == CODEC_ID_RV40)
		//				is->video_st->codec->skip_frame = AVDISCARD_BIDIR;
		//			else
		//			    is->video_st->codec->skip_frame = AVDISCARD_NONKEY;
		is->video_st->codec->skip_frame = AVDISCARD_BIDIR;     
		
    }else{
        is->video_st->codec->skip_frame = AVDISCARD_DEFAULT;
    }
	
    avcodec_decode_video2(is->video_st->codec, frame, &got_picture, pkt);
	
    if (got_picture) {
        int ret = 1;
		
        if (decoder_reorder_pts == -1) {
            *pts = *(int64_t*)av_opt_ptr(avcodec_get_frame_class(), frame, "best_effort_timestamp");
        } else if (decoder_reorder_pts) {
            *pts = frame->pkt_pts;
        } else {
            *pts = frame->pkt_dts;
        }
		
        if (*pts == AV_NOPTS_VALUE) {
            *pts = 0;
        }
		
        if (((is->av_sync_type == AV_SYNC_AUDIO_MASTER && is->audio_st) || is->av_sync_type == AV_SYNC_EXTERNAL_CLOCK) &&
			(framedrop>0 || (framedrop && is->audio_st))) {
            SDL_LockMutex(is->pictq_mutex);
            if (is->frame_last_pts != AV_NOPTS_VALUE && *pts) {
                double clockdiff = get_video_clock(is) - get_master_clock(is);
                double dpts = av_q2d(is->video_st->time_base) * *pts;
                double ptsdiff = dpts - is->frame_last_pts;
                if (fabs(clockdiff) < AV_NOSYNC_THRESHOLD &&
					ptsdiff > 0 && ptsdiff < AV_NOSYNC_THRESHOLD &&
					clockdiff + ptsdiff - is->frame_last_filter_delay < 0) {
                    is->frame_last_dropped_pos = pkt->pos;
                    is->frame_last_dropped_pts = dpts;
                    is->frame_drops_early++;
                    ret = 0;
                }
            }
            SDL_UnlockMutex(is->pictq_mutex);
        }
		
        if (ret)
            is->frame_last_returned_time = av_gettime() / 1000000.0;
		
        return ret;
    }
    return 0;
}




static int video_thread(void *arg)
{
    VideoState *is = arg;
    AVFrame *frame = avcodec_alloc_frame();
    int64_t pts_int = AV_NOPTS_VALUE, pos = -1;
    double pts;
    int ret;
	
	
	
    for (;;) {
        AVPacket pkt;
        while (is->paused && !is->videoq.abort_request)
            SDL_Delay(10);
		//__SKIP
	retry:        
        ret = get_video_frame(is, frame, &pts_int, &pkt);
		
		//	        if(is->skip_pkt>0 && frame->pict_type != AV_PICTURE_TYPE_I  ){
		//	            is->skip_pkt = 0;
		//	            is->frame_drops_late++;
		//	#if defined(DEBUG_SYNC) 
		//	            iLog("====== frame_drops_early[%d]",is->frame_drops_early);
		//	#endif
		//	            goto retry;
		//	        }
		
        
        pos = pkt.pos;
        av_free_packet(&pkt);
		
        if (ret < 0)
            goto the_end;
		
        is->frame_last_filter_delay = av_gettime() / 1000000.0 - is->frame_last_returned_time;
        if (fabs(is->frame_last_filter_delay) > AV_NOSYNC_THRESHOLD / 10.0)
            is->frame_last_filter_delay = 0;
		
		
		
        pts = pts_int * av_q2d(is->video_st->time_base);
		
        ret = queue_picture(is, frame, pts, pos);
        if (ret < 0)
            goto the_end;
		
        if (is->step)
            stream_toggle_pause(is);
    }
the_end:
	
    av_free(frame);
    return 0;
}


/* copy samples for viewing in editor window */
static void update_sample_display(VideoState *is, short *samples, int samples_size)
{
    int size, len;
	
    size = samples_size / sizeof(short);
    while (size > 0) {
        len = SAMPLE_ARRAY_SIZE - is->sample_array_index;
        if (len > size)
            len = size;
        memcpy(is->sample_array + is->sample_array_index, samples, len * sizeof(short));
        samples += len;
        is->sample_array_index += len;
        if (is->sample_array_index >= SAMPLE_ARRAY_SIZE)
            is->sample_array_index = 0;
        size -= len;
    }
}

/* return the wanted number of samples to get better sync if sync_type is video
 * or external master clock */
static int synchronize_audio(VideoState *is, int nb_samples)
{
    int wanted_nb_samples = nb_samples;
	
    /* if not master, then we try to remove or add samples to correct the clock */
    if (((is->av_sync_type == AV_SYNC_VIDEO_MASTER && is->video_st) ||
         is->av_sync_type == AV_SYNC_EXTERNAL_CLOCK)) {
        double diff, avg_diff;
        int min_nb_samples, max_nb_samples;
		
        diff = get_audio_clock(is) - get_master_clock(is);
		
        if (diff < AV_NOSYNC_THRESHOLD) {
            is->audio_diff_cum = diff + is->audio_diff_avg_coef * is->audio_diff_cum;
            if (is->audio_diff_avg_count < AUDIO_DIFF_AVG_NB) {
                /* not enough measures to have a correct estimate */
                is->audio_diff_avg_count++;
            } else {
                /* estimate the A-V difference */
                avg_diff = is->audio_diff_cum * (1.0 - is->audio_diff_avg_coef);
				
                if (fabs(avg_diff) >= is->audio_diff_threshold) {
                    wanted_nb_samples = nb_samples + (int)(diff * is->audio_src_freq);
                    min_nb_samples = ((nb_samples * (100 - SAMPLE_CORRECTION_PERCENT_MAX) / 100));
                    max_nb_samples = ((nb_samples * (100 + SAMPLE_CORRECTION_PERCENT_MAX) / 100));
                    wanted_nb_samples = FFMIN(FFMAX(wanted_nb_samples, min_nb_samples), max_nb_samples);
                }
				
#if defined(DEBUG_SYNC) 
                iLog( "diff=%f adiff=%f sample_diff=%d apts=%0.3f vpts=%0.3f %f\n",
					 diff, avg_diff, wanted_nb_samples - nb_samples,
					 is->audio_clock, is->video_clock, is->audio_diff_threshold);
#endif
            }
        } else {
            /* too big difference : may be initial PTS errors, so
			 reset A-V filter */
            is->audio_diff_avg_count = 0;
            is->audio_diff_cum       = 0;
        }
    }
	
    return wanted_nb_samples;
}

/* decode one audio frame and returns its uncompressed size */
static int audio_decode_frame(VideoState *is, double *pts_ptr)
{
    AVPacket *pkt_temp = &is->audio_pkt_temp;
    AVPacket *pkt = &is->audio_pkt;
    AVCodecContext *dec = is->audio_st->codec;
    int len1, len2, data_size, resampled_data_size;
    int64_t dec_channel_layout;
    int got_frame;
    double pts;
    int new_packet = 0;
    int flush_complete = 0;
    int wanted_nb_samples;
	
    for (;;) {
        /* NOTE: the audio packet can contain several frames */
        while (pkt_temp->size > 0 || (!pkt_temp->data && new_packet)) {
            if (!is->frame) {
                if (!(is->frame = avcodec_alloc_frame()))
                    return AVERROR(ENOMEM);
            } else
                avcodec_get_frame_defaults(is->frame);
			
            if (flush_complete)
                break;
            new_packet = 0;
			
            len1 = avcodec_decode_audio4(dec, is->frame, &got_frame, pkt_temp);
            if (len1 < 0) {
                /* if error, we skip the frame */
                pkt_temp->size = 0;
                break;
            }
			
            pkt_temp->data += len1;
            pkt_temp->size -= len1;
            
			
            if (!got_frame) {
                /* stop sending empty packets if the decoder is finished */
                if (!pkt_temp->data && dec->codec->capabilities & CODEC_CAP_DELAY)
                    flush_complete = 1;
                continue;
            }
            data_size = av_samples_get_buffer_size(NULL, dec->channels,
                                                   is->frame->nb_samples,
                                                   dec->sample_fmt, 1);
			
            dec_channel_layout = (dec->channel_layout && dec->channels == av_get_channel_layout_nb_channels(dec->channel_layout)) ? dec->channel_layout : av_get_default_channel_layout(dec->channels);
            wanted_nb_samples = synchronize_audio(is, is->frame->nb_samples);
			
            if (dec->sample_fmt != is->audio_src_fmt ||
                dec_channel_layout != is->audio_src_channel_layout ||
                dec->sample_rate != is->audio_src_freq ||
                (wanted_nb_samples != is->frame->nb_samples && !is->swr_ctx)) {
                if (is->swr_ctx)
                    swr_free(&is->swr_ctx);
                is->swr_ctx = swr_alloc_set_opts(NULL,
                                                 is->audio_tgt_channel_layout, is->audio_tgt_fmt, is->audio_tgt_freq,
                                                 dec_channel_layout,           dec->sample_fmt,   dec->sample_rate,
                                                 0, NULL);
                if (!is->swr_ctx || swr_init(is->swr_ctx) < 0) {
                    eLog("Cannot create sample rate converter for conversion of %d Hz %s %d channels to %d Hz %s %d channels!\n",
						 dec->sample_rate,
						 av_get_sample_fmt_name(dec->sample_fmt),
						 dec->channels,
						 is->audio_tgt_freq,
						 av_get_sample_fmt_name(is->audio_tgt_fmt),
						 is->audio_tgt_channels);
                    break;
                }
                is->audio_src_channel_layout = dec_channel_layout;
                is->audio_src_channels = dec->channels;
                is->audio_src_freq = dec->sample_rate;
                is->audio_src_fmt = dec->sample_fmt;
				iLog("audio out audio_tgt_channel_layout[%lld] fmt[%d] sample_rate[%d] channels[%d]\n",
					 is->audio_tgt_channel_layout,is->audio_tgt_fmt,is->audio_tgt_freq,is->audio_tgt_channels);
				iLog("audio in   audio_tgt_channel_layout[%lld] fmt[%d] sample_rate[%d] channels[%d]\n",
					 dec_channel_layout,dec->sample_fmt,dec->sample_rate,dec->channels);                
				iLog("audio src   audio_src_channel_layout[%lld] fmt[%d] sample_rate[%d] channels[%d]\n",
					 is->audio_src_channel_layout,is->audio_src_fmt,is->audio_src_freq,is->audio_src_channels);
            }
			
            resampled_data_size = data_size;
            if (is->swr_ctx) {
                const uint8_t *in[] = { is->frame->data[0] };
                uint8_t *out[] = {is->audio_buf2};
                if (wanted_nb_samples != is->frame->nb_samples) {
                    if (swr_set_compensation(is->swr_ctx, (wanted_nb_samples - is->frame->nb_samples) * is->audio_tgt_freq / dec->sample_rate,
											 wanted_nb_samples * is->audio_tgt_freq / dec->sample_rate) < 0) {
                        eLog("swr_set_compensation() failed\n");
                        break;
                    }
                }
                len2 = swr_convert(is->swr_ctx, out, sizeof(is->audio_buf2) / is->audio_tgt_channels / av_get_bytes_per_sample(is->audio_tgt_fmt),
								   in, is->frame->nb_samples);
                if (len2 < 0) {
                    eLog("audio_resample() failed\n");
                    break;
                }
                if (len2 == sizeof(is->audio_buf2) / is->audio_tgt_channels / av_get_bytes_per_sample(is->audio_tgt_fmt)) {
                    eLog("warning: audio buffer is probably too small\n");
                    swr_init(is->swr_ctx);
                }
                is->audio_buf = is->audio_buf2;
                resampled_data_size = len2 * is->audio_tgt_channels * av_get_bytes_per_sample(is->audio_tgt_fmt);
            } else {
                is->audio_buf = is->frame->data[0];
            }
			
            /* if no pts, then compute it */
            pts = is->audio_clock;
            *pts_ptr = pts;
            is->audio_clock += (double)data_size / (dec->channels * dec->sample_rate * av_get_bytes_per_sample(dec->sample_fmt));
			//	            iLog("len2[%d] * is->audio_tgt_channels[%d] * av_get_bytes_per_sample(is->audio_tgt_fmt)[%d]\n",len2,
			//	                is->audio_tgt_channels, av_get_bytes_per_sample(is->audio_tgt_fmt));
#if defined(DEBUG_SYNC)
			{
                static double last_clock;
                iLog("audio: delay=%0.3f clock=%0.3f pts=%0.3f\n",
					 is->audio_clock - last_clock,
					 is->audio_clock, pts);
                last_clock = is->audio_clock;
            }
#endif
            return resampled_data_size;
        }
		
        /* free the current packet */
        if (pkt->data)
            av_free_packet(pkt);
        memset(pkt_temp, 0, sizeof(*pkt_temp));
		
        if (is->paused || is->audioq.abort_request) {
            return -1;
        }
		
        /* read next packet */
        if ((new_packet = packet_queue_get(&is->audioq, pkt, 1)) < 0)
            return -1;
		
        if (pkt->data == flush_pkt.data)
            avcodec_flush_buffers(dec);
		
        *pkt_temp = *pkt;
		
        /* if update the audio clock with the pts */
        if (pkt->pts != AV_NOPTS_VALUE) {
            is->audio_clock = av_q2d(is->audio_st->time_base)*pkt->pts;
        }
    }
}


///* prepare a new audio buffer */
//void egl_audio_callback(SLAndroidSimpleBufferQueueItf bq, void *context)
//{
//    VideoState *is = context;
//    int audio_size,len;
//    int bytes_per_sec;
//    int frame_size = av_samples_get_buffer_size(NULL, is->audio_tgt_channels, 1, is->audio_tgt_fmt, 1);
//    double pts;    
//    SLresult result;
//    
//    audio_callback_time = av_gettime();
//	
//    audio_size = audio_decode_frame(is, &pts);
//    if (audio_size < 0) {
//        /* if error, just output silence */
//        is->audio_buf      = is->silence_buf;
//        is->audio_buf_size = sizeof(is->silence_buf) / frame_size * frame_size;
//    } else {
//        if (is->show_mode != SHOW_MODE_VIDEO)
//            update_sample_display(is, (int16_t *)is->audio_buf, audio_size);
//        is->audio_buf_size = audio_size;
//    }
//    len = is->audio_buf_size ;
//    result = (*bq)->Enqueue(bq, (short *)is->audio_buf ,  len );
//    if (result != SL_RESULT_SUCCESS){
//        eLog(" (*bq)->Enqueue(bq, (short *)(is->audio_buf), len1[%d]); %d", len , result);
//    }
//    bytes_per_sec = is->audio_tgt_freq * is->audio_tgt_channels * av_get_bytes_per_sample(is->audio_tgt_fmt);
//	
//    /* Let's assume the audio driver that is used by SDL has two periods. */
//    is->audio_current_pts = is->audio_clock - (double)( len ) / bytes_per_sec; //fixme 2*len or len?  __YUBO__
//    is->audio_current_pts_drift = is->audio_current_pts - audio_callback_time / 1000000.0;
//}





/* open a given stream. Return 0 if OK */
static int stream_component_open(VideoState *is, int stream_index)
{
    AVFormatContext *ic = is->ic;
    AVCodecContext *avctx;
    AVCodec *codec;
    SDL_AudioSpec wanted_spec, spec;
    AVDictionary *opts;
    AVDictionaryEntry *t = NULL;
    int64_t wanted_channel_layout = 0;
    int wanted_nb_channels,i;
    const char *env;
//    SLresult result;
//    SLint32 flags;
//    SLDataFormat_PCM format_pcm;
//    SLDataLocator_AndroidSimpleBufferQueue loc_bufq;
	
    iLog("stream_component_open(0x%x, %d)\n",is, stream_index);
	
    if (stream_index < 0 || stream_index >= ic->nb_streams)
        return -1;
    avctx = ic->streams[stream_index]->codec;
	
    codec = avcodec_find_decoder(avctx->codec_id);
    opts = filter_codec_opts(codec_opts, codec, ic, ic->streams[stream_index]);
	
    switch(avctx->codec_type){
        case AVMEDIA_TYPE_AUDIO   : if(audio_codec_name   ) codec= avcodec_find_decoder_by_name(   audio_codec_name); break;
        case AVMEDIA_TYPE_SUBTITLE: if(subtitle_codec_name) codec= avcodec_find_decoder_by_name(subtitle_codec_name); break;
        case AVMEDIA_TYPE_VIDEO   : if(video_codec_name   ) codec= avcodec_find_decoder_by_name(   video_codec_name); break;
    }
    if (!codec){
        eLog("codec not found \n");
        return -1;
    }
    iLog("codecid[%d], avctx->codec_type[%d]\n",codec->id, avctx->codec_type);
	
    avctx->workaround_bugs   = workaround_bugs;
    avctx->lowres            = lowres;
    if(avctx->lowres > codec->max_lowres){
        wLog("The maximum value for lowres supported by the decoder is %d\n",
			 codec->max_lowres);
        avctx->lowres= codec->max_lowres;
    }
    avctx->idct_algo         = idct;
    avctx->skip_frame        = skip_frame;
    avctx->skip_idct         = skip_idct;
    avctx->skip_loop_filter  = skip_loop_filter;
    avctx->error_concealment = error_concealment;
	
    if(avctx->lowres) avctx->flags |= CODEC_FLAG_EMU_EDGE;
    if (fast)   avctx->flags2 |= CODEC_FLAG2_FAST;
    if(codec->capabilities & CODEC_CAP_DR1)
        avctx->flags |= CODEC_FLAG_EMU_EDGE;
	
	
	wanted_spec.freq = avctx->sample_rate;
	
    if (!av_dict_get(opts, "threads", NULL, 0))
        av_dict_set(&opts, "threads", "auto", 0);
    if (!codec ||
        avcodec_open2(avctx, codec, &opts) < 0)
        return -1;
    if ((t = av_dict_get(opts, "", NULL, AV_DICT_IGNORE_SUFFIX))) {
        eLog("Option %s not found.\n", t->key);
        return AVERROR_OPTION_NOT_FOUND;
    }
	
    /* prepare audio output */
    if (avctx->codec_type == AVMEDIA_TYPE_AUDIO) {
		
		for (i=0; i<NUM_BUFFERS; i++) {
			AudioQueueEnqueueBuffer(AQ.queue, AQ.buffers[i], 0, nil);
		}
		

		AQ.dataFormat.mSampleRate=avctx->sample_rate;//采样频率
		AQ.dataFormat.mFormatID=kAudioFormatLinearPCM;
		AQ.dataFormat.mFormatFlags=kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
		AQ.dataFormat.mBytesPerFrame=4;
		AQ.dataFormat.mBytesPerPacket=4;
		AQ.dataFormat.mFramesPerPacket=1;//wav 通常为1
		AQ.dataFormat.mChannelsPerFrame=2;//通道数
		AQ.dataFormat.mBitsPerChannel=16;//采样的位数
		AQ.dataFormat.mReserved=0;

		
		//创建播放用的音频队列
		iLog("AudioQueueNewOutput ");
		AudioQueueNewOutput(&AQ.dataFormat, audioCallback, is,
							nil, nil, 0, &AQ.queue);
		
		
        
        // configure audio source
//        loc_bufq.locatorType = SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE;
//        loc_bufq.numBuffers = 2;
//        format_pcm.formatType        = SL_DATAFORMAT_PCM;
//        format_pcm.numChannels     = 2;
//        format_pcm.samplesPerSec   = avctx->sample_rate*1000;
//        format_pcm.bitsPerSample    = SL_PCMSAMPLEFORMAT_FIXED_16;
//        format_pcm.containerSize     = 16;
//        format_pcm.channelMask      = SL_SPEAKER_FRONT_LEFT|SL_SPEAKER_FRONT_RIGHT;
//        format_pcm.endianness        = SL_BYTEORDER_LITTLEENDIAN;       
//        SLDataSource audioSrc = {&loc_bufq, &format_pcm};
        
//        // configure audio sink
//        SLDataLocator_OutputMix loc_outmix = {SL_DATALOCATOR_OUTPUTMIX, outputMixObject};
//        SLDataSink audioSnk = {&loc_outmix, NULL};
//        // create audio player
//        const SLInterfaceID ids[3] = {SL_IID_BUFFERQUEUE, SL_IID_EFFECTSEND,
//			/*SL_IID_MUTESOLO,*/ SL_IID_VOLUME};
//        const SLboolean req[3] = {SL_BOOLEAN_TRUE, SL_BOOLEAN_TRUE,
//			/*SL_BOOLEAN_TRUE,*/ SL_BOOLEAN_TRUE};
//        iLog("CreateAudioPlayer \nformatType[%d]\nnumChannels[%d]\nsamplesPerSec[%d]\nbitsPerSample[%d]\ncontainerSize[%d]\nchannelMask[%d]\nendianness[%d]",
//			 format_pcm.formatType,format_pcm.numChannels,format_pcm.samplesPerSec,
//			 format_pcm.bitsPerSample,format_pcm.containerSize,format_pcm.channelMask,
//			 format_pcm.endianness); 
//        result = (*engineEngine)->CreateAudioPlayer(engineEngine, &bqPlayerObject, &audioSrc, &audioSnk,
//													3, ids, req);
//        iLog("CreateAudioPlayer %d",result);
//        // realize the player
//        result = (*bqPlayerObject)->Realize(bqPlayerObject, SL_BOOLEAN_FALSE);
//        iLog("(*bqPlayerObject)->Realize(bqPlayerObject, SL_BOOLEAN_FALSE) %d",result);
//        // get the play interface
//        result = (*bqPlayerObject)->GetInterface(bqPlayerObject, SL_IID_PLAY, &bqPlayerPlay);
//        iLog("(*bqPlayerObject)->GetInterface(bqPlayerObject, SL_IID_PLAY, &bqPlayerPlay); %d",result);
//        // get the buffer queue interface
//        result = (*bqPlayerObject)->GetInterface(bqPlayerObject, SL_IID_BUFFERQUEUE,&bqPlayerBufferQueue);
//        iLog("(*bqPlayerObject)->GetInterface(bqPlayerObject, SL_IID_BUFFERQUEUE ,&bqPlayerBufferQueue) %d",result);
//        // register callback on the buffer queue
//        result = (*bqPlayerBufferQueue)->RegisterCallback(bqPlayerBufferQueue, egl_audio_callback, is);
//        iLog("(*bqPlayerBufferQueue)->RegisterCallback(bqPlayerBufferQueue, egl_audio_callback, is) %d",result);
//        // get the effect send interface
//        result = (*bqPlayerObject)->GetInterface(bqPlayerObject, SL_IID_EFFECTSEND,&bqPlayerEffectSend);
//        iLog("(*bqPlayerObject)->GetInterface(bqPlayerObject, SL_IID_EFFECTSEND,&bqPlayerEffectSend) %d",result);
//        // get the volume interface
//        result = (*bqPlayerObject)->GetInterface(bqPlayerObject, SL_IID_VOLUME, &bqPlayerVolume);
//        iLog("(*bqPlayerObject)->GetInterface(bqPlayerObject, SL_IID_VOLUME, &bqPlayerVolume) %d",result);
		
		
        is->audio_src_fmt = is->audio_tgt_fmt = AV_SAMPLE_FMT_S16;
        is->audio_src_freq = is->audio_tgt_freq = avctx->sample_rate;
        is->audio_src_channel_layout = is->audio_tgt_channel_layout = av_get_default_channel_layout(2);
        is->audio_src_channels = is->audio_tgt_channels = 2;
		iLog("stream_component_open audio out audio_tgt_channel_layout[%lld] fmt[%d] sample_rate[%d] channels[%d]\n",
			 is->audio_tgt_channel_layout,is->audio_tgt_fmt,is->audio_tgt_freq,is->audio_tgt_channels);        
		
    }
	
    ic->streams[stream_index]->discard = AVDISCARD_DEFAULT;
    switch (avctx->codec_type) {
		case AVMEDIA_TYPE_AUDIO:
			is->audio_stream = stream_index;
			is->audio_st = ic->streams[stream_index];
			is->audio_buf_size  = 0;
			is->audio_buf_index = 0;
			
			/* init averaging filter */
			is->audio_diff_avg_coef  = exp(log(0.01) / AUDIO_DIFF_AVG_NB);
			is->audio_diff_avg_count = 0;
			/* since we do not have a precise anough audio fifo fullness,
			 we correct audio sync only if larger than this threshold */
			is->audio_diff_threshold = 2.0 * SDL_AUDIO_BUFFER_SIZE / wanted_spec.freq;
			
			memset(&is->audio_pkt, 0, sizeof(is->audio_pkt));
			packet_queue_init(&is->audioq);
			
			
			int frame_size = av_samples_get_buffer_size(NULL, is->audio_tgt_channels, 1, is->audio_tgt_fmt, 1);
			for (i=0; i<NUM_BUFFERS; i++) {
				AudioQueueAllocateBuffer(AQ.queue, BUFFER_SIZE_BYTES, &AQ.buffers[i]);
				AQ.buffers[i]->mAudioDataByteSize = sizeof(is->silence_buf) / frame_size * frame_size;
				memcpy(AQ.buffers[i]->mAudioData,is->silence_buf,AQ.buffers[i]->mAudioDataByteSize);
				iLog("buffer[%d] data[0x%x] size[%d]\n",i,AQ.buffers[i]->mAudioData,AQ.buffers[i]->mAudioDataByteSize);
				AudioQueueEnqueueBuffer(AQ.queue, AQ.buffers[i], 0, nil);
			}
			
			AudioQueueStart(AQ.queue, nil);
			AQ.mIsRunning = true;
			
			
			
			break;
		case AVMEDIA_TYPE_VIDEO:
			is->video_stream = stream_index;
			is->video_st = ic->streams[stream_index];
			packet_queue_init(&is->videoq);
			is->video_tid = SDL_CreateThread(video_thread, is);
			break;
		case AVMEDIA_TYPE_SUBTITLE:
			is->subtitle_stream = stream_index;
			is->subtitle_st = ic->streams[stream_index];
			packet_queue_init(&is->subtitleq);
			
			//       is->subtitle_tid = SDL_CreateThread(subtitle_thread, is);
			break;
		default:
			break;
    }
    return 0;
}

static void stream_component_close(VideoState *is, int stream_index)
{
    AVFormatContext *ic = is->ic;
    AVCodecContext *avctx;
	
    if (stream_index < 0 || stream_index >= ic->nb_streams)
        return;
    avctx = ic->streams[stream_index]->codec;
	
    switch (avctx->codec_type) {
		case AVMEDIA_TYPE_AUDIO:
			packet_queue_abort(&is->audioq);
			
			//        SDL_CloseAudio();
			
			packet_queue_end(&is->audioq);
			if (is->swr_ctx)
				swr_free(&is->swr_ctx);
			av_free_packet(&is->audio_pkt);
			av_freep(&is->audio_buf1);
			is->audio_buf = NULL;
			av_freep(&is->frame);
			
			if (is->rdft) {
				av_rdft_end(is->rdft);
				av_freep(&is->rdft_data);
				is->rdft = NULL;
				is->rdft_bits = 0;
			}
			break;
		case AVMEDIA_TYPE_VIDEO:
			packet_queue_abort(&is->videoq);
			
			/* note: we also signal this mutex to make sure we deblock the
			 video thread in all cases */
			SDL_LockMutex(is->pictq_mutex);
			SDL_CondSignal(is->pictq_cond);
			SDL_UnlockMutex(is->pictq_mutex);
			
			SDL_WaitThread(is->video_tid, NULL);
			
			packet_queue_end(&is->videoq);
			break;
		case AVMEDIA_TYPE_SUBTITLE:
			packet_queue_abort(&is->subtitleq);
			
			/* note: we also signal this mutex to make sure we deblock the
			 video thread in all cases */
			SDL_LockMutex(is->subpq_mutex);
			is->subtitle_stream_changed = 1;
			
			SDL_CondSignal(is->subpq_cond);
			SDL_UnlockMutex(is->subpq_mutex);
			
			//        SDL_WaitThread(is->subtitle_tid, NULL);
			
			packet_queue_end(&is->subtitleq);
			break;
		default:
			break;
    }
	
    ic->streams[stream_index]->discard = AVDISCARD_ALL;
    avcodec_close(avctx);
    switch (avctx->codec_type) {
		case AVMEDIA_TYPE_AUDIO:
			is->audio_st = NULL;
			is->audio_stream = -1;
			break;
		case AVMEDIA_TYPE_VIDEO:
			is->video_st = NULL;
			is->video_stream = -1;
			break;
		case AVMEDIA_TYPE_SUBTITLE:
			is->subtitle_st = NULL;
			is->subtitle_stream = -1;
			break;
		default:
			break;
    }
}

static int decode_interrupt_cb(void *ctx)
{
    VideoState *is = ctx;
    return is->abort_request;
}

/* this thread gets the stream from the disk or the network */
static int read_thread(void *arg)
{
    VideoState *is = arg;
    AVFormatContext *ic = NULL;
    int err, i, ret;
    int st_index[AVMEDIA_TYPE_NB];
    AVPacket pkt1, *pkt = &pkt1;
    int eof = 0;
    int pkt_in_play_range = 0;
    AVDictionaryEntry *t;
    AVDictionary **opts;
    int orig_nb_streams;
	
    memset(st_index, -1, sizeof(st_index));
    is->video_stream = -1;
    is->audio_stream = -1;
    is->subtitle_stream = -1;
	
    ic = avformat_alloc_context();
    ic->interrupt_callback.callback = decode_interrupt_cb;
    ic->interrupt_callback.opaque = is;
    err = avformat_open_input(&ic, is->filename, is->iformat, &format_opts);
    if (err < 0) {
        print_error(is->filename, err);
        ret = -1;
        goto fail;
    }
    if ((t = av_dict_get(format_opts, "", NULL, AV_DICT_IGNORE_SUFFIX))) {
        eLog("Option %s not found.\n", t->key);
        ret = AVERROR_OPTION_NOT_FOUND;
        goto fail;
    }
    is->ic = ic;
	
    if (genpts)
        ic->flags |= AVFMT_FLAG_GENPTS;
	
    opts = setup_find_stream_info_opts(ic, codec_opts);
    orig_nb_streams = ic->nb_streams;
	
    err = avformat_find_stream_info(ic, opts);
    if (err < 0) {
        eLog( "%s: could not find codec parameters\n", is->filename);
        ret = -1;
        goto fail;
    }
    for (i = 0; i < orig_nb_streams; i++)
        av_dict_free(&opts[i]);
    av_freep(&opts);
	
    if (ic->pb)
        ic->pb->eof_reached = 0; // FIXME hack, ffplay maybe should not use url_feof() to test for the end
	
    if (seek_by_bytes < 0)
        seek_by_bytes = !!(ic->iformat->flags & AVFMT_TS_DISCONT);
	
    /* if seeking requested, we execute it */
    if (start_time != AV_NOPTS_VALUE) {
        int64_t timestamp;
		
        timestamp = start_time;
        /* add the stream start time */
        if (ic->start_time != AV_NOPTS_VALUE)
            timestamp += ic->start_time;
        ret = avformat_seek_file(ic, -1, INT64_MIN, timestamp, INT64_MAX, 0);
        if (ret < 0) {
            eLog( "%s: could not seek to position %0.3f\n",
				 is->filename, (double)timestamp / AV_TIME_BASE);
        }
    }
	
    for (i = 0; i < ic->nb_streams; i++)
        ic->streams[i]->discard = AVDISCARD_ALL;
    if (!video_disable)
        st_index[AVMEDIA_TYPE_VIDEO] =
		av_find_best_stream(ic, AVMEDIA_TYPE_VIDEO,
							wanted_stream[AVMEDIA_TYPE_VIDEO], -1, NULL, 0);
    if (!audio_disable)
        st_index[AVMEDIA_TYPE_AUDIO] =
		av_find_best_stream(ic, AVMEDIA_TYPE_AUDIO,
							wanted_stream[AVMEDIA_TYPE_AUDIO],
							st_index[AVMEDIA_TYPE_VIDEO],
							NULL, 0);
    if (!video_disable)
        st_index[AVMEDIA_TYPE_SUBTITLE] =
		av_find_best_stream(ic, AVMEDIA_TYPE_SUBTITLE,
							wanted_stream[AVMEDIA_TYPE_SUBTITLE],
							(st_index[AVMEDIA_TYPE_AUDIO] >= 0 ?
							 st_index[AVMEDIA_TYPE_AUDIO] :
							 st_index[AVMEDIA_TYPE_VIDEO]),
							NULL, 0);
    if (show_status) {
        av_dump_format(ic, 0, is->filename, 0);
    }
	
    is->show_mode = show_mode;
	
    /* open the streams */
    if (st_index[AVMEDIA_TYPE_AUDIO] >= 0) {
        iLog("read_thread AVMEDIA_TYPE_AUDIO stream_component_open\n");
        stream_component_open(is, st_index[AVMEDIA_TYPE_AUDIO]);
    }
	
    ret = -1;
    if (st_index[AVMEDIA_TYPE_VIDEO] >= 0) {
        iLog("read_thread AVMEDIA_TYPE_VIDEO stream_component_open\n");
        ret = stream_component_open(is, st_index[AVMEDIA_TYPE_VIDEO]);
    }
	//    iLog("SDL_CreateThread(refresh_thread, is)!!!!!!!!!!");
	//    is->refresh_tid = SDL_CreateThread(refresh_thread, is);
    if (is->show_mode == SHOW_MODE_NONE)
        is->show_mode = ret >= 0 ? SHOW_MODE_VIDEO : SHOW_MODE_RDFT;
	
    st_index[AVMEDIA_TYPE_SUBTITLE] = -1;   //__YUBO fixme
    if (st_index[AVMEDIA_TYPE_SUBTITLE] >= 0) {
        stream_component_open(is, st_index[AVMEDIA_TYPE_SUBTITLE]);
    }
	
    if (is->video_stream < 0 && is->audio_stream < 0) {
        eLog( "%s: could not open codecs\n", is->filename);
        ret = -1;
        goto fail;
    }
	
    for (;;) {
        if (is->abort_request)
            break;
        if (is->paused != is->last_paused) {
            is->last_paused = is->paused;
            if (is->paused)
                is->read_pause_return = av_read_pause(ic);
            else
                av_read_play(ic);
        }
#if CONFIG_RTSP_DEMUXER || CONFIG_MMSH_PROTOCOL
        if (is->paused &&
			(!strcmp(ic->iformat->name, "rtsp") ||
			 (ic->pb && !strncmp(input_filename, "mmsh:", 5)))) {
				/* wait 10 ms to avoid trying to get another packet */
				/* XXX: horrible */
				SDL_Delay(10);
				continue;
			}
#endif
        if (is->seek_req) {
            int64_t seek_target = is->seek_pos;
            int64_t seek_min    = is->seek_rel > 0 ? seek_target - is->seek_rel + 2: INT64_MIN;
            int64_t seek_max    = is->seek_rel < 0 ? seek_target - is->seek_rel - 2: INT64_MAX;
			// FIXME the +-2 is due to rounding being not done in the correct direction in generation
			//      of the seek_pos/seek_rel variables
			
            ret = avformat_seek_file(is->ic, -1, seek_min, seek_target, seek_max, is->seek_flags);
            if (ret < 0) {
                eLog( "%s: error while seeking\n", is->ic->filename);
            } else {
                if (is->audio_stream >= 0) {
                    packet_queue_flush(&is->audioq);
                    packet_queue_put(&is->audioq, &flush_pkt);
                }
                if (is->subtitle_stream >= 0) {
                    packet_queue_flush(&is->subtitleq);
                    packet_queue_put(&is->subtitleq, &flush_pkt);
                }
                if (is->video_stream >= 0) {
                    packet_queue_flush(&is->videoq);
                    packet_queue_put(&is->videoq, &flush_pkt);
                }
            }
            is->seek_req = 0;
            eof = 0;
        }
		
        /* if the queue are full, no need to read more */
        if (   is->audioq.size + is->videoq.size + is->subtitleq.size > MAX_QUEUE_SIZE
            || (   (is->audioq   .size  > MIN_AUDIOQ_SIZE || is->audio_stream < 0)
                && (is->videoq   .nb_packets > MIN_FRAMES || is->video_stream < 0)
                && (is->subtitleq.nb_packets > MIN_FRAMES || is->subtitle_stream < 0))) {
				/* wait 10 ms */
				SDL_Delay(10);
				continue;
			}
        if (eof) {
            if (is->video_stream >= 0) {
                av_init_packet(pkt);
                pkt->data = NULL;
                pkt->size = 0;
                pkt->stream_index = is->video_stream;
                packet_queue_put(&is->videoq, pkt);
            }
            if (is->audio_stream >= 0 &&
                is->audio_st->codec->codec->capabilities & CODEC_CAP_DELAY) {
                av_init_packet(pkt);
                pkt->data = NULL;
                pkt->size = 0;
                pkt->stream_index = is->audio_stream;
                packet_queue_put(&is->audioq, pkt);
            }
            SDL_Delay(10);
            if (is->audioq.size + is->videoq.size + is->subtitleq.size == 0) {
                if (loop != 1 && (!loop || --loop)) {
                    stream_seek(is, start_time != AV_NOPTS_VALUE ? start_time : 0, 0, 0);
                } else if (autoexit) {
                    ret = AVERROR_EOF;
                    goto fail;
                }
            }
            eof=0;
            continue;
        }
        ret = av_read_frame(ic, pkt);
        if (ret < 0) {
            if (ret == AVERROR_EOF || url_feof(ic->pb))
                eof = 1;
            if (ic->pb && ic->pb->error)
                break;
            SDL_Delay(100); /* wait for user event */
            continue;
        }
        /* check if packet is in play range specified by user, then queue, otherwise discard */
        pkt_in_play_range = duration == AV_NOPTS_VALUE ||
		(pkt->pts - ic->streams[pkt->stream_index]->start_time) *
		av_q2d(ic->streams[pkt->stream_index]->time_base) -
		(double)(start_time != AV_NOPTS_VALUE ? start_time : 0) / 1000000
		<= ((double)duration / 1000000);
        if (pkt->stream_index == is->audio_stream && pkt_in_play_range) {
            packet_queue_put(&is->audioq, pkt);
        } else if (pkt->stream_index == is->video_stream && pkt_in_play_range) {
            packet_queue_put(&is->videoq, pkt);
        } else if (pkt->stream_index == is->subtitle_stream && pkt_in_play_range) {
            packet_queue_put(&is->subtitleq, pkt);
        } else {
            av_free_packet(pkt);
        }
    }
    /* wait until the end */
    while (!is->abort_request) {
        SDL_Delay(100);
    }
	
    ret = 0;
fail:
    /* close each stream */
    if (is->audio_stream >= 0)
        stream_component_close(is, is->audio_stream);
    if (is->video_stream >= 0)
        stream_component_close(is, is->video_stream);
    if (is->subtitle_stream >= 0)
        stream_component_close(is, is->subtitle_stream);
    if (is->ic) {
        avformat_close_input(&is->ic);
    }
	
    if (ret != 0) {
        SDL_Event event;
		
        event.type = FF_QUIT_EVENT;
        event.user.data1 = is;
        SDL_PushEvent(&event);
    }
    return 0;
}

static VideoState *stream_open(const char *filename, AVInputFormat *iformat, VideoState *is)
{
	
    av_strlcpy(is->filename, filename, sizeof(is->filename));
    is->iformat = iformat;
    is->ytop    = 0;
    is->xleft   = 0;
	
    /* start video display */
    is->pictq_mutex = SDL_CreateMutex();
    is->pictq_cond  = SDL_CreateCond();
	
	//	    is->surface_mutex = SDL_CreateMutex();
	//	    is->surface_cond  = SDL_CreateCond();
	//	    iLog("is->surface_cond  = SDL_CreateCond() done");
	//	    is->surface2_cond  = SDL_CreateCond();
	
    is->subpq_mutex = SDL_CreateMutex();
    is->subpq_cond  = SDL_CreateCond();
	
    is->av_sync_type = av_sync_type;
    is->read_tid  = SDL_CreateThread(read_thread, is);
    if (!is->read_tid) {
        av_free(is);
        return NULL;
    }
    return is;
}

static void stream_cycle_channel(VideoState *is, int codec_type)
{
    AVFormatContext *ic = is->ic;
    int start_index, stream_index;
    AVStream *st;
	
    if (codec_type == AVMEDIA_TYPE_VIDEO)
        start_index = is->video_stream;
    else if (codec_type == AVMEDIA_TYPE_AUDIO)
        start_index = is->audio_stream;
    else
        start_index = is->subtitle_stream;
    if (start_index < (codec_type == AVMEDIA_TYPE_SUBTITLE ? -1 : 0))
        return;
    stream_index = start_index;
    for (;;) {
        if (++stream_index >= is->ic->nb_streams)
        {
            if (codec_type == AVMEDIA_TYPE_SUBTITLE)
            {
                stream_index = -1;
                goto the_end;
            } else
                stream_index = 0;
        }
        if (stream_index == start_index)
            return;
        st = ic->streams[stream_index];
        if (st->codec->codec_type == codec_type) {
            /* check that parameters are OK */
            switch (codec_type) {
				case AVMEDIA_TYPE_AUDIO:
					if (st->codec->sample_rate != 0 &&
						st->codec->channels != 0)
						goto the_end;
					break;
				case AVMEDIA_TYPE_VIDEO:
				case AVMEDIA_TYPE_SUBTITLE:
					goto the_end;
				default:
					break;
            }
        }
    }
the_end:
    stream_component_close(is, start_index);
    stream_component_open(is, stream_index);
}


static void toggle_full_screen(VideoState *is)
{
    av_unused int i;
    is_full_screen = !is_full_screen;
#if defined(__APPLE__) && SDL_VERSION_ATLEAST(1, 2, 14)
    /* OS X needs to reallocate the SDL overlays */
    for (i = 0; i < VIDEO_PICTURE_QUEUE_SIZE; i++) {
        is->pictq[i].reallocate = 1;
    }
#endif
    video_open(is, 1);
}

static void toggle_pause(VideoState *is)
{
    stream_toggle_pause(is);
    is->step = 0;
}

static void step_to_next_frame(VideoState *is)
{
    /* if the stream is paused unpause it, then step */
    if (is->paused)
        stream_toggle_pause(is);
    is->step = 1;
}



/* handle an event sent by the GUI */
static int event_loop(void *is)
{
    SDL_Event event;
    VideoState *cur_stream = is;
    double incr, pos, frac;
	
    for (;;) {
        double x;
        SDL_WaitEvent(&event);
        switch (event.type) {
			case SDL_KEYDOWN:
				if (exit_on_keydown) {
					do_exit(cur_stream);
					break;
				}
				switch (event.key.keysym.sym) {
					case SDLK_ESCAPE:
					case SDLK_q:
						do_exit(cur_stream);
						break;
					case SDLK_f:
						toggle_full_screen(cur_stream);
						break;
					case SDLK_p:
					case SDLK_SPACE:
						toggle_pause(cur_stream);
						break;
					case SDLK_s: // S: Step to next frame
						step_to_next_frame(cur_stream);
						break;
					case SDLK_a:
						stream_cycle_channel(cur_stream, AVMEDIA_TYPE_AUDIO);
						break;
					case SDLK_v:
						stream_cycle_channel(cur_stream, AVMEDIA_TYPE_VIDEO);
						break;
					case SDLK_t:
						stream_cycle_channel(cur_stream, AVMEDIA_TYPE_SUBTITLE);
						break;
					case SDLK_w:
						//                toggle_audio_display(cur_stream);
						break;
					case SDLK_PAGEUP:
						incr = 600.0;
						goto do_seek;
					case SDLK_PAGEDOWN:
						incr = -600.0;
						goto do_seek;
					case SDLK_LEFT:
						incr = -10.0;
						goto do_seek;
					case SDLK_RIGHT:
						incr = 10.0;
						goto do_seek;
					case SDLK_UP:
						incr = 60.0;
						goto do_seek;
					case SDLK_DOWN:
						incr = -60.0;
					do_seek:
						if (seek_by_bytes) {
							if (cur_stream->video_stream >= 0 && cur_stream->video_current_pos >= 0) {
								pos = cur_stream->video_current_pos;
							} else if (cur_stream->audio_stream >= 0 && cur_stream->audio_pkt.pos >= 0) {
								pos = cur_stream->audio_pkt.pos;
							} else
								pos = avio_seek(cur_stream->ic->pb, 0, SEEK_CUR);
							if (cur_stream->ic->bit_rate)
								incr *= cur_stream->ic->bit_rate / 8.0;
							else
								incr *= 180000.0;
							pos += incr;
							stream_seek(cur_stream, pos, incr, 1);
						} else {
							pos = get_master_clock(cur_stream);
							pos += incr;
							stream_seek(cur_stream, (int64_t)(pos * AV_TIME_BASE), (int64_t)(incr * AV_TIME_BASE), 0);
						}
						break;
					default:
						break;
				}
				break;
			case SDL_MOUSEBUTTONDOWN:
				if (exit_on_mousedown) {
					do_exit(cur_stream);
					break;
				}
			case SDL_MOUSEMOTION:
				if (event.type == SDL_MOUSEBUTTONDOWN) {
					x = event.button.x;
				} else {
					if (event.motion.state != SDL_PRESSED)
						break;
					x = event.motion.x;
				}
                if (seek_by_bytes || cur_stream->ic->duration <= 0) {
                    uint64_t size =  avio_size(cur_stream->ic->pb);
                    stream_seek(cur_stream, size*x/cur_stream->width, 0, 1);
                } else {
                    int64_t ts;
                    int ns, hh, mm, ss;
                    int tns, thh, tmm, tss;
                    tns  = cur_stream->ic->duration / 1000000LL;
                    thh  = tns / 3600;
                    tmm  = (tns % 3600) / 60;
                    tss  = (tns % 60);
                    frac = x / cur_stream->width;
                    ns   = frac * tns;
                    hh   = ns / 3600;
                    mm   = (ns % 3600) / 60;
                    ss   = (ns % 60);
                    fprintf(stderr, "Seek to %2.0f%% (%2d:%02d:%02d) of total duration (%2d:%02d:%02d)       \n", frac*100,
                            hh, mm, ss, thh, tmm, tss);
                    ts = frac * cur_stream->ic->duration;
                    if (cur_stream->ic->start_time != AV_NOPTS_VALUE)
                        ts += cur_stream->ic->start_time;
                    stream_seek(cur_stream, ts, 0, 0);
                }
				break;
			case SDL_VIDEORESIZE:
                screen = EGL_SetVideoMode(event.resize.w, event.resize.h, 0,
                                          SDL_HWSURFACE|SDL_RESIZABLE|SDL_ASYNCBLIT|SDL_HWACCEL, cur_stream);
                screen_width  = cur_stream->width  = event.resize.w;
                screen_height = cur_stream->height = event.resize.h;
				break;
			case SDL_QUIT:
			case FF_QUIT_EVENT:
				do_exit(cur_stream);
				break;
			case FF_ALLOC_EVENT:
				video_open(event.user.data1, 0);
				alloc_picture(event.user.data1);
				break;
			case FF_REFRESH_EVENT:
				//	            video_refresh(event.user.data1);
				//	            cur_stream->refresh = 0;
				break;
			default:
				break;
        }
    }
    return 0;
}


static int opt_frame_size(const char *opt, const char *arg)
{
    wLog("Option -s is deprecated, use -video_size.\n");
    return opt_default("video_size", arg);
}

static int opt_width(const char *opt, const char *arg)
{
    screen_width = parse_number_or_die(opt, arg, OPT_INT64, 1, INT_MAX);
    return 0;
}

static int opt_height(const char *opt, const char *arg)
{
    screen_height = parse_number_or_die(opt, arg, OPT_INT64, 1, INT_MAX);
    return 0;
}

static int opt_format(const char *opt, const char *arg)
{
    file_iformat = av_find_input_format(arg);
    if (!file_iformat) {
        eLog("Unknown input format: %s\n", arg);
        return AVERROR(EINVAL);
    }
    return 0;
}

static int opt_frame_pix_fmt(const char *opt, const char *arg)
{
    wLog("Option -pix_fmt is deprecated, use -pixel_format.\n");
    return opt_default("pixel_format", arg);
}

static int opt_sync(const char *opt, const char *arg)
{
    if (!strcmp(arg, "audio"))
        av_sync_type = AV_SYNC_AUDIO_MASTER;
    else if (!strcmp(arg, "video"))
        av_sync_type = AV_SYNC_VIDEO_MASTER;
    else if (!strcmp(arg, "ext"))
        av_sync_type = AV_SYNC_EXTERNAL_CLOCK;
    else {
        eLog("Unknown value for %s: %s\n", opt, arg);
        exit(1);
    }
    return 0;
}

static int opt_seek(const char *opt, const char *arg)
{
    start_time = parse_time_or_die(opt, arg, 1);
    return 0;
}

static int opt_duration(const char *opt, const char *arg)
{
    duration = parse_time_or_die(opt, arg, 1);
    return 0;
}

static int opt_show_mode(const char *opt, const char *arg)
{
    show_mode = !strcmp(arg, "video") ? SHOW_MODE_VIDEO :
	!strcmp(arg, "waves") ? SHOW_MODE_WAVES :
	!strcmp(arg, "rdft" ) ? SHOW_MODE_RDFT  :
	parse_number_or_die(opt, arg, OPT_INT, 0, SHOW_MODE_NB-1);
    return 0;
}

static void opt_input_file(void *optctx, const char *filename)
{
    if (input_filename) {
        eLog("Argument '%s' provided as input filename, but '%s' was already specified.\n",
			 filename, input_filename);
        exit_program(1);
    }
    if (!strcmp(filename, "-"))
        filename = "pipe:";
    input_filename = filename;
}

static int opt_codec(void *o, const char *opt, const char *arg)
{
    switch(opt[strlen(opt)-1]){
		case 'a' :    audio_codec_name = arg; break;
		case 's' : subtitle_codec_name = arg; break;
		case 'v' :    video_codec_name = arg; break;
    }
    return 0;
}

static int dummy;

static const OptionDef options[] = {
    { "L", OPT_EXIT, {(void*)opt_license}, "show license" },
    { "h", OPT_EXIT, {(void*)opt_help}, "show help" },
    { "?", OPT_EXIT, {(void*)opt_help}, "show help" },
    { "help", OPT_EXIT, {(void*)opt_help}, "show help" },
    { "-help", OPT_EXIT, {(void*)opt_help}, "show help" },
    { "version", OPT_EXIT, {(void*)opt_version}, "show version" },
    { "formats"  , OPT_EXIT, {(void*)opt_formats  }, "show available formats" },
    { "codecs"   , OPT_EXIT, {(void*)opt_codecs   }, "show available codecs" },
    { "bsfs"     , OPT_EXIT, {(void*)opt_bsfs     }, "show available bit stream filters" },
    { "protocols", OPT_EXIT, {(void*)opt_protocols}, "show available protocols" },
    { "filters",   OPT_EXIT, {(void*)opt_filters  }, "show available filters" },
    { "sample_fmts", OPT_EXIT, {.func_arg = show_sample_fmts }, "show available audio sample formats" },
    { "loglevel", HAS_ARG, {(void*)opt_loglevel}, "set libav* logging level", "loglevel" },
    { "v", HAS_ARG, {(void*)opt_loglevel}, "set libav* logging level", "loglevel" },
    { "debug", HAS_ARG, {(void*)opt_codec_debug}, "set debug flags", "flags" },
    { "report", 0, {(void*)opt_report}, "generate a report" },
    { "max_alloc", HAS_ARG, {(void*)opt_max_alloc}, "set maximum size of a single allocated block", "bytes" },
    { "x", HAS_ARG, { (void*)opt_width }, "force displayed width", "width" },
    { "y", HAS_ARG, { (void*)opt_height }, "force displayed height", "height" },
    { "s", HAS_ARG | OPT_VIDEO, { (void*)opt_frame_size }, "set frame size (WxH or abbreviation)", "size" },
    { "fs", OPT_BOOL, { (void*)&is_full_screen }, "force full screen" },
    { "an", OPT_BOOL, { (void*)&audio_disable }, "disable audio" },
    { "vn", OPT_BOOL, { (void*)&video_disable }, "disable video" },
    { "ast", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&wanted_stream[AVMEDIA_TYPE_AUDIO] }, "select desired audio stream", "stream_number" },
    { "vst", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&wanted_stream[AVMEDIA_TYPE_VIDEO] }, "select desired video stream", "stream_number" },
    { "sst", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&wanted_stream[AVMEDIA_TYPE_SUBTITLE] }, "select desired subtitle stream", "stream_number" },
    { "ss", HAS_ARG, { (void*)&opt_seek }, "seek to a given position in seconds", "pos" },
    { "t", HAS_ARG, { (void*)&opt_duration }, "play  \"duration\" seconds of audio/video", "duration" },
    { "bytes", OPT_INT | HAS_ARG, { (void*)&seek_by_bytes }, "seek by bytes 0=off 1=on -1=auto", "val" },
    { "nodisp", OPT_BOOL, { (void*)&display_disable }, "disable graphical display" },
    { "f", HAS_ARG, { (void*)opt_format }, "force format", "fmt" },
    { "pix_fmt", HAS_ARG | OPT_EXPERT | OPT_VIDEO, { (void*)opt_frame_pix_fmt }, "set pixel format", "format" },
    { "stats", OPT_BOOL | OPT_EXPERT, { (void*)&show_status }, "show status", "" },
    { "bug", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&workaround_bugs }, "workaround bugs", "" },
    { "fast", OPT_BOOL | OPT_EXPERT, { (void*)&fast }, "non spec compliant optimizations", "" },
    { "genpts", OPT_BOOL | OPT_EXPERT, { (void*)&genpts }, "generate pts", "" },
    { "drp", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&decoder_reorder_pts }, "let decoder reorder pts 0=off 1=on -1=auto", ""},
    { "lowres", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&lowres }, "", "" },
    { "skiploop", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&skip_loop_filter }, "", "" },
    { "skipframe", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&skip_frame }, "", "" },
    { "skipidct", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&skip_idct }, "", "" },
    { "idct", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&idct }, "set idct algo",  "algo" },
    { "ec", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&error_concealment }, "set error concealment options",  "bit_mask" },
    { "sync", HAS_ARG | OPT_EXPERT, { (void*)opt_sync }, "set audio-video sync. type (type=audio/video/ext)", "type" },
    { "autoexit", OPT_BOOL | OPT_EXPERT, { (void*)&autoexit }, "exit at the end", "" },
    { "exitonkeydown", OPT_BOOL | OPT_EXPERT, { (void*)&exit_on_keydown }, "exit on key down", "" },
    { "exitonmousedown", OPT_BOOL | OPT_EXPERT, { (void*)&exit_on_mousedown }, "exit on mouse down", "" },
    { "loop", OPT_INT | HAS_ARG | OPT_EXPERT, { (void*)&loop }, "set number of times the playback shall be looped", "loop count" },
    { "framedrop", OPT_BOOL | OPT_EXPERT, { (void*)&framedrop }, "drop frames when cpu is too slow", "" },
    { "window_title", OPT_STRING | HAS_ARG, { (void*)&window_title }, "set window title", "window title" },
    { "rdftspeed", OPT_INT | HAS_ARG| OPT_AUDIO | OPT_EXPERT, { (void*)&rdftspeed }, "rdft speed", "msecs" },
    { "showmode", HAS_ARG, {(void*)opt_show_mode}, "select show mode (0 = video, 1 = waves, 2 = RDFT)", "mode" },
    { "default", HAS_ARG | OPT_AUDIO | OPT_VIDEO | OPT_EXPERT, { (void*)opt_default }, "generic catch all option", "" },
    { "i", OPT_BOOL, {(void *)&dummy}, "read specified file", "input_file"},
    { "codec", HAS_ARG | OPT_FUNC2, {(void*)opt_codec}, "force decoder", "decoder" },
    { NULL, },
};

static void show_usage(void)
{
    iLog("Simple media player\n");
    iLog("usage: %s [options] input_file\n", program_name);
}

static int opt_help(const char *opt, const char *arg)
{
    av_log_set_callback(log_callback_help);
    show_usage();
    show_help_options(options, "Main options:\n",
                      OPT_EXPERT, 0);
    show_help_options(options, "\nAdvanced options:\n",
                      OPT_EXPERT, OPT_EXPERT);
    printf("\n");
    show_help_children(avcodec_get_class(), AV_OPT_FLAG_DECODING_PARAM);
    show_help_children(avformat_get_class(), AV_OPT_FLAG_DECODING_PARAM);
    show_help_children(sws_get_class(), AV_OPT_FLAG_ENCODING_PARAM);
    printf("\nWhile playing:\n"
           "q, ESC              quit\n"
           "f                   toggle full screen\n"
           "p, SPC              pause\n"
           "a                   cycle audio channel\n"
           "v                   cycle video channel\n"
           "t                   cycle subtitle channel\n"
           "w                   show audio waves\n"
           "s                   activate frame-step mode\n"
           "left/right          seek backward/forward 10 seconds\n"
           "down/up             seek backward/forward 1 minute\n"
           "page down/page up   seek backward/forward 10 minutes\n"
           "mouse click         seek to percentage in file corresponding to fraction of width\n"
           );
    return 0;
}









static int lockmgr(void **mtx, enum AVLockOp op)
{
	switch(op) {
		case AV_LOCK_CREATE:
			*mtx = SDL_CreateMutex();
			if(!*mtx)
				return 1;
			return 0;
		case AV_LOCK_OBTAIN:
			return !!SDL_LockMutex(*mtx);
		case AV_LOCK_RELEASE:
			return !!SDL_UnlockMutex(*mtx);
		case AV_LOCK_DESTROY:
			SDL_DestroyMutex(*mtx);
			return 0;
	}
	return 1;
}




- (int)nativeRender
{
//	iLog("nativeRender\n");
	while(!gis->refresh){
		if(!gis->abort_request)
			[self video_refresh];
		usleep(gis->audio_st && gis->show_mode != SHOW_MODE_VIDEO ? rdftspeed*1000 : 5000);
	};
	gis->refresh = 0;
}


-(void) nativeResize
{
	VideoState *is = gis;
	int w = glView->backingWidth;
	int h = glView->backingHeight;
	
    iLog("controller nativeResize w[%d] [h%d]\n",w,h);

    screen = EGL_SetVideoMode(w, h, 0,
                              SDL_HWSURFACE|SDL_RESIZABLE|SDL_ASYNCBLIT|SDL_HWACCEL, is);
    screen_width  = is->width = w;
    screen_height = is->height = h;
    iLog("config_changed width[%d] height[%d]\n",w,h);
	
	int rect[4] = {0,is->video_st->codec->height,is->video_st->codec->width,-is->video_st->codec->height};
	glTexParameteriv(GL_TEXTURE_2D, GL_TEXTURE_CROP_RECT_OES, rect);
	
    return 0;    
}






int nativeNotify(VideoState *is,int msgid)
{
    VideoState *cur_stream = is;
    double incr, pos, frac;    
    switch(msgid) {
        case NOTIFY_TOUCH_LEFT:
			incr = -10.0;
			goto do_seek_notify;
            break;
        case NOTIFY_TOUCH_RIGHT:
			incr = 10.0;
			goto do_seek_notify;
            break;
        case NOTIFY_TOUCH_UP:
            break;
        case NOTIFY_TOUCH_DOWN:
            iLog("nativePause\n");
            toggle_pause(is);
            break;
        do_seek_notify:
			if (seek_by_bytes) {
				if (cur_stream->video_stream >= 0 && cur_stream->video_current_pos >= 0) {
					pos = cur_stream->video_current_pos;
				} else if (cur_stream->audio_stream >= 0 && cur_stream->audio_pkt.pos >= 0) {
					pos = cur_stream->audio_pkt.pos;
				} else
					pos = avio_seek(cur_stream->ic->pb, 0, SEEK_CUR);
				if (cur_stream->ic->bit_rate)
					incr *= cur_stream->ic->bit_rate / 8.0;
				else
					incr *= 180000.0;
				pos += incr;
				stream_seek(cur_stream, pos, incr, 1);
			} else {
				pos = get_master_clock(cur_stream);
				pos += incr;
				stream_seek(cur_stream, (int64_t)(pos * AV_TIME_BASE), (int64_t)(incr * AV_TIME_BASE), 0);
			}
			break;
		default:
			break;
			
			
    }
	return 0;
	
}

int nativeDone(VideoState *is)
{
    do_exit(is);
}


VideoState *nativeInit(int argc, char *arg)
{
	
//    EGLint w, h, dummy, format,numConfigs;
//    EGLConfig config;
//    EGLSurface surface;
//    EGLContext context;
    VideoState *is;
    char *argv[16];
	
    int iret,i;
    char *p;
	
    strcpy(input_argv, arg);
    p = input_argv;
    for(i = 0 ; i < argc; i++){
        LTrim(p);
        argv[i] = p;
        p = strchr(argv[i], ' ');
        if(p)
            *p++ = '\0';
    }    
	
	
    
    is = av_mallocz(sizeof(VideoState));
    if (!is) {
        eLog("Failed to initialize VideoState!\n");
        exit(1);
    } 
	
    
	
    /* register all codecs, demux and protocols */
    avcodec_register_all();
    av_register_all();
    avformat_network_init();
    av_log_set_callback(av_log_callback);
    init_opts();
    //audio_init();
	
	
    parse_options(NULL, argc, argv, options, opt_input_file);
	
    if (!input_filename) {
        eLog("An input file must be specified\n");
        eLog("Use -h to get full help or, even better, run 'man %s'\n", program_name);
        exit(1);
    }
	
	
    if (display_disable) {
        video_disable = 1;
    }
	
    if (SDL_Init (SDL_INIT_TIMER | SDL_INIT_EVENTTHREAD)) {
        eLog("Could not initialize SDL \n");
        eLog("(Did you set the DISPLAY variable?)\n");
        exit(1);
    }
	
	
	
    iLog("input_filename '%s'\n", input_filename);
	
    SDL_EventState(SDL_USEREVENT, SDL_IGNORE);
	
	
    if (av_lockmgr_register(lockmgr)) {
        eLog("Could not initialize lock manager!\n");
        do_exit(NULL);
    }
	
    av_init_packet(&flush_pkt);
    flush_pkt.data = "FLUSH";
	
    return is;
}
//END_INCLUDE(all)





- (void)nativeStart
{
	VideoState *is = gis;
    is->width = glView->backingWidth; 
    is->height = glView->backingHeight;
    char filename[128];
    iLog("nativeStart  input_filename0 '%s' \n", input_filename);
	decode_filename(filename,input_filename);
	iLog("nativeStart  input_filename1 '%s' \n", filename);
    is = stream_open(filename, file_iformat,is);
    if (!is) {
        eLog("Failed to initialize VideoState!\n");
        do_exit(NULL);
    }
    while(is->video_st == NULL){
        SDL_Delay(10);
    }
    [self nativeResize]; 
	
    is->loop_tid = SDL_CreateThread(event_loop,is);
}

int nativeSeek(VideoState *is,int seek){
	int64_t ts;
	int ns, hh, mm, ss;
	int tns, thh, tmm, tss;
	double frac;
	tns  = is->ic->duration / 1000000LL;
	thh  = tns / 3600;
	tmm  = (tns % 3600) / 60;
	tss  = (tns % 60);
	
	ns   = seek / 1000;
	hh   = ns / 3600;
	mm   = (ns % 3600) / 60;
	ss   = (ns % 60);
	iLog("Seek to [%d]  (%2d:%02d:%02d) of total duration (%2d:%02d:%02d)       \n",
		 seek, hh, mm, ss, thh, tmm, tss);
	ts = seek * 1000LL;
	if (is->ic->start_time != AV_NOPTS_VALUE)
		ts += is->ic->start_time;
	stream_seek(is, ts, 0, 0);    
}

int nativeGetClock(VideoState *is){
    return (int)(get_master_clock(is) * 1000);
}



int RemotePlayerMsg(int msgid, VideoState *is){
    switch (msgid){
        case SYNC_PLAYER_CLOCK:
            break;
        default:
            break;
            
    }
}



#pragma mark -
#pragma mark sys

// The designated initializer. Override to perform setup that is required before the view is loaded.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
	NSLog(@"stormplayViewController initWithNibName");
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
		self.view=self.uiview;
		
    }
    return self;
}



- (void) sysncPlayerClock
{
	int time = nativeGetClock(gis);
	iLog("sysncPlayerClock [%d]\n",time);
	SeekSlider.value = (float)time;
	[self printTime:time];
}

// set the mixers values according to the UI state
- (void)setUIDefaults
{
    [self setOutputVolume:VolumeSlider];
    VolumeSlider.continuous = YES;
	
	SeekSlider.maximumValue = gis->ic->duration / 1000LL;
	SeekSlider.continuous = NO;
    
}


- (int) donePlay
{
	//	return nativeDone(is);
}

// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
	// return (interfaceOrientation == UIInterfaceOrientationPortrait);
	NSLog(@"stormplayViewController shouldAutorotateToInterfaceOrientation");
	self.view=self.uiview;
	return YES;
    
}


- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc that aren't in use.
}

- (void)viewDidUnload {
	// Release any retained subviews of the main view.
	self.uiview = nil;
}


- (void)dealloc
{
	[glView release];
	[playaudio release];
	[VolumeSlider release];
	[super dealloc];
}



#pragma mark -
#pragma mark video/audio

- (void) video_image_display
{
	//iLog("video_image_display \n");
    VideoPicture *vp;
    AVPicture pict;
    float aspect_ratio;
    int width, height, x, y;
    int i;
    SDL_Rect rect;
    
	
    vp = &gis->pictq[gis->pictq_rindex];
    if (vp->bmp) {
        /* XXX: use variable in the frame */
        if (gis->video_st->sample_aspect_ratio.num)
            aspect_ratio = av_q2d(gis->video_st->sample_aspect_ratio);
        else if (gis->video_st->codec->sample_aspect_ratio.num)
            aspect_ratio = av_q2d(gis->video_st->codec->sample_aspect_ratio);
        else
            aspect_ratio = 0;
        if (aspect_ratio <= 0.0)
            aspect_ratio = 1.0;
        aspect_ratio *= (float)vp->width / (float)vp->height;
		
		
        /* XXX: we suppose the screen has a 1.0 pixel ratio */
		
        height = gis->height;
        width = ((int)rint(height * aspect_ratio)) & ~1;
        if (width > gis->width) {
            width = gis->width;
            height = ((int)rint(width / aspect_ratio)) & ~1;
        }
        x = (gis->width - width) / 2;
        y = (gis->height - height) / 2;
        gis->no_background = 0;
        rect.x = gis->xleft + x;
        rect.y = gis->ytop  + y;
        rect.w = FFMAX(width,  1);
        rect.h = FFMAX(height, 1);
		
		
		[EAGLContext setCurrentContext:glView->context];
		
		glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
#ifdef GL_565       
        glTexImage2D(GL_TEXTURE_2D,		/* target */
					 0,			/* level */
					 GL_RGB,			/* internal format */
					 vp->bmp->w,		/* width */
					 vp->bmp->h,		/* height */
					 0,			/* border */
					 GL_RGB,			/* format */
					 GL_UNSIGNED_SHORT_5_6_5,/* type */
					 vp->bmp->pict.data[0]);		/* pixels */
#else
		glTexImage2D(GL_TEXTURE_2D,		/* target */
					 0,			/* level */
					 GL_RGB,			/* internal format */
					 vp->bmp->w,		/* width */
					 vp->bmp->h,		/* height */
					 0,			/* border */
					 GL_RGB,			/* format */
					 GL_UNSIGNED_BYTE,/* type */
					 vp->bmp->pict.data[0]);		/* pixels */
#endif	
        glDrawTexiOES(rect.x , rect.y, 0, rect.w, rect.h);
        //glDrawTexiOES(0 , 0, 0, vp->bmp->w, vp->bmp->h);
        
		//	        iLog("EGL_DisplayRGBOverlay glDrawTexiOES x[%d] y[%d] w[%d] h[%d]",
		//	            rect.x , rect.y, rect.w, rect.h);
        check_gl_error("video_image_display");
        gis->refresh = 1;
		glBindRenderbufferOES(GL_RENDERBUFFER_OES, glView->viewRenderbuffer);
		[glView->context presentRenderbuffer:GL_RENDERBUFFER_OES];		
		
    }
}


- (void)drawFrame 
{
	//NSLog(@"EAGLView drawView");
    
    [EAGLContext setCurrentContext:glView->context];
    
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, glView->viewFramebuffer);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	
	glTexImage2D(GL_TEXTURE_2D,
				 0,
				 GL_RGB,
				 352,
				 288,
				 0,
				 GL_RGB,
				 GL_UNSIGNED_SHORT_5_6_5,
				 pic_data);
	check_gl_error("glTexImage2D");
	glDrawTexiOES(0, 0, 0, glView->backingWidth, glView->backingHeight);
	check_gl_error("glDrawTexiOES");
	
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, glView->viewRenderbuffer);
    [glView->context presentRenderbuffer:GL_RENDERBUFFER_OES];
}

- (void) startVideo
{
	NSLog(@"stormplayViewController startVideo");
	
	if (!glView->animating)
	{	
		glView->displayLink = [NSClassFromString(@"CADisplayLink") displayLinkWithTarget:self selector:@selector(nativeRender)];
		[glView->displayLink setFrameInterval:glView->animationFrameInterval];
		[glView->displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
		glView->animating = TRUE;
	}
}

- (void)stopVideo
{
	NSLog(@"stormplayViewController stopVideo");
	if (glView->animating)
	{

		[glView->displayLink invalidate];
		glView->displayLink = nil;
		glView->animating = FALSE;
	}
}


static void audioCallback(void *inUserData,AudioQueueRef inAQ,
                           AudioQueueBufferRef buffer){
	//iLog("audioCallback\n");

	
	
    VideoState *is = inUserData;
    int audio_size,len;
    int bytes_per_sec;
    int frame_size = av_samples_get_buffer_size(NULL, is->audio_tgt_channels, 1, is->audio_tgt_fmt, 1);
    double pts;    
    
    audio_callback_time = av_gettime();
	
	
    audio_size = audio_decode_frame(is, &pts);
    if (audio_size < 0) {
        /* if error, just output silence */
        is->audio_buf      = is->silence_buf;
        is->audio_buf_size = sizeof(is->silence_buf) / frame_size * frame_size;
    } else {
        if (is->show_mode != SHOW_MODE_VIDEO)
            update_sample_display(is, (int16_t *)is->audio_buf, audio_size);
        is->audio_buf_size = audio_size;
    }
	
	len = is->audio_buf_size;
	buffer->mAudioDataByteSize=is->audio_buf_size; //len = is->audio_buf_size ;
	memcpy(buffer->mAudioData, is->audio_buf, is->audio_buf_size);
	AudioQueueEnqueueBuffer(inAQ, buffer, 0, nil);
	

    bytes_per_sec = is->audio_tgt_freq * is->audio_tgt_channels * av_get_bytes_per_sample(is->audio_tgt_fmt);
	
    /* Let's assume the audio driver that is used by SDL has two periods. */
    is->audio_current_pts = is->audio_clock - (double)( len ) / bytes_per_sec; //fixme 2*len or len?  __YUBO__
    is->audio_current_pts_drift = is->audio_current_pts - audio_callback_time / 1000000.0;
	
	
}

- (void) startAudio
{
	NSLog(@"stormplayViewController startAudio");
    AudioQueueStart(AQ.queue, nil);
	AQ.mIsRunning = true;
}

-(void) stopAudio
{
	AudioQueueStop(AQ.queue, false);
	AQ.mIsRunning = false;
}


- (void)done
{
	AudioQueueDispose(AQ.queue, true);
}


@end
