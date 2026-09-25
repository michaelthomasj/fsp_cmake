/* generated HAL header file - do not edit */
#ifndef HAL_DATA_H_
#define HAL_DATA_H_
#include <stdint.h>
#include "bsp_api.h"
#include "common_data.h"

#include "rm_mcuboot_port.h"
#if defined(MCUBOOT_USE_MBED_TLS)
#include "mbedtls/platform.h"
#elif (defined(MCUBOOT_USE_OCRYPTO) && defined(RM_MCUBOOT_PORT_USE_OCRYPTO_PORT))
#include "rm_ocrypto_port.h"
#endif
FSP_HEADER
void mcuboot_quick_setup();
void hal_entry(void);
void g_hal_init(void);
FSP_FOOTER
#endif /* HAL_DATA_H_ */
