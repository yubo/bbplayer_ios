//
//  stormplayAppDelegate.h
//  stormplay
//
//  Created by bf apple on 12-5-23.
//  Copyright 2012 baofeng.com All rights reserved.
//  yubo@baofeng.com
//

#import <UIKit/UIKit.h>

@class stormplayViewController;



@interface stormplayAppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *window;
	stormplayViewController *viewController;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet stormplayViewController *viewController;


@end

