#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MobileCoreServices/MobileCoreServices.h>

#pragma mark - Forward Declarations
@interface WKConversationInputPanel : UIView
@end

#pragma mark - 1. 核心发送引擎 (绝对防闪退)

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
            id voiceContent = nil;
            SEL initSel = NSSelectorFromString(@"initWithData:second:waveform:");
            if ([voiceContentClass respondsToSelector:initSel]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                voiceContent = [voiceContentClass performSelector:initSel withObject:amrData withObject:@(duration) withObject:dummyWaveform];
                #pragma clang diagnostic pop
            }

            if (voiceContent) {
                Class sdkClass = NSClassFromString(@"WKSDK");
                id sharedSDK = [sdkClass performSelector:NSSelectorFromString(@"shared")];
                id chatManager = [sharedSDK performSelector:NSSelectorFromString(@"chatManager")];

                if (chatManager) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [chatManager performSelector:NSSelectorFromString(@"sendMessage:channel:") withObject:voiceContent withObject:channel];
                    #pragma clang diagnostic pop
                    NSLog(@"[UUUVoiceFun] 趣味语音发送成功！");
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] 发送崩溃拦截: %@", e);
        }
    });
}

#pragma mark - 2. Plist 详情合集列表页

@interface UUUVoiceFunDetailViewController : UITableViewController
@property (nonatomic, strong) NSArray *voiceList;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 返回" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
}

- (void)close {
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.voiceList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DetailCell"];

    NSDictionary *voiceDict = self.voiceList[indexPath.row];
    cell.textLabel.text = voiceDict[@"name"] ?: [NSString stringWithFormat:@"语音 %ld", (long)indexPath.row + 1];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 秒", voiceDict[@"duration"] ?: @"?"];
    cell.imageView.image = [UIImage systemImageNamed:@"play.circle"];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *voiceDict = self.voiceList[indexPath.row];
    NSData *audioData = voiceDict[@"audioData"];
    NSInteger duration = [voiceDict[@"duration"] integerValue] ?: 1;

    if (audioData) {
        sendAMRVoiceData(audioData, duration, self.currentChannel);
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        NSLog(@"[UUUVoiceFun] 无法读取音频数据！");
    }
}
@end

#pragma mark - 3. 趣味语音主面板

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
    [self.view addSubview:self.tableView];

    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, self.view.bounds.size.width - 30, 80)];
    footerLabel.numberOfLines = 0;
    footerLabel.font = [UIFont systemFontOfSize:12];
    footerLabel.textColor = [UIColor grayColor];
    footerLabel.text = @"温馨提示：沙盒路径/Documents/趣味语音包/，可以通过[导入语音]来添加 mp3 或 plist合集。";
    self.tableView.tableFooterView = footerLabel;

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        if ([file hasSuffix:@".plist"] || [file hasSuffix:@".mp3"] || [file hasSuffix:@".amr"]) {
            [self.dataSource addObject:file];
        }
    }
    [self.tableView reloadData];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)importVoice {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data", @"public.audio"] inMode:UIDocumentPickerModeImport];
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.dataSource.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"本地语音专区"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    NSString *fileName = self.dataSource[indexPath.row];
    cell.textLabel.text = fileName;

    if ([fileName hasSuffix:@".plist"]) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"music.note"];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *fileName = self.dataSource[indexPath.row];
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:fileName];

    if ([fileName hasSuffix:@".plist"]) {
        id plistObj = [NSArray arrayWithContentsOfFile:fullPath] ?: [NSDictionary dictionaryWithContentsOfFile:fullPath];
        NSArray *list = nil;

        if ([plistObj isKindOfClass:[NSArray class]]) {
            list = plistObj;
        } else if ([plistObj isKindOfClass:[NSDictionary class]]) {
            list = plistObj[@"voices"] ?: @[plistObj];
        }

        if (list.count > 0) {
            UUUVoiceFunDetailViewController *detailVC = [[UUUVoiceFunDetailViewController alloc] init];
            detailVC.voiceList = list;
            detailVC.currentChannel = self.currentChannel;
            detailVC.title = [fileName stringByDeletingPathExtension];
            [self.navigationController pushViewController:detailVC animated:YES];
        }
    } else if ([fileName hasSuffix:@".mp3"] || [fileName hasSuffix:@".amr"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self processAndSendSingleAudio:fullPath];
        });
    }
}

#pragma mark - 单曲转码防闪退处理
- (void)processAndSendSingleAudio:(NSString *)filePath {
    NSData *amrData = nil;
    NSInteger duration = 1;

    if ([filePath hasSuffix:@".mp3"]) {
        NSString *wavPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmp_fun.wav"];
        NSString *amrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmp_fun.amr"];
        [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:amrPath error:nil];

        @try {
            NSError *error = nil;
            AVAudioFile *inputFile = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:filePath] error:&error];
            if (inputFile) {
                AVAudioFormat *outputFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];
                AVAudioFile *outputFile = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:wavPath] settings:outputFormat.settings error:&error];
                AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inputFile.processingFormat frameCapacity:(AVAudioFrameCount)inputFile.length];
                [inputFile readIntoBuffer:buffer error:nil];

                AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inputFile.processingFormat toFormat:outputFormat];
                AVAudioPCMBuffer *outBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outputFormat frameCapacity:(AVAudioFrameCount)(buffer.frameCapacity * (8000.0 / inputFile.fileFormat.sampleRate))];
                [converter convertToBuffer:outBuffer error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
                    *outStatus = AVAudioConverterInputStatus_HaveData;
                    return buffer;
                }];
                [outputFile writeFromBuffer:outBuffer error:nil];

                duration = MAX(1, MIN((NSInteger)(inputFile.length / inputFile.fileFormat.sampleRate), 60));

                Class converterCls = NSClassFromString(@"VoiceConverter");
                SEL encSel = NSSelectorFromString(@"EncodeWavToAmr:amrSavePath:sampleRateType:");
                if (converterCls && [converterCls respondsToSelector:encSel]) {
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
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] MP3转换崩溃拦截: %@", e);
        }
    } else {
        amrData = [NSData dataWithContentsOfFile:filePath];
    }

    if (amrData) {
        sendAMRVoiceData(amrData, duration, self.currentChannel);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self close];
        });
    }
}
@end

#pragma mark - 4. 全局可移动悬浮窗

@interface UUUFloatingVoiceButton : UIButton
@property (nonatomic, weak) UIViewController *currentChatVC;
+ (instancetype)sharedButton;
@end

@implementation UUUFloatingVoiceButton

+ (instancetype)sharedButton {
    static UUUFloatingVoiceButton *btn = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        btn = [UUUFloatingVoiceButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 70, 300, 50, 50);
        btn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.8];
        btn.layer.cornerRadius = 25;
        btn.layer.shadowColor = [UIColor blackColor].CGColor;
        btn.layer.shadowOpacity = 0.4;
        btn.layer.shadowOffset = CGSizeMake(0, 2);
        [btn setTitle:@"\U0001F3B5" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:24];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];
        [btn addTarget:btn action:@selector(btnClicked) forControlEvents:UIControlEventTouchUpInside];
    });
    return btn;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    newCenter.x = MAX(25, MIN(newCenter.x, [UIScreen mainScreen].bounds.size.width - 25));
    newCenter.y = MAX(100, MIN(newCenter.y, [UIScreen mainScreen].bounds.size.height - 100));
    self.center = newCenter;
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)btnClicked {
    if (!self.currentChatVC) return;
    id channel = [self.currentChatVC valueForKey:@"channel"];
    if (channel) {
        UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
        vc.currentChannel = channel;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self.currentChatVC presentViewController:nav animated:YES completion:nil];
    }
}
@end

#pragma mark - 5. 生命周期 Hook (解决幽灵悬浮窗与崩溃)

%group UUUVoiceFunHooks

%hook WKConversationInputPanel

- (void)didMoveToWindow {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *chatVC = nil;
        UIResponder *responder = self;
        while ((responder = [responder nextResponder])) {
            if ([responder isKindOfClass:[UIViewController class]]) {
                chatVC = (UIViewController *)responder;
                break;
            }
        }

        UUUFloatingVoiceButton *btn = [UUUFloatingVoiceButton sharedButton];

        if (self.window && chatVC) {
            btn.currentChatVC = chatVC;
            if (btn.superview != chatVC.view) {
                [btn removeFromSuperview];
                [chatVC.view addSubview:btn];
                [chatVC.view bringSubviewToFront:btn];
            }
            btn.hidden = NO;
        } else {
            btn.hidden = YES;
        }
    });
}

%end

%end

#pragma mark - 6. 模块静态初始化封装

static void initVoiceFunModule_once() {
    static BOOL initialized = NO;
    if (initialized) return;

    if (NSClassFromString(@"WKConversationInputPanel")) {
        NSLog(@"[UUUVoiceFun] 动态激活趣味语音悬浮系统...");
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
