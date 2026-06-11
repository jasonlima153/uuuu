#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/runtime.h>

#pragma mark - Forward Declarations
@interface WKConversationInputPanel : UIView
@end

#pragma mark - 1. 核心发送引擎 (C函数指针硬编码，绝对防闪退)

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

            if (voiceContentClass && [voiceContentClass respondsToSelector:initSel]) {
                typedef id (*InitFunc)(id, SEL, id, NSInteger, id);
                InitFunc initFunc = (InitFunc)[voiceContentClass methodForSelector:initSel];
                id voiceContent = initFunc(voiceContentClass, initSel, amrData, duration, dummyWaveform);

                if (voiceContent) {
                    Class sdkClass = NSClassFromString(@"WKSDK");
                    id sharedSDK = [sdkClass performSelector:NSSelectorFromString(@"shared")];
                    id chatManager = [sharedSDK performSelector:NSSelectorFromString(@"chatManager")];

                    if (chatManager) {
                        typedef void (*SendFunc)(id, SEL, id, id);
                        SendFunc sendFunc = (SendFunc)[chatManager methodForSelector:NSSelectorFromString(@"sendMessage:channel:")];
                        sendFunc(chatManager, NSSelectorFromString(@"sendMessage:channel:"), voiceContent, channel);
                        NSLog(@"[UUUVoiceFun] 核心通道发送成功！");
                    }
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] 发送层崩溃拦截: %@", e);
        }
    });
}

#pragma mark - 2. 语音详情列表页 (带右侧蓝色发送按钮)

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
    NSInteger duration = [voiceDict[@"duration"] integerValue];

    if (audioData) {
        sendAMRVoiceData(audioData, duration, self.currentChannel);
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}
@end

#pragma mark - 3. 万能主面板 (精准适配字典型 Plist: {"语音名": "Base64"})

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
                // 精准通杀 {"语音名" : "Base64字符串"} 结构 (爱情公寓.plist 格式)
                [plistObj enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
                    NSMutableDictionary *normItem = [NSMutableDictionary dictionary];
                    normItem[@"name"] = key;
                    normItem[@"duration"] = @(2); // 字典包无时长字段，默认 2 秒

                    if ([obj isKindOfClass:[NSString class]]) {
                        normItem[@"audioData"] = [[NSData alloc] initWithBase64EncodedString:obj options:0];
                    } else if ([obj isKindOfClass:[NSData class]]) {
                        normItem[@"audioData"] = obj;
                    }

                    if (normItem[@"audioData"]) [normalizedList addObject:normItem];
                }];
            } else if ([plistObj isKindOfClass:[NSArray class]]) {
                // 兼容数组结构 [{"name":"xx", "audioData":"base64"}]
                for (NSDictionary *item in plistObj) {
                    if ([item isKindOfClass:[NSDictionary class]]) {
                        NSMutableDictionary *normItem = [NSMutableDictionary dictionary];
                        normItem[@"name"] = item[@"name"] ?: item[@"title"] ?: @"未命名";
                        normItem[@"duration"] = item[@"duration"] ?: item[@"time"] ?: @(2);
                        id rawData = item[@"audioData"] ?: item[@"voice"] ?: item[@"data"] ?: item[@"amr"];
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
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] Plist解析失败: %@", e);
        }
    } else if ([fileName hasSuffix:@".mp3"] || [fileName hasSuffix:@".amr"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self processSingleAudio:fullPath];
        });
    }
}

- (void)processSingleAudio:(NSString *)filePath {
    NSData *amrData = nil;
    NSInteger duration = 2;

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
                    typedef int (*EncodeFunc)(id, SEL, NSString*, NSString*, int);
                    EncodeFunc func = (EncodeFunc)[converterCls methodForSelector:encSel];
                    func(converterCls, encSel, wavPath, amrPath, 0);
                    amrData = [NSData dataWithContentsOfFile:amrPath];
                }
            }
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] MP3转换异常: %@", e); }
    } else {
        amrData = [NSData dataWithContentsOfFile:filePath];
    }

    if (amrData) {
        sendAMRVoiceData(amrData, duration, self.currentChannel);
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
