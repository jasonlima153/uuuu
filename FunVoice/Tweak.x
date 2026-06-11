#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/runtime.h>

#pragma mark - Forward Declarations
@interface WKConversationInputPanel : UIView
@end

#pragma mark - 1. 核心发送引擎 (NSInvocation + C函数指针双保险)

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
                // 智能判断是类方法还是实例方法，双模式安全调用
                if ([voiceContentClass respondsToSelector:initSel]) {
                    NSMethodSignature *sig = [voiceContentClass methodSignatureForSelector:initSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:voiceContentClass];
                    [inv setSelector:initSel];
                    [inv setArgument:&amrData atIndex:2];
                    [inv setArgument:&duration atIndex:3];
                    [inv setArgument:&dummyWaveform atIndex:4];
                    [inv invoke];
                    [inv getReturnValue:&voiceContent];
                } else {
                    id instance = [voiceContentClass alloc];
                    if ([instance respondsToSelector:initSel]) {
                        NSMethodSignature *sig = [instance methodSignatureForSelector:initSel];
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        [inv setTarget:instance];
                        [inv setSelector:initSel];
                        [inv setArgument:&amrData atIndex:2];
                        [inv setArgument:&duration atIndex:3];
                        [inv setArgument:&dummyWaveform atIndex:4];
                        [inv invoke];
                        [inv getReturnValue:&voiceContent];
                    }
                }
            }

            if (voiceContent) {
                Class sdkClass = NSClassFromString(@"WKSDK");
                id sharedSDK = [sdkClass performSelector:NSSelectorFromString(@"shared")];
                id chatManager = [sharedSDK performSelector:NSSelectorFromString(@"chatManager")];

                if (chatManager) {
                    // C函数指针硬编码，绕过 performSelector 3-arg 限制
                    typedef void (*SendFunc)(id, SEL, id, id);
                    SendFunc sendFunc = (SendFunc)[chatManager methodForSelector:NSSelectorFromString(@"sendMessage:channel:")];
                    sendFunc(chatManager, NSSelectorFromString(@"sendMessage:channel:"), voiceContent, channel);
                    NSLog(@"[UUUVoiceFun] 趣味语音成功投递到发送队列！");
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] 发送层异常拦截: %@", e);
        }
    });
}

#pragma mark - 2. Plist 详情列表页 (带 SILK 格式智能拦截)

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

- (void)close {
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.voiceList.count;
}

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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)sendButtonClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.voiceList.count) return;

    NSDictionary *voiceDict = self.voiceList[row];
    NSData *audioData = voiceDict[@"audioData"];
    NSInteger duration = [voiceDict[@"duration"] integerValue] ?: 1;

    // 智能拦截 SILK 格式，阻止卡死和红叹号
    if (audioData.length > 5) {
        const char *bytes = audioData.bytes;
        if (bytes[0] == 0x02 && bytes[1] == '#' && bytes[2] == '!') {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"格式不支持"
                                                                           message:@"该 plist 包含微信 SILK 格式，UUUTalk 不支持发送！\n\n请直接下载并导入普通的 .mp3 语音文件，插件会自动无损转码发送。"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
    }

    if (audioData) {
        sendAMRVoiceData(audioData, duration, self.currentChannel);
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}
@end

#pragma mark - 3. 万能主面板与 MP3 极致安全转码

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
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

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

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.dataSource.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"MainCell"];
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
        @try {
            id plistObj = [NSDictionary dictionaryWithContentsOfFile:fullPath] ?: [NSArray arrayWithContentsOfFile:fullPath];
            NSMutableArray *normalizedList = [NSMutableArray array];

            if ([plistObj isKindOfClass:[NSDictionary class]]) {
                [plistObj enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
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
            }
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] Plist解析失败: %@", e); }
    } else if ([fileName hasSuffix:@".mp3"] || [fileName hasSuffix:@".amr"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self processSingleAudio:fullPath];
        });
    }
}

// 【核心修复】：彻底解决 MP3 转码卡死（死循环）问题
- (void)processSingleAudio:(NSString *)filePath {
    __block NSData *amrData = nil;
    __block NSInteger duration = 1;

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

                __block BOOL hasSuppliedData = NO;
                [converter convertToBuffer:outBuffer error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
                    if (hasSuppliedData) {
                        *outStatus = AVAudioConverterInputStatus_EndOfStream; // 终结死循环
                        return nil;
                    }
                    hasSuppliedData = YES;
                    *outStatus = AVAudioConverterInputStatus_HaveData;
                    return buffer;
                }];
                [outputFile writeFromBuffer:outBuffer error:nil];

                duration = MAX(1, MIN((NSInteger)(inputFile.length / inputFile.fileFormat.sampleRate), 60));

                // 文件关闭后再传给底层C++库
                outputFile = nil;

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
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] MP3底层转码异常: %@", e); }
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

#pragma mark - 4. 悬浮窗拖拽与点击 (UIButton Category)

@interface UIButton (UUUVoiceFun)
- (void)uuu_handlePan:(UIPanGestureRecognizer *)pan;
- (void)uuu_openVoicePanel;
@end

@implementation UIButton (UUUVoiceFun)

- (void)uuu_handlePan:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    CGPoint translation = [pan translationInView:btn.superview];
    CGPoint newCenter = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    newCenter.x = MAX(24, MIN(newCenter.x, [UIScreen mainScreen].bounds.size.width - 24));
    newCenter.y = MAX(100, MIN(newCenter.y, [UIScreen mainScreen].bounds.size.height - 100));
    btn.center = newCenter;
    [pan setTranslation:CGPointZero inView:btn.superview];
}

- (void)uuu_openVoicePanel {
    UIViewController *chatVC = objc_getAssociatedObject(self, "chatVC");
    if (!chatVC) return;
    id channel = [chatVC valueForKey:@"channel"];
    if (channel) {
        UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
        vc.currentChannel = channel;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [chatVC presentViewController:nav animated:YES completion:nil];
    }
}

@end

#pragma mark - 5. Hook: 绑定 WKConversationInputPanel (已验证存在的类)

%group UUUVoiceFunHooks

%hook WKConversationInputPanel

- (void)didMoveToWindow {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIResponder *responder = self;
        UIViewController *chatVC = nil;
        while ((responder = [responder nextResponder])) {
            if ([responder isKindOfClass:[UIViewController class]]) {
                chatVC = (UIViewController *)responder;
                break;
            }
        }

        if (self.window && chatVC) {
            if ([chatVC.view viewWithTag:888999]) return;

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

            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:floatBtn action:@selector(uuu_handlePan:)];
            [floatBtn addGestureRecognizer:pan];
            [floatBtn addTarget:floatBtn action:@selector(uuu_openVoicePanel) forControlEvents:UIControlEventTouchUpInside];

            objc_setAssociatedObject(floatBtn, "chatVC", chatVC, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [chatVC.view addSubview:floatBtn];
            [chatVC.view bringSubviewToFront:floatBtn];
        }
    });
}

%end

%end

#pragma mark - 6. 模块初始化

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
