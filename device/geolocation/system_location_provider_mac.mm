// Copyright (c) 2014 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.


#include "device/geolocation/system_location_provider_mac.h"
#include "base/mac/scoped_nsobject.h"

#import <Foundation/Foundation.h>
#import<CoreLocation/CoreLocation.h>

namespace device {
  
class SystemLocationProviderMac
    : public LocationProvider {
  
public:
  
  SystemLocationProviderMac();
  ~SystemLocationProviderMac() override;
  
  // LocationProvider implementation
  void SetUpdateCallback(
      const LocationProviderUpdateCallback& callback) override;
  bool StartProvider(bool high_accuracy) override;
  void StopProvider() override;
  const Geoposition& GetPosition() override;
  void OnPermissionGranted() override;

  void NotifyNewGeoposition(const Geoposition& position);
  void RequestRefresh();
  
private:
  Geoposition last_position_;
  LocationProviderUpdateCallback callback_;
  base::ThreadChecker thread_checker_;

  // need to make it static, as in Yosemite, it will ask for permission everytime we start updating location
  static CLLocationManager* location_manager_;
  
  DISALLOW_COPY_AND_ASSIGN(SystemLocationProviderMac);
  
};

}  //namespace device

void CLLocation2Geoposition(CLLocation *location, device::Geoposition *position) {
  position->latitude          = location.coordinate.latitude;
  position->longitude         = location.coordinate.longitude;
  position->altitude          = location.altitude;
  position->accuracy          = location.horizontalAccuracy;
  position->altitude_accuracy = location.verticalAccuracy;
  position-> error_code       = device::Geoposition::ERROR_CODE_NONE;
  position->timestamp         = base::Time::FromCFAbsoluteTime(CFDateGetAbsoluteTime(CFDateRef(location.timestamp)));
  DCHECK(position->Validate());
}

@interface SystemLocationMacDelegate : NSObject<CLLocationManagerDelegate> {
@private
  device::SystemLocationProviderMac* system_location_provider_;
}
@end

@implementation SystemLocationMacDelegate

- (id) init: (device::SystemLocationProviderMac*) system_location_provider {
  system_location_provider_ = system_location_provider;
  return self;
}

- (void) dealloc {
  system_location_provider_ = NULL;
  [super dealloc];
}

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray *)locations {
  CLLocation* location = [locations lastObject];
  device::Geoposition geoposition;
  CLLocation2Geoposition(location, &geoposition);
  system_location_provider_->NotifyNewGeoposition(geoposition);
}

- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error {
  if (error.code >= 0) {
    device::Geoposition geoposition;
    geoposition.error_code = error.code == kCLErrorDenied ?
      device::Geoposition::ERROR_CODE_PERMISSION_DENIED : device::Geoposition::ERROR_CODE_POSITION_UNAVAILABLE;

    system_location_provider_->NotifyNewGeoposition(geoposition);
  }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
  if (status == kCLAuthorizationStatusAuthorized) {
    system_location_provider_->OnPermissionGranted();
  } else if (status != kCLAuthorizationStatusNotDetermined) {
    device::Geoposition geoposition;
    geoposition.error_code = device::Geoposition::ERROR_CODE_PERMISSION_DENIED;
    system_location_provider_->NotifyNewGeoposition(geoposition);
  }
}

@end


namespace device {

CLLocationManager* SystemLocationProviderMac::location_manager_ = NULL;

SystemLocationProviderMac::SystemLocationProviderMac() {
  if (location_manager_ == NULL)
    location_manager_ = [[CLLocationManager alloc] init];
}

SystemLocationProviderMac::~SystemLocationProviderMac() {
  StopProvider();
}

void SystemLocationProviderMac::NotifyNewGeoposition(
    const Geoposition& position) {
  DCHECK(thread_checker_.CalledOnValidThread());
  last_position_ = position;
  if (!callback_.is_null())
    callback_.Run(this, position);
}

void SystemLocationProviderMac::SetUpdateCallback(
    const LocationProviderUpdateCallback& callback) {
  callback_ = callback;
}

bool SystemLocationProviderMac::StartProvider(bool high_accuracy) {
  DCHECK(thread_checker_.CalledOnValidThread());
  location_manager_.desiredAccuracy = kCLLocationAccuracyBest;
  location_manager_.delegate = [[SystemLocationMacDelegate alloc] init: this];
  RequestRefresh();
  return true;
}

void SystemLocationProviderMac::StopProvider() {
  DCHECK(thread_checker_.CalledOnValidThread());
  [location_manager_ stopUpdatingLocation];
  if (location_manager_.delegate) {
    [[location_manager_ delegate] release];
    location_manager_.delegate = NULL;
  }
}

const Geoposition& SystemLocationProviderMac::GetPosition() {
  DCHECK(thread_checker_.CalledOnValidThread());
  CLLocation2Geoposition(location_manager_.location, &last_position_);
  return last_position_;
}

void SystemLocationProviderMac::RequestRefresh() {
  DCHECK(thread_checker_.CalledOnValidThread());
  [location_manager_ startUpdatingLocation];
}

void SystemLocationProviderMac::OnPermissionGranted() {
  DCHECK(thread_checker_.CalledOnValidThread());
  RequestRefresh();
}

// SystemLocationProvider factory function
std::unique_ptr<LocationProvider> NewSystemLocationProvider() {
  return std::unique_ptr<LocationProvider>(new SystemLocationProviderMac());
}
  
}  // namespace device
