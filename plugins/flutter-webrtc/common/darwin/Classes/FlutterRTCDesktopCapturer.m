#import <objc/runtime.h>

#import "FlutterRTCDesktopCapturer.h"

#if TARGET_OS_IPHONE
#import <ReplayKit/ReplayKit.h>
#import "FlutterBroadcastScreenCapturer.h"
#import "FlutterRPScreenRecorder.h"
#endif

#if TARGET_OS_OSX
// ScreenCaptureKit is used as a workaround for macOS 15 window-capture issues.
// Guard availability at runtime to keep compatibility.
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>

@interface FlutterSCKInlineCapturer : NSObject <SCStreamOutput, SCStreamDelegate>
@property(nonatomic, weak) id<RTCVideoCapturerDelegate> captureDelegate;
@property(nonatomic, strong) RTCVideoCapturer *rtcCapturer;
@property(nonatomic, strong) SCStream *stream;
@property(nonatomic, strong) dispatch_queue_t sampleQueue;
@property(nonatomic, assign) int64_t startTimeNs;
@property(nonatomic, assign) BOOL sentFirstFrame;
@end

@implementation FlutterSCKInlineCapturer

- (instancetype)initWithCaptureDelegate:(id<RTCVideoCapturerDelegate>)captureDelegate {
  self = [super init];
  if (self) {
    _captureDelegate = captureDelegate;
    _rtcCapturer = [[RTCVideoCapturer alloc] initWithDelegate:captureDelegate];
    _sampleQueue = dispatch_queue_create("FlutterSCKInlineCapturer.sample", DISPATCH_QUEUE_SERIAL);
    _startTimeNs = 0;
    _sentFirstFrame = NO;
  }
  return self;
}

- (void)startWithWindowName:(NSString *)windowName fps:(NSInteger)fps {
  __weak __typeof(self) weakSelf = self;
  [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent * _Nullable content,
                                                                NSError * _Nullable error) {
    __strong __typeof(weakSelf) self = weakSelf;
    if (!self) return;
    if (error || !content) {
      NSLog(@"[SCK] getShareableContent failed: %@", error);
      return;
    }

    SCWindow *target = nil;
    NSString *needle = windowName.lowercaseString;
    for (SCWindow *w in content.windows) {
      if (w.title && [w.title.lowercaseString isEqualToString:needle]) {
        target = w;
        break;
      }
    }
    if (!target) {
      for (SCWindow *w in content.windows) {
        if (w.title && [w.title.lowercaseString containsString:needle]) {
          target = w;
          break;
        }
      }
    }
    if (!target) {
      for (SCWindow *w in content.windows) {
        if (w.title.length > 0) { target = w; break; }
      }
    }
    if (!target && content.windows.count > 0) {
      target = content.windows.firstObject;
    }
    if (!target) {
      NSLog(@"[SCK] No window matched for name=%@", windowName);
      return;
    }

    NSLog(@"[SCK] Selected window: title=%@ id=%llu", target.title, target.windowID);

    SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
    config.width = (int)MAX(1, target.frame.size.width);
    config.height = (int)MAX(1, target.frame.size.height);
    // Prefer NV12; it is the most commonly supported format for RTC pipelines.
    config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    config.showsCursor = NO;
    config.scalesToFit = YES;
    if (fps > 0) {
      config.minimumFrameInterval = CMTimeMake(1, (int32_t)fps);
    }

    SCContentFilter *filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:target];
    self.stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
    self.sentFirstFrame = NO;
    self.startTimeNs = 0;

    NSError *addErr = nil;
    [self.stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:self.sampleQueue error:&addErr];
    if (addErr) {
      NSLog(@"[SCK] addStreamOutput failed: %@", addErr);
      self.stream = nil;
      return;
    }

    [self.stream startCaptureWithCompletionHandler:^(NSError * _Nullable startErr) {
      if (startErr) {
        NSLog(@"[SCK] startCapture failed: %@", startErr);
        self.stream = nil;
      } else {
        NSLog(@"[SCK] startCapture ok (fps=%ld)", (long)fps);
      }
    }];
  }];
}

- (void)stop {
  SCStream *stream = self.stream;
  if (!stream) return;
  self.stream = nil;
  [stream stopCaptureWithCompletionHandler:^(NSError * _Nullable error) {
    if (error) {
      NSLog(@"[SCK] stopCapture error: %@", error);
    } else {
      NSLog(@"[SCK] stopCapture ok");
    }
  }];
}

- (void)stream:(SCStream *)stream
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
        ofType:(SCStreamOutputType)type {
  if (type != SCStreamOutputTypeScreen) return;
  CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  if (!pixelBuffer) return;

  // Debug: keep the first-frame logging, but avoid spam.
  OSType fmt = CVPixelBufferGetPixelFormatType(pixelBuffer);

  if (self.startTimeNs == 0) {
    self.startTimeNs = (int64_t)(CACurrentMediaTime() * 1000000000.0);
  }
  int64_t nowNs = (int64_t)(CACurrentMediaTime() * 1000000000.0);
  int64_t tsNs = nowNs - self.startTimeNs;

  RTCCVPixelBuffer *buffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
  RTCVideoFrame *frame = [[RTCVideoFrame alloc] initWithBuffer:buffer
                                                     rotation:RTCVideoRotation_0
                                                  timeStampNs:tsNs];
  // Pass a real RTCVideoCapturer instance; some implementations treat nil capturer specially.
  [self.captureDelegate capturer:self.rtcCapturer didCaptureVideoFrame:frame];

  if (!self.sentFirstFrame) {
    self.sentFirstFrame = YES;
    NSLog(@"[SCK] first frame fmt=%u %dx%d", (unsigned)fmt, frame.width, frame.height);
  }
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
  NSLog(@"[SCK] stream stopped: %@", error);
}

@end

RTCDesktopMediaList* _screen = nil;
RTCDesktopMediaList* _window = nil;
NSArray<RTCDesktopSource*>* _captureSources;
FlutterSCKInlineCapturer* _sckCapturer = nil;
#endif

@implementation FlutterWebRTCPlugin (DesktopCapturer)

- (void)getDisplayMedia:(NSDictionary*)constraints result:(FlutterResult)result {
  // Note: window capture on macOS 15 can produce garbled frames with legacy capturer.
  // We conditionally use ScreenCaptureKit for window sources.
  NSString* mediaStreamId = [[NSUUID UUID] UUIDString];
  RTCMediaStream* mediaStream = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];
  RTCVideoSource* videoSource = [self.peerConnectionFactory videoSourceForScreenCast:YES];
  NSString* trackUUID = [[NSUUID UUID] UUIDString];

#if TARGET_OS_IPHONE
  BOOL useBroadcastExtension = false;
  id videoConstraints = constraints[@"video"];
  if ([videoConstraints isKindOfClass:[NSDictionary class]]) {
    // constraints.video.deviceId
    useBroadcastExtension =
        [((NSDictionary*)videoConstraints)[@"deviceId"] isEqualToString:@"broadcast"];
  }

  id screenCapturer;

  if (useBroadcastExtension) {
    screenCapturer = [[FlutterBroadcastScreenCapturer alloc] initWithDelegate:videoSource];
  } else {
    screenCapturer = [[FlutterRPScreenRecorder alloc] initWithDelegate:videoSource];
  }

  [screenCapturer startCapture];
  NSLog(@"start %@ capture", useBroadcastExtension ? @"broadcast" : @"replykit");

  self.videoCapturerStopHandlers[trackUUID] = ^(CompletionHandler handler) {
    NSLog(@"stop %@ capture, trackID %@", useBroadcastExtension ? @"broadcast" : @"replykit",
          trackUUID);
    [screenCapturer stopCaptureWithCompletionHandler:handler];
  };

  if (useBroadcastExtension) {
    NSString* extension =
        [[[NSBundle mainBundle] infoDictionary] valueForKey:kRTCScreenSharingExtension];

    RPSystemBroadcastPickerView* picker = [[RPSystemBroadcastPickerView alloc] init];
    picker.showsMicrophoneButton = false;
    if (extension) {
      picker.preferredExtension = extension;
    } else {
      NSLog(@"Not able to find the %@ key", kRTCScreenSharingExtension);
    }
    SEL selector = NSSelectorFromString(@"buttonPressed:");
    if ([picker respondsToSelector:selector]) {
      [picker performSelector:selector withObject:nil];
    }
  }
#endif

#if TARGET_OS_OSX
  /* example for constraints:
      {
          'audio': false,
          'video": {
              'deviceId':  {'exact': sourceId},
              'mandatory': {
                  'frameRate': 30.0
              },
          }
      }
  */
  NSString* sourceId = nil;
  BOOL useDefaultScreen = NO;
  NSInteger fps = 30;
  id videoConstraints = constraints[@"video"];
  if ([videoConstraints isKindOfClass:[NSNumber class]] && [videoConstraints boolValue] == YES) {
    useDefaultScreen = YES;
  } else if ([videoConstraints isKindOfClass:[NSDictionary class]]) {
    NSDictionary* deviceId = videoConstraints[@"deviceId"];
    if (deviceId != nil && [deviceId isKindOfClass:[NSDictionary class]]) {
      if (deviceId[@"exact"] != nil) {
        sourceId = deviceId[@"exact"];
        if (sourceId == nil) {
          result(@{@"error" : @"No deviceId.exact found"});
          return;
        }
      }
    } else {
      // fall back to default screen if no deviceId is specified
      useDefaultScreen = YES;
    }
    id mandatory = videoConstraints[@"mandatory"];
    if (mandatory != nil && [mandatory isKindOfClass:[NSDictionary class]]) {
      id frameRate = mandatory[@"frameRate"];
      if (frameRate != nil && [frameRate isKindOfClass:[NSNumber class]]) {
        fps = [frameRate integerValue];
      }
    }
  }
  RTCDesktopCapturer* desktopCapturer;
  RTCDesktopSource* source = nil;
  if (useDefaultScreen) {
    desktopCapturer = [[RTCDesktopCapturer alloc] initWithDefaultScreen:self
                                                        captureDelegate:videoSource];
  } else {
    source = [self getSourceById:sourceId];
    if (source == nil) {
      result(@{@"error" : [NSString stringWithFormat:@"No source found for id: %@", sourceId]});
      return;
    }

    if (source.sourceType == RTCDesktopSourceTypeWindow) {
      if (@available(macOS 12.3, *)) {
        _sckCapturer = [[FlutterSCKInlineCapturer alloc] initWithCaptureDelegate:videoSource];
        [_sckCapturer startWithWindowName:source.name fps:fps];
        NSLog(@"start desktop capture (SCK): sourceId: %@, type: window, fps: %lu", sourceId, fps);
        self.videoCapturerStopHandlers[trackUUID] = ^(CompletionHandler handler) {
          NSLog(@"stop desktop capture (SCK): sourceId: %@, type: window, trackID %@", sourceId, trackUUID);
          [_sckCapturer stop];
          _sckCapturer = nil;
          handler();
        };
        desktopCapturer = nil;
      } else {
        desktopCapturer = [[RTCDesktopCapturer alloc] initWithSource:source
                                                            delegate:self
                                                     captureDelegate:videoSource];
      }
    } else {
      desktopCapturer = [[RTCDesktopCapturer alloc] initWithSource:source
                                                          delegate:self
                                                   captureDelegate:videoSource];
    }
  }
  if (desktopCapturer != nil) {
    [desktopCapturer startCaptureWithFPS:fps];
    NSLog(@"start desktop capture: sourceId: %@, type: %@, fps: %lu", sourceId,
          source.sourceType == RTCDesktopSourceTypeScreen ? @"screen" : @"window", fps);

    self.videoCapturerStopHandlers[trackUUID] = ^(CompletionHandler handler) {
      NSLog(@"stop desktop capture: sourceId: %@, type: %@, trackID %@", sourceId,
            source.sourceType == RTCDesktopSourceTypeScreen ? @"screen" : @"window", trackUUID);
      [desktopCapturer stopCapture];
      handler();
    };
  }
#endif

  RTCVideoTrack* videoTrack = [self.peerConnectionFactory videoTrackWithSource:videoSource
                                                                       trackId:trackUUID];
  [mediaStream addVideoTrack:videoTrack];

  [self.localTracks setObject:videoTrack forKey:trackUUID];

  NSMutableArray* audioTracks = [NSMutableArray array];
  NSMutableArray* videoTracks = [NSMutableArray array];

  for (RTCVideoTrack* track in mediaStream.videoTracks) {
    [videoTracks addObject:@{
      @"id" : track.trackId,
      @"kind" : track.kind,
      @"label" : track.trackId,
      @"enabled" : @(track.isEnabled),
      @"remote" : @(YES),
      @"readyState" : @"live"
    }];
  }

  self.localStreams[mediaStreamId] = mediaStream;
  result(
      @{@"streamId" : mediaStreamId, @"audioTracks" : audioTracks, @"videoTracks" : videoTracks});
}

- (void)getDesktopSources:(NSDictionary*)argsMap result:(FlutterResult)result {
#if TARGET_OS_OSX
  NSLog(@"getDesktopSources");

  NSArray* types = [argsMap objectForKey:@"types"];
  if (types == nil) {
    result([FlutterError errorWithCode:@"ERROR" message:@"types is required" details:nil]);
    return;
  }

  if (![self buildDesktopSourcesListWithTypes:types forceReload:YES result:result]) {
    NSLog(@"getDesktopSources failed.");
    return;
  }

  NSMutableArray* sources = [NSMutableArray array];
  NSEnumerator* enumerator = [_captureSources objectEnumerator];
  RTCDesktopSource* object;
  while ((object = enumerator.nextObject) != nil) {
    NSData* data = nil;
    NSImage* thumbImage = [object UpdateThumbnail];
    if (thumbImage) {
      NSImage* resizedImg = [self resizeImage:thumbImage forSize:NSMakeSize(320, 180)];
      data = [resizedImg TIFFRepresentation];
      if (data) {
        NSBitmapImageRep* imageRep = [NSBitmapImageRep imageRepWithData:data];
        data = [imageRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
      }
    }
    [sources addObject:@{
      @"id" : object.sourceId,
      @"name" : object.name,
      @"thumbnailSize" : data ? @{@"width" : @320, @"height" : @180} : @{@"width" : @0, @"height" : @0},
      @"type" : object.sourceType == RTCDesktopSourceTypeScreen ? @"screen" : @"window",
      @"thumbnail" : data ?: [NSNull null],
    }];
  }
  result(@{@"sources" : sources});
#else
  result([FlutterError errorWithCode:@"ERROR" message:@"Not supported on iOS" details:nil]);
#endif
}

- (void)getDesktopSourceThumbnail:(NSDictionary*)argsMap result:(FlutterResult)result {
#if TARGET_OS_OSX
  NSLog(@"getDesktopSourceThumbnail");
  NSString* sourceId = argsMap[@"sourceId"];
  RTCDesktopSource* object = [self getSourceById:sourceId];
  if (object == nil) {
    result(@{@"error" : @"No source found"});
    return;
  }
  NSImage* image = [object UpdateThumbnail];
  if (image != nil) {
    NSImage* resizedImg = [self resizeImage:image forSize:NSMakeSize(320, 180)];
    NSData* data = [resizedImg TIFFRepresentation];
    result(data);
  } else {
    result(@{@"error" : @"No thumbnail found"});
  }

#else
  result([FlutterError errorWithCode:@"ERROR" message:@"Not supported on iOS" details:nil]);
#endif
}

- (void)updateDesktopSources:(NSDictionary*)argsMap result:(FlutterResult)result {
#if TARGET_OS_OSX
  NSLog(@"updateDesktopSources");
  NSArray* types = [argsMap objectForKey:@"types"];
  if (types == nil) {
    result([FlutterError errorWithCode:@"ERROR" message:@"types is required" details:nil]);
    return;
  }
  if (![self buildDesktopSourcesListWithTypes:types forceReload:NO result:result]) {
    NSLog(@"updateDesktopSources failed.");
    return;
  }
  result(@{@"result" : @YES});
#else
  result([FlutterError errorWithCode:@"ERROR" message:@"Not supported on iOS" details:nil]);
#endif
}

#if TARGET_OS_OSX
- (NSImage*)resizeImage:(NSImage*)sourceImage forSize:(CGSize)targetSize {
  CGSize imageSize = sourceImage.size;
  CGFloat width = imageSize.width;
  CGFloat height = imageSize.height;
  CGFloat targetWidth = targetSize.width;
  CGFloat targetHeight = targetSize.height;
  CGFloat scaleFactor = 0.0;
  CGFloat scaledWidth = targetWidth;
  CGFloat scaledHeight = targetHeight;
  CGPoint thumbnailPoint = CGPointMake(0.0, 0.0);

  if (CGSizeEqualToSize(imageSize, targetSize) == NO) {
    CGFloat widthFactor = targetWidth / width;
    CGFloat heightFactor = targetHeight / height;

    // scale to fit the longer
    scaleFactor = (widthFactor > heightFactor) ? widthFactor : heightFactor;
    scaledWidth = ceil(width * scaleFactor);
    scaledHeight = ceil(height * scaleFactor);

    // center the image
    if (widthFactor > heightFactor) {
      thumbnailPoint.y = (targetHeight - scaledHeight) * 0.5;
    } else if (widthFactor < heightFactor) {
      thumbnailPoint.x = (targetWidth - scaledWidth) * 0.5;
    }
  }

  NSImage* newImage = [[NSImage alloc] initWithSize:NSMakeSize(scaledWidth, scaledHeight)];
  CGRect thumbnailRect = {thumbnailPoint, {scaledWidth, scaledHeight}};
  NSRect imageRect = NSMakeRect(0.0, 0.0, width, height);

  [newImage lockFocus];
    [sourceImage drawInRect:thumbnailRect fromRect:imageRect operation:NSCompositingOperationCopy fraction:1.0];
  [newImage unlockFocus];

  return newImage;
}

- (RTCDesktopSource*)getSourceById:(NSString*)sourceId {
  NSEnumerator* enumerator = [_captureSources objectEnumerator];
  RTCDesktopSource* object;
  while ((object = enumerator.nextObject) != nil) {
    if ([sourceId isEqualToString:object.sourceId]) {
      return object;
    }
  }
  return nil;
}

- (BOOL)buildDesktopSourcesListWithTypes:(NSArray*)types
                             forceReload:(BOOL)forceReload
                                  result:(FlutterResult)result {
  BOOL captureWindow = NO;
  BOOL captureScreen = NO;
  _captureSources = [NSMutableArray array];

  NSEnumerator* typesEnumerator = [types objectEnumerator];
  NSString* type;
  while ((type = typesEnumerator.nextObject) != nil) {
    if ([type isEqualToString:@"screen"]) {
      captureScreen = YES;
    } else if ([type isEqualToString:@"window"]) {
      captureWindow = YES;
    } else {
      result([FlutterError errorWithCode:@"ERROR" message:@"Invalid type" details:nil]);
      return NO;
    }
  }

  if (!captureWindow && !captureScreen) {
    result([FlutterError errorWithCode:@"ERROR"
                               message:@"At least one type is required"
                               details:nil]);
    return NO;
  }

  if (captureWindow) {
    if (!_window)
      _window = [[RTCDesktopMediaList alloc] initWithType:RTCDesktopSourceTypeWindow delegate:self];
    [_window UpdateSourceList:forceReload updateAllThumbnails:YES];
    NSArray<RTCDesktopSource*>* sources = [_window getSources];
    _captureSources = [_captureSources arrayByAddingObjectsFromArray:sources];
  }
  if (captureScreen) {
    if (!_screen)
      _screen = [[RTCDesktopMediaList alloc] initWithType:RTCDesktopSourceTypeScreen delegate:self];
    [_screen UpdateSourceList:forceReload updateAllThumbnails:YES];
    NSArray<RTCDesktopSource*>* sources = [_screen getSources];
    _captureSources = [_captureSources arrayByAddingObjectsFromArray:sources];
  }
  NSLog(@"captureSources: %lu", [_captureSources count]);
  return YES;
}

#pragma mark - RTCDesktopMediaListDelegate delegate

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
- (void)didDesktopSourceAdded:(RTC_OBJC_TYPE(RTCDesktopSource) *)source {
  // NSLog(@"didDesktopSourceAdded: %@, id %@", source.name, source.sourceId);
  if (self.eventSink) {
    NSImage* image = [source UpdateThumbnail];
    NSData* data = [[NSData alloc] init];
    if (image != nil) {
      NSImage* resizedImg = [self resizeImage:image forSize:NSMakeSize(320, 180)];
      data = [resizedImg TIFFRepresentation];
    }
    postEvent(self.eventSink, @{
      @"event" : @"desktopSourceAdded",
      @"id" : source.sourceId,
      @"name" : source.name,
      @"thumbnailSize" : @{@"width" : @0, @"height" : @0},
      @"type" : source.sourceType == RTCDesktopSourceTypeScreen ? @"screen" : @"window",
      @"thumbnail" : data
    });
  }
}

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
- (void)didDesktopSourceRemoved:(RTC_OBJC_TYPE(RTCDesktopSource) *)source {
  // NSLog(@"didDesktopSourceRemoved: %@, id %@", source.name, source.sourceId);
  if (self.eventSink) {
    postEvent(self.eventSink, @{
      @"event" : @"desktopSourceRemoved",
      @"id" : source.sourceId,
    });
  }
}

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
- (void)didDesktopSourceNameChanged:(RTC_OBJC_TYPE(RTCDesktopSource) *)source {
  // NSLog(@"didDesktopSourceNameChanged: %@, id %@", source.name, source.sourceId);
  if (self.eventSink) {
    postEvent(self.eventSink, @{
      @"event" : @"desktopSourceNameChanged",
      @"id" : source.sourceId,
      @"name" : source.name,
    });
  }
}

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
- (void)didDesktopSourceThumbnailChanged:(RTC_OBJC_TYPE(RTCDesktopSource) *)source {
  // NSLog(@"didDesktopSourceThumbnailChanged: %@, id %@", source.name, source.sourceId);
  if (self.eventSink) {
    NSImage* resizedImg = [self resizeImage:[source thumbnail] forSize:NSMakeSize(320, 180)];
    NSData* data = [resizedImg TIFFRepresentation];
    postEvent(self.eventSink, @{
      @"event" : @"desktopSourceThumbnailChanged",
      @"id" : source.sourceId,
      @"thumbnail" : data
    });
  }
}

#pragma mark - RTCDesktopCapturerDelegate delegate

- (void)didSourceCaptureStart:(RTCDesktopCapturer*)capturer {
  NSLog(@"didSourceCaptureStart");
}

- (void)didSourceCapturePaused:(RTCDesktopCapturer*)capturer {
  NSLog(@"didSourceCapturePaused");
}

- (void)didSourceCaptureStop:(RTCDesktopCapturer*)capturer {
  NSLog(@"didSourceCaptureStop");
}

- (void)didSourceCaptureError:(RTCDesktopCapturer*)capturer {
  NSLog(@"didSourceCaptureError");
}

#endif

@end
