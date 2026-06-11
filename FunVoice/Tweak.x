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

#pragma mark - 2. 核心发送引擎 (全链路运行时自检，0计算)

static void verifyAndSendVoice(NSData *amrData, NSInteger duration, id channel) {
    if (!amrData || !channel) {
        NSLog(@"[UUUVoiceFun] 拦截：amrData 或 channel 为空");
        return;
    }
    // 0字节拦截阀门：转码失败生成的空 AMR 绝不交给发送接口
    if (amrData.length < 50) {
        NSLog(@"[UUUVoiceFun] 拦截：AMR 数据异常 (%lu 字节)，疑似转码失败产生的空文件", (unsigned long)amrData.length);
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

#pragma mark - 3. Plist 详情列表页 (带 SILK 拦截)

@interface UUUVoiceFunDetailViewController : UITableViewController
@property (nonatomic, strong) NSArray *voiceList;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 55;
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
        sendBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        sendBtn.layer.cornerRadius = 14;
        sendBtn.frame = CGRectMake(0, 0, 56, 28);
        [sendBtn addTarget:self action:@selector(sendButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = sendBtn;
    }

    NSDictionary *voiceDict = self.voiceList[indexPath.row];
    cell.textLabel.text = voiceDict[@"name"];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 秒", voiceDict[@"duration"]];
    cell.detailTextLabel.textColor = [UIColor grayColor];
    cell.imageView.image = [UIImage systemImageNamed:@"bubble.left.and.bubble.right"];

    ((UIButton *)cell.accessoryView).tag = indexPath.row;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; }

- (void)sendButtonClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.voiceList.count) return;

    NSDictionary *voiceDict = self.voiceList[row];
    NSData *audioData = voiceDict[@"audioData"];
    NSInteger duration = [voiceDict[@"duration"] integerValue] ?: 1;

    // SILK 格式拦截：微信提取的 Plist 含 SILK 编码，服务器不认
    if (audioData.length > 5) {
        const char *bytes = audioData.bytes;
        if (bytes[0] == 0x02 && bytes[1] == '#' && bytes[2] == '!') {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"格式警告"
                message:@"该语音为 SILK 格式（通常来自微信），服务器无法识别。\n请导入普通 MP3 文件，插件会自动转换为兼容格式。"
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
    }

    if (audioData) {
        verifyAndSendVoice(audioData, duration, self.currentChannel);
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}
@end

#pragma mark - 4. 主面板：MP3 导入净化引擎 + Plist 展示

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
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入MP3/Plist" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 60;
    [self.view addSubview:self.tableView];

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        if ([file hasSuffix:@".plist"]) {
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

    NSString *ext = fileURL.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"mp3"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"正在提纯转换..."
            message:@"正在将 MP3 净化为专属 Plist 语音包"
            preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:nil];

        [self convertMP3ToSafePlist:fileURL completion:^{
            [alert dismissViewControllerAnimated:YES completion:^{
                [self loadVoicePacks];
                UIAlertController *success = [UIAlertController alertControllerWithTitle:@"转换成功"
                    message:@"MP3 已成功打包为安全的 Plist，发送绝不闪退！"
                    preferredStyle:UIAlertControllerStyleAlert];
                [success addAction:[UIAlertAction actionWithTitle:@"去发送" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:success animated:YES completion:nil];
            }];
        }];
    } else if ([ext isEqualToString:@"plist"]) {
        NSString *destPath = [self.basePath stringByAppendingPathComponent:fileURL.lastPathComponent];
        [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:destPath] error:nil];
        [self loadVoicePacks];
    } else {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"格式错误"
            message:@"请导入 MP3 音乐或 Plist 语音包"
            preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
    }

    if (accessed) [fileURL stopAccessingSecurityScopedResource];
}

#pragma mark - C 语言手写 44 字节标准 WAV 头

- (BOOL)createStrictWavFile:(NSData *)pcmData savePath:(NSString *)savePath {
    if (!pcmData) return NO;
    uint32_t dataSize = (uint32_t)pcmData.length;
    NSMutableData *wavData = [NSMutableData dataWithCapacity:44 + dataSize];

    uint32_t chunkSize = dataSize + 36;
    uint32_t subchunk1Size = 16;
    uint16_t audioFormat = 1; // PCM
    uint16_t numChannels = 1;
    uint32_t sampleRate = 8000;
    uint32_t byteRate = 16000;
    uint16_t blockAlign = 2;
    uint16_t bitsPerSample = 16;

    [wavData appendBytes:"RIFF" length:4];
    [wavData appendBytes:&chunkSize length:4];
    [wavData appendBytes:"WAVEfmt " length:8];
    [wavData appendBytes:&subchunk1Size length:4];
    [wavData appendBytes:&audioFormat length:2];
    [wavData appendBytes:&numChannels length:2];
    [wavData appendBytes:&sampleRate length:4];
    [wavData appendBytes:&byteRate length:4];
    [wavData appendBytes:&blockAlign length:2];
    [wavData appendBytes:&bitsPerSample length:2];
    [wavData appendBytes:"data" length:4];
    [wavData appendBytes:&dataSize length:4];
    [wavData appendData:pcmData];

    return [wavData writeToFile:savePath atomically:YES];
}

#pragma mark - MP3 净化提纯引擎

- (void)convertMP3ToSafePlist:(NSURL *)fileURL completion:(void(^)(void))completion {
    NSString *basePath = self.basePath;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        @try {
            @autoreleasepool {
                AVAudioFile *inFile = [[AVAudioFile alloc] initForReading:fileURL error:nil];
                if (!inFile || inFile.fileFormat.sampleRate == 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(); });
                    return;
                }

                AVAudioFormat *outFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];

                AVAudioFrameCount framesToRead = (AVAudioFrameCount)MIN(inFile.length, inFile.fileFormat.sampleRate * 60.0);
                AVAudioPCMBuffer *inBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inFile.processingFormat frameCapacity:framesToRead];
                [inFile readIntoBuffer:inBuffer frameCount:framesToRead error:nil];

                AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inBuffer.format toFormat:outFormat];
                AVAudioFrameCount outFrames = (AVAudioFrameCount)(framesToRead * (8000.0 / inFile.fileFormat.sampleRate));
                AVAudioPCMBuffer *outBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outFormat frameCapacity:MAX(100, outFrames)];

                __block BOOL inputGiven = NO;
                [converter convertToBuffer:outBuffer error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount p, AVAudioConverterInputStatus *outStatus) {
                    if (inputGiven) { *outStatus = AVAudioConverterInputStatus_EndOfStream; return nil; }
                    inputGiven = YES;
                    *outStatus = AVAudioConverterInputStatus_HaveData;
                    return inBuffer;
                }];

                // 提取纯净 PCM 裸流
                NSData *pcmData = [NSData dataWithBytes:outBuffer.int16ChannelData[0] length:outBuffer.frameLength * 2];
                NSInteger duration = MAX(1, MIN((NSInteger)(framesToRead / inFile.fileFormat.sampleRate), 60));

                // 手写 44 字节标准 WAV 头
                NSString *tmpDir = NSTemporaryDirectory();
                NSString *wavPath = [tmpDir stringByAppendingPathComponent:@"pure_tmp.wav"];
                NSString *amrPath = [tmpDir stringByAppendingPathComponent:@"pure_tmp.amr"];
                [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
                [[NSFileManager defaultManager] removeItemAtPath:amrPath error:nil];
                [self createStrictWavFile:pcmData savePath:wavPath];

                // VoiceConverter 编码（WAV 头干净，不会闪退）
                Class converterCls = NSClassFromString(@"VoiceConverter");
                SEL encSel = NSSelectorFromString(@"EncodeWavToAmr:amrSavePath:sampleRateType:");
                if ([converterCls respondsToSelector:encSel]) {
                    NSMethodSignature *sig = [converterCls methodSignatureForSelector:encSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:converterCls];
                    [inv setSelector:encSel];
                    [inv setArgument:&wavPath atIndex:2];
                    [inv setArgument:&amrPath atIndex:3];
                    int type = 0;
                    [inv setArgument:&type atIndex:4];
                    [inv invoke];
                } else {
                    NSLog(@"[UUUVoiceFun] EncodeWavToAmr 不存在！扫描 VoiceConverter...");
                    dumpMethodsForClass(converterCls, YES);
                }

                NSData *amrData = [NSData dataWithContentsOfFile:amrPath];
                [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
                [[NSFileManager defaultManager] removeItemAtPath:amrPath error:nil];

                if (amrData && amrData.length >= 50) {
                    // 打包为 Plist
                    NSString *name = [[fileURL lastPathComponent] stringByDeletingPathExtension];
                    NSDictionary *voiceItem = @{
                        @"name": name,
                        @"duration": @(duration),
                        @"audioData": amrData
                    };
                    NSString *plistPath = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", name]];
                    [@[voiceItem] writeToFile:plistPath atomically:YES];
                    NSLog(@"[UUUVoiceFun] MP3 提纯成功: %@ (%ld字节, %ld秒)", name, (long)amrData.length, (long)duration);
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] 提纯异常: %@", e);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion();
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.dataSource.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MainCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"MainCell"];
    }
    cell.textLabel.text = self.dataSource[indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *fileName = self.dataSource[indexPath.row];
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:fileName];

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
            for (NSDictionary *item in (NSArray *)plistObj) {
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
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                message:@"该 Plist 文件格式不兼容或为空"
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] Plist解析失败: %@", e); }
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
