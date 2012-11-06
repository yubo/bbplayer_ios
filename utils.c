/*
 *  utils.c
 *  stormplay
 *
 *  Created by bf apple on 12-5-24.
 *  Copyright 2012 __MyCompanyName__. All rights reserved.
 *
 */

#include "utils.h"

void printdir(char *dir){
	printf("printdir begin");
	DIR *dp;
	struct dirent *entry;
	struct stat statbuf;
	if(dp = opendir(dir)){
		while ((entry = readdir(dp)) != NULL) {
			lstat(entry->d_name, &statbuf);
			printf("printdir %s",entry->d_name);
		}
	}
}