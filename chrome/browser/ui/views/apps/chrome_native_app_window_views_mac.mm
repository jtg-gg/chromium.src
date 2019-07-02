// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "chrome/browser/ui/views/apps/chrome_native_app_window_views_mac.h"

#import <Cocoa/Cocoa.h>

#import "base/mac/scoped_nsobject.h"
#import "base/mac/sdk_forward_declarations.h"
#include "chrome/browser/apps/app_shim/extension_app_shim_handler_mac.h"
#include "chrome/browser/apps/platform_apps/app_window_registry_util.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#import "chrome/browser/ui/views/apps/app_window_native_widget_mac.h"
#import "chrome/browser/ui/views/apps/native_app_window_frame_view_mac.h"
#include "chrome/grit/chromium_strings.h"
#include "chrome/grit/generated_resources.h"
#include "ui/base/l10n/l10n_util_mac.h"
#import "ui/gfx/mac/coordinate_conversion.h"
#import "ui/views_bridge_mac/native_widget_mac_nswindow.h"

// This observer is used to get NSWindow notifications. We need to monitor
// zoom and full screen events to store the correct bounds to Restore() to.
@interface ResizeNotificationObserver : NSObject {
 @private
  // Weak. Owns us.
  ChromeNativeAppWindowViewsMac* nativeAppWindow_;
}
- (id)initForNativeAppWindow:(ChromeNativeAppWindowViewsMac*)nativeAppWindow;
- (void)onWindowWillStartLiveResize:(NSNotification*)notification;
- (void)onWindowWillExitFullScreen:(NSNotification*)notification;
- (void)onWindowDidExitFullScreen:(NSNotification*)notification;
- (void)stopObserving;
@end

@implementation ResizeNotificationObserver

- (id)initForNativeAppWindow:(ChromeNativeAppWindowViewsMac*)nativeAppWindow {
  if ((self = [super init])) {
    nativeAppWindow_ = nativeAppWindow;
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(onWindowWillStartLiveResize:)
               name:NSWindowWillStartLiveResizeNotification
             object:static_cast<ui::BaseWindow*>(nativeAppWindow)
                        ->GetNativeWindow()
                        .GetNativeNSWindow()];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(onWindowWillExitFullScreen:)
               name:NSWindowWillExitFullScreenNotification
             object:static_cast<ui::BaseWindow*>(nativeAppWindow)
                        ->GetNativeWindow()
                        .GetNativeNSWindow()];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(onWindowDidExitFullScreen:)
               name:NSWindowDidExitFullScreenNotification
             object:static_cast<ui::BaseWindow*>(nativeAppWindow)
                        ->GetNativeWindow()
                        .GetNativeNSWindow()];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(onWindowDidResize:)
               name:NSWindowDidResizeNotification
             object:static_cast<ui::BaseWindow*>(nativeAppWindow)
                        ->GetNativeWindow()
                        .GetNativeNSWindow()];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(onWindowWillEnterFullScreen:)
               name:NSWindowWillEnterFullScreenNotification
             object:static_cast<ui::BaseWindow*>(nativeAppWindow)
                        ->GetNativeWindow()
                        .GetNativeNSWindow()];
  }
  return self;
}

- (void)onWindowWillStartLiveResize:(NSNotification*)notification {
  nativeAppWindow_->OnWindowWillStartLiveResize();
}

- (void)onWindowWillExitFullScreen:(NSNotification*)notification {
  nativeAppWindow_->OnWindowWillExitFullScreen();
}

- (void)onWindowDidExitFullScreen:(NSNotification*)notification {
  nativeAppWindow_->OnWindowDidExitFullScreen();
}

- (void)onWindowDidResize:(NSNotification*)notification {
  nativeAppWindow_->OnWindowDidResize();
}

- (void)onWindowWillEnterFullScreen:(NSNotification*)notification {
  nativeAppWindow_->OnWindowWillEnterFullScreen();
}

- (void)stopObserving {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  nativeAppWindow_ = nullptr;
}

@end

namespace {

bool NSWindowIsMaximized(NSWindow* window) {
  // -[NSWindow isZoomed] only works if the zoom button is enabled.
  if ([[window standardWindowButton:NSWindowZoomButton] isEnabled])
    return [window isZoomed];

  // We don't attempt to distinguish between a window that has been explicitly
  // maximized versus one that has just been dragged by the user to fill the
  // screen. This is the same behavior as -[NSWindow isZoomed] above.
  return NSEqualRects([window frame], [[window screen] visibleFrame]);
}

}  // namespace

typedef views::NativeWidgetMac NativeWidgetMac;

ChromeNativeAppWindowViewsMac::ChromeNativeAppWindowViewsMac() {}

ChromeNativeAppWindowViewsMac::~ChromeNativeAppWindowViewsMac() {
  [nswindow_observer_ stopObserving];
}

void ChromeNativeAppWindowViewsMac::OnWindowWillStartLiveResize() {
  if (!NSWindowIsMaximized(GetNativeWindow().GetNativeNSWindow()) &&
      !in_fullscreen_transition_) {
    bounds_before_maximize_ = [GetNativeWindow().GetNativeNSWindow() frame];
  }
}

TitleBarStyle ChromeNativeAppWindowViewsMac::title_bar_style() const {
  const NativeWidgetMac* widget_mac = static_cast<const NativeWidgetMac*>(widget()->native_widget());
  return widget_mac->title_bar_style();
}

void ChromeNativeAppWindowViewsMac::title_bar_style(TitleBarStyle style) {
  NativeWidgetMac* widget_mac = static_cast<NativeWidgetMac*>(widget()->native_widget());
  widget_mac->title_bar_style(style);
}

void ChromeNativeAppWindowViewsMac::OnWindowWillExitFullScreen() {
  in_fullscreen_transition_ = true;
  if (title_bar_style() == TitleBarStyle::HIDDEN_INSET) {
    base::scoped_nsobject<NSToolbar> toolbar(
        [[NSToolbar alloc] initWithIdentifier:@"titlebarStylingToolbar"]);
    [toolbar setShowsBaselineSeparator:NO];
    [GetNativeWindow().GetNativeNSWindow() setToolbar:toolbar];
  }
}

void ChromeNativeAppWindowViewsMac::OnWindowDidExitFullScreen() {
  in_fullscreen_transition_ = false;
}

void ChromeNativeAppWindowViewsMac::OnWindowWillEnterFullScreen() {
  if (title_bar_style() == TitleBarStyle::HIDDEN_INSET) {
    [GetNativeWindow().GetNativeNSWindow() setToolbar:nil];
  }
}

void ChromeNativeAppWindowViewsMac::OnWindowDidResize() {
  Adjust_Hidden_Inset_Buttons();
}

void ChromeNativeAppWindowViewsMac::OnBeforeWidgetInit(
    const extensions::AppWindow::CreateParams& create_params,
    views::Widget::InitParams* init_params,
    views::Widget* widget) {
  DCHECK(!init_params->native_widget);
  init_params->remove_standard_frame = IsFrameless();
  NativeWidgetMac* widget_mac = new AppWindowNativeWidgetMac(widget, this);
  init_params->native_widget = widget_mac;

  if (create_params.title_bar_style == "hidden")
    widget_mac->title_bar_style(TitleBarStyle::HIDDEN);
  else if (!std::strncmp(create_params.title_bar_style.c_str(), "hidden-inset", 12)) {
    widget_mac->title_bar_style(TitleBarStyle::HIDDEN_INSET);
    sscanf(create_params.title_bar_style.c_str()+13, "%lf,%lf", &window_buttons_offset_.x, &window_buttons_offset_.y);
  }

  ChromeNativeAppWindowViews::OnBeforeWidgetInit(create_params, init_params,
                                                 widget);
}

views::NonClientFrameView*
ChromeNativeAppWindowViewsMac::CreateStandardDesktopAppFrame() {
  return new NativeAppWindowFrameViewMac(widget(), this);
}

views::NonClientFrameView*
ChromeNativeAppWindowViewsMac::CreateNonStandardAppFrame() {
  return new NativeAppWindowFrameViewMac(widget(), this);
}

bool ChromeNativeAppWindowViewsMac::IsMaximized() const {
  return !IsMinimized() && !IsFullscreen() &&
         NSWindowIsMaximized(GetNativeWindow().GetNativeNSWindow());
}

gfx::Rect ChromeNativeAppWindowViewsMac::GetRestoredBounds() const {
  if (NSWindowIsMaximized(GetNativeWindow().GetNativeNSWindow()))
    return gfx::ScreenRectFromNSRect(bounds_before_maximize_);

  return ChromeNativeAppWindowViews::GetRestoredBounds();
}

void ChromeNativeAppWindowViewsMac::Show() {
  UnhideWithoutActivation();
  ChromeNativeAppWindowViews::Show();
  Adjust_Hidden_Inset_Buttons();
}

void ChromeNativeAppWindowViewsMac::ShowInactive() {
  if (is_hidden_with_app_)
    return;

  ChromeNativeAppWindowViews::ShowInactive();
}

void ChromeNativeAppWindowViewsMac::Activate() {
  UnhideWithoutActivation();
  ChromeNativeAppWindowViews::Activate();
}

void ChromeNativeAppWindowViewsMac::Maximize() {
  if (IsFullscreen())
    return;

  NSWindow* window = GetNativeWindow().GetNativeNSWindow();
  if (!NSWindowIsMaximized(window))
    [window setFrame:[[window screen] visibleFrame] display:YES animate:YES];

  if (IsMinimized())
    [window deminiaturize:nil];
}

void ChromeNativeAppWindowViewsMac::Restore() {
  NSWindow* window = GetNativeWindow().GetNativeNSWindow();
  if (NSWindowIsMaximized(window))
    [window setFrame:bounds_before_maximize_ display:YES animate:YES];

  ChromeNativeAppWindowViews::Restore();
}

void ChromeNativeAppWindowViewsMac::FlashFrame(bool flash) {
  apps::ExtensionAppShimHandler::Get()->RequestUserAttentionForWindow(
      app_window(), flash ? apps::APP_SHIM_ATTENTION_CRITICAL
                          : apps::APP_SHIM_ATTENTION_CANCEL);
}

void ChromeNativeAppWindowViewsMac::OnWidgetCreated(views::Widget* widget) {
  if (title_bar_style() != TitleBarStyle::NORMAL) {
    NativeWidgetMacNSWindow* window = (NativeWidgetMacNSWindow*)(GetNativeWindow().GetNativeNSWindow());
    window.styleMask |= NSFullSizeContentViewWindowMask;
    if (@available(macos 10.10, *))
      [window setTitlebarAppearsTransparent:YES];
    if (title_bar_style() == TitleBarStyle::HIDDEN_INSET) {
      base::scoped_nsobject<NSToolbar> toolbar(
          [[NSToolbar alloc] initWithIdentifier:@"titlebarStylingToolbar"]);
      [toolbar setShowsBaselineSeparator:NO];
      [window setToolbar:toolbar];
      [window enableWindowButtonsOffset];
      [window setWindowButtonsOffset:window_buttons_offset_];
    }
  }

  nswindow_observer_.reset(
      [[ResizeNotificationObserver alloc] initForNativeAppWindow:this]);
}

void ChromeNativeAppWindowViewsMac::ShowWithApp() {
  is_hidden_with_app_ = false;
  if (!app_window()->is_hidden())
    ShowInactive();
}

void ChromeNativeAppWindowViewsMac::HideWithApp() {
  is_hidden_with_app_ = true;
  ChromeNativeAppWindowViews::Hide();
}

void ChromeNativeAppWindowViewsMac::UnhideWithoutActivation() {
  if (is_hidden_with_app_) {
    apps::ExtensionAppShimHandler::Get()->UnhideWithoutActivationForWindow(
        app_window());
    is_hidden_with_app_ = false;
  }
}

bool ChromeNativeAppWindowViewsMac::Adjust_Hidden_Inset_Buttons() {
  if (title_bar_style() != TitleBarStyle::HIDDEN_INSET)
    return false;
  
  NativeWidgetMacNSWindow* window = (NativeWidgetMacNSWindow*)(GetNativeWindow().GetNativeNSWindow());
  [window setToolbar:window.toolbar];
  return [window adjustButton:[window standardWindowButton:NSWindowCloseButton] ofKind:NSWindowCloseButton] &&
      [window adjustButton:[window standardWindowButton:NSWindowMiniaturizeButton] ofKind:NSWindowMiniaturizeButton] &&
      [window adjustButton:[window standardWindowButton:NSWindowZoomButton] ofKind:NSWindowZoomButton];
}

bool ChromeNativeAppWindowViewsMac::SetWindowButtonsOffset(int x, int y) {
  if (title_bar_style() != TitleBarStyle::HIDDEN_INSET)
    return false;
  
  NativeWidgetMacNSWindow* window = (NativeWidgetMacNSWindow*)(GetNativeWindow().GetNativeNSWindow());
  if(x >=0 && y>=0) {
    window_buttons_offset_.x = x;
    window_buttons_offset_.y = y;
    [window setWindowButtonsOffset:window_buttons_offset_];
  }
  return Adjust_Hidden_Inset_Buttons();
}

bool ChromeNativeAppWindowViewsMac::userWillWaitForInProgressDownloads(int downloadCount) const {
  NSString* titleText = nil;
  NSString* explanationText = nil;
  NSString* waitTitle = nil;
  NSString* exitTitle = nil;
  
  // Set the dialog text based on whether or not there are multiple downloads.
  // Dialog text: warning and explanation.
  titleText = l10n_util::GetPluralNSStringF(
      IDS_ABANDON_DOWNLOAD_DIALOG_TITLE, downloadCount);
  explanationText = l10n_util::GetPluralNSStringF(
      IDS_ABANDON_DOWNLOAD_DIALOG_BROWSER_MESSAGE, downloadCount);
  // Cancel download and exit button text.
  exitTitle = l10n_util::GetPluralNSStringF(
      IDS_ABANDON_DOWNLOAD_DIALOG_EXIT_BUTTON, downloadCount);
  
  // Wait for download button text.
  waitTitle = l10n_util::GetPluralNSStringF(
      IDS_ABANDON_DOWNLOAD_DIALOG_CONTINUE_BUTTON, downloadCount);
  
  // 'waitButton' is the default choice.
  base::scoped_nsobject<NSAlert> alert([[NSAlert alloc] init]);
  [alert setMessageText:titleText];
  [alert setInformativeText:explanationText];
  [alert addButtonWithTitle:waitTitle];
  [alert addButtonWithTitle:exitTitle];
  
  // 'waitButton' is the default choice.
  int choice = [alert runModal];
  return choice == NSAlertFirstButtonReturn ? YES : NO;
}

// Check all profiles for in progress downloads, and if we find any, prompt the
// user to see if we should continue to exit (and thus cancel the downloads), or
// if we should wait.
bool ChromeNativeAppWindowViewsMac::shouldQuitWithInProgressDownloads() const {
  // count the active window (not closing) by checking the window's visibility
  // windows are set to "invisible" moments before it is closed
  int notClosingWindow = 0;
  for (auto const &window : AppWindowRegistryUtil::GetAppNativeWindowList()) {
    if (window.GetNativeNSWindow().visible)
      notClosingWindow++;
  }
  if (notClosingWindow > 1)
    return true;   // Not the last window; can definitely close.
  
  static bool cancel_download_prompt = false;
  int total_download_count = DownloadCoreService::NonMaliciousDownloadCountAllProfiles();
  if (total_download_count > 0 && !cancel_download_prompt) {
    cancel_download_prompt = true;
    if (userWillWaitForInProgressDownloads(total_download_count)) {
      cancel_download_prompt = false;
      return false;
    }
    // User wants to exit, keep cancel_download_prompt to true, so we won't ask the user again
    return true;
  }
  
  // No profiles or active downloads found, okay to exit.
  return true;
}

bool ChromeNativeAppWindowViewsMac::NWCanClose(bool user_force) {
  if (browser_shutdown::IsTryingToQuit() || shouldQuitWithInProgressDownloads()) {
    return ChromeNativeAppWindowViews::NWCanClose(user_force);
  }
  return false;
}
