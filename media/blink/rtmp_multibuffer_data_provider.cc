// Copyright 2018 Jefry Tedjokusumo. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "media/blink/rtmp_multibuffer_data_provider.h"

#include "base/bind.h"
#include "base/task_scheduler/post_task.h"
#include "base/threading/thread_task_runner_handle.h"
#include "media/blink/url_index.h"
#include "media/ffmpeg/ffmpeg_common.h"

namespace media {

RTMPMultiBufferDataProvider::RTMPMultiBufferDataProvider(
    UrlData* url_data,
    MultiBufferBlockId pos,
    bool is_client_audio_element)
    : pb_(NULL), shutting_down_(false), read_result_(0), pos_(pos), url_data_(url_data), weak_factory_(this) {
  AVDictionary* opt = NULL;
  av_dict_parse_string(&opt, url_data->url().query().c_str(), "=", ";", 0);
  
  worker_thread_.reset(new base::Thread("RTMPMultiBufferDataProvider_worker"));
  worker_thread_->Start();
  worker_thread_->task_runner()->PostTaskAndReply(
    FROM_HERE,
    base::Bind(&RTMPMultiBufferDataProvider::FFMPEGOpen, base::Unretained(this), opt),
    base::Bind(&RTMPMultiBufferDataProvider::FFMPEGOpenHandler, weak_factory_.GetWeakPtr())
  );
}
    
// MultiBuffer::DataProvider implementation
MultiBufferBlockId RTMPMultiBufferDataProvider::Tell() const {
  return pos_;
}

bool RTMPMultiBufferDataProvider::Available() const {
  if (fifo_.empty())
    return false;
  if (fifo_.back()->end_of_stream())
    return true;
  if (fifo_.front()->data_size() == block_size())
    return true;
  return false;
}

int64_t RTMPMultiBufferDataProvider::AvailableBytes() const {
  int64_t bytes = 0;
  for (const auto i : fifo_) {
    if (i->end_of_stream())
    break;
    bytes += i->data_size();
  }
  return bytes;
}

scoped_refptr<DataBuffer> RTMPMultiBufferDataProvider::Read() {
  DCHECK(Available());
  scoped_refptr<DataBuffer> ret = fifo_.front();
  fifo_.pop_front();
  ++pos_;
  return ret;
}

void RTMPMultiBufferDataProvider::Terminate() {
  fifo_.push_back(DataBuffer::CreateEOSBuffer());
  url_data_->multibuffer()->OnDataProviderEvent(this);
}

RTMPMultiBufferDataProvider::~RTMPMultiBufferDataProvider() {
  DLOG(INFO) << "~RTMPMultiBufferDataProvider " << this;
  shutting_down_ = true;
  base::AutoLock lock(lock_);
  HandleError(read_result_);
  avio_close(pb_);
  worker_thread_->Stop();
  worker_thread_.reset();
}

int64_t RTMPMultiBufferDataProvider::block_size() const {
  int64_t ret = 1;
  return ret << url_data_->multibuffer()->block_size_shift();
}

int RTMPMultiBufferDataProvider::interrupt_cb(void *ctx) {
  RTMPMultiBufferDataProvider* this_ = reinterpret_cast<RTMPMultiBufferDataProvider*>(ctx);
  return this_->shutting_down_ ? -1 : 0;
}

void RTMPMultiBufferDataProvider::FFMPEGOpen(AVDictionary* opt) {
  base::AutoLock lock(lock_);
  const AVIOInterruptCB int_cb = { RTMPMultiBufferDataProvider::interrupt_cb, this };
  int ret = avio_open2(&pb_, url_data_->url().spec().c_str(), AVIO_FLAG_READ, &int_cb, &opt);
  av_dict_free(&opt);
  DLOG(INFO) << "RTMPMultiBufferDataProvider::FFMPEGOpen " << ret;
}

void RTMPMultiBufferDataProvider::FFMPEGOpenHandler() {
  if (pb_ == NULL) {
    base::ThreadTaskRunnerHandle::Get()->PostTask(
      FROM_HERE, base::Bind(&UrlData::Fail,
                            url_data_));
  } else {
    worker_thread_->task_runner()->PostTaskAndReply(
      FROM_HERE,
      base::Bind(&RTMPMultiBufferDataProvider::FFMPEGReadData, base::Unretained(this)),
      base::Bind(&RTMPMultiBufferDataProvider::DidReceiveData, weak_factory_.GetWeakPtr())
    );
  }
}

void RTMPMultiBufferDataProvider::FFMPEGReadData() {
  base::AutoLock lock(lock_);
  data_.resize(1024*32);
  read_result_ = avio_read_partial(pb_, data_.data(), data_.size());
  if ( read_result_ > 0 ) {
    data_.resize(read_result_);
  } else {
    LOG(INFO) << "RTMPMultiBufferDataProvider::FFMPEGReadData " << read_result_;
  }
}

bool RTMPMultiBufferDataProvider::HandleError(int read_result) {
  if (read_result < 0) {
    read_result_ = 0;
    if ( read_result == AVERROR_EOF ) {
      Terminate();
    } else if (!shutting_down_) {
      url_data_->Fail();
    }
    return true;
  }
  return false;
}

void RTMPMultiBufferDataProvider::DidReceiveData() {
  if (HandleError(read_result_)) {
    return;
  }
  int data_length = data_.size();
  const unsigned char* data = data_.data();
  url_data_->AddBytesReadFromNetwork(data_length);
  while (data_length) {
    if (fifo_.empty() || fifo_.back()->data_size() == block_size()) {
      fifo_.push_back(new DataBuffer(block_size()));
      fifo_.back()->set_data_size(0);
    }
    int last_block_size = fifo_.back()->data_size();
    int to_append = std::min<int>(data_length, block_size() - last_block_size);
    DCHECK_GT(to_append, 0);
    memcpy(fifo_.back()->writable_data() + last_block_size, data, to_append);
    data += to_append;
    fifo_.back()->set_data_size(last_block_size + to_append);
    data_length -= to_append;
  }
  url_data_->multibuffer()->OnDataProviderEvent(this);
  worker_thread_->task_runner()->PostTaskAndReply(
    FROM_HERE,
    base::Bind(&RTMPMultiBufferDataProvider::FFMPEGReadData, base::Unretained(this)),
    base::Bind(&RTMPMultiBufferDataProvider::DidReceiveData, weak_factory_.GetWeakPtr())
  );
}
}  // namespace media
