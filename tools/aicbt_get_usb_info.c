// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Diagnostic-only probe for the AIC Bluedroid character device.
 *
 * This opens /dev/aicbt_dev and issues GET_USB_INFO exactly once.  It does not
 * send firmware blobs, HCI commands, or any other vendor-HAL operation.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define AICBT_DEV_PATH "/dev/aicbt_dev"
#define GET_USB_INFO _IOR('E', 180, int)

int main(int argc, char **argv)
{
    const char *path = AICBT_DEV_PATH;
    int fd;
    int ret;
    int saved_errno;
    int usb_info = 0;
    uint32_t raw;
    unsigned int vid;
    unsigned int pid;

    if (argc > 2) {
        fprintf(stderr, "Usage: %s [device]\n", argv[0]);
        return 2;
    }
    if (argc == 2)
        path = argv[1];

    fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        saved_errno = errno;
        fprintf(stderr, "open(%s) failed: errno=%d (%s)\n",
                path, saved_errno, strerror(saved_errno));
        return 1;
    }

    errno = 0;
    ret = ioctl(fd, GET_USB_INFO, &usb_info);
    saved_errno = errno;
    raw = (uint32_t)usb_info;
    pid = raw & 0xffffu;
    vid = (raw >> 16) & 0xffffu;

    printf("device=%s\n", path);
    printf("GET_USB_INFO=0x%08lx\n", (unsigned long)GET_USB_INFO);
    printf("ioctl_ret=%d\n", ret);
    printf("errno=%d (%s)\n", saved_errno, strerror(saved_errno));
    printf("usb_info_raw=0x%08x (%d)\n", raw, usb_info);
    printf("decoded_vid=0x%04x\n", vid);
    printf("decoded_pid=0x%04x\n", pid);

    if (close(fd) < 0) {
        saved_errno = errno;
        fprintf(stderr, "close(%s) failed: errno=%d (%s)\n",
                path, saved_errno, strerror(saved_errno));
        return 1;
    }

    return ret < 0 ? 1 : 0;
}
