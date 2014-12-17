// Copyright (c) 2014 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef DEVICE_GEOLOCATION_SYSTEM_LOCATION_PROVIDER_WIN_H_
#define DEVICE_GEOLOCATION_SYSTEM_LOCATION_PROVIDER_WIN_H_

#include "base/single_thread_task_runner.h"
#include "base/win/scoped_com_initializer.h"
#include "device/geolocation/system_location_provider.h"
#include <windows.h>
#include <atlbase.h>
#include <atlcom.h>
#include <LocationApi.h>

namespace device {

class SystemLocationDataProviderWin :
  public CComObjectRoot,
  public ILocationEvents { // We must include this interface so the Location API knows how to talk to our object

public:
  SystemLocationDataProviderWin();

  DECLARE_NOT_AGGREGATABLE(SystemLocationDataProviderWin)

  BEGIN_COM_MAP(SystemLocationDataProviderWin)
    COM_INTERFACE_ENTRY(ILocationEvents)
  END_COM_MAP()

  // ILocationEvents
  // This is called when there is a new location report
  STDMETHOD(OnLocationChanged)(REFIID reportType, ILocationReport* pLocationReport);

  // This is called when the status of a report type changes.
  // The LOCATION_REPORT_STATUS enumeration is defined in LocApi.h in the SDK
  STDMETHOD(OnStatusChanged)(REFIID reportType, LOCATION_REPORT_STATUS status);

  typedef base::Callback<void(mojom::Geoposition)> SystemLocationDataUpdateCallback;
  void SetCallback(SystemLocationDataUpdateCallback callback);

protected:
  virtual ~SystemLocationDataProviderWin();
  void DoRunCallbacks(mojom::Geoposition position);

  // callback to SystemLocationProviderWin, currently we only store 1 callback, change it to set if more is needed
  SystemLocationDataUpdateCallback system_location_callback_;
  // The task runner for the client thread, all callbacks should run on it.
  scoped_refptr<base::SingleThreadTaskRunner> client_task_runner_;
};

class SystemLocationProviderWin :
  public LocationProvider {
public:
  SystemLocationProviderWin();
  ~SystemLocationProviderWin() override;

  // LocationProvider implementation
  void SetUpdateCallback(
    const LocationProviderUpdateCallback& callback) override;
  void StartProvider(bool high_accuracy) override;
  void StopProvider() override;
  const mojom::Geoposition& GetPosition() override;
  void OnPermissionGranted() override;

  void NotifyNewGeoposition(mojom::Geoposition position);

private:
  CComPtr<ILocation> location_; // This is the main Location interface
  CComObject<SystemLocationDataProviderWin>* location_data_provider_; // This is our callback object for location reports
  IID report_type_;

  mojom::Geoposition last_position_;
  LocationProviderUpdateCallback callback_;
  base::ThreadChecker thread_checker_;
  const std::unique_ptr<const base::win::ScopedCOMInitializer> scoped_com_initializer_;

  DISALLOW_COPY_AND_ASSIGN(SystemLocationProviderWin);
};

}  // namespace device

#endif  // DEVICE_GEOLOCATION_SYSTEM_LOCATION_PROVIDER_WIN_H_
