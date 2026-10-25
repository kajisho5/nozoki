// 撮影用：高精細（2倍表示）の仮想ディスプレイを作り、このプログラムが動いている間だけ置いておく。
// macOS の CoreGraphics にある CGVirtualDisplay（公開されていないクラス）を使う。アプリ本体には含めない。
// ビルド: clang -fobjc-arc -framework Foundation -framework CoreGraphics scripts/hidpi-display.m -o hidpi-display
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain) dispatch_queue_t queue;
@property (retain) NSString *name;
@property unsigned int maxPixelsWide;
@property unsigned int maxPixelsHigh;
@property CGSize sizeInMillimeters;
@property unsigned int productID;
@property unsigned int vendorID;
@property unsigned int serialNum;
@property (copy) void (^terminationHandler)(id, id);
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property unsigned int hiDPI;
@property (retain) NSArray *modes;
@end
@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (readonly) CGDirectDisplayID displayID;
@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    unsigned int w = 1280, h = 800;  // 見た目の大きさ（実際の画素はこの2倍）
    CGVirtualDisplayDescriptor *d = [CGVirtualDisplayDescriptor new];
    d.queue = dispatch_get_main_queue();
    d.name = @"ZipPeek Screenshots";
    d.maxPixelsWide = w * 2;
    d.maxPixelsHigh = h * 2;
    d.sizeInMillimeters = CGSizeMake(286, 179);  // 13インチ相当（2倍表示に選ばれやすい密度）
    d.productID = 0x1234;
    d.vendorID = 0x3456;
    d.serialNum = 0x0001;
    CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:d];
    if (!display) { fprintf(stderr, "仮想ディスプレイを作れない\n"); return 1; }
    CGVirtualDisplaySettings *s = [CGVirtualDisplaySettings new];
    s.hiDPI = 1;
    s.modes = @[ [[CGVirtualDisplayMode alloc] initWithWidth:w * 2 height:h * 2 refreshRate:60],
                 [[CGVirtualDisplayMode alloc] initWithWidth:w height:h refreshRate:60] ];
    if (![display applySettings:s]) { fprintf(stderr, "設定を適用できない\n"); return 1; }
    printf("%u\n", display.displayID);
    fflush(stdout);
    [[NSRunLoop mainRunLoop] run];
  }
  return 0;
}
