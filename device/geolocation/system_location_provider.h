// Copyright (c) 2014 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef DEVICE_GEOLOCATION_SYSTEM_LOCATION_PROVIDER_H_
#define DEVICE_GEOLOCATION_SYSTEM_LOCATION_PROVIDER_H_

#include "base/memory/ref_counted.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string16.h"
#include "base/threading/non_thread_safe.h"
#include "base/threading/thread.h"
#include "device/geolocation/location_provider_base.h"
#include "content/common/content_export.h"
#include "device/geolocation/geoposition.h"

#if defined(OS_WIN)
#include "device/geolocation/system_location_provider_win.h"
#elif defined(OS_MACOSX)
#include "device/geolocation/system_location_provider_mac.h"
#endif

namespace device {

// Factory functions for the various types of location provider to abstract
// over the platform-dependent implementations.
DEVICE_GEOLOCATION_EXPORT std::unique_ptr<LocationProvider> NewSystemLocationProvider();
}  // namespace device

#endif  //DEVICE_GEOLOCATION_SYSTEM_LOCATION_PROVIDER_H_
