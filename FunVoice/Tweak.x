#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - Forward Declarations
@interface WKConversationVC : UIViewController
@end

// ==========================================
// 原生协议声明
// ==========================================
@protocol UUUTalkCoreProtocols <NSObject>
+ (int)EncodeWavToAmr:(NSString *)wavPath amrSavePath:(NSString *)amrPath sampleRateType:(int)type;
- (instancetype)initWithData:(NSData *)data second:(NSInteger)second waveform:(NSData *)waveform;
+ (id)shared;
- (id)chatManager;
- (void)sendMessage:(id)msg channel:(id)channel;
@end

#pragma mark - 1. 核心发送引擎 (alloc + init 实例方法)

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
            if (voiceContentClass) {
                id<UUUTalkCoreProtocols> allocatedVoice = [voiceContentClass alloc];
                id voiceContent = [allocatedVoice initWithData:amrData second:duration waveform:dummyWaveform];

                Class sdkClass = NSClassFromString(@"WKSDK");
                id<UUUTalkCoreProtocols> sharedSDK = [sdkClass shared];
                id<UUUTalkCoreProtocols> chatManager = [sharedSDK chatManager];

                if (chatManager && voiceContent) {
                    [chatManager sendMessage:voiceContent channel:channel];
                    NSLog(@"[UUUVoiceFun] 趣味语音安全组装并发送成功！");
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] 发送异常拦截: %@", e);
        }
    });
}

#pragma mark - 2. 趣味语音主面板

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
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入MP3" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

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
                    if (converter) {
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

                inFile = nil;
                outFile = nil;

                Class converterCls = NSClassFromString(@"VoiceConverter");
                if (converterCls) {
                    id<UUUTalkCoreProtocols> converterProto = (id<UUUTalkCoreProtocols>)converterCls;
                    [converterProto EncodeWavToAmr:wavPath amrSavePath:amrPath sampleRateType:0];
                    amrData = [NSData dataWithContentsOfFile:amrPath];
                }
            }
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] MP3转码容错拦截: %@", e); }
    } else {
        amrData = [NSData dataWithContentsOfFile:filePath];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (amrData) {
            sendAMRVoiceData(amrData, duration, self.currentChannel);
            [self close];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"解析失败" message:@"MP3文件已损坏或不支持转码" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}
@end

#pragma mark - 3. Hook: WKConversationVC

%group UUUVoiceFunHooks

%hook WKConversationVC

- (void)viewDidLoad {
    %orig;

    // 按钮去重：防止 viewDidLoad 多次调用时创建重复按钮
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
    id channel = [self valueForKey:@"channel"];
    if (channel) {
        UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
        vc.currentChannel = channel;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

%end

%end

#pragma mark - 4. 模块初始化

static void initVoiceFunModule_once() {
    static BOOL initialized = NO;
    if (initialized) return;
    if (NSClassFromString(@"WKConversationVC")) {
        %init(UUUVoiceFunHooks);
        initialized = YES;
    }
}

%ctor {
    if (NSClassFromString(@"WKConversationVC")) {
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
