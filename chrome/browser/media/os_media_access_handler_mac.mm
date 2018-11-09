// Copyright (c) 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/media/os_media_access_handler_mac.h"
#import <AVFoundation/AVFoundation.h>
#include "base/task/post_task.h"
#include "content/public/browser/browser_task_traits.h"

void OSMediaAccessHandlerMac::CheckDevicesAndRunCallback(
      content::WebContents* web_contents,
      const content::MediaStreamRequest& request,
      content::MediaResponseCallback callback,
      bool audio_allowed,
      bool video_allowed) {
  if (@available(macOS 10.14, *)) {
    const AVAuthorizationStatus audioStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    const AVAuthorizationStatus videoStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    const bool audioAuthorized = audioStatus == AVAuthorizationStatusAuthorized;
    const bool videoAuthorized = videoStatus == AVAuthorizationStatusAuthorized;
    
    if ((audio_allowed && !audioAuthorized) || (video_allowed && !videoAuthorized)) {
      scoped_refptr<OSMediaAccessHandlerMac> waitAuthorization =
          new OSMediaAccessHandlerMac(web_contents, request, std::move(callback), audio_allowed, video_allowed);

      if (audio_allowed && !audioAuthorized) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
          base::PostTaskWithTraits(FROM_HERE, {content::BrowserThread::UI},
              base::BindOnce(&OSMediaAccessHandlerMac::AccessMediaHandler, waitAuthorization, granted));
        }];
      }
      if (video_allowed && !videoAuthorized) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
          base::PostTaskWithTraits(FROM_HERE, {content::BrowserThread::UI},
              base::BindOnce(&OSMediaAccessHandlerMac::AccessMediaHandler, waitAuthorization, granted));
        }];
      }
    } //(audio && !audioAuthorized) || (video && !videoAuthorized)
  } //@available(macOS 10.14, *)
  
  if (callback)
    MediaAccessHandler::CheckDevicesAndRunCallback(
        web_contents, request, std::move(callback),
        audio_allowed, video_allowed);

}

OSMediaAccessHandlerMac::OSMediaAccessHandlerMac(
      content::WebContents* web_contents,
      const content::MediaStreamRequest& request,
      content::MediaResponseCallback callback,
      bool audio_allowed,
      bool video_allowed)
      : web_contents_(web_contents), request_(request), callback_(std::move(callback)),
        audio_allowed_(audio_allowed), video_allowed_(video_allowed) {
}

OSMediaAccessHandlerMac::~OSMediaAccessHandlerMac() {
}

void OSMediaAccessHandlerMac::AccessMediaHandler(bool granted) {
  if (!callback_)
    return;

  if (granted) {
    if(HasOneRef()) //if we have > 1 ref, means we need to wait "the other" request access
      MediaAccessHandler::CheckDevicesAndRunCallback(web_contents_, request_, std::move(callback_),
                                                     audio_allowed_, video_allowed_);
  } else {
    std::move(callback_).Run(blink::MediaStreamDevices(),
                             blink::MEDIA_DEVICE_PERMISSION_DENIED, nullptr);
  }
}
