# RELEASE NAME: 20180702_BT_ANDROID_9.0
# RTKBT_API_VERSION=2.1.1.0

CUR_PATH := hardware/aic/aicbt

BOARD_HAVE_BLUETOOTH := true

PRODUCT_PACKAGES += \
	libbt-vendor-aic

# Do not set persist.service.bdroid.bdaddr to a shared constant here. Products
# using this reference integration must obtain a unique Bluetooth address from
# controller OTP/eFuse or provision a unique per-device address downstream.
