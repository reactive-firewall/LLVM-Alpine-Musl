#include <cstddef>
#include <cstdlib>
extern "C" {

void* __cxa_allocate_exception(std::size_t size) {
    return std::malloc(size);
}
void __cxa_free_exception(void* ptr) noexcept {
    std::free(ptr);
}
void __cxa_throw(void* /*ex*/, void* /*info*/, void (*/*dtor*/)(void*)) {
    // minimal stub: abort if used during bootstrap stage
    std::abort();
}
void* __cxa_get_exception_ptr(void*) { return nullptr; }
void __cxa_begin_catch(void*) {}
void __cxa_end_catch() {}
}
