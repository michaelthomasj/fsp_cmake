#include "new_thread0.h"
#include "SEGGER_RTT.h"

/* New Thread entry function */
/* pvParameters contains TaskHandle_t */
void new_thread0_entry(void * pvParameters)
{
    FSP_PARAMETER_NOT_USED(pvParameters);

    /* Reaching here proves the secure -> non-secure jump succeeded: this task
     * runs in the non-secure FreeRTOS image started by TF-M. Report over SEGGER
     * RTT (this NS image has its own RTT control block, separate from BL2/secure). */
    SEGGER_RTT_Init();
    SEGGER_RTT_WriteString(0, "[NS] non-secure world running (TF-M S->NS jump OK)\r\n");

    uint32_t heartbeat = 0U;
    while (1)
    {
        /* Periodic heartbeat so liveness is visible in the RTT viewer. */
        SEGGER_RTT_printf(0, "[NS] heartbeat %u\r\n", (unsigned)heartbeat++);
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
