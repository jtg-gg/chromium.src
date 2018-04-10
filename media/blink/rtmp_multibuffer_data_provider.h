// Copyright 2018 Jefry Tedjokusumo. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef MEDIA_BLINK_RTMP_MULTIBUFFER_DATA_PROVIDER_H_
#define MEDIA_BLINK_RTMP_MULTIBUFFER_DATA_PROVIDER_H_

#include "base/memory/weak_ptr.h"
#include "base/threading/thread.h"
#include "media/blink/multibuffer.h"

struct AVDictionary;
struct AVIOContext;

namespace media {

class UrlData;

class RTMPMultiBufferDataProvider: public MultiBuffer::DataProvider {
public:

  RTMPMultiBufferDataProvider(
      UrlData* url_data,
      MultiBufferBlockId pos,
      bool is_client_audio_element);

  ~RTMPMultiBufferDataProvider() override;

  // MultiBuffer::DataProvider implementation
  MultiBufferBlockId Tell() const override;
  bool Available() const override;
  int64_t AvailableBytes() const override;
  scoped_refptr<DataBuffer> Read() override;
  void SetDeferred(bool defer) override {}

private:
  static int interrupt_cb(void *ctx);
  void Terminate();
  bool HandleError(int read_result);
  int64_t block_size() const;
  void FFMPEGOpen(AVDictionary* opt);
  void FFMPEGOpenHandler();
  void FFMPEGReadData();
  void DidReceiveData();
      
  AVIOContext* pb_;
  std::vector<unsigned char> data_;
  std::unique_ptr<base::Thread> worker_thread_;
  base::Lock lock_;
  bool shutting_down_;
  int read_result_;

  // Current Position.
  MultiBufferBlockId pos_;

  // This is where we actually get read data from.
  // We don't need (or want) a scoped_refptr for this one, because
  // we are owned by it. Note that we may change this when we encounter
  // a redirect because we actually change ownership.
  UrlData* url_data_;

  // Temporary storage for incoming data.
  std::list<scoped_refptr<DataBuffer>> fifo_;
  base::WeakPtrFactory<RTMPMultiBufferDataProvider> weak_factory_;
};

}  // namespace media
#endif  // MEDIA_BLINK_RTMP_MULTIBUFFER_DATA_PROVIDER_H_
