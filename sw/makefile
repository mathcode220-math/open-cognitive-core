CC = gcc
CFLAGS = -Wall -Wextra -O2 -std=c99
LDFLAGS = 

SRCS = occp_bridge.c
HDRS = occp_bridge.h
TARGET = occp_bridge_test

all: $(TARGET)

$(TARGET): $(SRCS) $(HDRS)
	$(CC) $(CFLAGS) -DOCCP_BRIDGE_TEST $(SRCS) -o $(TARGET) $(LDFLAGS)
	@echo "Build complete: $(TARGET)"

liboccp.so: $(SRCS) $(HDRS)
	$(CC) $(CFLAGS) -fPIC -shared $(SRCS) -o liboccp.so $(LDFLAGS)
	@echo "Library built: liboccp.so"

clean:
	rm -f $(TARGET) liboccp.so *.o
	@echo "Clean complete"

test: $(TARGET)
	@echo "Running OCCP Bridge test..."
	@echo "=============================="
	./$(TARGET)
	@echo "=============================="

.PHONY: all clean test
