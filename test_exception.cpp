#include <iostream>
#include <exception>
#include <typeinfo>

struct E { virtual ~E(){} };
int main() {
    try {
        throw E();
    } catch (...) {
        std::cout << "caught\n";
    }
    std::cout << "type_info name: " << typeid(E).name() << "\n";
    return 0;
}
