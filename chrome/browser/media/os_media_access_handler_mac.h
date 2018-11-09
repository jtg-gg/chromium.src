// Copyright (c) 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_BROWSER_MEDIA_OS_MEDIA_ACCESS_HANDLER_MAC_H_
#define CHROME_BROWSER_MEDIA_OS_MEDIA_ACCESS_HANDLER_MAC_H_

#include "base/callback.h"
#include "chrome/browser/media/extension_media_access_handler.h"

class OSMediaAccessHandlerMac : public ExtensionMediaAccessHandler,
                                public base::RefCountedThreadSafe<OSMediaAccessHandlerMac> {
public:
  static void CheckDevicesAndRunCallback(
      content::WebContents* web_contents,
      const content::MediaStreamRequest& request,
      content::MediaResponseCallback callback,
      bool audio_allowed,
      bool video_allowed);

private:
  friend class base::RefCountedThreadSafe<OSMediaAccessHandlerMac>;
  OSMediaAccessHandlerMac(content::WebContents* web_contents,
                          const content::MediaStreamRequest& request,
                          content::MediaResponseCallback callback,
                          bool audio_allowed,
                          bool video_allowed);
  ~OSMediaAccessHandlerMac() override;
  void AccessMediaHandler(bool granted);

  content::WebContents* web_contents_;
  const content::MediaStreamRequest& request_;
  content::MediaResponseCallback callback_;
  const bool audio_allowed_;
  const bool video_allowed_;
};

#endif  // CHROME_BROWSER_MEDIA_OS_MEDIA_ACCESS_HANDLER_MAC_H_
