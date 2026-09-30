#ifndef __LOG_H__
#define __LOG_H__

#include <dlog.h>
#include <stdio.h>

#ifdef LOG_TAG
#undef LOG_TAG
#endif
#define LOG_TAG "VideoPlayerVideoHolePlugin"

#ifndef __MODULE__
#define __MODULE__ strrchr("/" __FILE__, '/') + 1
#endif

#define LOG(prio, fmt, arg...)                                         \
  dlog_print(prio, LOG_TAG, "%s: %s(%d) > " fmt, __MODULE__, __func__, \
             __LINE__, ##arg)

// Prairie patch: retail TVs block dlog, but flutter-tizen forwards the app's
// stderr over --tizen-logging-port, so tee non-debug logs there too.
#define LOG_STDERR(prio, fmt, arg...)                                    \
  do {                                                                   \
    LOG(prio, fmt, ##arg);                                               \
    fprintf(stderr, "[" LOG_TAG "] %s: %s(%d) > " fmt "\n", __MODULE__, \
            __func__, __LINE__, ##arg);                                  \
  } while (0)

#define LOG_DEBUG(fmt, args...) LOG(DLOG_DEBUG, fmt, ##args)
#define LOG_INFO(fmt, args...) LOG_STDERR(DLOG_INFO, fmt, ##args)
#define LOG_WARN(fmt, args...) LOG_STDERR(DLOG_WARN, fmt, ##args)
#define LOG_ERROR(fmt, args...) LOG_STDERR(DLOG_ERROR, fmt, ##args)

#endif  // __LOG_H__
