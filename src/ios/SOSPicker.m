//
//  SOSPicker.m
//  SyncOnSet
//
//  Created by Christopher Sullivan on 10/25/13.
//
//

#import "SOSPicker.h"
#import "ELCAlbumPickerController.h"
#import "ELCImagePickerController.h"
#import "ELCAssetTablePicker.h"

#define CDV_PHOTO_PREFIX @"cdv_photo_"

@implementation SOSPicker

+ (ALAssetsLibrary *)defaultAssetsLibrary {
    static dispatch_once_t pred = 0;
    static ALAssetsLibrary *library = nil;
    dispatch_once(&pred, ^{
        library = [[ALAssetsLibrary alloc] init];
    });
    
    // TODO: Dealloc this later?
    return library;
}

@synthesize callbackId;

- (void) getPictures:(CDVInvokedUrlCommand *)command {
	NSDictionary *options = [command.arguments objectAtIndex: 0];

	NSInteger maximumImagesCount = [[options objectForKey:@"maximumImagesCount"] integerValue];
    NSInteger minimumImagesCount = [[options objectForKey:@"minimumImagesCount"] integerValue];
	self.width = [[options objectForKey:@"width"] integerValue];
	self.height = [[options objectForKey:@"height"] integerValue];
	self.quality = [[options objectForKey:@"quality"] integerValue];

	// Create the an album controller and image picker
	ELCAlbumPickerController *albumController = [[ELCAlbumPickerController alloc] init];
	
	if (maximumImagesCount == 1) {
      albumController.immediateReturn = true;
      albumController.singleSelection = true;
   } else {
      albumController.immediateReturn = false;
      albumController.singleSelection = false;
   }
    
    albumController.minimumImagesCount = minimumImagesCount;//TODO
    albumController.maximumImagesCount = maximumImagesCount;//TODO
   
   ELCImagePickerController *imagePicker = [[ELCImagePickerController alloc] initWithRootViewController:albumController];
   imagePicker.maximumImagesCount = maximumImagesCount;
    imagePicker.minimumImagesCount = minimumImagesCount;
   imagePicker.returnsOriginalImage = 1;
   imagePicker.imagePickerDelegate = self;

   albumController.parent = imagePicker;
	self.callbackId = command.callbackId;
	// Present modally
    imagePicker.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
	[self.viewController presentViewController:imagePicker
	                       animated:YES
	                     completion:nil];
}

- (void) getPictureBinary:(CDVInvokedUrlCommand *)command {
    NSDictionary *options = [command.arguments objectAtIndex: 0];
	NSURL *assetUrl = [NSURL URLWithString:[options objectForKey:@"assetUrl"]];
    int quality = [[options objectForKey:@"quality"] intValue];
    
    // Grab the asset library
    ALAssetsLibrary *library = [SOSPicker defaultAssetsLibrary];
    
    // Run a background job
    [self.commandDelegate runInBackground:^{
        
        NSString* docsPath = [NSTemporaryDirectory()stringByStandardizingPath];
        
        NSFileManager* fileMgr = [[NSFileManager alloc] init];
        
    
        [library assetForURL:assetUrl resultBlock:^(ALAsset *asset) {
            CDVPluginResult *pluginResult = nil;
            NSError* err = nil;
            
            NSString* filePath;
            UIImageOrientation orientation = [[asset valueForProperty:@"ALAssetPropertyOrientation"] intValue];
        
            UIImage* orgImg = [UIImage imageWithCGImage:[[asset defaultRepresentation ] fullResolutionImage] scale:1.0f orientation:orientation];
            NSData *orgData = UIImageJPEGRepresentation(orgImg, quality/100.0f);
            orgImg = nil;
        
            do {
                NSString *uuid = [[NSUUID UUID] UUIDString];
                filePath = [NSString stringWithFormat:@"%@/%@%@.%@", docsPath, CDV_PHOTO_PREFIX, uuid, @"jpg"];
            } while ([fileMgr fileExistsAtPath:filePath]);
            
            if (![orgData writeToFile:filePath options:NSAtomicWrite error:&err]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
                
            }else{
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:filePath];
            }
        
            ;
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        
        
    } failureBlock:^(NSError *error) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
    }];
}

- (void)elcImagePickerController:(ELCImagePickerController *)picker didFinishPickingMediaWithInfo:(NSArray *)info {
	CDVPluginResult* result = nil;
	NSMutableArray *resultStrings = [[NSMutableArray alloc] init];
    NSData* data = nil;
    NSString* docsPath = [NSTemporaryDirectory()stringByStandardizingPath];
    NSError* err = nil;
    NSFileManager* fileMgr = [[NSFileManager alloc] init];
    NSString* filePath;
    ALAsset* asset = nil;
    UIImageOrientation orientation = UIImageOrientationUp;;
    CGSize targetSize = CGSizeMake(self.width, self.height);
	for (NSDictionary *dict in info) {
        asset = [dict objectForKey:@"ALAsset"];
        // From ELCImagePickerController.m

        do {
            NSString *uuid = [[NSUUID UUID] UUIDString];
            filePath = [NSString stringWithFormat:@"%@/%@%@.%@", docsPath, CDV_PHOTO_PREFIX, uuid, @"jpg"];
        } while ([fileMgr fileExistsAtPath:filePath]);
        
        @autoreleasepool {
            ALAssetRepresentation *assetRep = [asset defaultRepresentation];
            CGImageRef imgRef = NULL;
            
            //defaultRepresentation returns image as it appears in photo picker, rotated and sized,
            //so use UIImageOrientationUp when creating our image below.
            if (false && picker.returnsOriginalImage) {
                imgRef = [assetRep fullResolutionImage];
                orientation = [[asset valueForProperty:@"ALAssetPropertyOrientation"] intValue];
            } else {
                imgRef = [assetRep fullScreenImage];
            }
            
            UIImage* image = [UIImage imageWithCGImage:imgRef scale:1.0f orientation:orientation];
            if (self.width == 0 && self.height == 0) {
                data = UIImageJPEGRepresentation(image, self.quality/100.0f);
            } else {
                UIImage* scaledImage = [self imageByScalingNotCroppingForSize:image toSize:targetSize];
                data = UIImageJPEGRepresentation(scaledImage, self.quality/100.0f);
            }
            
            if (![data writeToFile:filePath options:NSAtomicWrite error:&err]) {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
                break;
            } else {
                NSURL *assetUrl = [asset valueForProperty:ALAssetPropertyAssetURL];
                CGSize size = [assetRep dimensions];
                NSDate *date = [asset valueForProperty:ALAssetPropertyDate];
                NSString *srcFilename = [assetRep filename];
                
                NSDateFormatter *df = [[NSDateFormatter alloc] init];
                [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                NSString *dateStr = [df stringFromDate:date];
                NSString *widthStr = [NSString stringWithFormat:@"%g", size.width];
                NSString *heightStr = [NSString stringWithFormat:@"%g", size.height];
                
                NSString *path = [[NSURL fileURLWithPath:filePath] absoluteString];
                
                NSDictionary * res = [NSDictionary dictionaryWithObjectsAndKeys:
                                      assetUrl.absoluteString, @"assetUrl",
                                      path, @"dispUrl",
                                      dateStr, @"date",
                                      srcFilename, @"filename",
                                      widthStr, @"width",
                                      heightStr, @"height",
                                      nil];
                
                //[resultStrings addObject:[[NSURL fileURLWithPath:filePath] absoluteString]];
                [resultStrings addObject:res];
            }
        }

	}
	
	if (nil == result) {
		result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:resultStrings];
	}

	[self.viewController dismissViewControllerAnimated:YES completion:nil];
	[self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
}

- (void)elcImagePickerControllerDidCancel:(ELCImagePickerController *)picker {
	[self.viewController dismissViewControllerAnimated:YES completion:nil];
	CDVPluginResult* pluginResult = nil;
    NSArray* emptyArray = [NSArray array];
	pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:emptyArray];
	[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
}

- (UIImage*)imageByScalingNotCroppingForSize:(UIImage*)anImage toSize:(CGSize)frameSize
{
    UIImage* sourceImage = anImage;
    UIImage* newImage = nil;
    CGSize imageSize = sourceImage.size;
    CGFloat width = imageSize.width;
    CGFloat height = imageSize.height;
    CGFloat targetWidth = frameSize.width;
    CGFloat targetHeight = frameSize.height;
    CGFloat scaleFactor = 0.0;
    CGSize scaledSize = frameSize;

    if (CGSizeEqualToSize(imageSize, frameSize) == NO) {
        CGFloat widthFactor = targetWidth / width;
        CGFloat heightFactor = targetHeight / height;

        // opposite comparison to imageByScalingAndCroppingForSize in order to contain the image within the given bounds
        if (widthFactor == 0.0) {
            scaleFactor = heightFactor;
        } else if (heightFactor == 0.0) {
            scaleFactor = widthFactor;
        } else if (widthFactor > heightFactor) {
            scaleFactor = heightFactor; // scale to fit height
        } else {
            scaleFactor = widthFactor; // scale to fit width
        }
        scaledSize = CGSizeMake(width * scaleFactor, height * scaleFactor);
    }

    UIGraphicsBeginImageContext(scaledSize); // this will resize

    [sourceImage drawInRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height)];

    newImage = UIGraphicsGetImageFromCurrentImageContext();
    if (newImage == nil) {
        NSLog(@"could not scale image");
    }

    // pop the context to get back to the default
    UIGraphicsEndImageContext();
    return newImage;
}

@end
