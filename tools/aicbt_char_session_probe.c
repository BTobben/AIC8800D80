// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Diagnostic-only char-session probe for the AIC Bluedroid /dev/aicbt_dev path.
 *
 * The probe keeps the character device open after GET_USB_INFO so the driver's
 * RX URB is not immediately cancelled by btchr_close().  By default it only
 * polls and reads.  With --send-reset it writes a single H4-framed HCI Reset
 * command (01 03 0c 00), then continues polling/reading until timeout.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define AICBT_DEFAULT_DEVICE "/dev/aicbt_dev"
#define AICBT_DEFAULT_TIMEOUT_MS 5000
#define AICBT_READ_BUF_SIZE 4096
#define GET_USB_INFO _IOR('E', 180, int)

static void usage(const char *prog)
{
    fprintf(stderr,
            "Usage: %s [--device PATH] [--timeout-ms N] [--pre-ioctl-delay-ms N] [--post-ioctl-delay-ms N] [--read-only | --send-reset]\n"
            "\n"
            "Default: --device %s --timeout-ms %d --pre-ioctl-delay-ms 0 --post-ioctl-delay-ms 0 --read-only\n",
            prog, AICBT_DEFAULT_DEVICE, AICBT_DEFAULT_TIMEOUT_MS);
}

static long long now_ms(void)
{
    struct timespec ts;

    if (clock_gettime(CLOCK_MONOTONIC, &ts) < 0)
        return -1;

    return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

static void print_hex(const char *prefix, const uint8_t *buf, ssize_t len)
{
    ssize_t i;

    printf("%s len=%zd", prefix, len);
    for (i = 0; i < len; i++)
        printf(" %02x", buf[i]);
    printf("\n");
}

static int parse_ms_arg(const char *arg, int *timeout_ms)
{
    char *end = NULL;
    long val;

    errno = 0;
    val = strtol(arg, &end, 10);
    if (errno || !end || *end != '\0' || val < 0 || val > 24L * 60L * 60L * 1000L)
        return -1;

    *timeout_ms = (int)val;
    return 0;
}

static int sleep_ms_checked(int delay_ms)
{
    struct timespec req;

    if (delay_ms <= 0)
        return 0;

    req.tv_sec = delay_ms / 1000;
    req.tv_nsec = (long)(delay_ms % 1000) * 1000000L;

    while (nanosleep(&req, &req) < 0) {
        if (errno != EINTR)
            return -1;
    }

    return 0;
}

int main(int argc, char **argv)
{
    const char *device = AICBT_DEFAULT_DEVICE;
    int timeout_ms = AICBT_DEFAULT_TIMEOUT_MS;
    int pre_ioctl_delay_ms = 0;
    int post_ioctl_delay_ms = 0;
    int send_reset = 0;
    int fd = -1;
    int ret;
    int saved_errno;
    int usb_info = 0;
    uint32_t raw;
    unsigned int vid;
    unsigned int pid;
    long long start;
    long long deadline;
    uint8_t read_buf[AICBT_READ_BUF_SIZE];
    static const uint8_t hci_reset_h4[] = { 0x01, 0x03, 0x0c, 0x00 };
    int i;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--device") == 0) {
            if (++i >= argc) {
                usage(argv[0]);
                return 2;
            }
            device = argv[i];
        } else if (strcmp(argv[i], "--timeout-ms") == 0) {
            if (++i >= argc || parse_ms_arg(argv[i], &timeout_ms) < 0) {
                usage(argv[0]);
                return 2;
            }
        } else if (strcmp(argv[i], "--pre-ioctl-delay-ms") == 0) {
            if (++i >= argc || parse_ms_arg(argv[i], &pre_ioctl_delay_ms) < 0) {
                usage(argv[0]);
                return 2;
            }
        } else if (strcmp(argv[i], "--post-ioctl-delay-ms") == 0) {
            if (++i >= argc || parse_ms_arg(argv[i], &post_ioctl_delay_ms) < 0) {
                usage(argv[0]);
                return 2;
            }
        } else if (strcmp(argv[i], "--read-only") == 0) {
            send_reset = 0;
        } else if (strcmp(argv[i], "--send-reset") == 0) {
            send_reset = 1;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    printf("device=%s\n", device);
    printf("timeout_ms=%d\n", timeout_ms);
    printf("pre_ioctl_delay_ms=%d\n", pre_ioctl_delay_ms);
    printf("post_ioctl_delay_ms=%d\n", post_ioctl_delay_ms);
    printf("mode=%s\n", send_reset ? "send-reset" : "read-only");
    printf("GET_USB_INFO=0x%08lx\n", (unsigned long)GET_USB_INFO);

    errno = 0;
    fd = open(device, O_RDWR | O_CLOEXEC);
    saved_errno = errno;
    printf("open_ret=%d errno=%d (%s)\n", fd, saved_errno, strerror(saved_errno));
    if (fd < 0)
        return 1;

    if (pre_ioctl_delay_ms > 0) {
        printf("pre_ioctl_delay_start delay_ms=%d\n", pre_ioctl_delay_ms);
        if (sleep_ms_checked(pre_ioctl_delay_ms) < 0) {
            saved_errno = errno;
            fprintf(stderr, "pre_ioctl_delay_failed errno=%d (%s)\n",
                    saved_errno, strerror(saved_errno));
            ret = 1;
            goto out_close;
        }
        printf("pre_ioctl_delay_done delay_ms=%d\n", pre_ioctl_delay_ms);
    }

    errno = 0;
    ret = ioctl(fd, GET_USB_INFO, &usb_info);
    saved_errno = errno;
    raw = (uint32_t)usb_info;
    pid = raw & 0xffffu;
    vid = (raw >> 16) & 0xffffu;
    printf("ioctl_ret=%d errno=%d (%s)\n", ret, saved_errno, strerror(saved_errno));
    printf("usb_info_raw=0x%08x (%d)\n", raw, usb_info);
    printf("decoded_vid=0x%04x\n", vid);
    printf("decoded_pid=0x%04x\n", pid);
    if (ret < 0) {
        ret = 1;
        goto out_close;
    }

    if (post_ioctl_delay_ms > 0) {
        printf("post_ioctl_delay_start delay_ms=%d\n", post_ioctl_delay_ms);
        if (sleep_ms_checked(post_ioctl_delay_ms) < 0) {
            saved_errno = errno;
            fprintf(stderr, "post_ioctl_delay_failed errno=%d (%s)\n",
                    saved_errno, strerror(saved_errno));
            ret = 1;
            goto out_close;
        }
        printf("post_ioctl_delay_done delay_ms=%d\n", post_ioctl_delay_ms);
    }

    if (send_reset) {
        ssize_t written;

        print_hex("write_hci_reset_h4", hci_reset_h4, (ssize_t)sizeof(hci_reset_h4));
        printf("note=--send-reset writes H4 bytes; kernel btchr_write consumes 0x01 as pkt_type and transmits the 3-byte HCI command payload\n");
        errno = 0;
        written = write(fd, hci_reset_h4, sizeof(hci_reset_h4));
        saved_errno = errno;
        printf("write_ret=%zd errno=%d (%s)\n", written, saved_errno,
                strerror(saved_errno));
        if (written < 0) {
            ret = 1;
            goto out_close;
        }
    }

    start = now_ms();
    if (start < 0) {
        saved_errno = errno;
        fprintf(stderr, "clock_gettime failed: errno=%d (%s)\n", saved_errno,
                strerror(saved_errno));
        ret = 1;
        goto out_close;
    }
    deadline = start + timeout_ms;
    ret = 0;

    for (;;) {
        struct pollfd pfd;
        long long now = now_ms();
        int remaining;

        if (now < 0) {
            saved_errno = errno;
            fprintf(stderr, "clock_gettime failed: errno=%d (%s)\n", saved_errno,
                    strerror(saved_errno));
            ret = 1;
            break;
        }
        if (now >= deadline)
            break;

        remaining = (int)(deadline - now);
        pfd.fd = fd;
        pfd.events = POLLIN | POLLERR | POLLHUP;
        pfd.revents = 0;

        errno = 0;
        ret = poll(&pfd, 1, remaining);
        saved_errno = errno;
        printf("poll_ret=%d errno=%d (%s) revents=0x%x remaining_ms=%d\n",
                ret, saved_errno, strerror(saved_errno), pfd.revents, remaining);

        if (ret < 0) {
            if (saved_errno == EINTR)
                continue;
            ret = 1;
            break;
        }
        if (ret == 0) {
            ret = 0;
            break;
        }

        if (pfd.revents & POLLIN) {
            ssize_t bytes_read;

            errno = 0;
            bytes_read = read(fd, read_buf, sizeof(read_buf));
            saved_errno = errno;
            printf("read_ret=%zd errno=%d (%s)\n", bytes_read, saved_errno,
                    strerror(saved_errno));
            if (bytes_read < 0) {
                if (saved_errno == EINTR)
                    continue;
                ret = 1;
                break;
            }
            if (bytes_read > 0)
                print_hex("read_data", read_buf, bytes_read);
        }

        if (pfd.revents & (POLLERR | POLLHUP)) {
            printf("poll_status=0x%x (POLLERR/POLLHUP observed)\n", pfd.revents);
            ret = 1;
            break;
        }
    }

    printf("session_done elapsed_ms=%lld\n", now_ms() - start);
out_close:
    errno = 0;
    saved_errno = 0;
    if (close(fd) < 0) {
        saved_errno = errno;
        printf("close_ret=-1 errno=%d (%s)\n", saved_errno, strerror(saved_errno));
        return 1;
    }
    printf("close_ret=0 errno=%d (%s)\n", saved_errno, strerror(saved_errno));

    return ret ? 1 : 0;
}
