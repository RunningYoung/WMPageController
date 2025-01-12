//
//  WMPageController.m
//  WMPageController
//
//  Created by Mark on 15/6/11.
//  Copyright (c) 2015年 yq. All rights reserved.
//

#import "WMPageController.h"
#import "WMPageConst.h"
@interface WMPageController () <WMMenuViewDelegate,UIScrollViewDelegate>{
    CGFloat viewHeight;
    CGFloat viewWidth;
    BOOL    animate;
}
@property (nonatomic, strong, readwrite) UIViewController *currentViewController;
@property (nonatomic, weak, readwrite) WMMenuView *menuView;
@property (nonatomic, weak, readwrite) UIScrollView *scrollView;

// 用于记录子控制器view的frame，用于 scrollView 上的展示的位置
@property (nonatomic, strong) NSMutableArray *childViewFrames;
// 当前展示在屏幕上的控制器，方便在滚动的时候读取 (避免不必要计算)
@property (nonatomic, strong) NSMutableDictionary *displayVC;
// 用于记录销毁的viewController的位置 (如果它是某一种scrollView的Controller的话)
@property (nonatomic, strong) NSMutableDictionary *posRecords;
@end

@implementation WMPageController
#pragma mark - Lazy Loading
- (NSMutableDictionary *)posRecords{
    if (_posRecords == nil) {
        _posRecords = [[NSMutableDictionary alloc] init];
    }
    return _posRecords;
}
- (NSMutableDictionary *)displayVC{
    if (_displayVC == nil) {
        _displayVC = [NSMutableDictionary dictionary];
    }
    return _displayVC;
}
#pragma mark - Public Methods
- (instancetype)initWithViewControllerClasses:(NSArray *)classes andTheirTitles:(NSArray *)titles {
    if (self = [super init]) {
        self.viewControllerClasses = [NSArray arrayWithArray:classes];
        self.titles = titles;

        [self setup];
    }
    return self;
}
- (instancetype)init {
    if (self = [super init]) {
        [self setup];
    }
    return self;
}
- (void)setItemsWidths:(NSArray *)itemsWidths{
    if (itemsWidths.count != self.titles.count) {
        return;
    }
    _itemsWidths = itemsWidths;
}
- (void)setSelectIndex:(int)selectIndex {
    _selectIndex = selectIndex;
    if (self.menuView) {
        [self.menuView selectItemAtIndex:selectIndex];
    }
}
#pragma mark - Private Methods
// 当子控制器init完成时发送通知
- (void)postFinishInitNotificationWithIndex:(int)index{
    if (!self.postNotification) return;
    NSDictionary *info = @{
                           @"index":@(index),
                           @"title":self.titles[index]
                           };
    [[NSNotificationCenter defaultCenter] postNotificationName:WMControllerDidFinishInitNotification
                                                        object:info];
}
// 当子控制器完全展示在user面前时发送通知
- (void)postFullyDisplayedNotificationWithCurrentIndex:(int)index{
    if (!self.postNotification) return;
    NSDictionary *info = @{
                           @"index":@(index),
                           @"title":self.titles[index]
                           };
    [[NSNotificationCenter defaultCenter] postNotificationName:WMControllerDidFullyDisplayedNotification
                                                        object:info];
}
// 初始化一些参数，在init中调用
- (void)setup{
    // title
    self.titleSizeSelected = WMTitleSizeSelected;
    self.titleColorSelected = WMTitleColorSelected;
    self.titleSizeNormal = WMTitleSizeNormal;
    self.titleColorNormal = WMTitleColorNormal;
    // menu
    self.menuBGColor = WMMenuBGColor;
    self.menuHeight = WMMenuHeight;
    self.menuItemWidth = WMMenuItemWidth;
}
// 包括宽高，子控制器视图frame
- (void)calculateSize{
    viewHeight = self.view.frame.size.height - self.menuHeight;
    viewWidth = self.view.frame.size.width;
    // 重新计算各个控制器视图的宽高
    _childViewFrames = [NSMutableArray array];
    for (int i = 0; i < self.viewControllerClasses.count; i++) {
        CGRect frame = CGRectMake(i*viewWidth, 0, viewWidth, viewHeight);
        [_childViewFrames addObject:[NSValue valueWithCGRect:frame]];
    }
}
- (void)addScrollView{
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    
    scrollView.pagingEnabled = YES;
    scrollView.backgroundColor = [UIColor whiteColor];
    scrollView.delegate = self;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.bounces = NO;
    
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;
}
- (void)addMenuView{
    CGRect frame = CGRectMake(0, 0, self.view.frame.size.width, self.menuHeight);
    WMMenuView *menuView = [[WMMenuView alloc] initWithFrame:frame buttonItems:self.titles backgroundColor:self.menuBGColor norSize:self.titleSizeNormal selSize:self.titleSizeSelected norColor:self.titleColorNormal selColor:self.titleColorSelected];
    menuView.delegate = self;
    menuView.style = self.menuViewStyle;
    if (self.titleFontName) {
        menuView.fontName = self.titleFontName;
    }
    if (self.progressColor) {
        menuView.lineColor = self.progressColor;
    }
    [self.view addSubview:menuView];
    self.menuView = menuView;
    // 如果设置了初始选择的序号，那么选中该item
    if (self.selectIndex != 0) {
        [self.menuView selectItemAtIndex:self.selectIndex];
    }
}
- (void)layoutChildViewControllers{
    int currentPage = (int)self.scrollView.contentOffset.x / viewWidth;
    int start,end;
    if (currentPage == 0) {
        start = currentPage;
        end = currentPage + 1;
    }else if (currentPage + 1 == self.viewControllerClasses.count){
        start = currentPage - 1;
        end = currentPage;
    }else{
        start = currentPage - 1;
        end = currentPage + 1;
    }
    for (int i = start; i <= end; i++) {
        CGRect frame = [self.childViewFrames[i] CGRectValue];
        UIViewController *vc = [self.displayVC objectForKey:@(i)];
        if ([self isInScreen:frame]) {
            if (vc == nil) {
                // vc在视野中了，但不存在，创建并添加到display
                [self addViewControllerAtIndex:i];
            }
        }else{
            if (vc) {
                // vc不在视野中且存在，移除他
                [self removeViewController:vc atIndex:i];
            }
        }
    }
}
// 添加子控制器
- (void)addViewControllerAtIndex:(int)index{
    Class vcClass = self.viewControllerClasses[index];
    UIViewController *viewController = [[vcClass alloc] init];
    viewController.view.frame = [self.childViewFrames[index] CGRectValue];
    [self addChildViewController:viewController];
    [viewController didMoveToParentViewController:self];
    [self.scrollView addSubview:viewController.view];
    [self.displayVC setObject:viewController forKey:@(index)];
    [self postFinishInitNotificationWithIndex:index];
    
    self.currentViewController = viewController;
    
    [self backToPositionIfNeeded:viewController atIndex:index];
}
// 移除控制器，且从display中移除
- (void)removeViewController:(UIViewController *)viewController atIndex:(NSInteger)index{
    [self rememberPositionIfNeeded:viewController atIndex:index];
    [viewController.view removeFromSuperview];
    [viewController willMoveToParentViewController:nil];
    [viewController removeFromParentViewController];
    [self.displayVC removeObjectForKey:@(index)];
}
- (void)backToPositionIfNeeded:(UIViewController *)controller atIndex:(NSInteger)index{
    if (!self.rememberLocation) return;
    UIScrollView *scrollView = [self isKindOfScrollViewController:controller];
    if (scrollView) {
        NSValue *pointValue = self.posRecords[@(index)];
        if (pointValue) {
            CGPoint pos = [pointValue CGPointValue];
            // 奇怪的现象，我发现collectionView的contentSize是 {0, 0};
            [scrollView setContentOffset:pos];
        }
    }
}
- (void)rememberPositionIfNeeded:(UIViewController *)controller atIndex:(NSInteger)index{
    if (!self.rememberLocation) return;
    UIScrollView *scrollView = [self isKindOfScrollViewController:controller];
    if (scrollView) {
        CGPoint pos = scrollView.contentOffset;
        self.posRecords[@(index)] = [NSValue valueWithCGPoint:pos];
    }
}
- (UIScrollView *)isKindOfScrollViewController:(UIViewController *)controller{
    UIScrollView *scrollView = nil;
    if ([controller.view isKindOfClass:[UIScrollView class]]) {
        // Controller的view是scrollView的子类(UITableViewController/UIViewController替换view为scrollView)
        scrollView = (UIScrollView *)controller.view;
    }else if (controller.view.subviews.count >= 1) {
        // Controller的view的subViews[0]存在且是scrollView的子类，并且frame等与view得frame(UICollectionViewController/UIViewController添加UIScrollView)
        UIView *view = controller.view.subviews[0];
        if ([view isKindOfClass:[UIScrollView class]]) {
            scrollView = (UIScrollView *)view;
        }
    }
    return scrollView;
}
- (BOOL)isInScreen:(CGRect)frame{
    CGFloat x = frame.origin.x;
    CGFloat ScreenWidth = self.scrollView.frame.size.width;
    
    CGFloat contentOffsetX = self.scrollView.contentOffset.x;
    if (CGRectGetMaxX(frame) > contentOffsetX && x-contentOffsetX < ScreenWidth) {
        return YES;
    }else{
        return NO;
    }
}
- (void)resetMenuView{
    WMMenuView *oldMenuView = self.menuView;
    [self addMenuView];
    [oldMenuView removeFromSuperview];
}
#pragma mark - Life Cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.edgesForExtendedLayout = UIRectEdgeNone;
    
    [self addScrollView];
    [self addMenuView];
    
    [self addViewControllerAtIndex:0];
}
- (void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    // 计算宽高及子控制器的视图frame
    [self calculateSize];
    CGRect scrollFrame = CGRectMake(0, self.menuHeight, viewWidth, viewHeight);
    self.scrollView.frame = scrollFrame;
    self.scrollView.contentSize = CGSizeMake(self.titles.count*viewWidth, viewHeight);
    [self.scrollView setContentOffset:CGPointMake(self.selectIndex*viewWidth, 0)];
    self.currentViewController.view.frame = [self.childViewFrames[self.selectIndex] CGRectValue];
    
    [self resetMenuView];

    [self.view layoutIfNeeded];
}
- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [self postFullyDisplayedNotificationWithCurrentIndex:self.selectIndex];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    [self.posRecords removeAllObjects];
    self.posRecords = nil;
}
#pragma mark - UIScrollView Delegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView{
    [self layoutChildViewControllers];
    if (animate) {
        CGFloat width = scrollView.frame.size.width;
        CGFloat contentOffsetX = scrollView.contentOffset.x;
        CGFloat rate = contentOffsetX / width;
        [self.menuView slideMenuAtProgress:rate];
    }
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView{
    animate = YES;
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView{
    _selectIndex = (int)scrollView.contentOffset.x / viewWidth;
    [self postFullyDisplayedNotificationWithCurrentIndex:self.selectIndex];
}
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView{
    [self postFullyDisplayedNotificationWithCurrentIndex:self.selectIndex];
}
#pragma mark - WMMenuView Delegate
- (void)menuView:(WMMenuView *)menu didSelesctedIndex:(NSInteger)index currentIndex:(NSInteger)currentIndex{
    NSInteger gap = (NSInteger)labs(index - currentIndex);
    animate = NO;
    CGPoint targetP = CGPointMake(viewWidth*index, 0);
    
    [self.scrollView setContentOffset:targetP animated:gap > 1?NO:self.pageAnimatable];
    if (gap > 1 || !self.pageAnimatable) {
        [self postFullyDisplayedNotificationWithCurrentIndex:(int)index];
        // 由于不触发-scrollViewDidScroll: 手动清除控制器..
        UIViewController *vc = [self.displayVC objectForKey:@(currentIndex)];
        if (vc) {
            [self removeViewController:vc atIndex:currentIndex];
        }
    }
    _selectIndex = (int)index;
}
- (CGFloat)menuView:(WMMenuView *)menu widthForItemAtIndex:(NSInteger)index{
    if (self.itemsWidths) {
        return [self.itemsWidths[index] floatValue];
    }
    return self.menuItemWidth;
}
@end
