CFLAGS = -I. -fPIC

TARGET = libaxibridge32.so
SOURCES = $(shell echo *.c)
OBJECTS = $(SOURCES:.c=.o)

all: $(TARGET)

clean:
	rm -rf *.o
	rm -rf *.so

$(TARGET): $(OBJECTS)
	$(CC) -shared $(CFLAGS) -o $(TARGET) $(OBJECTS)
	strip --strip-unneeded $(TARGET)
