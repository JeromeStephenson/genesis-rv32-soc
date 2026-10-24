#include <FreeRTOS.h>
#include <task.h>

#define UART_BASE       0x10000000UL
#define GPIO_BASE       0x10001000UL
#define UART_DATA       (*(volatile uint32_t *)(UART_BASE + 0x0UL))
#define UART_STAT       (*(volatile uint32_t *)(UART_BASE + 0x4UL))
#define GPIO_OUT        (*(volatile uint32_t *)(GPIO_BASE + 0x4UL))
#define UART_TX_EMPTY   (1UL << 0)

static void uart_putc(char c) { while ((UART_STAT & UART_TX_EMPTY) == 0UL) {} UART_DATA = (uint32_t)c; }
static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

/* --- The User Task --- */
static void vBlinkTask(void *pvParameters) {
    uint32_t count = 0;
    (void)pvParameters;
    for (;;) {
        GPIO_OUT = ++count;
        uart_puts("FreeRTOS Alive! Count: ");
        uart_putc('0' + (count / 10));
        uart_putc('0' + (count % 10));
        uart_puts("\r\n");
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

/* --- Static Memory for User Task --- */
StaticTask_t xBlinkTaskTCB;
StackType_t  xBlinkTaskStack[256];

/* --- Static Memory for Idle Task (REQUIRED) --- */
StaticTask_t xIdleTaskTCB;
StackType_t  uxIdleTaskStack[configMINIMAL_STACK_SIZE];

void vApplicationGetIdleTaskMemory(StaticTask_t **ppxIdleTaskTCBBuffer,
                                   StackType_t **ppxIdleTaskStackBuffer,
                                   uint32_t *pulIdleTaskStackSize)
{
    *ppxIdleTaskTCBBuffer   = &xIdleTaskTCB;
    *ppxIdleTaskStackBuffer = uxIdleTaskStack;
    *pulIdleTaskStackSize   = configMINIMAL_STACK_SIZE;
}

/* --- Malloc Failed Hook --- */
void vApplicationMallocFailedHook(void) {
    uart_puts("\r\nFATAL: Malloc Failed!\r\n");
    for(;;);
}

/* --- Port Handlers --- */
void freertos_risc_v_application_interrupt_handler(void) { 
    uint32_t meie = (1UL << 11); __asm volatile ("csrc mie, %0" :: "r"(meie)); 
}
void freertos_risc_v_application_exception_handler(void) { 
    uint32_t cause; __asm volatile ("csrr %0, mcause" : "=r"(cause)); GPIO_OUT = cause; for (;;) {} 
}

/* --- Declare the FreeRTOS trap handler --- */
extern void freertos_risc_v_trap_handler(void);

int main(void) {
    uart_puts("\r\n=== Starting FreeRTOS (100% Static) ===\r\n");
    
    /* CRITICAL: Point mtvec to FreeRTOS trap handler BEFORE starting scheduler */
    uint32_t mtvec_val = (uint32_t)freertos_risc_v_trap_handler;
    __asm volatile ("csrw mtvec, %0" :: "r"(mtvec_val));
    uart_puts("mtvec set to FreeRTOS handler\r\n");
    
    /* Create the user task STATICALLY */
    TaskHandle_t xHandle = xTaskCreateStatic(vBlinkTask, "Blink", 256, NULL, 1, xBlinkTaskStack, &xBlinkTaskTCB);
    
    if (xHandle == NULL) {
        uart_puts("FATAL: Static task creation failed!\r\n");
        for(;;);
    }
    
    uart_puts("Starting Scheduler...\r\n");
    vTaskStartScheduler();
    
    uart_puts("FATAL: Scheduler returned!\r\n");
    for(;;);
    return 0;
}
