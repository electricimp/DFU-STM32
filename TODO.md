1. Current implementation of `STM32USARTPort._readByte()` do not use interrupts (callbacks), but polls UART for data using `imp.sleep()`. It may be suboptimal, especially for Flash ROM erasing operation. To make `STM32USARTPort` more responsive, always use `flashSectorMap` parameter and never resort to bulk erase in final product.

2. Agent-device communication has no built-in integrity control. As a workaround, you can implement a watchdog on agent side to restart device in case of breakdowns or write failures. See [`imp.wakeup()`](https://developer.electricimp.com/api/imp/wakeup) on how to set up a timer.

   If you experience individual chunk loss, you may set up a chunk counter. Add an index to each chunk in `DFUSTM32Agent` `beforeSendChunk` callback, than ensure the correct chunk succession and delete that index in `DFUSTM32Device` `onReceiveChunk` callback.

3. Logging control is not yet implemented. Debug messages can not be disabled.
