/*
 * simple android media player based on the FFmpeg libraries
 * 2012-3
 * yubo@yubo.org
 */

/*
 * simple ios media player based on the FFmpeg libraries
 * 2012-5
 * yubo@yubo.org
 */

#ifndef NATIVEPLAYER_UTILS_H
#define NATIVEPLAYER_UTILS_H

#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <pthread.h>
#include <dirent.h>
#include <sys/stat.h>
#include <stdarg.h>



#define UNUSED  __attribute__((unused))
#define LOGI(...) ((void)printf(__VA_ARGS__))
#define LOGW(...) ((void)printf(__VA_ARGS__))
#define LOGE(...) ((void)printf(__VA_ARGS__))
#define eLog(...) ((void)printf(__VA_ARGS__))
#define iLog(...) ((void)printf(__VA_ARGS__))
#define wLog(...) ((void)printf(__VA_ARGS__))




void av_log_callback(void* ptr, int level, const char* fmt, va_list vl);
int saveYUV(AVFrame *pFrame);
int IsSpace(int c);
void LTrim(char * s);
void RTrim(char *s);
void trim(char *s);
int htoi(char c);
void decode_filename(char* out,const char* in);
void printdir(char *dir);

#endif /* NATIVEPLAYER_UTILS_H */
