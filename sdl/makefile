
SRC= thread/pthread/SDL_syscond.c \
                thread/pthread/SDL_sysmutex.c \
                thread/pthread/SDL_syssem.c \
                thread/pthread/SDL_systhread.c \
                thread/SDL_thread.c \
                SDL_utils.c \
                SDL.c \
                SDL_fatal.c \
                events/SDL_events.c \
                events/SDL_quit.c \
                timer/SDL_timer.c \
                timer/unix/SDL_systimer.c

OBJS=$(addsuffix .o,$(SRC))
SRC_FILES=$(addsuffix .c,$(SRC))



%.o: %c
	$(CC) $< $(CFLAGS) -c -o $@

.phony: all clean

setenv MACOSX_DEPLOYMENT_TARGET 10.6
setenv PATH "/Developer/Platforms/iPhoneSimulator.platform/Developer/usr/bin:/Developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin"

all: libsdl.a $(OBJS)

libsdl.a: $(OBJS)
	
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE    := sdl

LOCAL_C_INCLUDES := $(LOCAL_PATH) $(LOCAL_PATH)/include $(LOCAL_PATH)/pthread

LOCAL_LDLIBS := -L$(SYSROOT)/usr/lib -llog 
#LOCAL_STATIC_LIBRARIES := avutil avcodec avformat swscale 
LOCAL_SRC_FILES := thread/pthread/SDL_syscond.c \
		thread/pthread/SDL_sysmutex.c \
		thread/pthread/SDL_syssem.c \
		thread/pthread/SDL_systhread.c \
		thread/SDL_thread.c \
		SDL_utils.c \
		SDL.c \
		SDL_fatal.c \
		events/SDL_events.c \
		events/SDL_quit.c \
		timer/SDL_timer.c \
		timer/unix/SDL_systimer.c \


include $(BUILD_STATIC_LIBRARY)
