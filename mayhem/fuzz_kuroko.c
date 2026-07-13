/*
 * In-process libFuzzer harness for the Kuroko interpreter.
 *
 * The upstream Mayhem target ran the `kuroko` CLI on a file input
 * (`kuroko @@`). An uninstrumented file-input CLI does not expose libFuzzer
 * coverage/sanitizer instrumentation over the interpreter, so this harness
 * drives the SAME code path in-process: it compiles and executes the fuzz
 * input as a Kuroko source program via the embedding API (krk_interpret),
 * exactly like runString() in src/kuroko.c. The VM is init'd and freed each
 * iteration so state does not leak between inputs.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <kuroko/kuroko.h>
#include <kuroko/vm.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	/* krk_interpret needs a NUL-terminated C string. */
	char *src = (char *)malloc(size + 1);
	if (!src) return 0;
	memcpy(src, data, size);
	src[size] = '\0';

	krk_initVM(0);
	krk_startModule("__main__");
	krk_attachNamedValue(&krk_currentThread.module->fields, "__doc__", NONE_VAL());
	krk_interpret(src, "<fuzz>");
	krk_freeVM();

	free(src);
	return 0;
}
