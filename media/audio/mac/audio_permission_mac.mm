// Copyright (c) 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "media/audio/mac/audio_permission_mac.h"
#import <AVFoundation/AVFoundation.h>

namespace media {
bool GetAudioPermission() {
  if (@available(macOS 10.14, *)) {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    return status==AVAuthorizationStatusAuthorized;
  } else {
    return true;
  }
}
}  // namespace media
