LOCAL_PATH := $(call my-dir)

###########################
#
# tclcsv shared library
#
###########################

include $(CLEAR_VARS)

tcl_path := $(LOCAL_PATH)/../tcl

include $(tcl_path)/tcl-config.mk

LOCAL_ADDITIONAL_DEPENDENCIES += $(tcl_path)/tcl-config.mk

LOCAL_MODULE := tclcsv

LOCAL_C_INCLUDES := $(tcl_includes) $(LOCAL_PATH)/src

LOCAL_EXPORT_C_INCLUDES := $(LOCAL_C_INCLUDES)

LOCAL_SRC_FILES := \
	src/csv.c \
	src/tclcsv.c

LOCAL_CFLAGS := $(tcl_cflags) \
	-DPACKAGE_NAME="\"tclcsv\"" \
	-DPACKAGE_VERSION="\"2.2.1\"" \
	-O2

LOCAL_SHARED_LIBRARIES := libtcl

LOCAL_LDLIBS :=

include $(BUILD_SHARED_LIBRARY)
