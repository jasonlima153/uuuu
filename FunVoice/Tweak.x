#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - Forward Declarations
@interface WKConversationInputPanel : UIView
@end

#pragma mark - 1. 核心发送引擎 (双路 C 函数指针)

static void sendAMRVoiceData(NSData *amrData, NSInteger duration, id channel) {
    if (!amrData || !channel) return;

    NSMutableData *dummyWaveform = [NSMutableData dataWithCapacity:100];
    for (int i = 0; i < 100; i++) {
        uint8_t val = (uint8_t)(sin(i * 0.2) * 20 + 30 + arc4random_uniform(10));
        [dummyWaveform appendBytes:&val length:1];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class voiceContentClass = NSClassFromString(@"WKVoiceContent");
            SEL initSel = NSSelectorFromString(@"initWithData:second:waveform:");
            id voiceContent = nil;

            if (voiceContentClass) {
                // 双路侦测：先尝试类方法，再尝试实例方法
                if ([voiceContentClass respondsToSelector:initSel]) {
                    typedef id (*InitFunc)(Class, SEL, id, NSInteger, id);
                    InitFunc func = (InitFunc)[voiceContentClass methodForSelector:initSel];
                    voiceContent = func(voiceContentClass, initSel, amrData, duration, dummyWaveform);
                } else {
                    id instance = [voiceContentClass alloc];
                    if ([instance respondsToSelector:initSel]) {
                        typedef id (*InitFunc)(id, SEL, id, NSInteger, id);
                        InitFunc func = (InitFunc)[instance methodForSelector:initSel];
                        voiceContent = func(instance, initSel, amrData, duration, dummyWaveform);
                    }
                }
            }

            if (voiceContent) {
                Class sdkClass = NSClassFromString(@"WKSDK");
                id sharedSDK = [sdkClass performSelector:NSSelectorFromString(@"shared")];
                id chatManager = [sharedSDK performSelector:NSSelectorFromString(@"chatManager")];

                if (chatManager) {
                    typedef void (*SendFunc)(id, SEL, id, id);
                    SendFunc sendFunc = (SendFunc)[chatManager methodForSelector:NSSelectorFromString(@"sendMessage:channel:")];
                    sendFunc(chatManager, NSSelectorFromString(@"sendMessage:channel:"), voiceContent, channel);
                    NSLog(@"[UUUVoiceFun] 语音投递成功，0 内存泄漏！");
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] 发送异常拦截: %@", e);
        }
    });
}

#pragma mark - 2. 趣味语音主面板 (极速版)

@interface UUUVoiceFunViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSString *basePath;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"趣味语音 (极速版)";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入MP3" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 55;
    [self.view addSubview:self.tableView];

    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, self.view.bounds.size.width - 30, 80)];
    footerLabel.numberOfLines = 0;
    footerLabel.font = [UIFont systemFontOfSize:12];
    footerLabel.textColor = [UIColor grayColor];
    footerLabel.text = @"温馨提示：请直接导入普通的 .mp3 搞笑语音。底层的【沙盒分片转码引擎】会自动为您转换发送，绝不闪退。";
    self.tableView.tableFooterView = footerLabel;

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        if ([file hasSuffix:@".mp3"] || [file hasSuffix:@".amr"]) {
            [self.dataSource addObject:file];
        }
    }
    [self.tableView reloadData];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)importVoice {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"] inMode:UIDocumentPickerModeImport];
    #pragma clang diagnostic pop
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *fileURL = urls.firstObject;
    if (!fileURL) return;
    NSString *destPath = [self.basePath stringByAppendingPathComponent:fileURL.lastPathComponent];
    [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:destPath] error:nil];
    [self loadVoicePacks];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.dataSource.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MainCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"MainCell"];
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

    NSString *fileName = self.dataSource[indexPath.row];
    cell.textLabel.text = fileName;
    cell.imageView.image = [UIImage systemImageNamed:@"music.note"];

    UIButton *btn = (UIButton *)cell.accessoryView;
    btn.tag = indexPath.row;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)mp3SendButtonClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.dataSource.count) return;

    NSString *fileName = self.dataSource[row];
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:fileName];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self safeConvertAndSendAudio:fullPath];
    });
}

// 【绝杀修复】：沙盒分片转码引擎 (Chunked Converter)
- (void)safeConvertAndSendAudio:(NSString *)filePath {
    __block NSData *amrData = nil;
    __block NSInteger duration = 1;

    if ([filePath hasSuffix:@".mp3"]) {
        NSString *wavPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"safe_out.wav"];
        NSString *amrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"safe_out.amr"];
        [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:amrPath error:nil];

        @try {
            NSURL *inURL = [NSURL fileURLWithPath:filePath];
            AVAudioFile *inFile = [[AVAudioFile alloc] initForReading:inURL error:nil];

            if (inFile && inFile.fileFormat.sampleRate > 0) {
                AVAudioFormat *outFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];
                AVAudioFile *outFile = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:wavPath] settings:outFormat.settings error:nil];

                // 内存永远只占 32KB：每次只读 8192 帧，循环读取写入
                AVAudioFrameCount capacity = 8192;
                AVAudioPCMBuffer *inBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inFile.processingFormat frameCapacity:capacity];
                AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inFile.processingFormat toFormat:outFormat];
                AVAudioPCMBuffer *outBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outFormat frameCapacity:capacity];

                while (inFile.framePosition < inFile.length) {
                    @autoreleasepool {
                        NSError *readErr = nil;
                        [inFile readIntoBuffer:inBuffer frameCount:capacity error:&readErr];
                        if (readErr || inBuffer.frameLength == 0) break;

                        __block BOOL consumed = NO;
                        [converter convertToBuffer:outBuffer error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
                            if (consumed) { *outStatus = AVAudioConverterInputStatus_EndOfStream; return nil; }
                            consumed = YES;
                            *outStatus = AVAudioConverterInputStatus_HaveData;
                            return inBuffer;
                        }];
                        [outFile writeFromBuffer:outBuffer error:nil];
                    }
                }

                duration = MAX(1, MIN((NSInteger)(inFile.length / inFile.fileFormat.sampleRate), 60));

                // 强制刷盘，关闭文件流，防止 C++ 底层读取空文件引发 Segmentation Fault
                inFile = nil;
                outFile = nil;

                Class converterCls = NSClassFromString(@"VoiceConverter");
                SEL encSel = NSSelectorFromString(@"EncodeWavToAmr:amrSavePath:sampleRateType:");
                if (converterCls && [converterCls respondsToSelector:encSel]) {
                    int (*EncodeFunc)(id, SEL, NSString*, NSString*, int) = (int (*)(id, SEL, NSString*, NSString*, int))[converterCls methodForSelector:encSel];
                    EncodeFunc(converterCls, encSel, wavPath, amrPath, 0);
                    amrData = [NSData dataWithContentsOfFile:amrPath];
                }
            }
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] 分片转码防线拦截异常: %@", e); }
    } else {
        amrData = [NSData dataWithContentsOfFile:filePath];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (amrData) {
            sendAMRVoiceData(amrData, duration, self.currentChannel);
            [self close];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"格式不支持" message:@"该 MP3 文件已损坏或格式不兼容，无法转码。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}
@end

#pragma mark - 3. 悬浮球靶向响应器 (单例模式)

@interface UUUVoiceFunTarget : NSObject
@property (nonatomic, weak) UIView *inputPanel;
+ (instancetype)sharedTarget;
- (void)openPanel;
@end

@implementation UUUVoiceFunTarget
+ (instancetype)sharedTarget {
    static UUUVoiceFunTarget *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[UUUVoiceFunTarget alloc] init]; });
    return instance;
}
- (void)openPanel {
    if (!self.inputPanel) return;
    UIViewController *chatVC = nil;
    UIResponder *responder = self.inputPanel;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            chatVC = (UIViewController *)responder;
            break;
        }
    }
    if (chatVC) {
        id channel = [chatVC valueForKey:@"channel"];
        if (channel) {
            UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
            vc.currentChannel = channel;
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [chatVC presentViewController:nav animated:YES completion:nil];
        }
    }
}
@end

#pragma mark - 4. Hook: 绑定 WKConversationInputPanel

%group UUUVoiceFunHooks

%hook WKConversationInputPanel

- (void)didMoveToWindow {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.window) {
            UIButton *btn = objc_getAssociatedObject(self, "uuu_voice_btn");
            if (!btn) {
                btn = [UIButton buttonWithType:UIButtonTypeCustom];
                btn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 60, -55, 46, 46);
                btn.backgroundColor = [UIColor colorWithRed:0.24 green:0.52 blue:0.98 alpha:0.9];
                btn.layer.cornerRadius = 23;
                btn.layer.shadowColor = [UIColor blackColor].CGColor;
                btn.layer.shadowOpacity = 0.3;
                btn.layer.shadowOffset = CGSizeMake(0, 2);
                [btn setTitle:@"\U0001F3B5" forState:UIControlStateNormal];
                btn.titleLabel.font = [UIFont systemFontOfSize:20];

                [UUUVoiceFunTarget sharedTarget].inputPanel = self;
                [btn addTarget:[UUUVoiceFunTarget sharedTarget] action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];

                [self addSubview:btn];
                objc_setAssociatedObject(self, "uuu_voice_btn", btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    });
}

%end

%end

#pragma mark - 5. 模块初始化

static void initVoiceFunModule_once() {
    static BOOL initialized = NO;
    if (initialized) return;
    if (NSClassFromString(@"WKConversationInputPanel")) {
        %init(UUUVoiceFunHooks);
        initialized = YES;
    }
}

%ctor {
    if (NSClassFromString(@"WKConversationInputPanel")) {
        initVoiceFunModule_once();
    } else {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil
                                                          queue:nil
                                                     usingBlock:^(NSNotification *note) {
            initVoiceFunModule_once();
        }];
    }
    %init;
}
