//
//  Copyright 2012 baofeng.com All rights reserved.
//  yubo@baofeng.com
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioFile.h>
#define NUM_BUFFERS 2
#define BUFFER_SIZE_BYTES 0x10000	//It must be pow(2,x)

@interface playAudio : NSObject{
@public


}


@property AudioQueueRef queue;



@end