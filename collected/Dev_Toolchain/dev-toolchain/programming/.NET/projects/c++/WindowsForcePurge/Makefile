# Makefile for OwnNPurge
# This creates a Windows executable that can take ownership and purge files/folders

CC = g++
CFLAGS = -Wall -Wextra -O2 -std=c++11
LDFLAGS = -static -static-libgcc -static-libstdc++
LIBS = -ladvapi32 -lshell32 -luser32 -lpsapi

# Target executable name
TARGET = ownNpurge.exe
SOURCE = ownNpurge.cpp

# Default target
all: $(TARGET)

# Build the executable
$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(TARGET) $(SOURCE) $(LIBS)

# Clean build artifacts
clean:
	del /f $(TARGET)

# Rebuild
rebuild: clean all

# Install (copy to system path - requires admin)
install: $(TARGET)
	copy $(TARGET) C:\Windows\System32\

# Help target
help:
	@echo "Available targets:"
	@echo "  all      - Build the executable (default)"
	@echo " clean    - Remove built executable"
	@echo "  rebuild  - Clean and rebuild"
	@echo "  install  - Install to system (requires admin)"
	@echo "  help     - Show this help"

.PHONY: all clean rebuild install help
