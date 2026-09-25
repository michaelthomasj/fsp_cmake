/* generated HAL source file - do not edit */
#include "hal_data.h"
#define RA_NOT_DEFINED (UINT32_MAX)
#if (RA_NOT_DEFINED != RA_NOT_DEFINED)
  void * const gp_mcuboot_flash_ctrl = &RA_NOT_DEFINED_ctrl;
  flash_cfg_t const * const gp_mcuboot_flash_cfg = &RA_NOT_DEFINED_cfg;
  flash_instance_t const * const gp_mcuboot_flash_instance = &RA_NOT_DEFINED;
#else
void *const gp_mcuboot_flash_ctrl = &g_mram0_ctrl;
flash_cfg_t const *const gp_mcuboot_flash_cfg = &g_mram0_cfg;
flash_instance_t const *const gp_mcuboot_flash_instance = &g_mram0;
#endif
#undef RA_NOT_DEFINED
void g_hal_init(void) {
	g_common_init();
}
