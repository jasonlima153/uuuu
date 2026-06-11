#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - Forward Declarations
@interface WKConversationVC : UIViewController
@end

#pragma mark - 1. 运行时方法扫描器 (Runtime Scanner)

static void dumpMethodsForClass(Class cls, BOOL isClassMethod) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(isClassMethod ? object_getClass(cls) : cls, &count);
    NSMutableString *logStr = [NSMutableString stringWithFormat:@"\n[%@] 真实%@方法列表 (%d个):\n",
        NSStringFromClass(cls), isClassMethod ? @"类(+)" : @"实例(-)", count];
    for (int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        [logStr appendFormat:@"  %@ %s\n", isClassMethod ? @"+" : @"-", sel_getName(sel)];
    }
    free(methods);
    NSLog(@"%@", logStr);
}

#pragma mark - 2. 核心发送引擎 (全链路运行时自检)

static void verifyAndSendVoice(NSData *amrData, NSInteger duration, id channel) {
    if (!amrData || !channel) {
        NSLog(@"[UUUVoiceFun] 拦截：amrData 或 channel 为空");
        return;
    }
    NSLog(@"[UUUVoiceFun] Channel 真实类型: %@", NSStringFromClass([channel class]));

    NSMutableData *dummyWaveform = [NSMutableData dataWithCapacity:100];
    for (int i = 0; i < 100; i++) {
        uint8_t val = (uint8_t)(sin(i * 0.2) * 20 + 30 + arc4random_uniform(10));
        [dummyWaveform appendBytes:&val length:1];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class voiceContentCls = NSClassFromString(@"WKVoiceContent");
            if (!voiceContentCls) {
                NSLog(@"[UUUVoiceFun] 找不到 WKVoiceContent 类");
                return;
            }

            SEL initSel = NSSelectorFromString(@"initWithData:second:waveform:");
            id voiceContent = nil;

            if ([voiceContentCls respondsToSelector:initSel]) {
                NSLog(@"[UUUVoiceFun] +[WKVoiceContent initWithData:second:waveform:] 存在");
                NSMethodSignature *sig = [voiceContentCls methodSignatureForSelector:initSel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:voiceContentCls];
                [inv setSelector:initSel];
                [inv setArgument:&amrData atIndex:2];
                [inv setArgument:&duration atIndex:3];
                [inv setArgument:&dummyWaveform atIndex:4];
                [inv invoke];
                __unsafe_unretained id ret = nil;
                [inv getReturnValue:&ret];
                voiceContent = ret;
            } else if ([voiceContentCls instancesRespondToSelector:initSel]) {
                NSLog(@"[UUUVoiceFun] -[WKVoiceContent initWithData:second:waveform:] 存在");
                id instance = [voiceContentCls alloc];
                NSMethodSignature *sig = [instance methodSignatureForSelector:initSel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:instance];
                [inv setSelector:initSel];
                [inv setArgument:&amrData atIndex:2];
                [inv setArgument:&duration atIndex:3];
                [inv setArgument:&dummyWaveform atIndex:4];
                [inv invoke];
                __unsafe_unretained id ret = nil;
                [inv getReturnValue:&ret];
                voiceContent = ret;
            } else {
                NSLog(@"[UUUVoiceFun] initWithData:second:waveform: 不存在！扫描全量方法...");
                dumpMethodsForClass(voiceContentCls, YES);
                dumpMethodsForClass(voiceContentCls, NO);
                return;
            }

            if (!voiceContent) {
                NSLog(@"[UUUVoiceFun] voiceContent 实例化失败");
                return;
            }
            NSLog(@"[UUUVoiceFun] voiceContent 创建成功，类型: %@", NSStringFromClass([voiceContent class]));

            Class sdkClass = NSClassFromString(@"WKSDK");
            if (![sdkClass respondsToSelector:@selector(shared)]) {
                NSLog(@"[UUUVoiceFun] WKSDK 没有 shared 方法");
                return;
            }
            id sharedSDK = [sdkClass performSelector:@selector(shared)];
            if (![sharedSDK respondsToSelector:@selector(chatManager)]) {
                NSLog(@"[UUUVoiceFun] sharedSDK 没有 chatManager 方法");
                return;
            }
            id chatManager = [sharedSDK performSelector:@selector(chatManager)];
            NSLog(@"[UUUVoiceFun] chatManager 获取成功，类型: %@", NSStringFromClass([chatManager class]));

            SEL sendSel = NSSelectorFromString(@"sendMessage:channel:");
            if (![chatManager respondsToSelector:sendSel]) {
                NSLog(@"[UUUVoiceFun] chatManager 没有 sendMessage:channel:！扫描全量方法...");
                dumpMethodsForClass([chatManager class], NO);
                return;
            }

            NSLog(@"[UUUVoiceFun] 全链路验证通过，准备发送");
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [chatManager performSelector:sendSel withObject:voiceContent withObject:channel];
            #pragma clang diagnostic pop
            NSLog(@"[UUUVoiceFun] 发送指令已安全投递！");

        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] 异常拦截: %@", e);
        }
    });
}

#pragma mark - 3. Plist 详情列表页

@interface UUUVoiceFunDetailViewController : UITableViewController
@property (nonatomic, strong) NSArray *voiceList;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 50;
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 返回" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
}

- (void)close { [self.navigationController popViewControllerAnimated:YES]; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.voiceList.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DetailCell"];
        UIButton *sendBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [sendBtn setTitle:@"发送" forState:UIControlStateNormal];
        sendBtn.backgroundColor = [UIColor colorWithRed:0.24 green:0.52 blue:0.98 alpha:1.0];
        [sendBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        sendBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        sendBtn.layer.cornerRadius = 14;
        sendBtn.frame = CGRectMake(0, 0, 56, 28);
        [sendBtn addTarget:self action:@selector(sendButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = sendBtn;
    }

    NSDictionary *voiceDict = self.voiceList[indexPath.row];
    cell.textLabel.text = voiceDict[@"name"];
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 秒", voiceDict[@"duration"]];
    cell.detailTextLabel.textColor = [UIColor grayColor];
    cell.imageView.image = [UIImage systemImageNamed:@"bubble.left.and.bubble.right"];

    UIButton *btn = (UIButton *)cell.accessoryView;
    btn.tag = indexPath.row;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; }

- (void)sendButtonClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.voiceList.count) return;

    NSDictionary *voiceDict = self.voiceList[row];
    NSData *audioData = voiceDict[@"audioData"];
    NSInteger duration = [voiceDict[@"duration"] integerValue] ?: 1;

    if (audioData) {
        verifyAndSendVoice(audioData, duration, self.currentChannel);
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}
@end

#pragma mark - 4. 趣味语音主面板 (MP3 + Plist 双引擎)

@interface UUUVoiceFunViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSString *basePath;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"趣味语音";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入语音" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 55;
    [self.view addSubview:self.tableView];

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        if ([file hasSuffix:@".mp3"] || [file hasSuffix:@".amr"] || [file hasSuffix:@".plist"]) {
            [self.dataSource addObject:file];
        }
    }
    [self.tableView reloadData];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)importVoice {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
    #pragma clang diagnostic pop
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *fileURL = urls.firstObject;
    if (!fileURL) return;

    BOOL accessed = [fileURL startAccessingSecurityScopedResource];
    NSString *destPath = [self.basePath stringByAppendingPathComponent:fileURL.lastPathComponent];
    [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:destPath] error:nil];
    if (accessed) {
        [fileURL stopAccessingSecurityScopedResource];
    }

    [self loadVoicePacks];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.dataSource.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MainCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"MainCell"];
    }

    NSString *fileName = self.dataSource[indexPath.row];
    cell.textLabel.text = fileName;

    if ([fileName hasSuffix:@".plist"]) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"music.note"];
        cell.accessoryType = UITableViewCellAccessoryNone;

        UIButton *sendBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [sendBtn setTitle:@"发送" forState:UIControlStateNormal];
        sendBtn.backgroundColor = [UIColor colorWithRed:0.24 green:0.52 blue:0.98 alpha:1.0];
        [sendBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        sendBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        sendBtn.layer.cornerRadius = 14;
        sendBtn.frame = CGRectMake(0, 0, 56, 28);
        [sendBtn addTarget:self action:@selector(mp3SendButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = sendBtn;
    }

    if (cell.accessoryView) {
        ((UIButton *)cell.accessoryView).tag = indexPath.row;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *fileName = self.dataSource[indexPath.row];
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:fileName];

    if ([fileName hasSuffix:@".plist"]) {
        @try {
            id plistObj = [NSDictionary dictionaryWithContentsOfFile:fullPath] ?: [NSArray arrayWithContentsOfFile:fullPath];
            NSMutableArray *normalizedList = [NSMutableArray array];

            if ([plistObj isKindOfClass:[NSDictionary class]]) {
                [(NSDictionary *)plistObj enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
                    NSMutableDictionary *normItem = [NSMutableDictionary dictionary];
                    normItem[@"name"] = key;
                    normItem[@"duration"] = @(2);
                    if ([obj isKindOfClass:[NSString class]]) {
                        normItem[@"audioData"] = [[NSData alloc] initWithBase64EncodedString:obj options:0];
                    } else if ([obj isKindOfClass:[NSData class]]) {
                        normItem[@"audioData"] = obj;
                    }
                    if (normItem[@"audioData"]) [normalizedList addObject:normItem];
                }];
            } else if ([plistObj isKindOfClass:[NSArray class]]) {
                for (NSDictionary *item in plistObj) {
                    if ([item isKindOfClass:[NSDictionary class]]) {
                        NSMutableDictionary *normItem = [NSMutableDictionary dictionary];
                        normItem[@"name"] = item[@"name"] ?: item[@"title"] ?: @"未命名";
                        normItem[@"duration"] = item[@"duration"] ?: item[@"time"] ?: @(2);
                        id rawData = item[@"audioData"] ?: item[@"voice"];
                        if ([rawData isKindOfClass:[NSString class]]) {
                            normItem[@"audioData"] = [[NSData alloc] initWithBase64EncodedString:rawData options:0];
                        } else if ([rawData isKindOfClass:[NSData class]]) {
                            normItem[@"audioData"] = rawData;
                        }
                        if (normItem[@"audioData"]) [normalizedList addObject:normItem];
                    }
                }
            }
            if (normalizedList.count > 0) {
                [normalizedList sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
                UUUVoiceFunDetailViewController *detailVC = [[UUUVoiceFunDetailViewController alloc] init];
                detailVC.voiceList = normalizedList;
                detailVC.currentChannel = self.currentChannel;
                detailVC.title = [fileName stringByDeletingPathExtension];
                [self.navigationController pushViewController:detailVC animated:YES];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"该 Plist 文件格式不兼容或为空" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] Plist解析失败: %@", e); }
    }
}

- (void)mp3SendButtonClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.dataSource.count) return;

    NSString *fileName = self.dataSource[row];
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:fileName];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self safeConvertAndSendAudio:fullPath];
    });
}

- (void)safeConvertAndSendAudio:(NSString *)filePath {
    __block NSData *amrData = nil;
    __block NSInteger duration = 1;

    if ([filePath hasSuffix:@".mp3"]) {
        NSString *wavPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"safe_out.wav"];
        NSString *amrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"safe_out.amr"];
        [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:amrPath error:nil];

        @try {
            @autoreleasepool {
                NSURL *inURL = [NSURL fileURLWithPath:filePath];
                AVAudioFile *inFile = [[AVAudioFile alloc] initForReading:inURL error:nil];

                if (inFile && inFile.fileFormat.sampleRate > 0) {
                    AVAudioFormat *outFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];
                    AVAudioFile *outFile = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:wavPath] settings:outFormat.settings error:nil];

                    AVAudioFrameCount framesToRead = (AVAudioFrameCount)MIN(inFile.length, inFile.fileFormat.sampleRate * 60.0);

                    if (framesToRead > 0) {
                        AVAudioPCMBuffer *inBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inFile.processingFormat frameCapacity:framesToRead];
                        [inFile readIntoBuffer:inBuffer frameCount:framesToRead error:nil];

                        AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inBuffer.format toFormat:outFormat];
                        AVAudioFrameCount outFrames = (AVAudioFrameCount)(framesToRead * (8000.0 / inFile.fileFormat.sampleRate));
                        AVAudioPCMBuffer *outBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outFormat frameCapacity:MAX(100, outFrames)];

                        __block BOOL inputGiven = NO;
                        [converter convertToBuffer:outBuffer error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
                            if (inputGiven) { *outStatus = AVAudioConverterInputStatus_EndOfStream; return nil; }
                            inputGiven = YES;
                            *outStatus = AVAudioConverterInputStatus_HaveData;
                            return inBuffer;
                        }];

                        [outFile writeFromBuffer:outBuffer error:nil];
                        duration = MAX(1, MIN((NSInteger)(framesToRead / inFile.fileFormat.sampleRate), 60));
                    }
                }
            }

            Class converterCls = NSClassFromString(@"VoiceConverter");
            SEL encSel = NSSelectorFromString(@"EncodeWavToAmr:amrSavePath:sampleRateType:");
            if ([converterCls respondsToSelector:encSel]) {
                NSLog(@"[UUUVoiceFun] +[VoiceConverter EncodeWavToAmr...] 验证通过");
                NSMethodSignature *sig = [converterCls methodSignatureForSelector:encSel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:converterCls];
                [inv setSelector:encSel];
                [inv setArgument:&wavPath atIndex:2];
                [inv setArgument:&amrPath atIndex:3];
                int type = 0;
                [inv setArgument:&type atIndex:4];
                [inv invoke];
                amrData = [NSData dataWithContentsOfFile:amrPath];
            } else {
                NSLog(@"[UUUVoiceFun] EncodeWavToAmr 不存在！扫描 VoiceConverter...");
                dumpMethodsForClass(converterCls, YES);
            }
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] MP3转码异常: %@", e); }
    } else {
        amrData = [NSData dataWithContentsOfFile:filePath];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (amrData && amrData.length > 0) {
            verifyAndSendVoice(amrData, duration, self.currentChannel);
            [self close];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"解析失败" message:@"文件为空或格式不支持" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}
@end

#pragma mark - 5. Hook: WKConversationVC

%group UUUVoiceFunHooks

%hook WKConversationVC

- (void)viewDidLoad {
    %orig;

    if ([self.view viewWithTag:888999]) return;

    UIButton *floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    floatBtn.tag = 888999;
    floatBtn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 65, 260, 48, 48);
    floatBtn.backgroundColor = [UIColor colorWithRed:0.24 green:0.52 blue:0.98 alpha:0.9];
    floatBtn.layer.cornerRadius = 24;
    floatBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    floatBtn.layer.shadowOpacity = 0.3;
    floatBtn.layer.shadowOffset = CGSizeMake(0, 2);
    [floatBtn setTitle:@"\U0001F3B5" forState:UIControlStateNormal];
    floatBtn.titleLabel.font = [UIFont systemFontOfSize:22];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(uuu_handlePan:)];
    [floatBtn addGestureRecognizer:pan];
    [floatBtn addTarget:self action:@selector(uuu_openVoicePanel) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:floatBtn];
}

- (void)viewWillLayoutSubviews {
    %orig;
    UIView *btn = [self.view viewWithTag:888999];
    if (btn) [self.view bringSubviewToFront:btn];
}

%new
- (void)uuu_handlePan:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    CGPoint translation = [pan translationInView:btn.superview];
    CGPoint newCenter = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    newCenter.x = MAX(24, MIN(newCenter.x, [UIScreen mainScreen].bounds.size.width - 24));
    newCenter.y = MAX(100, MIN(newCenter.y, [UIScreen mainScreen].bounds.size.height - 100));
    btn.center = newCenter;
    [pan setTranslation:CGPointZero inView:btn.superview];
}

%new
- (void)uuu_openVoicePanel {
    SEL channelSel = NSSelectorFromString(@"channel");
    if (![self respondsToSelector:channelSel]) {
        NSLog(@"[UUUVoiceFun] WKConversationVC 没有 channel 方法！扫描...");
        dumpMethodsForClass([self class], NO);
        return;
    }

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id channel = [self performSelector:channelSel];
    #pragma clang diagnostic pop

    if (channel) {
        NSLog(@"[UUUVoiceFun] channel 获取成功，类型: %@", NSStringFromClass([channel class]));
        UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
        vc.currentChannel = channel;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    } else {
        NSLog(@"[UUUVoiceFun] channel 返回 nil");
    }
}

%end

%end

#pragma mark - 6. 模块初始化

%ctor {
    if (NSClassFromString(@"WKConversationVC")) {
        %init(UUUVoiceFunHooks);
    }
}
