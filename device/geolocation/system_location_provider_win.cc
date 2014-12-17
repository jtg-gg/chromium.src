// Copyright (c) 2014 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "device/geolocation/system_location_provider_win.h"
#include "base/bind.h"
#include "base/memory/ptr_util.h"
#include "base/threading/thread_task_runner_handle.h"
#include "base/win/windows_version.h"

namespace device {

#if defined(COMPONENT_BUILD)
class CDummyModule : public CAtlExeModuleT<CDummyModule> {};
CDummyModule _Module;
#endif

SystemLocationProviderWin::SystemLocationProviderWin() 
    : scoped_com_initializer_(std::make_unique<base::win::ScopedCOMInitializer>(base::win::ScopedCOMInitializer::kMTA)) {
  report_type_ = IID_ILatLongReport; // Array of report types of interest. Other ones include IID_ICivicAddressReport
}

SystemLocationProviderWin::~SystemLocationProviderWin() {
  StopProvider();
}

void SystemLocationProviderWin::NotifyNewGeoposition(mojom::Geoposition position) {
  DCHECK(thread_checker_.CalledOnValidThread());
  last_position_ = position;
  if (!callback_.is_null())
    callback_.Run(this, position);
}

void SystemLocationProviderWin::SetUpdateCallback(
  const LocationProviderUpdateCallback& callback) {
  callback_ = callback;
}

void SystemLocationProviderWin::StartProvider(bool high_accuracy) {
  DCHECK(thread_checker_.CalledOnValidThread());
  HRESULT hr = 0;
  if (location_ == NULL) {
    hr = location_.CoCreateInstance(CLSID_Location); // Create the Location object
    if (SUCCEEDED(hr)) {
      hr = CComObject<SystemLocationDataProviderWin>::CreateInstance(&location_data_provider_); // Create the callback object
      if (NULL != location_data_provider_) {
        location_data_provider_->AddRef();
      }
    }

    if (SUCCEEDED(hr)) {
      location_data_provider_->SetCallback(base::Bind(&SystemLocationProviderWin::NotifyNewGeoposition, base::Unretained(this)));
      // Request permissions for this user account to receive location data for all the
      // types defined in REPORT_TYPES (which is currently just one report)
      hr = location_->RequestPermissions(NULL, &report_type_, 1, FALSE); // FALSE means an asynchronous request
      if (FAILED(hr)) {
        mojom::Geoposition position;
        position.error_code = mojom::Geoposition_ErrorCode::PERMISSION_DENIED;
        NotifyNewGeoposition(position);
      }
      else {
        // Tell the Location API that we want to register for reports (which is currently just one report)
        hr = location_->RegisterForReport(location_data_provider_, report_type_, 0);
      }
    }
  }

  if (SUCCEEDED(hr)) {
    location_->SetDesiredAccuracy(IID_ILatLongReport, high_accuracy ? LOCATION_DESIRED_ACCURACY_HIGH : LOCATION_DESIRED_ACCURACY_DEFAULT);
  }

  //return SUCCEEDED(hr);
}

void SystemLocationProviderWin::StopProvider() {
  DCHECK(thread_checker_.CalledOnValidThread());
  // Unregister from reports from the Location API
  location_->UnregisterForReport(report_type_);

  // Cleanup
  if (NULL != location_data_provider_) {
    location_data_provider_->SetCallback(SystemLocationDataProviderWin::SystemLocationDataUpdateCallback());
    location_data_provider_->Release();
    location_data_provider_ = NULL;
  }
}

static void getGeopositionData(CComPtr<ILatLongReport>& spLatLongReport, mojom::Geoposition& position) {
  SYSTEMTIME systemTime;
  if (SUCCEEDED(spLatLongReport->GetTimestamp(&systemTime))) {
    FILETIME currentTime;
    if (TRUE == SystemTimeToFileTime(&systemTime, &currentTime)) {
      position.timestamp = base::Time::FromFileTime(currentTime);
    }
  }

  DOUBLE latitude = 0, longitude = 0, altitude = 0, errorRadius = 0, altitudeError = 0;

  if (SUCCEEDED(spLatLongReport->GetLatitude(&latitude))) {
    position.latitude = latitude;
  }

  if (SUCCEEDED(spLatLongReport->GetLongitude(&longitude))) {
    position.longitude = longitude;
  }

  if (SUCCEEDED(spLatLongReport->GetAltitude(&altitude))) {
    position.altitude = altitude;
  }

  if (SUCCEEDED(spLatLongReport->GetErrorRadius(&errorRadius))) {
    position.accuracy = errorRadius;
  }

  if (SUCCEEDED(spLatLongReport->GetAltitudeError(&altitudeError))) {
    position.altitude_accuracy = altitudeError;
  }
}

const mojom::Geoposition& SystemLocationProviderWin::GetPosition() {
  CComPtr<ILocationReport> spLocationReport; // This is our location report object
  CComPtr<ILatLongReport> spLatLongReport; // This is our LatLong report object

  // Get the current latitude/longitude location report,
  HRESULT hr = location_->GetReport(IID_ILatLongReport, &spLocationReport);
  // then get a pointer to the ILatLongReport interface by calling QueryInterface
  if (SUCCEEDED(hr)) {
    hr = spLocationReport->QueryInterface(&spLatLongReport);
    getGeopositionData(spLatLongReport, last_position_);
  } else {
    last_position_.error_code = hr == E_ACCESSDENIED ? mojom::Geoposition_ErrorCode::PERMISSION_DENIED : mojom::Geoposition_ErrorCode::POSITION_UNAVAILABLE;
  }
  return last_position_;
}

void SystemLocationProviderWin::OnPermissionGranted() {
  DCHECK(thread_checker_.CalledOnValidThread());
}

SystemLocationDataProviderWin::SystemLocationDataProviderWin()
    : client_task_runner_(base::ThreadTaskRunnerHandle::Get()) {
  DCHECK(client_task_runner_);
}

SystemLocationDataProviderWin::~SystemLocationDataProviderWin() {
}

void SystemLocationDataProviderWin::DoRunCallbacks(mojom::Geoposition position) {
  if(!system_location_callback_.is_null())
    client_task_runner_->PostTask(FROM_HERE, base::Bind(system_location_callback_, position));
}

void SystemLocationDataProviderWin::SetCallback(SystemLocationDataUpdateCallback callback) {
  // system_location_callback_ currently can only handle 1 callback
  system_location_callback_ = callback;
}

// This is called when there is a new location report
STDMETHODIMP SystemLocationDataProviderWin::OnLocationChanged(REFIID reportType, ILocationReport* pLocationReport) {
  // If the report type is a Latitude/Longitude report (as opposed to IID_ICivicAddressReport or another type)
  if (IID_ILatLongReport == reportType) {
    mojom::Geoposition position;
    CComPtr<ILatLongReport> spLatLongReport;

    // Get the ILatLongReport interface from ILocationReport
    if ((SUCCEEDED(pLocationReport->QueryInterface(IID_PPV_ARGS(&spLatLongReport)))) && (NULL != spLatLongReport.p)) {
      getGeopositionData(spLatLongReport, position);
      DoRunCallbacks(position);
    }
  }
  return S_OK;
}

// This is called when the status of a report type changes.
// The LOCATION_REPORT_STATUS enumeration is defined in LocApi.h in the SDK
STDMETHODIMP SystemLocationDataProviderWin::OnStatusChanged(REFIID reportType, LOCATION_REPORT_STATUS status) {
  if (IID_ILatLongReport == reportType) {
    mojom::Geoposition position;
    switch (status) {
    case REPORT_NOT_SUPPORTED:
      position.error_message = "No devices detected.";
      position.error_code = mojom::Geoposition_ErrorCode::POSITION_UNAVAILABLE;
      DoRunCallbacks(position);
      break;
    case REPORT_ERROR:
      position.error_message = "Report error.";
      position.error_code = mojom::Geoposition_ErrorCode::POSITION_UNAVAILABLE;
      DoRunCallbacks(position);
      break;
    case REPORT_ACCESS_DENIED:
      position.error_message= "Access denied to reports.";
      position.error_code = mojom::Geoposition_ErrorCode::PERMISSION_DENIED;
      DoRunCallbacks(position);
      break;
    case REPORT_INITIALIZING:
    case REPORT_RUNNING:
      break;
    }
  } else if (IID_ICivicAddressReport == reportType) {
  }

  return S_OK;
}
// SystemLocationProvider factory function
std::unique_ptr<LocationProvider> NewSystemLocationProvider() {
  if (base::win::GetVersion() > base::win::VERSION_WIN7)
    return base::WrapUnique(new SystemLocationProviderWin());
  return NULL;
}
  
}  // namespace device
