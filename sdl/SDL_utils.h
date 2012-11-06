#include "SDL_error.h"
#include <sys/time.h>


void SDL_Error(SDL_errorcode code);
void SDL_SetError(char *c);
void SDL_ClearError(void);

